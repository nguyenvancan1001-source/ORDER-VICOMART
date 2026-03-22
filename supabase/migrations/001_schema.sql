-- ============================================================
-- VICOMART ORDER SYSTEM - Migration 001: Schema
-- ============================================================

-- Enable UUID
create extension if not exists "pgcrypto";

-- ── MASTER DATA ────────────────────────────────────────────

create table if not exists suppliers (
  id            text primary key,                        -- e.g. NCC01
  name          text not null,
  contact       text,
  lead_time     int default 1,
  is_active     boolean default true,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

create table if not exists stores (
  id            text primary key,                        -- e.g. S01
  name          text not null,
  address       text,
  is_active     boolean default true,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

create table if not exists products (
  id            text primary key,                        -- e.g. P001
  name          text not null,
  unit          text not null,
  is_active     boolean default true,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

create table if not exists supplier_products (
  id                  uuid primary key default gen_random_uuid(),
  supplier_id         text not null references suppliers(id),
  product_id          text not null references products(id),
  latest_price        numeric(15,2) default 0,
  min_order_qty       int default 1,
  pack_size           int default 1,
  is_active           boolean default true,
  created_at          timestamptz default now(),
  updated_at          timestamptz default now(),
  unique(supplier_id, product_id)
);

-- ── SECURITY ───────────────────────────────────────────────

create table if not exists profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  username      text unique,
  full_name     text,
  role          text not null check (role in ('admin','buyer_head_office','store_user','supplier_user')),
  store_id      text references stores(id),
  supplier_id   text references suppliers(id),
  is_active     boolean default true,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

-- ── ORDERS ─────────────────────────────────────────────────

create sequence if not exists order_seq;

create table if not exists orders (
  id                    uuid primary key default gen_random_uuid(),
  order_code            text unique not null,
  store_id              text not null references stores(id),
  supplier_id           text not null references suppliers(id),
  status                text not null default 'draft' check (status in (
                          'draft','submitted','pending_supplier','confirmed',
                          'partial_confirmed','rejected','cancelled',
                          'delivering','delivered','closed'
                        )),
  order_date            date not null default current_date,
  delivery_date         date,
  order_note            text,
  supplier_note         text,
  reject_reason         text,
  total_ordered_amount  numeric(15,2) default 0,
  total_confirmed_amount numeric(15,2) default 0,
  submitted_at          timestamptz,
  supplier_responded_at timestamptz,
  delivering_at         timestamptz,
  delivered_at          timestamptz,
  closed_at             timestamptz,
  created_by            uuid references auth.users(id),
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
);

create table if not exists order_items (
  id                  uuid primary key default gen_random_uuid(),
  order_id            uuid not null references orders(id) on delete cascade,
  product_id          text not null references products(id),
  ordered_qty         numeric(15,3) not null check (ordered_qty > 0),
  confirmed_qty       numeric(15,3) default 0,
  expected_unit_price numeric(15,2) default 0,
  confirmed_unit_price numeric(15,2) default 0,
  item_status         text default 'pending' check (item_status in ('pending','confirmed','partial','rejected')),
  line_note           text,
  created_at          timestamptz default now(),
  updated_at          timestamptz default now()
);

-- ── EVENTS & LOGS ──────────────────────────────────────────

create table if not exists order_events (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references orders(id) on delete cascade,
  event_type  text not null,
  payload     jsonb default '{}',
  created_by  uuid references auth.users(id),
  created_at  timestamptz default now()
);

create table if not exists audit_logs (
  id          uuid primary key default gen_random_uuid(),
  table_name  text not null,
  record_id   text not null,
  action      text not null check (action in ('INSERT','UPDATE','DELETE')),
  old_data    jsonb,
  new_data    jsonb,
  changed_by  uuid references auth.users(id),
  changed_at  timestamptz default now()
);

create table if not exists notifications (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid references orders(id),
  recipient   text,
  channel     text default 'internal',
  event_type  text,
  payload     jsonb default '{}',
  sent_at     timestamptz,
  status      text default 'pending',
  created_at  timestamptz default now()
);

create table if not exists api_integrations (
  id          uuid primary key default gen_random_uuid(),
  supplier_id text references suppliers(id),
  api_type    text,
  config      jsonb default '{}',
  is_active   boolean default false,
  created_at  timestamptz default now()
);

-- ── INDEXES ────────────────────────────────────────────────

create index if not exists idx_orders_store_id on orders(store_id);
create index if not exists idx_orders_supplier_id on orders(supplier_id);
create index if not exists idx_orders_status on orders(status);
create index if not exists idx_orders_order_date on orders(order_date desc);
create index if not exists idx_order_items_order_id on order_items(order_id);
create index if not exists idx_order_events_order_id on order_events(order_id);
create index if not exists idx_profiles_role on profiles(role);
create index if not exists idx_profiles_store_id on profiles(store_id);
create index if not exists idx_profiles_supplier_id on profiles(supplier_id);
create index if not exists idx_supplier_products_supplier on supplier_products(supplier_id);
