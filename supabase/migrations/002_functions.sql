-- ============================================================
-- VICOMART ORDER SYSTEM - Migration 002: Helper Functions & Business Logic
-- ============================================================

-- ── PROFILE HELPERS ────────────────────────────────────────

create or replace function current_role()
returns text language sql stable security definer as $$
  select role from profiles where id = auth.uid();
$$;

create or replace function current_store_id()
returns text language sql stable security definer as $$
  select store_id from profiles where id = auth.uid();
$$;

create or replace function current_supplier_id()
returns text language sql stable security definer as $$
  select supplier_id from profiles where id = auth.uid();
$$;

-- ── ORDER CODE GENERATOR ───────────────────────────────────

create or replace function generate_order_code(p_store_id text)
returns text language plpgsql security definer as $$
declare
  v_store_code text;
  v_date_str   text;
  v_seq        bigint;
  v_code       text;
begin
  -- Map store_id to short code (extend as needed)
  v_store_code := upper(left(regexp_replace(p_store_id, '[^a-zA-Z0-9]', '', 'g'), 3));
  v_date_str   := to_char(current_date, 'YYYYMMDD');
  
  -- Get next sequence for today + store combo
  select coalesce(max(
    cast(right(order_code, 3) as int)
  ), 0) + 1
  into v_seq
  from orders
  where store_id = p_store_id
    and order_date = current_date;

  v_code := format('ORD-%s-%s-%s', v_store_code, v_date_str, lpad(v_seq::text, 3, '0'));
  return v_code;
end;
$$;

-- ── LOG ORDER EVENT ────────────────────────────────────────

create or replace function log_order_event(
  p_order_id  uuid,
  p_event_type text,
  p_payload   jsonb default '{}'
)
returns void language plpgsql security definer as $$
begin
  insert into order_events(order_id, event_type, payload, created_by)
  values (p_order_id, p_event_type, p_payload, auth.uid());
end;
$$;

-- ── CREATE ORDER ───────────────────────────────────────────

create or replace function create_order(
  p_store_id      text,
  p_supplier_id   text,
  p_delivery_date date,
  p_order_note    text,
  p_items         jsonb  -- [{product_id, ordered_qty, expected_unit_price}]
)
returns uuid language plpgsql security definer as $$
declare
  v_order_id   uuid;
  v_order_code text;
  v_item       jsonb;
  v_role       text;
  v_store_id   text;
begin
  -- Permission check
  v_role     := current_role();
  v_store_id := current_store_id();

  if v_role = 'store_user' and v_store_id != p_store_id then
    raise exception 'Access denied: not your store';
  end if;
  if v_role not in ('admin','buyer_head_office','store_user') then
    raise exception 'Access denied: role % cannot create orders', v_role;
  end if;

  -- Validate items
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Order must have at least one item';
  end if;

  v_order_code := generate_order_code(p_store_id);

  insert into orders(order_code, store_id, supplier_id, delivery_date, order_note, created_by)
  values (v_order_code, p_store_id, p_supplier_id, p_delivery_date, p_order_note, auth.uid())
  returning id into v_order_id;

  -- Insert items
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    insert into order_items(order_id, product_id, ordered_qty, expected_unit_price)
    values (
      v_order_id,
      v_item->>'product_id',
      (v_item->>'ordered_qty')::numeric,
      coalesce((v_item->>'expected_unit_price')::numeric, 0)
    );
  end loop;

  -- Update total
  update orders
  set total_ordered_amount = (
    select sum(ordered_qty * expected_unit_price) from order_items where order_id = v_order_id
  )
  where id = v_order_id;

  perform log_order_event(v_order_id, 'order_created', jsonb_build_object('store_id', p_store_id, 'supplier_id', p_supplier_id));
  return v_order_id;
end;
$$;

-- ── SUBMIT ORDER ───────────────────────────────────────────

create or replace function submit_order(p_order_id uuid)
returns void language plpgsql security definer as $$
declare
  v_order orders%rowtype;
  v_role  text;
begin
  v_role := current_role();
  select * into v_order from orders where id = p_order_id;

  if not found then raise exception 'Order not found'; end if;
  if v_role = 'store_user' and v_order.store_id != current_store_id() then
    raise exception 'Access denied';
  end if;
  if v_order.status != 'draft' then
    raise exception 'Only draft orders can be submitted';
  end if;
  if (select count(*) from order_items where order_id = p_order_id) = 0 then
    raise exception 'Cannot submit order with no items';
  end if;

  update orders
  set status = 'pending_supplier', submitted_at = now(), updated_at = now()
  where id = p_order_id;

  perform log_order_event(p_order_id, 'submitted', '{}'::jsonb);
end;
$$;

-- ── CANCEL ORDER ───────────────────────────────────────────

create or replace function cancel_order(p_order_id uuid, p_reason text default '')
returns void language plpgsql security definer as $$
declare
  v_order orders%rowtype;
  v_role  text;
begin
  v_role := current_role();
  select * into v_order from orders where id = p_order_id;
  if not found then raise exception 'Order not found'; end if;
  if v_role = 'store_user' and v_order.store_id != current_store_id() then
    raise exception 'Access denied';
  end if;
  if v_order.status not in ('draft','submitted','pending_supplier') then
    raise exception 'Order cannot be cancelled at this stage';
  end if;

  update orders
  set status = 'cancelled', reject_reason = p_reason, updated_at = now()
  where id = p_order_id;

  perform log_order_event(p_order_id, 'cancelled', jsonb_build_object('reason', p_reason));
end;
$$;

-- ── SUPPLIER CONFIRM ORDER ─────────────────────────────────

create or replace function supplier_confirm_order(
  p_order_id      uuid,
  p_items_json    jsonb,  -- [{order_item_id, confirmed_qty, confirmed_unit_price, item_status, line_note}]
  p_supplier_note text default ''
)
returns void language plpgsql security definer as $$
declare
  v_order       orders%rowtype;
  v_role        text;
  v_supplier_id text;
  v_item        jsonb;
  v_has_partial boolean := false;
  v_new_status  text;
begin
  v_role        := current_role();
  v_supplier_id := current_supplier_id();

  select * into v_order from orders where id = p_order_id;
  if not found then raise exception 'Order not found'; end if;
  if v_role = 'supplier_user' and v_order.supplier_id != v_supplier_id then
    raise exception 'Access denied: not your order';
  end if;
  if v_role not in ('supplier_user','admin','buyer_head_office') then
    raise exception 'Access denied';
  end if;
  if v_order.status != 'pending_supplier' then
    raise exception 'Order is not pending supplier response';
  end if;

  -- Update each item
  for v_item in select * from jsonb_array_elements(p_items_json)
  loop
    update order_items
    set confirmed_qty        = (v_item->>'confirmed_qty')::numeric,
        confirmed_unit_price = coalesce((v_item->>'confirmed_unit_price')::numeric, expected_unit_price),
        item_status          = coalesce(v_item->>'item_status', 'confirmed'),
        line_note            = v_item->>'line_note',
        updated_at           = now()
    where id = (v_item->>'order_item_id')::uuid
      and order_id = p_order_id;
  end loop;

  -- Determine new status
  if exists (
    select 1 from order_items
    where order_id = p_order_id
      and (confirmed_qty < ordered_qty or item_status in ('partial','rejected'))
  ) then
    v_new_status := 'partial_confirmed';
  else
    v_new_status := 'confirmed';
  end if;

  update orders
  set status                  = v_new_status,
      supplier_note           = p_supplier_note,
      supplier_responded_at   = now(),
      total_confirmed_amount  = (
        select sum(confirmed_qty * confirmed_unit_price)
        from order_items where order_id = p_order_id
      ),
      updated_at = now()
  where id = p_order_id;

  perform log_order_event(p_order_id, v_new_status, jsonb_build_object('supplier_note', p_supplier_note));
end;
$$;

-- ── SUPPLIER REJECT ORDER ──────────────────────────────────

create or replace function supplier_reject_order(p_order_id uuid, p_reason text)
returns void language plpgsql security definer as $$
declare
  v_order orders%rowtype;
  v_role  text;
begin
  if p_reason is null or trim(p_reason) = '' then
    raise exception 'Reject reason is required';
  end if;
  v_role := current_role();
  select * into v_order from orders where id = p_order_id;
  if not found then raise exception 'Order not found'; end if;
  if v_role = 'supplier_user' and v_order.supplier_id != current_supplier_id() then
    raise exception 'Access denied';
  end if;
  if v_order.status != 'pending_supplier' then
    raise exception 'Order is not pending supplier response';
  end if;

  update orders
  set status = 'rejected', reject_reason = p_reason,
      supplier_responded_at = now(), updated_at = now()
  where id = p_order_id;

  perform log_order_event(p_order_id, 'rejected', jsonb_build_object('reason', p_reason));
end;
$$;

-- ── MARK DELIVERING / DELIVERED / CLOSE ────────────────────

create or replace function mark_order_delivering(p_order_id uuid)
returns void language plpgsql security definer as $$
begin
  if current_role() not in ('admin','buyer_head_office') then raise exception 'Access denied'; end if;
  update orders set status='delivering', delivering_at=now(), updated_at=now() where id=p_order_id and status in ('confirmed','partial_confirmed');
  if not found then raise exception 'Order not found or wrong status'; end if;
  perform log_order_event(p_order_id, 'delivering', '{}'::jsonb);
end;
$$;

create or replace function mark_order_delivered(p_order_id uuid)
returns void language plpgsql security definer as $$
begin
  if current_role() not in ('admin','buyer_head_office') then raise exception 'Access denied'; end if;
  update orders set status='delivered', delivered_at=now(), updated_at=now() where id=p_order_id and status in ('delivering','confirmed','partial_confirmed');
  if not found then raise exception 'Order not found or wrong status'; end if;
  perform log_order_event(p_order_id, 'delivered', '{}'::jsonb);
end;
$$;

create or replace function close_order(p_order_id uuid)
returns void language plpgsql security definer as $$
begin
  if current_role() not in ('admin','buyer_head_office') then raise exception 'Access denied'; end if;
  update orders set status='closed', closed_at=now(), updated_at=now() where id=p_order_id and status='delivered';
  if not found then raise exception 'Order not found or not delivered yet'; end if;
  perform log_order_event(p_order_id, 'closed', '{}'::jsonb);
end;
$$;

-- ── AUDIT TRIGGER ──────────────────────────────────────────

create or replace function audit_trigger_fn()
returns trigger language plpgsql security definer as $$
begin
  insert into audit_logs(table_name, record_id, action, old_data, new_data, changed_by)
  values (
    TG_TABLE_NAME,
    coalesce(NEW.id::text, OLD.id::text),
    TG_OP,
    case when TG_OP in ('UPDATE','DELETE') then to_jsonb(OLD) end,
    case when TG_OP in ('INSERT','UPDATE') then to_jsonb(NEW) end,
    auth.uid()
  );
  return coalesce(NEW, OLD);
end;
$$;

create or replace trigger audit_orders
  after insert or update or delete on orders
  for each row execute function audit_trigger_fn();

create or replace trigger audit_order_items
  after insert or update or delete on order_items
  for each row execute function audit_trigger_fn();
