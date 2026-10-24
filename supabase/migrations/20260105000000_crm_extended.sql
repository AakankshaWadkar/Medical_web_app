-- Migration: 20260105000000_crm_extended.sql
-- Description: Stage (d) CRM Extended - E-Detailing, Sample/Gift Distributions, RCPA, DCR, Targets/Achievements, MR Documents
-- Conventions: tenant_id uuid not null, apply_tenant_rls, numeric(14,2), timestamptz, check constraints

--------------------------------------------------------------------------------
-- 1. Doctor Brand Prescriptions
--------------------------------------------------------------------------------
create table public.doctor_brand_prescriptions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  doctor_id uuid not null references public.doctors(id) on delete cascade,
  mr_id uuid references public.app_users(id) on delete set null,
  product_id uuid not null references public.products(id) on delete restrict,
  prescribing_habit text not null check (prescribing_habit in ('regular', 'occasional', 'trial', 'non_prescriber')),
  potential_units_per_month integer not null default 0 check (potential_units_per_month >= 0),
  audit_date date not null default current_date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.doctor_brand_prescriptions');
create index idx_doc_brand_prescriptions_lookup on public.doctor_brand_prescriptions (tenant_id, doctor_id, product_id);
create index idx_doc_brand_prescriptions_mr on public.doctor_brand_prescriptions (tenant_id, mr_id);

--------------------------------------------------------------------------------
-- 2. E-Detailing Sessions
--------------------------------------------------------------------------------
create table public.e_detailings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  visit_id uuid not null references public.field_visits(id) on delete cascade,
  mr_id uuid references public.app_users(id) on delete set null,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  total_duration_seconds integer not null default 0 check (total_duration_seconds >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.e_detailings');
create index idx_e_detailings_visit on public.e_detailings (tenant_id, visit_id);
create index idx_e_detailings_mr on public.e_detailings (tenant_id, mr_id);

--------------------------------------------------------------------------------
-- 3. E-Detailing Slides
--------------------------------------------------------------------------------
create table public.e_detailing_slides (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  e_detailing_id uuid not null references public.e_detailings(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  slide_number integer not null check (slide_number > 0),
  duration_seconds integer not null default 0 check (duration_seconds >= 0),
  doctor_feedback text check (doctor_feedback is null or doctor_feedback in ('very_interested', 'interested', 'neutral', 'not_interested')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.e_detailing_slides');
create index idx_e_detailing_slides_session on public.e_detailing_slides (tenant_id, e_detailing_id);
create index idx_e_detailing_slides_product on public.e_detailing_slides (tenant_id, product_id);

--------------------------------------------------------------------------------
-- 4. Doctor Gift Distributions
--------------------------------------------------------------------------------
create table public.doctor_gift_distributions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  visit_id uuid not null references public.field_visits(id) on delete cascade,
  doctor_id uuid not null references public.doctors(id) on delete cascade,
  gift_item_id uuid not null references public.gift_items(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  acknowledged_by_doctor boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.doctor_gift_distributions');
create index idx_doc_gift_dist_lookup on public.doctor_gift_distributions (tenant_id, visit_id, gift_item_id);
create index idx_doc_gift_dist_doctor on public.doctor_gift_distributions (tenant_id, doctor_id);
create index idx_doc_gift_dist_gift_item on public.doctor_gift_distributions (tenant_id, gift_item_id);

--------------------------------------------------------------------------------
-- 5. Doctor Sample Distributions
--------------------------------------------------------------------------------
create table public.doctor_sample_distributions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  visit_id uuid not null references public.field_visits(id) on delete cascade,
  doctor_id uuid not null references public.doctors(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  batch_id uuid references public.product_batches(id) on delete set null,
  quantity integer not null check (quantity > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.doctor_sample_distributions');
create index idx_doc_sample_dist_lookup on public.doctor_sample_distributions (tenant_id, visit_id, product_id);
create index idx_doc_sample_dist_doctor on public.doctor_sample_distributions (tenant_id, doctor_id);
create index idx_doc_sample_dist_batch on public.doctor_sample_distributions (tenant_id, batch_id);

--------------------------------------------------------------------------------
-- 6. RCPA Audits
--------------------------------------------------------------------------------
create table public.rcpa_audits (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  visit_id uuid references public.field_visits(id) on delete set null,
  mr_id uuid references public.app_users(id) on delete set null,
  chemist_id uuid not null references public.chemists(id) on delete cascade,
  doctor_id uuid not null references public.doctors(id) on delete cascade,
  audit_date date not null default current_date,
  prescription_trend text check (prescription_trend is null or prescription_trend in ('increasing', 'steady', 'declining')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.rcpa_audits');
create index idx_rcpa_audits_composite on public.rcpa_audits (tenant_id, chemist_id, doctor_id, audit_date desc);
create index idx_rcpa_audits_visit on public.rcpa_audits (tenant_id, visit_id);
create index idx_rcpa_audits_mr on public.rcpa_audits (tenant_id, mr_id);

--------------------------------------------------------------------------------
-- 7. RCPA Audit Items
--------------------------------------------------------------------------------
create table public.rcpa_audit_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  rcpa_audit_id uuid not null references public.rcpa_audits(id) on delete cascade,
  our_product_id uuid not null references public.products(id) on delete restrict,
  our_units_prescribed integer not null default 0 check (our_units_prescribed >= 0),
  competitor_brand_name text,
  competitor_company text,
  competitor_units_prescribed integer not null default 0 check (competitor_units_prescribed >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.rcpa_audit_items');
create index idx_rcpa_audit_items_audit on public.rcpa_audit_items (tenant_id, rcpa_audit_id);
create index idx_rcpa_audit_items_product on public.rcpa_audit_items (tenant_id, our_product_id);

--------------------------------------------------------------------------------
-- 8. Daily Call Reports (DCR)
--------------------------------------------------------------------------------
create table public.daily_call_reports (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  mr_id uuid not null references public.app_users(id) on delete cascade,
  report_date date not null default current_date,
  beat_id uuid references public.beats(id) on delete set null,
  total_calls integer not null default 0 check (total_calls >= 0),
  doctor_calls integer not null default 0 check (doctor_calls >= 0),
  chemist_calls integer not null default 0 check (chemist_calls >= 0),
  stockist_calls integer not null default 0 check (stockist_calls >= 0),
  total_pob_value numeric(14,2) not null default 0.00 check (total_pob_value >= 0),
  status text not null default 'draft' check (status in ('draft', 'submitted', 'approved', 'rejected')),
  submitted_at timestamptz,
  approved_by_user_id uuid references public.app_users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_daily_call_reports_mr_date unique (tenant_id, mr_id, report_date)
);

call public.apply_tenant_rls('public.daily_call_reports');
create index idx_dcr_beat on public.daily_call_reports (tenant_id, beat_id);
create index idx_dcr_approved_by on public.daily_call_reports (tenant_id, approved_by_user_id);

--------------------------------------------------------------------------------
-- 9. Sales Targets
--------------------------------------------------------------------------------
create table public.sales_targets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null references public.app_users(id) on delete cascade,
  target_type text not null check (target_type in ('secondary_sales', 'primary_sales', 'doctor_calls', 'pob_value')),
  target_month integer not null check (target_month between 1 and 12),
  target_year integer not null check (target_year >= 2000),
  division_id uuid references public.business_divisions(id) on delete set null,
  product_id uuid references public.products(id) on delete set null,
  target_quantity bigint not null default 0 check (target_quantity >= 0),
  target_amount numeric(14,2) not null default 0.00 check (target_amount >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.sales_targets');
create index idx_sales_targets_user_period on public.sales_targets (tenant_id, user_id, target_year, target_month);
create index idx_sales_targets_division on public.sales_targets (tenant_id, division_id);
create index idx_sales_targets_product on public.sales_targets (tenant_id, product_id);

--------------------------------------------------------------------------------
-- 10. Sales Achievements
--------------------------------------------------------------------------------
create table public.sales_achievements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  sales_target_id uuid not null references public.sales_targets(id) on delete cascade,
  achieved_quantity bigint not null default 0 check (achieved_quantity >= 0),
  achieved_amount numeric(14,2) not null default 0.00 check (achieved_amount >= 0),
  achievement_percentage numeric(6,2) not null default 0.00 check (achievement_percentage >= 0),
  computed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.sales_achievements');
create index idx_sales_achievements_target on public.sales_achievements (tenant_id, sales_target_id);

--------------------------------------------------------------------------------
-- 11. MR Documents
--------------------------------------------------------------------------------
create table public.mr_documents (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  mr_id uuid not null references public.app_users(id) on delete cascade,
  document_type text not null check (document_type in ('pan', 'aadhar', 'driving_license', 'appointment_letter', 'other')),
  title text not null,
  file_id uuid references public.file_storage(id) on delete set null,
  expiry_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.mr_documents');
create index idx_mr_documents_user on public.mr_documents (tenant_id, mr_id);
create index idx_mr_documents_file on public.mr_documents (tenant_id, file_id);
