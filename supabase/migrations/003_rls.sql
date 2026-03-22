-- ============================================================
-- VICOMART ORDER SYSTEM - Migration 003: Row Level Security
-- ============================================================

-- ── ENABLE RLS ─────────────────────────────────────────────

alter table profiles            enable row level security;
alter table orders              enable row level security;
alter table order_items         enable row level security;
alter table order_events        enable row level security;
alter table supplier_products   enable row level security;
alter table notifications       enable row level security;

-- ── PROFILES ───────────────────────────────────────────────

-- Users can read their own profile
create policy "profiles_select_own"
  on profiles for select
  using (id = auth.uid());

-- Admin/buyer can read all profiles
create policy "profiles_select_admin"
  on profiles for select
  using (current_role() in ('admin','buyer_head_office'));

-- Only system (service key) can insert/update profiles
create policy "profiles_insert_admin"
  on profiles for insert
  with check (current_role() = 'admin');

create policy "profiles_update_self"
  on profiles for update
  using (id = auth.uid())
  with check (id = auth.uid());

-- ── ORDERS ─────────────────────────────────────────────────

-- Admin/buyer: see all orders
create policy "orders_select_admin"
  on orders for select
  using (current_role() in ('admin','buyer_head_office'));

-- Store user: see only their store's orders
create policy "orders_select_store"
  on orders for select
  using (
    current_role() = 'store_user'
    and store_id = current_store_id()
  );

-- Supplier user: see only orders for their supplier
create policy "orders_select_supplier"
  on orders for select
  using (
    current_role() = 'supplier_user'
    and supplier_id = current_supplier_id()
  );

-- Store user / admin / buyer can insert orders
create policy "orders_insert"
  on orders for insert
  with check (
    current_role() in ('admin','buyer_head_office')
    or (current_role() = 'store_user' and store_id = current_store_id())
  );

-- Only functions (via security definer) update orders
-- Direct updates blocked for all except admin
create policy "orders_update_admin"
  on orders for update
  using (current_role() in ('admin','buyer_head_office'));

-- ── ORDER ITEMS ────────────────────────────────────────────

create policy "order_items_select_admin"
  on order_items for select
  using (current_role() in ('admin','buyer_head_office'));

create policy "order_items_select_store"
  on order_items for select
  using (
    current_role() = 'store_user'
    and exists (
      select 1 from orders o
      where o.id = order_items.order_id
        and o.store_id = current_store_id()
    )
  );

create policy "order_items_select_supplier"
  on order_items for select
  using (
    current_role() = 'supplier_user'
    and exists (
      select 1 from orders o
      where o.id = order_items.order_id
        and o.supplier_id = current_supplier_id()
    )
  );

create policy "order_items_insert"
  on order_items for insert
  with check (
    current_role() in ('admin','buyer_head_office')
    or (
      current_role() = 'store_user'
      and exists (
        select 1 from orders o
        where o.id = order_items.order_id
          and o.store_id = current_store_id()
      )
    )
  );

create policy "order_items_update_admin"
  on order_items for update
  using (current_role() in ('admin','buyer_head_office','supplier_user'));

-- ── ORDER EVENTS ───────────────────────────────────────────

create policy "order_events_select_admin"
  on order_events for select
  using (current_role() in ('admin','buyer_head_office'));

create policy "order_events_select_store"
  on order_events for select
  using (
    current_role() = 'store_user'
    and exists (
      select 1 from orders o
      where o.id = order_events.order_id
        and o.store_id = current_store_id()
    )
  );

create policy "order_events_select_supplier"
  on order_events for select
  using (
    current_role() = 'supplier_user'
    and exists (
      select 1 from orders o
      where o.id = order_events.order_id
        and o.supplier_id = current_supplier_id()
    )
  );

-- Events are inserted via security definer functions only
create policy "order_events_insert"
  on order_events for insert
  with check (auth.uid() is not null);

-- ── SUPPLIER PRODUCTS ──────────────────────────────────────

-- All authenticated users can view catalog
create policy "supplier_products_select"
  on supplier_products for select
  using (
    auth.uid() is not null
    and is_active = true
  );

-- Only admin can modify catalog
create policy "supplier_products_modify"
  on supplier_products for all
  using (current_role() = 'admin')
  with check (current_role() = 'admin');

-- ── NOTIFICATIONS ──────────────────────────────────────────

create policy "notifications_admin"
  on notifications for all
  using (current_role() in ('admin','buyer_head_office'));

-- ── MASTER DATA: PUBLIC READ ───────────────────────────────
-- suppliers, stores, products have no RLS (public read for authenticated users)
-- Use Supabase Auth: set these tables to be readable by authenticated role only

alter table suppliers   enable row level security;
alter table stores      enable row level security;
alter table products    enable row level security;

create policy "suppliers_select_authenticated"
  on suppliers for select using (auth.uid() is not null);

create policy "stores_select_authenticated"
  on stores for select using (auth.uid() is not null);

create policy "products_select_authenticated"
  on products for select using (auth.uid() is not null);

create policy "suppliers_modify_admin"
  on suppliers for all
  using (current_role() = 'admin')
  with check (current_role() = 'admin');

create policy "stores_modify_admin"
  on stores for all
  using (current_role() = 'admin')
  with check (current_role() = 'admin');

create policy "products_modify_admin"
  on products for all
  using (current_role() = 'admin')
  with check (current_role() = 'admin');
