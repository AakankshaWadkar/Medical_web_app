-- Migration: 20260104000000_product_warehouse_purchase_sales.sql
-- Stage (c): Product / Warehouse / Purchase (Proposed) / Sales

-- ============================================================================
-- 1. PRODUCT CATALOG EXTENSIONS
-- ============================================================================

-- Sub Categories
create table public.sub_categories (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete cascade,
  code        text not null,
  name        text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  version     bigint not null default 1,
  unique (tenant_id, category_id, code)
);
create index idx_sub_categories_cat on public.sub_categories (tenant_id, category_id);
call public.apply_tenant_rls('public.sub_categories');

-- Manufacturers
create table public.manufacturers (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants(id) on delete cascade,
  code            text not null,
  name            text not null,
  drug_license_no text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  version         bigint not null default 1,
  unique (tenant_id, code)
);
call public.apply_tenant_rls('public.manufacturers');

-- Generic Medicines (Salt / Molecule Master)
create table public.generic_medicines (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  code        text not null,
  name        text not null,
  description text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  version     bigint not null default 1,
  unique (tenant_id, code)
);
call public.apply_tenant_rls('public.generic_medicines');

-- Dosage Forms (Tablet, Syrup, Injection, Ointment, Capsule)
create table public.dosage_forms (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenants(id) on delete cascade,
  code       text not null,
  name       text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version    bigint not null default 1,
  unique (tenant_id, code)
);
call public.apply_tenant_rls('public.dosage_forms');

-- Strengths (500mg, 100ml, 250mcg)
create table public.strengths (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenants(id) on delete cascade,
  value      text not null,
  unit       text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version    bigint not null default 1,
  unique (tenant_id, value, unit)
);
call public.apply_tenant_rls('public.strengths');

-- Therapeutic Classes (Antibiotic, Analgesic, Cardiovascular)
create table public.therapeutic_classes (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenants(id) on delete cascade,
  code       text not null,
  name       text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version    bigint not null default 1,
  unique (tenant_id, code)
);
call public.apply_tenant_rls('public.therapeutic_classes');

-- Product Types (Ethical, Generic, OTC, Critical Care)
create table public.product_types (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenants(id) on delete cascade,
  code       text not null,
  name       text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version    bigint not null default 1,
  unique (tenant_id, code)
);
call public.apply_tenant_rls('public.product_types');

-- HSN Codes (GST Tax Classification)
create table public.hsn_codes (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  hsn_code         text not null,
  description      text,
  default_gst_rate numeric(5,2) not null default 12.00,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  version          bigint not null default 1,
  unique (tenant_id, hsn_code)
);
call public.apply_tenant_rls('public.hsn_codes');

-- GST Rates
create table public.gst_rates (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants(id) on delete cascade,
  rate_percentage numeric(5,2) not null,
  cgst_percentage numeric(5,2) not null,
  sgst_percentage numeric(5,2) not null,
  igst_percentage numeric(5,2) not null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  version         bigint not null default 1,
  unique (tenant_id, rate_percentage)
);
call public.apply_tenant_rls('public.gst_rates');

-- Price Lists
create table public.price_lists (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenants(id) on delete cascade,
  code          text not null,
  name          text not null,
  currency_code text not null default 'INR',
  is_default    boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  version       bigint not null default 1,
  unique (tenant_id, code)
);
call public.apply_tenant_rls('public.price_lists');

-- Product Compositions
create table public.compositions (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.tenants(id) on delete cascade,
  product_id          uuid not null references public.products(id) on delete cascade,
  generic_medicine_id uuid not null references public.generic_medicines(id) on delete cascade,
  strength_id         uuid references public.strengths(id) on delete set null,
  dosage_ratio        text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  version             bigint not null default 1
);
create index idx_compositions_prod on public.compositions (tenant_id, product_id);
create index idx_compositions_mol on public.compositions (tenant_id, generic_medicine_id);
create index idx_compositions_str on public.compositions (tenant_id, strength_id);
call public.apply_tenant_rls('public.compositions');

-- Product Packaging
create table public.product_packages (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants(id) on delete cascade,
  product_id      uuid not null references public.products(id) on delete cascade,
  packaging_level text not null default 'primary' check (packaging_level in ('primary','secondary','tertiary')),
  items_per_pack  integer not null default 1,
  gross_weight_kg numeric(8,3),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  version         bigint not null default 1
);
create index idx_prod_packages_prod on public.product_packages (tenant_id, product_id);
call public.apply_tenant_rls('public.product_packages');

-- Product Price Schedules
create table public.product_prices (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  product_id     uuid not null references public.products(id) on delete cascade,
  price_list_id  uuid not null references public.price_lists(id) on delete cascade,
  mrp            numeric(14,2) not null default 0.00,
  ptr            numeric(14,2) not null default 0.00,
  pts            numeric(14,2) not null default 0.00,
  ptd            numeric(14,2) not null default 0.00,
  pt_dr          numeric(14,2) not null default 0.00,
  effective_from timestamptz not null default now(),
  effective_to   timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  version        bigint not null default 1
);
create index idx_prod_prices_prod on public.product_prices (tenant_id, product_id);
create index idx_prod_prices_list on public.product_prices (tenant_id, price_list_id);
call public.apply_tenant_rls('public.product_prices');

-- Product Images
create table public.product_images (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenants(id) on delete cascade,
  product_id    uuid not null references public.products(id) on delete cascade,
  file_id       uuid not null references public.file_storage(id) on delete cascade,
  is_primary    boolean not null default false,
  display_order integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  version       bigint not null default 1
);
create index idx_prod_images_prod on public.product_images (tenant_id, product_id);
create index idx_prod_images_file on public.product_images (tenant_id, file_id);
call public.apply_tenant_rls('public.product_images');

-- Product Documents
create table public.product_documents (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenants(id) on delete cascade,
  product_id    uuid not null references public.products(id) on delete cascade,
  file_id       uuid not null references public.file_storage(id) on delete cascade,
  document_type text not null default 'brochure' check (document_type in ('prescribing_info','clinical_study','certificate_of_analysis','brochure')),
  title         text not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  version       bigint not null default 1
);
create index idx_prod_docs_prod on public.product_documents (tenant_id, product_id);
create index idx_prod_docs_file on public.product_documents (tenant_id, file_id);
call public.apply_tenant_rls('public.product_documents');

-- ============================================================================
-- 2. WAREHOUSE & INVENTORY MANAGEMENT
-- ============================================================================

-- Warehouses / Depots
create table public.warehouses (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  branch_id      uuid references public.branches(id) on delete set null,
  code           text not null,
  name           text not null,
  warehouse_type text not null default 'regional' check (warehouse_type in ('central_depot','cnf','regional','transit')),
  address        text,
  manager_id     uuid references public.app_users(id) on delete set null,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  version        bigint not null default 1,
  unique (tenant_id, code)
);
create index idx_warehouses_branch on public.warehouses (tenant_id, branch_id);
create index idx_warehouses_manager on public.warehouses (tenant_id, manager_id);
call public.apply_tenant_rls('public.warehouses');

-- Warehouse Storage Locations (Bins / Racks)
create table public.warehouse_locations (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenants(id) on delete cascade,
  warehouse_id uuid not null references public.warehouses(id) on delete cascade,
  aisle        text,
  rack         text,
  shelf        text,
  bin_code     text not null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  version      bigint not null default 1,
  unique (tenant_id, warehouse_id, bin_code)
);
create index idx_wh_locations_wh on public.warehouse_locations (tenant_id, warehouse_id);
call public.apply_tenant_rls('public.warehouse_locations');

-- Product Batches (Regulatory Expiry Dates & Batch Quality)
create table public.product_batches (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references public.tenants(id) on delete cascade,
  product_id         uuid not null references public.products(id) on delete cascade,
  batch_number       text not null,
  manufacturing_date date,
  expiry_date        date not null,
  mrp                numeric(14,2) not null default 0.00,
  ptr                numeric(14,2) not null default 0.00,
  cost_price         numeric(14,2) not null default 0.00,
  is_quarantined     boolean not null default false,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  version            bigint not null default 1,
  unique (tenant_id, product_id, batch_number)
);
create index idx_batches_product on public.product_batches (tenant_id, product_id);
create index idx_batches_expiry on public.product_batches (tenant_id, expiry_date);
call public.apply_tenant_rls('public.product_batches');

-- Real-Time Stock Balance
create table public.inventory_stocks (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references public.tenants(id) on delete cascade,
  warehouse_id       uuid not null references public.warehouses(id) on delete cascade,
  product_id         uuid not null references public.products(id) on delete cascade,
  batch_id           uuid not null references public.product_batches(id) on delete cascade,
  quantity_on_hand   bigint not null default 0,
  quantity_allocated bigint not null default 0,
  quantity_available bigint not null default 0,
  reorder_level      bigint not null default 0,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  version            bigint not null default 1,
  unique (tenant_id, warehouse_id, product_id, batch_id)
);
create index idx_inv_stocks_wh on public.inventory_stocks (tenant_id, warehouse_id);
create index idx_inv_stocks_prod on public.inventory_stocks (tenant_id, product_id);
create index idx_inv_stocks_batch on public.inventory_stocks (tenant_id, batch_id);
call public.apply_tenant_rls('public.inventory_stocks');

-- Double-Entry Stock Movement Ledger
create table public.stock_transactions (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  warehouse_id     uuid not null references public.warehouses(id) on delete cascade,
  product_id       uuid not null references public.products(id) on delete cascade,
  batch_id         uuid not null references public.product_batches(id) on delete cascade,
  transaction_type text not null check (transaction_type in ('grn','dispatch','transfer_in','transfer_out','adjustment_in','adjustment_out','sample_issue')),
  reference_type   text,
  reference_id     uuid,
  quantity         bigint not null,
  unit_cost        numeric(14,2) not null default 0.00,
  balance_after    bigint not null default 0,
  remarks          text,
  transaction_date timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  version          bigint not null default 1
);
create index idx_stock_tx_wh on public.stock_transactions (tenant_id, warehouse_id);
create index idx_stock_tx_prod on public.stock_transactions (tenant_id, product_id);
create index idx_stock_tx_batch on public.stock_transactions (tenant_id, batch_id);
call public.apply_tenant_rls('public.stock_transactions');

-- Inter-Warehouse Stock Transfers
create table public.stock_transfers (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.tenants(id) on delete cascade,
  transfer_number     text not null,
  from_warehouse_id   uuid not null references public.warehouses(id) on delete cascade,
  to_warehouse_id     uuid not null references public.warehouses(id) on delete cascade,
  status              text not null default 'draft' check (status in ('draft','in_transit','received','cancelled')),
  dispatch_date       timestamptz,
  receive_date        timestamptz,
  requested_by_user_id uuid references public.app_users(id) on delete set null,
  approved_by_user_id  uuid references public.app_users(id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  version             bigint not null default 1,
  unique (tenant_id, transfer_number)
);
create index idx_transfers_from_wh on public.stock_transfers (tenant_id, from_warehouse_id);
create index idx_transfers_to_wh on public.stock_transfers (tenant_id, to_warehouse_id);
call public.apply_tenant_rls('public.stock_transfers');

-- Stock Transfer Line Items
create table public.stock_transfer_items (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references public.tenants(id) on delete cascade,
  stock_transfer_id uuid not null references public.stock_transfers(id) on delete cascade,
  product_id        uuid not null references public.products(id) on delete cascade,
  batch_id          uuid not null references public.product_batches(id) on delete cascade,
  quantity_sent     bigint not null check (quantity_sent > 0),
  quantity_received bigint not null default 0,
  remarks           text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  version           bigint not null default 1
);
create index idx_transfer_items_parent on public.stock_transfer_items (tenant_id, stock_transfer_id);
create index idx_transfer_items_prod on public.stock_transfer_items (tenant_id, product_id);
create index idx_transfer_items_batch on public.stock_transfer_items (tenant_id, batch_id);
call public.apply_tenant_rls('public.stock_transfer_items');

-- Physical Stock Audit Adjustments
create table public.stock_adjustments (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references public.tenants(id) on delete cascade,
  warehouse_id       uuid not null references public.warehouses(id) on delete cascade,
  adjustment_number  text not null,
  reason             text not null check (reason in ('physical_count_diff','damaged','expired','theft')),
  status             text not null default 'draft' check (status in ('draft','approved','rejected')),
  approved_by_user_id uuid references public.app_users(id) on delete set null,
  adjustment_date    timestamptz not null default now(),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  version            bigint not null default 1,
  unique (tenant_id, adjustment_number)
);
create index idx_adjustments_wh on public.stock_adjustments (tenant_id, warehouse_id);
call public.apply_tenant_rls('public.stock_adjustments');

-- Stock Adjustment Line Items
create table public.stock_adjustment_items (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.tenants(id) on delete cascade,
  stock_adjustment_id uuid not null references public.stock_adjustments(id) on delete cascade,
  product_id          uuid not null references public.products(id) on delete cascade,
  batch_id            uuid not null references public.product_batches(id) on delete cascade,
  system_quantity     bigint not null default 0,
  counted_quantity    bigint not null default 0,
  difference_quantity bigint not null default 0,
  unit_cost           numeric(14,2) not null default 0.00,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  version             bigint not null default 1
);
create index idx_adj_items_parent on public.stock_adjustment_items (tenant_id, stock_adjustment_id);
create index idx_adj_items_prod on public.stock_adjustment_items (tenant_id, product_id);
create index idx_adj_items_batch on public.stock_adjustment_items (tenant_id, batch_id);
call public.apply_tenant_rls('public.stock_adjustment_items');

-- Automated Reorder Alerts
create table public.stock_reorder_alerts (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  warehouse_id     uuid not null references public.warehouses(id) on delete cascade,
  product_id       uuid not null references public.products(id) on delete cascade,
  min_quantity     bigint not null default 100,
  reorder_quantity bigint not null default 500,
  last_alert_date  timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  version          bigint not null default 1,
  unique (tenant_id, warehouse_id, product_id)
);
create index idx_reorder_alerts_wh on public.stock_reorder_alerts (tenant_id, warehouse_id);
create index idx_reorder_alerts_prod on public.stock_reorder_alerts (tenant_id, product_id);
call public.apply_tenant_rls('public.stock_reorder_alerts');

-- Gift Items Master (Promotional gifts / Detailing aids)
create table public.gift_items (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  code        text not null,
  name        text not null,
  description text,
  category    text not null default 'reminder_item' check (category in ('reminder_item','medical_kit','executive_gift','festival_gift')),
  unit_cost   numeric(14,2) not null default 0.00,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  version     bigint not null default 1,
  unique (tenant_id, code)
);
call public.apply_tenant_rls('public.gift_items');

-- Gift Warehouse Inventory
create table public.gift_inventories (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references public.tenants(id) on delete cascade,
  warehouse_id       uuid not null references public.warehouses(id) on delete cascade,
  gift_item_id       uuid not null references public.gift_items(id) on delete cascade,
  quantity_on_hand   bigint not null default 0,
  quantity_allocated bigint not null default 0,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  version            bigint not null default 1,
  unique (tenant_id, warehouse_id, gift_item_id)
);
create index idx_gift_inv_wh on public.gift_inventories (tenant_id, warehouse_id);
create index idx_gift_inv_item on public.gift_inventories (tenant_id, gift_item_id);
call public.apply_tenant_rls('public.gift_inventories');

-- Gift Stock Transactions
create table public.gift_stock_transactions (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  warehouse_id     uuid not null references public.warehouses(id) on delete cascade,
  gift_item_id     uuid not null references public.gift_items(id) on delete cascade,
  transaction_type text not null check (transaction_type in ('purchase','issue_to_mr','adjustment')),
  reference_type   text,
  reference_id     uuid,
  quantity         bigint not null,
  balance_after    bigint not null default 0,
  transaction_date timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  version          bigint not null default 1
);
create index idx_gift_tx_wh on public.gift_stock_transactions (tenant_id, warehouse_id);
create index idx_gift_tx_item on public.gift_stock_transactions (tenant_id, gift_item_id);
call public.apply_tenant_rls('public.gift_stock_transactions');

-- MR Sample Drug Allocations
create table public.sample_allocations (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references public.tenants(id) on delete cascade,
  mr_id                 uuid not null references public.app_users(id) on delete cascade,
  product_id            uuid not null references public.products(id) on delete cascade,
  batch_id              uuid not null references public.product_batches(id) on delete cascade,
  allocated_quantity    bigint not null default 0,
  distributed_quantity  bigint not null default 0,
  period_start          date not null,
  period_end            date not null,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  deleted_at            timestamptz,
  version               bigint not null default 1
);
create index idx_sample_alloc_mr on public.sample_allocations (tenant_id, mr_id, period_start);
create index idx_sample_alloc_prod on public.sample_allocations (tenant_id, product_id);
create index idx_sample_alloc_batch on public.sample_allocations (tenant_id, batch_id);
call public.apply_tenant_rls('public.sample_allocations');

-- MR Gift Item Allocations
create table public.gift_allocations (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references public.tenants(id) on delete cascade,
  mr_id                 uuid not null references public.app_users(id) on delete cascade,
  gift_item_id          uuid not null references public.gift_items(id) on delete cascade,
  allocated_quantity    bigint not null default 0,
  distributed_quantity  bigint not null default 0,
  period_start          date not null,
  period_end            date not null,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  deleted_at            timestamptz,
  version               bigint not null default 1
);
create index idx_gift_alloc_mr on public.gift_allocations (tenant_id, mr_id, period_start);
create index idx_gift_alloc_item on public.gift_allocations (tenant_id, gift_item_id);
call public.apply_tenant_rls('public.gift_allocations');

-- ============================================================================
-- 3. PURCHASE & PROCUREMENT (PROPOSED MODULE)
-- ============================================================================

-- PROPOSED: Supplier Categories
create table public.supplier_categories (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  code        text not null,
  name        text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  version     bigint not null default 1,
  unique (tenant_id, code)
);
call public.apply_tenant_rls('public.supplier_categories');

-- PROPOSED: Suppliers Master
create table public.suppliers (
  id                   uuid primary key default gen_random_uuid(),
  tenant_id            uuid not null references public.tenants(id) on delete cascade,
  supplier_code        text not null,
  name                 text not null,
  supplier_category_id uuid references public.supplier_categories(id) on delete set null,
  gst_number           text,
  drug_license_no      text,
  pan_number           text,
  credit_limit         numeric(14,2) not null default 0.00,
  status               text not null default 'active' check (status in ('active','blocked','under_review')),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz,
  version              bigint not null default 1,
  unique (tenant_id, supplier_code)
);
create index idx_suppliers_category on public.suppliers (tenant_id, supplier_category_id);
call public.apply_tenant_rls('public.suppliers');

-- PROPOSED: Purchase Requisitions
create table public.purchase_requisitions (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.tenants(id) on delete cascade,
  requisition_number  text not null,
  requested_by_user_id uuid references public.app_users(id) on delete set null,
  department_id       uuid references public.departments(id) on delete set null,
  required_date       date,
  status              text not null default 'draft' check (status in ('draft','submitted','approved','rejected','ordered')),
  remarks             text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  version             bigint not null default 1,
  unique (tenant_id, requisition_number)
);
create index idx_pr_requester on public.purchase_requisitions (tenant_id, requested_by_user_id);
create index idx_pr_dept on public.purchase_requisitions (tenant_id, department_id);
call public.apply_tenant_rls('public.purchase_requisitions');

-- PROPOSED: Purchase Requisition Items
create table public.purchase_requisition_items (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references public.tenants(id) on delete cascade,
  requisition_id     uuid not null references public.purchase_requisitions(id) on delete cascade,
  product_id         uuid not null references public.products(id) on delete cascade,
  requested_quantity bigint not null check (requested_quantity > 0),
  estimated_rate     numeric(14,2) not null default 0.00,
  purpose            text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  version            bigint not null default 1
);
create index idx_pr_items_parent on public.purchase_requisition_items (tenant_id, requisition_id);
create index idx_pr_items_prod on public.purchase_requisition_items (tenant_id, product_id);
call public.apply_tenant_rls('public.purchase_requisition_items');

-- PROPOSED: Purchase Orders (PO)
create table public.purchase_orders (
  id                   uuid primary key default gen_random_uuid(),
  tenant_id            uuid not null references public.tenants(id) on delete cascade,
  po_number            text not null,
  supplier_id          uuid not null references public.suppliers(id) on delete cascade,
  warehouse_id         uuid not null references public.warehouses(id) on delete cascade,
  order_date           date not null default current_date,
  expected_delivery_date date,
  subtotal             numeric(14,2) not null default 0.00,
  tax_amount           numeric(14,2) not null default 0.00,
  total_amount         numeric(14,2) not null default 0.00,
  status               text not null default 'draft' check (status in ('draft','issued','partially_received','completed','cancelled')),
  approved_by_user_id  uuid references public.app_users(id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz,
  version              bigint not null default 1,
  unique (tenant_id, po_number)
);
create index idx_po_supplier on public.purchase_orders (tenant_id, supplier_id);
create index idx_po_warehouse on public.purchase_orders (tenant_id, warehouse_id);
create index idx_po_approver on public.purchase_orders (tenant_id, approved_by_user_id);
call public.apply_tenant_rls('public.purchase_orders');

-- PROPOSED: Purchase Order Items
create table public.purchase_order_items (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references public.tenants(id) on delete cascade,
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  product_id        uuid not null references public.products(id) on delete cascade,
  ordered_quantity  bigint not null check (ordered_quantity > 0),
  unit_price        numeric(14,2) not null default 0.00,
  tax_rate          numeric(5,2) not null default 0.00,
  tax_amount        numeric(14,2) not null default 0.00,
  line_total        numeric(14,2) not null default 0.00,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  version           bigint not null default 1
);
create index idx_po_items_parent on public.purchase_order_items (tenant_id, purchase_order_id);
create index idx_po_items_prod on public.purchase_order_items (tenant_id, product_id);
call public.apply_tenant_rls('public.purchase_order_items');

-- PROPOSED: Goods Receipt Notes (GRN)
create table public.goods_receipt_notes (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references public.tenants(id) on delete cascade,
  grn_number        text not null,
  purchase_order_id uuid references public.purchase_orders(id) on delete set null,
  supplier_id       uuid not null references public.suppliers(id) on delete cascade,
  warehouse_id      uuid not null references public.warehouses(id) on delete cascade,
  invoice_number    text,
  invoice_date      date,
  received_date     timestamptz not null default now(),
  status            text not null default 'draft' check (status in ('draft','verified','posted')),
  remarks           text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  version           bigint not null default 1,
  unique (tenant_id, grn_number)
);
create index idx_grn_po on public.goods_receipt_notes (tenant_id, purchase_order_id);
create index idx_grn_supplier on public.goods_receipt_notes (tenant_id, supplier_id);
create index idx_grn_warehouse on public.goods_receipt_notes (tenant_id, warehouse_id);
call public.apply_tenant_rls('public.goods_receipt_notes');

-- PROPOSED: Goods Receipt Items (QA inspection)
create table public.goods_receipt_items (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references public.tenants(id) on delete cascade,
  grn_id            uuid not null references public.goods_receipt_notes(id) on delete cascade,
  po_item_id        uuid references public.purchase_order_items(id) on delete set null,
  product_id        uuid not null references public.products(id) on delete cascade,
  batch_number      text not null,
  mfg_date          date,
  expiry_date       date not null,
  quantity_received bigint not null default 0,
  quantity_accepted bigint not null default 0,
  quantity_rejected bigint not null default 0,
  unit_price        numeric(14,2) not null default 0.00,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  version           bigint not null default 1
);
create index idx_grn_items_parent on public.goods_receipt_items (tenant_id, grn_id);
create index idx_grn_items_prod on public.goods_receipt_items (tenant_id, product_id);
create index idx_grn_items_po_item on public.goods_receipt_items (tenant_id, po_item_id);
call public.apply_tenant_rls('public.goods_receipt_items');

-- PROPOSED: Purchase Bills (Accounts Payable)
create table public.purchase_bills (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants(id) on delete cascade,
  bill_number     text not null,
  supplier_id     uuid not null references public.suppliers(id) on delete cascade,
  grn_id          uuid references public.goods_receipt_notes(id) on delete set null,
  po_id           uuid references public.purchase_orders(id) on delete set null,
  bill_date       date not null default current_date,
  due_date        date,
  subtotal        numeric(14,2) not null default 0.00,
  tax_amount      numeric(14,2) not null default 0.00,
  discount_amount numeric(14,2) not null default 0.00,
  total_amount    numeric(14,2) not null default 0.00,
  status          text not null default 'pending' check (status in ('pending','partially_paid','paid','void')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  version         bigint not null default 1,
  unique (tenant_id, bill_number)
);
create index idx_pb_supplier on public.purchase_bills (tenant_id, supplier_id);
create index idx_pb_grn on public.purchase_bills (tenant_id, grn_id);
create index idx_pb_po on public.purchase_bills (tenant_id, po_id);
call public.apply_tenant_rls('public.purchase_bills');

-- PROPOSED: Purchase Bill Items
create table public.purchase_bill_items (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  purchase_bill_id uuid not null references public.purchase_bills(id) on delete cascade,
  grn_item_id      uuid references public.goods_receipt_items(id) on delete set null,
  product_id       uuid not null references public.products(id) on delete cascade,
  quantity         bigint not null check (quantity > 0),
  unit_price       numeric(14,2) not null default 0.00,
  tax_amount       numeric(14,2) not null default 0.00,
  line_total       numeric(14,2) not null default 0.00,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  version          bigint not null default 1
);
create index idx_pb_items_parent on public.purchase_bill_items (tenant_id, purchase_bill_id);
create index idx_pb_items_prod on public.purchase_bill_items (tenant_id, product_id);
call public.apply_tenant_rls('public.purchase_bill_items');

-- PROPOSED: Purchase Returns / Debit Notes
create table public.purchase_returns (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenants(id) on delete cascade,
  return_number text not null,
  supplier_id   uuid not null references public.suppliers(id) on delete cascade,
  warehouse_id  uuid not null references public.warehouses(id) on delete cascade,
  return_date   date not null default current_date,
  reason        text not null check (reason in ('qc_failed','damaged','short_expiry')),
  subtotal      numeric(14,2) not null default 0.00,
  tax_amount    numeric(14,2) not null default 0.00,
  total_amount  numeric(14,2) not null default 0.00,
  status        text not null default 'draft' check (status in ('draft','approved','completed')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  version       bigint not null default 1,
  unique (tenant_id, return_number)
);
create index idx_pr_returns_supplier on public.purchase_returns (tenant_id, supplier_id);
create index idx_pr_returns_wh on public.purchase_returns (tenant_id, warehouse_id);
call public.apply_tenant_rls('public.purchase_returns');

-- PROPOSED: Purchase Return Items
create table public.purchase_return_items (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references public.tenants(id) on delete cascade,
  purchase_return_id uuid not null references public.purchase_returns(id) on delete cascade,
  product_id         uuid not null references public.products(id) on delete cascade,
  batch_id           uuid not null references public.product_batches(id) on delete cascade,
  quantity           bigint not null check (quantity > 0),
  unit_price         numeric(14,2) not null default 0.00,
  tax_amount         numeric(14,2) not null default 0.00,
  line_total         numeric(14,2) not null default 0.00,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  version            bigint not null default 1
);
create index idx_pr_ret_items_parent on public.purchase_return_items (tenant_id, purchase_return_id);
create index idx_pr_ret_items_prod on public.purchase_return_items (tenant_id, product_id);
create index idx_pr_ret_items_batch on public.purchase_return_items (tenant_id, batch_id);
call public.apply_tenant_rls('public.purchase_return_items');

-- ============================================================================
-- 4. SALES (PRIMARY & SECONDARY SALES)
-- ============================================================================

-- Customer Categories
create table public.customer_categories (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenants(id) on delete cascade,
  code       text not null,
  name       text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version    bigint not null default 1,
  unique (tenant_id, code)
);
call public.apply_tenant_rls('public.customer_categories');

-- Primary Orders (Stockist -> Company wholesale order)
create table public.primary_orders (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenants(id) on delete cascade,
  order_number text not null,
  stockist_id  uuid not null references public.stockists(id) on delete cascade,
  division_id  uuid references public.business_divisions(id) on delete set null,
  order_date   date not null default current_date,
  status       text not null default 'draft' check (status in ('draft','submitted','approved','processing','dispatched','cancelled')),
  subtotal     numeric(14,2) not null default 0.00,
  tax_amount   numeric(14,2) not null default 0.00,
  total_amount numeric(14,2) not null default 0.00,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  version      bigint not null default 1,
  unique (tenant_id, order_number)
);
create index idx_primary_orders_stockist on public.primary_orders (tenant_id, stockist_id);
create index idx_primary_orders_division on public.primary_orders (tenant_id, division_id);
call public.apply_tenant_rls('public.primary_orders');

-- Primary Order Line Items
create table public.primary_order_items (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  primary_order_id uuid not null references public.primary_orders(id) on delete cascade,
  product_id       uuid not null references public.products(id) on delete cascade,
  ordered_quantity bigint not null check (ordered_quantity > 0),
  unit_price       numeric(14,2) not null default 0.00,
  discount_percent numeric(5,2) not null default 0.00,
  tax_amount       numeric(14,2) not null default 0.00,
  line_total       numeric(14,2) not null default 0.00,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  version          bigint not null default 1
);
create index idx_po_items_order on public.primary_order_items (tenant_id, primary_order_id);
create index idx_po_items_product on public.primary_order_items (tenant_id, product_id);
call public.apply_tenant_rls('public.primary_order_items');

-- Primary Tax Invoices
create table public.primary_invoices (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  invoice_number   text not null,
  primary_order_id uuid references public.primary_orders(id) on delete set null,
  stockist_id      uuid not null references public.stockists(id) on delete cascade,
  invoice_date     date not null default current_date,
  due_date         date,
  subtotal         numeric(14,2) not null default 0.00,
  tax_amount       numeric(14,2) not null default 0.00,
  total_amount     numeric(14,2) not null default 0.00,
  status           text not null default 'issued' check (status in ('issued','partially_paid','paid','cancelled')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  version          bigint not null default 1,
  unique (tenant_id, invoice_number)
);
create index idx_primary_inv_order on public.primary_invoices (tenant_id, primary_order_id);
create index idx_primary_inv_stockist on public.primary_invoices (tenant_id, stockist_id);
call public.apply_tenant_rls('public.primary_invoices');

-- Primary Invoice Items (with Batch allocation)
create table public.primary_invoice_items (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references public.tenants(id) on delete cascade,
  primary_invoice_id uuid not null references public.primary_invoices(id) on delete cascade,
  product_id         uuid not null references public.products(id) on delete cascade,
  batch_id           uuid not null references public.product_batches(id) on delete cascade,
  quantity           bigint not null check (quantity > 0),
  free_quantity      bigint not null default 0,
  unit_price         numeric(14,2) not null default 0.00,
  discount_amount    numeric(14,2) not null default 0.00,
  tax_amount         numeric(14,2) not null default 0.00,
  line_total         numeric(14,2) not null default 0.00,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  version            bigint not null default 1
);
create index idx_primary_inv_items_inv on public.primary_invoice_items (tenant_id, primary_invoice_id);
create index idx_primary_inv_items_prod on public.primary_invoice_items (tenant_id, product_id);
create index idx_primary_inv_items_batch on public.primary_invoice_items (tenant_id, batch_id);
call public.apply_tenant_rls('public.primary_invoice_items');

-- Primary Sales Aggregates
create table public.primary_sales (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants(id) on delete cascade,
  stockist_id     uuid not null references public.stockists(id) on delete cascade,
  invoice_id      uuid references public.primary_invoices(id) on delete set null,
  sale_date       date not null default current_date,
  total_value     numeric(14,2) not null default 0.00,
  reporting_month integer not null check (reporting_month between 1 and 12),
  reporting_year  integer not null check (reporting_year between 2020 and 2100),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  version         bigint not null default 1
);
create index idx_primary_sales_stockist on public.primary_sales (tenant_id, stockist_id);
create index idx_primary_sales_period on public.primary_sales (tenant_id, reporting_year, reporting_month);
call public.apply_tenant_rls('public.primary_sales');

-- Primary Sales Items
create table public.primary_sales_items (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  primary_sales_id uuid not null references public.primary_sales(id) on delete cascade,
  product_id       uuid not null references public.products(id) on delete cascade,
  quantity         bigint not null check (quantity > 0),
  rate             numeric(14,2) not null default 0.00,
  total_amount     numeric(14,2) not null default 0.00,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  version          bigint not null default 1
);
create index idx_ps_items_parent on public.primary_sales_items (tenant_id, primary_sales_id);
create index idx_ps_items_prod on public.primary_sales_items (tenant_id, product_id);
call public.apply_tenant_rls('public.primary_sales_items');

-- Delivery Challans / Logistics Lorry Receipts
create table public.delivery_challans (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  challan_number   text not null,
  invoice_id       uuid references public.primary_invoices(id) on delete set null,
  warehouse_id     uuid not null references public.warehouses(id) on delete cascade,
  transporter_name text,
  lr_number        text,
  dispatch_date    timestamptz not null default now(),
  delivery_date    timestamptz,
  status           text not null default 'dispatched' check (status in ('prepared','dispatched','in_transit','delivered')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  version          bigint not null default 1,
  unique (tenant_id, challan_number)
);
create index idx_challans_inv on public.delivery_challans (tenant_id, invoice_id);
create index idx_challans_wh on public.delivery_challans (tenant_id, warehouse_id);
call public.apply_tenant_rls('public.delivery_challans');

-- Sales Returns / Market Breakage & Expiry
create table public.sales_returns (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenants(id) on delete cascade,
  return_number text not null,
  return_type   text not null default 'expired' check (return_type in ('saleable','breakage','expired')),
  customer_type text not null check (customer_type in ('stockist','chemist')),
  entity_id     uuid not null,
  warehouse_id  uuid not null references public.warehouses(id) on delete cascade,
  return_date   date not null default current_date,
  reason        text,
  subtotal      numeric(14,2) not null default 0.00,
  tax_amount    numeric(14,2) not null default 0.00,
  total_amount  numeric(14,2) not null default 0.00,
  status        text not null default 'draft' check (status in ('draft','verified','credited')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  version       bigint not null default 1,
  unique (tenant_id, return_number)
);
create index idx_sr_customer on public.sales_returns (tenant_id, customer_type, entity_id);
create index idx_sr_warehouse on public.sales_returns (tenant_id, warehouse_id);
call public.apply_tenant_rls('public.sales_returns');

-- Sales Return Line Items
create table public.sales_return_items (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants(id) on delete cascade,
  sales_return_id uuid not null references public.sales_returns(id) on delete cascade,
  product_id      uuid not null references public.products(id) on delete cascade,
  batch_id        uuid not null references public.product_batches(id) on delete cascade,
  quantity        bigint not null check (quantity > 0),
  unit_price      numeric(14,2) not null default 0.00,
  tax_amount      numeric(14,2) not null default 0.00,
  line_total      numeric(14,2) not null default 0.00,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  version         bigint not null default 1
);
create index idx_sr_items_parent on public.sales_return_items (tenant_id, sales_return_id);
create index idx_sr_items_prod on public.sales_return_items (tenant_id, product_id);
create index idx_sr_items_batch on public.sales_return_items (tenant_id, batch_id);
call public.apply_tenant_rls('public.sales_return_items');

-- Customer Payments (Accounts Receivable)
create table public.customer_payments (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  receipt_number   text not null,
  customer_type    text not null check (customer_type in ('stockist','chemist')),
  entity_id        uuid not null,
  payment_date     date not null default current_date,
  payment_mode     text not null default 'cheque' check (payment_mode in ('cash','cheque','neft','rtgs','upi')),
  reference_number text,
  amount           numeric(14,2) not null default 0.00,
  status           text not null default 'cleared' check (status in ('pending','cleared','bounced')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  version          bigint not null default 1,
  unique (tenant_id, receipt_number)
);
create index idx_cust_payments_customer on public.customer_payments (tenant_id, customer_type, entity_id);
call public.apply_tenant_rls('public.customer_payments');

-- Payment Allocations to Invoices
create table public.payment_allocations (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  payment_id       uuid not null references public.customer_payments(id) on delete cascade,
  invoice_id       uuid not null references public.primary_invoices(id) on delete cascade,
  allocated_amount numeric(14,2) not null default 0.00,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  version          bigint not null default 1
);
create index idx_pay_alloc_pay on public.payment_allocations (tenant_id, payment_id);
create index idx_pay_alloc_inv on public.payment_allocations (tenant_id, invoice_id);
call public.apply_tenant_rls('public.payment_allocations');

-- Field Collections (MR cash/cheque collected from chemists/stockists)
create table public.collections (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants(id) on delete cascade,
  mr_id           uuid not null references public.app_users(id) on delete cascade,
  customer_type   text not null check (customer_type in ('stockist','chemist')),
  entity_id       uuid not null,
  collection_date date not null default current_date,
  amount          numeric(14,2) not null default 0.00,
  payment_mode    text not null default 'cheque' check (payment_mode in ('cheque','cash','online')),
  cheque_number   text,
  cheque_date     date,
  status          text not null default 'collected' check (status in ('collected','deposited','verified')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  version         bigint not null default 1
);
create index idx_collections_mr on public.collections (tenant_id, mr_id, collection_date desc);
create index idx_collections_customer on public.collections (tenant_id, customer_type, entity_id);
call public.apply_tenant_rls('public.collections');

-- Customer Credit Limits
create table public.credit_limits (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  customer_type    text not null check (customer_type in ('stockist','chemist')),
  entity_id        uuid not null,
  credit_limit     numeric(14,2) not null default 0.00,
  current_exposure numeric(14,2) not null default 0.00,
  overdue_amount   numeric(14,2) not null default 0.00,
  status           text not null default 'regular' check (status in ('regular','warning','stopped')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  version          bigint not null default 1,
  unique (tenant_id, customer_type, entity_id)
);
call public.apply_tenant_rls('public.credit_limits');

-- Sales Representative Stockist Alignment
create table public.sales_representatives_mapping (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  user_id     uuid not null references public.app_users(id) on delete cascade,
  stockist_id uuid not null references public.stockists(id) on delete cascade,
  is_primary  boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  version     bigint not null default 1,
  unique (tenant_id, user_id, stockist_id)
);
create index idx_srm_user on public.sales_representatives_mapping (tenant_id, user_id);
create index idx_srm_stockist on public.sales_representatives_mapping (tenant_id, stockist_id);
call public.apply_tenant_rls('public.sales_representatives_mapping');
