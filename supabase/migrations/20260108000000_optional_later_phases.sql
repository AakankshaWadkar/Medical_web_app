-- Migration: 20260108000000_optional_later_phases.sql
-- Description: Stage (g) OPTIONAL LATER-PHASE TABLES: Finance, Secondary Sales, Reports (Views), and API & Integration (api_keys, webhooks)
-- Conventions: tenant_id uuid not null, apply_tenant_rls, numeric(14,2), timestamptz, check constraints

--------------------------------------------------------------------------------
-- SECTION 1: FINANCE & ACCOUNTING LEDGER (OPTIONAL)
--------------------------------------------------------------------------------

-- 1. Account Groups
create table public.account_groups (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  group_code text not null,
  group_name text not null,
  category text not null check (category in ('asset', 'liability', 'equity', 'income', 'expense')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_account_groups_code unique (tenant_id, group_code)
);

call public.apply_tenant_rls('public.account_groups');

-- 2. Chart of Accounts
create table public.chart_of_accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  account_code text not null,
  account_name text not null,
  account_type text not null,
  account_group_id uuid not null references public.account_groups(id) on delete restrict,
  parent_id uuid references public.chart_of_accounts(id) on delete set null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_chart_of_accounts_code unique (tenant_id, account_code)
);

call public.apply_tenant_rls('public.chart_of_accounts');
create index idx_chart_of_accounts_group on public.chart_of_accounts (tenant_id, account_group_id);
create index idx_chart_of_accounts_parent on public.chart_of_accounts (tenant_id, parent_id);

-- 3. Tax Masters
create table public.tax_masters (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  tax_code text not null,
  tax_name text not null,
  rate numeric(5,2) not null check (rate >= 0),
  tax_type text not null check (tax_type in ('gst', 'tds', 'tcs', 'cess')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_tax_masters_code unique (tenant_id, tax_code)
);

call public.apply_tenant_rls('public.tax_masters');

-- 4. TDS Sections
create table public.tds_sections (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  section_code text not null,
  description text,
  rate_individual numeric(5,2) not null default 0.00 check (rate_individual >= 0),
  rate_corporate numeric(5,2) not null default 0.00 check (rate_corporate >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_tds_sections_code unique (tenant_id, section_code)
);

call public.apply_tenant_rls('public.tds_sections');

-- 5. Bank Accounts
create table public.bank_accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  bank_name text not null,
  account_number text not null,
  ifsc_code text,
  branch_name text,
  opening_balance numeric(14,2) not null default 0.00,
  current_balance numeric(14,2) not null default 0.00,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_bank_accounts_number unique (tenant_id, account_number)
);

call public.apply_tenant_rls('public.bank_accounts');

-- 6. Bank Transactions
create table public.bank_transactions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  bank_account_id uuid not null references public.bank_accounts(id) on delete cascade,
  transaction_date date not null default current_date,
  transaction_type text not null check (transaction_type in ('deposit', 'withdrawal', 'transfer')),
  reference_no text,
  amount numeric(14,2) not null check (amount > 0),
  balance_after numeric(14,2) not null default 0.00,
  status text not null default 'pending' check (status in ('cleared', 'pending', 'reconciled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.bank_transactions');
create index idx_bank_transactions_composite on public.bank_transactions (tenant_id, bank_account_id, transaction_date desc);

-- 7. Bank Reconciliations
create table public.bank_reconciliations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  bank_account_id uuid not null references public.bank_accounts(id) on delete cascade,
  statement_date date not null,
  statement_balance numeric(14,2) not null default 0.00,
  book_balance numeric(14,2) not null default 0.00,
  difference numeric(14,2) not null default 0.00,
  status text not null default 'discrepancy' check (status in ('balanced', 'discrepancy')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.bank_reconciliations');
create index idx_bank_recon_date on public.bank_reconciliations (tenant_id, bank_account_id, statement_date);

-- 8. Journal Entries
create table public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  entry_number text not null,
  entry_date date not null default current_date,
  reference_type text,
  reference_id uuid,
  narration text,
  status text not null default 'draft' check (status in ('draft', 'posted', 'voided')),
  posted_by_user_id uuid references public.app_users(id) on delete set null,
  posted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_journal_entries_number unique (tenant_id, entry_number)
);

call public.apply_tenant_rls('public.journal_entries');
create index idx_journal_entries_posted_by on public.journal_entries (tenant_id, posted_by_user_id);

-- 9. Journal Entry Lines
create table public.journal_entry_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  journal_entry_id uuid not null references public.journal_entries(id) on delete cascade,
  account_id uuid not null references public.chart_of_accounts(id) on delete restrict,
  debit_amount numeric(14,2) not null default 0.00 check (debit_amount >= 0),
  credit_amount numeric(14,2) not null default 0.00 check (credit_amount >= 0),
  narration text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.journal_entry_lines');
create index idx_je_lines_entry on public.journal_entry_lines (tenant_id, journal_entry_id);
create index idx_je_lines_account on public.journal_entry_lines (tenant_id, account_id);

-- 10. General Ledgers
create table public.general_ledgers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  account_id uuid not null references public.chart_of_accounts(id) on delete restrict,
  transaction_date date not null default current_date,
  journal_entry_id uuid references public.journal_entries(id) on delete cascade,
  debit numeric(14,2) not null default 0.00 check (debit >= 0),
  credit numeric(14,2) not null default 0.00 check (credit >= 0),
  balance numeric(14,2) not null default 0.00,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.general_ledgers');
create index idx_gl_account_date on public.general_ledgers (tenant_id, account_id, transaction_date desc);
create index idx_gl_journal_entry on public.general_ledgers (tenant_id, journal_entry_id);

-- 11. Customer Ledgers
create table public.customer_ledgers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  customer_type text not null check (customer_type in ('stockist', 'chemist')),
  entity_id uuid not null,
  transaction_date date not null default current_date,
  reference_type text,
  reference_id uuid,
  debit numeric(14,2) not null default 0.00 check (debit >= 0),
  credit numeric(14,2) not null default 0.00 check (credit >= 0),
  running_balance numeric(14,2) not null default 0.00,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.customer_ledgers');
create index idx_cust_ledger_composite on public.customer_ledgers (tenant_id, customer_type, entity_id, transaction_date desc);

-- 12. Supplier Ledgers
create table public.supplier_ledgers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  transaction_date date not null default current_date,
  reference_type text,
  reference_id uuid,
  debit numeric(14,2) not null default 0.00 check (debit >= 0),
  credit numeric(14,2) not null default 0.00 check (credit >= 0),
  running_balance numeric(14,2) not null default 0.00,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.supplier_ledgers');
create index idx_supp_ledger_composite on public.supplier_ledgers (tenant_id, supplier_id, transaction_date desc);

-- 13. TDS Deductions
create table public.tds_deductions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  bill_id uuid references public.purchase_bills(id) on delete set null,
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  section_id uuid not null references public.tds_sections(id) on delete restrict,
  base_amount numeric(14,2) not null check (base_amount >= 0),
  tds_amount numeric(14,2) not null check (tds_amount >= 0),
  payment_status text not null default 'deducted' check (payment_status in ('deducted', 'deposited')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.tds_deductions');
create index idx_tds_bill on public.tds_deductions (tenant_id, bill_id);
create index idx_tds_supplier on public.tds_deductions (tenant_id, supplier_id);
create index idx_tds_section on public.tds_deductions (tenant_id, section_id);

-- 14. GST Returns
create table public.gst_returns (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  return_type text not null check (return_type in ('gstr1', 'gstr3b', 'gstr9')),
  return_period text not null,
  filing_date date,
  ack_number text,
  status text not null default 'draft' check (status in ('draft', 'filed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_gst_returns_period unique (tenant_id, return_type, return_period)
);

call public.apply_tenant_rls('public.gst_returns');

-- 15. Credit Notes
create table public.credit_notes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  credit_note_number text not null,
  invoice_id uuid references public.primary_invoices(id) on delete set null,
  customer_type text not null check (customer_type in ('stockist', 'chemist')),
  entity_id uuid not null,
  date date not null default current_date,
  amount numeric(14,2) not null check (amount >= 0),
  reason text,
  status text not null default 'draft' check (status in ('draft', 'approved', 'adjusted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_credit_notes_number unique (tenant_id, credit_note_number)
);

call public.apply_tenant_rls('public.credit_notes');
create index idx_credit_notes_invoice on public.credit_notes (tenant_id, invoice_id);

-- 16. Credit Note Items
create table public.credit_note_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  credit_note_id uuid not null references public.credit_notes(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity bigint not null default 0 check (quantity >= 0),
  rate numeric(14,2) not null default 0.00 check (rate >= 0),
  tax_amount numeric(14,2) not null default 0.00 check (tax_amount >= 0),
  line_total numeric(14,2) not null default 0.00 check (line_total >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.credit_note_items');
create index idx_cn_items_note on public.credit_note_items (tenant_id, credit_note_id);
create index idx_cn_items_product on public.credit_note_items (tenant_id, product_id);

-- 17. Debit Notes
create table public.debit_notes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  debit_note_number text not null,
  bill_id uuid references public.purchase_bills(id) on delete set null,
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  date date not null default current_date,
  amount numeric(14,2) not null check (amount >= 0),
  reason text,
  status text not null default 'draft' check (status in ('draft', 'approved', 'adjusted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_debit_notes_number unique (tenant_id, debit_note_number)
);

call public.apply_tenant_rls('public.debit_notes');
create index idx_debit_notes_bill on public.debit_notes (tenant_id, bill_id);
create index idx_debit_notes_supplier on public.debit_notes (tenant_id, supplier_id);

-- 18. Debit Note Items
create table public.debit_note_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  debit_note_id uuid not null references public.debit_notes(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity bigint not null default 0 check (quantity >= 0),
  rate numeric(14,2) not null default 0.00 check (rate >= 0),
  tax_amount numeric(14,2) not null default 0.00 check (tax_amount >= 0),
  line_total numeric(14,2) not null default 0.00 check (line_total >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.debit_note_items');
create index idx_dn_items_note on public.debit_note_items (tenant_id, debit_note_id);
create index idx_dn_items_product on public.debit_note_items (tenant_id, product_id);

-- 19. Cheque Books
create table public.cheque_books (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  bank_account_id uuid not null references public.bank_accounts(id) on delete cascade,
  cheque_book_number text not null,
  start_cheque_no text not null,
  end_cheque_no text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_cheque_books_number unique (tenant_id, bank_account_id, cheque_book_number)
);

call public.apply_tenant_rls('public.cheque_books');
create index idx_cheque_books_bank on public.cheque_books (tenant_id, bank_account_id);

-- 20. Cheque Leaves
create table public.cheque_leaves (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  cheque_book_id uuid not null references public.cheque_books(id) on delete cascade,
  cheque_number text not null,
  status text not null default 'available' check (status in ('available', 'issued', 'cleared', 'bounced', 'cancelled')),
  issued_to text,
  issue_date date,
  clearance_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_cheque_leaves_num unique (tenant_id, cheque_book_id, cheque_number)
);

call public.apply_tenant_rls('public.cheque_leaves');
create index idx_cheque_leaves_book on public.cheque_leaves (tenant_id, cheque_book_id);


--------------------------------------------------------------------------------
-- SECTION 2: SECONDARY SALES
--------------------------------------------------------------------------------

-- 21. Secondary Sales
create table public.secondary_sales (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  stockist_id uuid not null references public.stockists(id) on delete cascade,
  chemist_id uuid references public.chemists(id) on delete set null,
  sale_date date not null default current_date,
  invoice_no text,
  total_value numeric(14,2) not null default 0.00 check (total_value >= 0),
  reporting_month integer not null check (reporting_month between 1 and 12),
  reporting_year integer not null check (reporting_year >= 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.secondary_sales');
create index idx_secondary_sales_period on public.secondary_sales (tenant_id, reporting_year, reporting_month);
create index idx_secondary_sales_stockist on public.secondary_sales (tenant_id, stockist_id);
create index idx_secondary_sales_chemist on public.secondary_sales (tenant_id, chemist_id);

-- 22. Secondary Sales Items
create table public.secondary_sales_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  secondary_sales_id uuid not null references public.secondary_sales(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  batch_id uuid references public.product_batches(id) on delete set null,
  quantity bigint not null default 0 check (quantity >= 0),
  free_quantity bigint not null default 0 check (free_quantity >= 0),
  rate numeric(14,2) not null default 0.00 check (rate >= 0),
  total_amount numeric(14,2) not null default 0.00 check (total_amount >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.secondary_sales_items');
create index idx_sec_sales_items_parent on public.secondary_sales_items (tenant_id, secondary_sales_id);
create index idx_sec_sales_items_product on public.secondary_sales_items (tenant_id, product_id);
create index idx_sec_sales_items_batch on public.secondary_sales_items (tenant_id, batch_id);


--------------------------------------------------------------------------------
-- SECTION 3: API & INTEGRATIONS (api_keys and webhooks only)
--------------------------------------------------------------------------------

-- 23. API Keys
create table public.api_keys (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  key_name text not null,
  key_prefix text not null,
  hashed_key text not null,
  scopes text[] not null default '{}',
  expires_at timestamptz,
  is_revoked boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_api_keys_prefix unique (tenant_id, key_prefix)
);

call public.apply_tenant_rls('public.api_keys');

-- 24. API Request Logs
create table public.api_request_logs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  api_key_id uuid references public.api_keys(id) on delete set null,
  endpoint text not null,
  method text not null,
  status_code integer not null,
  ip_address text,
  response_time_ms integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.api_request_logs');
create index idx_api_request_logs_composite on public.api_request_logs (tenant_id, api_key_id, created_at desc);

-- 25. Webhook Endpoints
create table public.webhook_endpoints (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  target_url text not null,
  secret text not null,
  events text[] not null default '{}',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.webhook_endpoints');
create index idx_webhook_endpoints_active on public.webhook_endpoints (tenant_id, is_active);

-- 26. Webhook Deliveries
create table public.webhook_deliveries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  webhook_endpoint_id uuid not null references public.webhook_endpoints(id) on delete cascade,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  status_code integer,
  attempt_count integer not null default 1,
  response_body text,
  delivered_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.webhook_deliveries');
create index idx_webhook_deliveries_endpoint on public.webhook_deliveries (tenant_id, webhook_endpoint_id, delivered_at desc);

-- 27. Mobile App Versions (Global reference catalog - allowlisted)
create table public.mobile_app_versions (
  id uuid primary key default gen_random_uuid(),
  platform text not null check (platform in ('android', 'ios')),
  min_version text not null,
  latest_version text not null,
  force_update boolean not null default false,
  release_notes text,
  release_date date not null default current_date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint uq_mobile_app_versions_platform unique (platform)
);

alter table public.mobile_app_versions enable row level security;
alter table public.mobile_app_versions force row level security;
create policy mobile_app_versions_read on public.mobile_app_versions for select to app_backend using (true);


--------------------------------------------------------------------------------
-- SECTION 4: REPORTING VIEWS (Reports are views, not tables)
--------------------------------------------------------------------------------

-- View 1: MR Performance Summary
create or replace view public.view_mr_performance_summary as
select
  v.tenant_id,
  v.mr_id,
  u.full_name as mr_name,
  date_trunc('month', coalesce(v.check_in_time, v.visit_date::timestamptz))::date as report_month,
  count(distinct v.id) as total_visits,
  count(distinct case when v.visit_type = 'doctor' then v.id end) as doctor_visits,
  count(distinct case when v.visit_type = 'chemist' then v.id end) as chemist_visits,
  count(distinct case when v.visit_type = 'stockist' then v.id end) as stockist_visits,
  coalesce(sum(p.total_amount), 0.00) as total_pob_booked
from public.field_visits v
join public.app_users u on u.id = v.mr_id
left join public.pobs p on p.visit_id = v.id
where v.visit_status = 'completed'
group by v.tenant_id, v.mr_id, u.full_name, date_trunc('month', coalesce(v.check_in_time, v.visit_date::timestamptz));

-- View 2: Doctor Coverage Metrics
create or replace view public.view_doctor_coverage_metrics as
select
  d.tenant_id,
  d.id as doctor_id,
  d.doctor_code,
  d.name as doctor_name,
  c.name as category_name,
  c.visit_frequency_per_month as target_frequency,
  date_trunc('month', coalesce(v.check_in_time, v.visit_date::timestamptz))::date as coverage_month,
  count(distinct v.id) as visits_completed,
  case
    when count(distinct v.id) >= c.visit_frequency_per_month then 'target_met'
    else 'below_target'
  end as coverage_status
from public.doctors d
join public.doctor_categories c on c.id = d.category_id
left join public.field_visits v on v.entity_id = d.id and v.visit_type = 'doctor' and v.visit_status = 'completed'
group by d.tenant_id, d.id, d.doctor_code, d.name, c.name, c.visit_frequency_per_month, date_trunc('month', coalesce(v.check_in_time, v.visit_date::timestamptz));

-- View 3: Secondary Sales Aggregates
create or replace view public.view_secondary_sales_aggregates as
select
  s.tenant_id,
  s.reporting_month,
  s.reporting_year,
  s.stockist_id,
  st.name as stockist_name,
  si.product_id,
  p.name as product_name,
  sum(si.quantity) as total_quantity_sold,
  sum(si.free_quantity) as total_free_quantity,
  sum(si.total_amount) as total_secondary_sales_value
from public.secondary_sales s
join public.secondary_sales_items si on si.secondary_sales_id = s.id
join public.stockists st on st.id = s.stockist_id
join public.products p on p.id = si.product_id
group by s.tenant_id, s.reporting_month, s.reporting_year, s.stockist_id, st.name, si.product_id, p.name;
