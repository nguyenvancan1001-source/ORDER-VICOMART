-- ============================================================
-- VICOMART ORDER SYSTEM - Migration 004: Seed Data (Staging)
-- DO NOT run on production!
-- ============================================================

-- Stores
insert into stores(id, name, address) values
  ('S01', 'Phú Bài', 'Hương Thủy, Thừa Thiên Huế'),
  ('S02', 'Vinh Thanh', 'Phú Vang, Thừa Thiên Huế'),
  ('S03', 'An Vân Dương', 'TP. Huế, Thừa Thiên Huế')
on conflict do nothing;

-- Suppliers
insert into suppliers(id, name, contact, lead_time) values
  ('NCC01', 'NCC Rau Củ ABC',       '0901234567', 1),
  ('NCC02', 'NCC Thực Phẩm XYZ',   '0912345678', 2),
  ('NCC03', 'NCC Đồ Khô DEF',      '0923456789', 3)
on conflict do nothing;

-- Products
insert into products(id, name, unit) values
  ('P001', 'Rau muống',        'kg'),
  ('P002', 'Cà chua',          'kg'),
  ('P003', 'Dưa leo',          'kg'),
  ('P004', 'Bắp cải',          'kg'),
  ('P005', 'Hành tây',         'kg'),
  ('P006', 'Thịt heo xay',     'kg'),
  ('P007', 'Gà ta nguyên con', 'con'),
  ('P008', 'Cá basa phi lê',   'kg'),
  ('P009', 'Tôm sú',           'kg'),
  ('P010', 'Trứng gà',         'vỉ 10'),
  ('P011', 'Gạo Jasmine',      'kg'),
  ('P012', 'Mì gói Hảo Hảo',  'thùng'),
  ('P013', 'Nước mắm Phú Quốc','chai'),
  ('P014', 'Dầu ăn Neptune',   'chai'),
  ('P015', 'Đường cát trắng',  'kg')
on conflict do nothing;

-- Supplier Products (catalog)
insert into supplier_products(supplier_id, product_id, latest_price, min_order_qty) values
  ('NCC01','P001', 8000,  5),
  ('NCC01','P002',15000,  5),
  ('NCC01','P003',12000,  5),
  ('NCC01','P004',10000,  5),
  ('NCC01','P005',18000,  3),
  ('NCC02','P006',95000,  2),
  ('NCC02','P007',120000, 1),
  ('NCC02','P008',75000,  2),
  ('NCC02','P009',180000, 1),
  ('NCC02','P010',28000,  5),
  ('NCC03','P011',22000, 10),
  ('NCC03','P012',125000, 1),
  ('NCC03','P013',45000,  6),
  ('NCC03','P014',55000,  6),
  ('NCC03','P015',18000,  5)
on conflict do nothing;

-- NOTE: User creation requires Supabase Auth.
-- After creating users via Auth dashboard or API, run:
--
-- insert into profiles(id, username, full_name, role, store_id, supplier_id) values
--   ('<auth_uid_admin>',     'admin',     'Quản trị viên',    'admin',              null,    null),
--   ('<auth_uid_buyer>',     'buyer',     'Nguyễn Thị Mua',   'buyer_head_office',  null,    null),
--   ('<auth_uid_store1>',    'store1',    'Lê Văn Cường',      'store_user',         'S01',   null),
--   ('<auth_uid_store2>',    'store2',    'Phạm Thị Dung',     'store_user',         'S02',   null),
--   ('<auth_uid_supplier1>', 'supplier1', 'Công ty ABC',       'supplier_user',      null,    'NCC01'),
--   ('<auth_uid_supplier2>', 'supplier2', 'Công ty XYZ',       'supplier_user',      null,    'NCC02');
