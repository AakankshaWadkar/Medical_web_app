-- Migration: 20260103000000_crm_mvp.sql
-- Stage (b): CRM masters and visits/Activity/POB (MVP slice)

-- 1. ISO Country master (Global reference catalog - allowlisted)
create table public.countries (
  code       text primary key,
  name       text not null,
  phone_code text
);
alter table public.countries enable row level security;
alter table public.countries force row level security;
create policy countries_read on public.countries for select to app_backend using (true);

-- 2. State master (Global reference catalog - allowlisted)
create table public.states (
  id             uuid primary key default gen_random_uuid(),
  country_code   text not null references public.countries(code),
  code           text not null,
  name           text not null,
  gst_state_code text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (country_code, code)
);
create index idx_states_country on public.states (country_code);
alter table public.states enable row level security;
alter table public.states force row level security;
create policy states_read on public.states for select to app_backend using (true);

-- 3. City / District master (Global reference catalog - allowlisted)
create table public.cities (
  id         uuid primary key default gen_random_uuid(),
  state_id   uuid not null references public.states(id),
  name       text not null,
  std_code   text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_cities_state on public.cities (state_id);
alter table public.cities enable row level security;
alter table public.cities force row level security;
create policy cities_read on public.cities for select to app_backend using (true);

-- 4. Postal PIN code master (Global reference catalog - allowlisted)
create table public.pin_codes (
  id         uuid primary key default gen_random_uuid(),
  city_id    uuid not null references public.cities(id),
  state_id   uuid not null references public.states(id),
  pin_code   text not null,
  area_name  text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_pin_codes_search on public.pin_codes (pin_code, city_id);
create index idx_pin_codes_state on public.pin_codes (state_id);
alter table public.pin_codes enable row level security;
alter table public.pin_codes force row level security;
create policy pin_codes_read on public.pin_codes for select to app_backend using (true);

-- 5. Polymorphic Addresses
create table public.addresses (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenants(id) on delete cascade,
  entity_type  text not null,
  entity_id    uuid not null,
  address_type text not null default 'clinic' check (address_type in ('billing','shipping','clinic','pharmacy','head_office','residence')),
  line1        text not null,
  line2        text,
  city         text not null,
  state        text not null,
  pin_code     text,
  country      text not null default 'India',
  latitude     double precision,
  longitude    double precision,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  version      bigint not null default 1
);
create index idx_addresses_entity on public.addresses (tenant_id, entity_type, entity_id);
call public.apply_tenant_rls('public.addresses');

-- 6. Polymorphic Contacts
create table public.contacts (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenants(id) on delete cascade,
  entity_type  text not null,
  entity_id    uuid not null,
  contact_type text not null default 'mobile' check (contact_type in ('phone','mobile','email','whatsapp')),
  name         text,
  value        text not null,
  designation  text,
  is_primary   boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  version      bigint not null default 1
);
create index idx_contacts_entity on public.contacts (tenant_id, entity_type, entity_id);
call public.apply_tenant_rls('public.contacts');

-- 7. Business Divisions (Cardio, Neuro, OTC, etc.)
create table public.business_divisions (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  code        text not null,
  name        text not null,
  description text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  version     bigint not null default 1,
  unique (tenant_id, code)
);
call public.apply_tenant_rls('public.business_divisions');

-- 8. Sales Geographic Regions
create table public.regions (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  code        text not null,
  name        text not null,
  manager_id  uuid references public.app_users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  version     bigint not null default 1,
  unique (tenant_id, code)
);
create index idx_regions_manager on public.regions (tenant_id, manager_id);
call public.apply_tenant_rls('public.regions');

-- 9. Sales Geographic Areas
create table public.areas (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  region_id   uuid not null references public.regions(id) on delete cascade,
  code        text not null,
  name        text not null,
  manager_id  uuid references public.app_users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  version     bigint not null default 1,
  unique (tenant_id, code)
);
create index idx_areas_region on public.areas (tenant_id, region_id);
create index idx_areas_manager on public.areas (tenant_id, manager_id);
call public.apply_tenant_rls('public.areas');

-- 10. Sales Territories (Assigned to MR)
create table public.territories (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  area_id     uuid not null references public.areas(id) on delete cascade,
  code        text not null,
  name        text not null,
  manager_id  uuid references public.app_users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  version     bigint not null default 1,
  unique (tenant_id, code)
);
create index idx_territories_area on public.territories (tenant_id, area_id);
create index idx_territories_manager on public.territories (tenant_id, manager_id);
call public.apply_tenant_rls('public.territories');

-- 11. Daily Field Coverage Beats
create table public.beats (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenants(id) on delete cascade,
  territory_id uuid not null references public.territories(id) on delete cascade,
  code         text not null,
  name         text not null,
  description  text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  version      bigint not null default 1,
  unique (tenant_id, territory_id, code)
);
create index idx_beats_territory on public.beats (tenant_id, territory_id);
call public.apply_tenant_rls('public.beats');

-- 12. Travel Routes within Beats
create table public.routes (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  beat_id     uuid not null references public.beats(id) on delete cascade,
  code        text not null,
  name        text not null,
  distance_km numeric(8,2) not null default 0.00,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  version     bigint not null default 1,
  unique (tenant_id, beat_id, code)
);
create index idx_routes_beat on public.routes (tenant_id, beat_id);
call public.apply_tenant_rls('public.routes');

-- 13. Doctor Specialities
create table public.doctor_specialities (
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
call public.apply_tenant_rls('public.doctor_specialities');

-- 14. Doctor Categories (A+, A, B, C)
create table public.doctor_categories (
  id                       uuid primary key default gen_random_uuid(),
  tenant_id                uuid not null references public.tenants(id) on delete cascade,
  code                     text not null,
  name                     text not null,
  visit_frequency_per_month integer not null default 1,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  deleted_at               timestamptz,
  version                  bigint not null default 1,
  unique (tenant_id, code)
);
call public.apply_tenant_rls('public.doctor_categories');

-- 15. Doctor Qualifications (MBBS, MD, MS)
create table public.doctor_qualifications (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenants(id) on delete cascade,
  abbreviation text not null,
  name         text not null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  version      bigint not null default 1,
  unique (tenant_id, abbreviation)
);
call public.apply_tenant_rls('public.doctor_qualifications');

-- 16. Hospitals & Clinics
create table public.hospitals (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenants(id) on delete cascade,
  name          text not null,
  hospital_type text not null default 'private_corporate' check (hospital_type in ('government','private_corporate','nursing_home','trust')),
  territory_id  uuid references public.territories(id) on delete set null,
  bed_count     integer default 0,
  address       text,
  status        text not null default 'active' check (status in ('active','closed')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  version       bigint not null default 1
);
create index idx_hospitals_territory on public.hospitals (tenant_id, territory_id);
call public.apply_tenant_rls('public.hospitals');

-- 17. Doctors Master
create table public.doctors (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  doctor_code      text not null,
  name             text not null,
  gender           text check (gender in ('male','female','other')),
  mobile           text,
  email            text,
  qualification_id uuid references public.doctor_qualifications(id) on delete set null,
  speciality_id    uuid references public.doctor_specialities(id) on delete set null,
  category_id      uuid references public.doctor_categories(id) on delete set null,
  doctor_type      text default 'private_practitioner' check (doctor_type in ('consultant','resident','private_practitioner')),
  hospital_id      uuid references public.hospitals(id) on delete set null,
  visit_frequency  integer not null default 1,
  dob              date,
  anniversary      date,
  division_id      uuid references public.business_divisions(id) on delete set null,
  territory_id     uuid references public.territories(id) on delete set null,
  area_id          uuid references public.areas(id) on delete set null,
  status           text not null default 'active' check (status in ('active','transferred','inactive')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  version          bigint not null default 1,
  unique (tenant_id, doctor_code)
);
create index idx_doctors_territory on public.doctors (tenant_id, territory_id);
create index idx_doctors_speciality on public.doctors (tenant_id, speciality_id);
create index idx_doctors_category on public.doctors (tenant_id, category_id);
create index idx_doctors_hospital on public.doctors (tenant_id, hospital_id);
call public.apply_tenant_rls('public.doctors');

-- 18. Doctor Affiliations
create table public.doctor_affiliations (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  doctor_id      uuid not null references public.doctors(id) on delete cascade,
  hospital_id    uuid not null references public.hospitals(id) on delete cascade,
  visiting_hours text,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  version        bigint not null default 1,
  unique (tenant_id, doctor_id, hospital_id)
);
create index idx_doc_affil_doc on public.doctor_affiliations (tenant_id, doctor_id);
create index idx_doc_affil_hosp on public.doctor_affiliations (tenant_id, hospital_id);
call public.apply_tenant_rls('public.doctor_affiliations');

-- 19. Chemist Categories
create table public.chemist_categories (
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
call public.apply_tenant_rls('public.chemist_categories');

-- 20. Chemists Master
create table public.chemists (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  chemist_code   text not null,
  name           text not null,
  contact_person text,
  mobile         text,
  email          text,
  chemist_type   text default 'independent' check (chemist_type in ('independent','chain_store','hospital_attached')),
  category_id    uuid references public.chemist_categories(id) on delete set null,
  territory_id   uuid references public.territories(id) on delete set null,
  division_id    uuid references public.business_divisions(id) on delete set null,
  visit_frequency integer not null default 2,
  dob            date,
  anniversary    date,
  gst_no         text,
  dl_no          text,
  status         text not null default 'active' check (status in ('active','pending_verification','inactive')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  version        bigint not null default 1,
  unique (tenant_id, chemist_code)
);
create index idx_chemists_territory on public.chemists (tenant_id, territory_id);
create index idx_chemists_category on public.chemists (tenant_id, category_id);
call public.apply_tenant_rls('public.chemists');

-- 21. Stockists Master (Channel Distributor)
create table public.stockists (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenants(id) on delete cascade,
  stockist_code text not null,
  name          text not null,
  stockist_type text not null default 'stockist' check (stockist_type in ('stockist','super_stockist','distributor')),
  territory_id  uuid references public.territories(id) on delete set null,
  area_id       uuid references public.areas(id) on delete set null,
  gst_no        text,
  dl_no         text,
  credit_limit  numeric(14,2) not null default 0.00,
  status        text not null default 'active' check (status in ('active','blocked','inactive')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  version       bigint not null default 1,
  unique (tenant_id, stockist_code)
);
create index idx_stockists_territory on public.stockists (tenant_id, territory_id);
create index idx_stockists_area on public.stockists (tenant_id, area_id);
call public.apply_tenant_rls('public.stockists');

-- 22. Chemist-Stockist Trade Links
create table public.chemist_stockists (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenants(id) on delete cascade,
  chemist_id   uuid not null references public.chemists(id) on delete cascade,
  stockist_id  uuid not null references public.stockists(id) on delete cascade,
  is_preferred boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  version      bigint not null default 1,
  unique (tenant_id, chemist_id, stockist_id)
);
create index idx_chem_stock_chem on public.chemist_stockists (tenant_id, chemist_id);
create index idx_chem_stock_stock on public.chemist_stockists (tenant_id, stockist_id);
call public.apply_tenant_rls('public.chemist_stockists');

-- 23. Product Categories
create table public.categories (
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
call public.apply_tenant_rls('public.categories');

-- 24. Product Brands
create table public.brands (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  division_id uuid references public.business_divisions(id) on delete set null,
  code        text not null,
  name        text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  version     bigint not null default 1,
  unique (tenant_id, code)
);
create index idx_brands_division on public.brands (tenant_id, division_id);
call public.apply_tenant_rls('public.brands');

-- 25. Units of Measure (UOM)
create table public.units_of_measure (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenants(id) on delete cascade,
  code       text not null,
  name       text not null,
  symbol     text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version    bigint not null default 1,
  unique (tenant_id, code)
);
call public.apply_tenant_rls('public.units_of_measure');

-- 26. Products Master (Finished Goods Medicine SKU)
create table public.products (
  id                       uuid primary key default gen_random_uuid(),
  tenant_id                uuid not null references public.tenants(id) on delete cascade,
  division_id              uuid references public.business_divisions(id) on delete set null,
  category_id              uuid references public.categories(id) on delete set null,
  brand_id                 uuid references public.brands(id) on delete set null,
  uom_id                   uuid references public.units_of_measure(id) on delete set null,
  product_code             text not null,
  name                     text not null,
  generic_name             text,
  description              text,
  mrp                      numeric(14,2) not null default 0.00,
  ptr                      numeric(14,2) not null default 0.00,
  pts                      numeric(14,2) not null default 0.00,
  is_active                boolean not null default true,
  is_prescription_required boolean not null default true,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  deleted_at               timestamptz,
  version                  bigint not null default 1,
  unique (tenant_id, product_code)
);
create index idx_products_brand on public.products (tenant_id, brand_id);
create index idx_products_category on public.products (tenant_id, category_id);
create index idx_products_division on public.products (tenant_id, division_id);
create index idx_products_uom on public.products (tenant_id, uom_id);
call public.apply_tenant_rls('public.products');

-- 27. Monthly Tour Plans (MTP)
create table public.tour_plans (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references public.tenants(id) on delete cascade,
  mr_id              uuid not null references public.app_users(id) on delete cascade,
  plan_month         integer not null check (plan_month between 1 and 12),
  plan_year          integer not null check (plan_year between 2020 and 2100),
  status             text not null default 'draft' check (status in ('draft','submitted','approved','rejected')),
  approved_by_user_id uuid references public.app_users(id) on delete set null,
  approved_at        timestamptz,
  remarks            text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  version            bigint not null default 1,
  unique (tenant_id, mr_id, plan_month, plan_year)
);
create index idx_tour_plans_mr on public.tour_plans (tenant_id, mr_id);
create index idx_tour_plans_approver on public.tour_plans (tenant_id, approved_by_user_id);
call public.apply_tenant_rls('public.tour_plans');

-- 28. Tour Plan Days
create table public.tour_plan_days (
  id                   uuid primary key default gen_random_uuid(),
  tenant_id            uuid not null references public.tenants(id) on delete cascade,
  tour_plan_id         uuid not null references public.tour_plans(id) on delete cascade,
  planned_date         date not null,
  territory_id         uuid references public.territories(id) on delete set null,
  beat_id              uuid references public.beats(id) on delete set null,
  route_id             uuid references public.routes(id) on delete set null,
  planned_doctor_count integer not null default 0,
  planned_chemist_count integer not null default 0,
  activity_type        text not null default 'field_work' check (activity_type in ('field_work','joint_work','transit','conference','meeting','holiday')),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz,
  version              bigint not null default 1,
  unique (tenant_id, tour_plan_id, planned_date)
);
create index idx_tour_days_plan on public.tour_plan_days (tenant_id, tour_plan_id);
create index idx_tour_days_beat on public.tour_plan_days (tenant_id, beat_id);
call public.apply_tenant_rls('public.tour_plan_days');

-- 29. Field Visits (Unified single table for Doctor, Chemist, Stockist, Hospital calls)
create table public.field_visits (
  id                   uuid primary key default gen_random_uuid(),
  tenant_id            uuid not null references public.tenants(id) on delete cascade,
  mr_id                uuid not null references public.app_users(id) on delete cascade,
  visit_type           text not null check (visit_type in ('doctor','chemist','stockist','hospital')),
  entity_type          text not null check (entity_type in ('doctors','chemists','stockists','hospitals')),
  entity_id            uuid not null,
  beat_id              uuid references public.beats(id) on delete set null,
  route_id             uuid references public.routes(id) on delete set null,
  tour_plan_day_id     uuid references public.tour_plan_days(id) on delete set null,
  visit_date           date not null default current_date,
  check_in_time        timestamptz,
  check_out_time       timestamptz,
  check_in_latitude    double precision,
  check_in_longitude   double precision,
  check_out_latitude   double precision,
  check_out_longitude  double precision,
  visit_status         text not null default 'completed' check (visit_status in ('planned','in_progress','completed','missed','cancelled')),
  remarks              text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz,
  version              bigint not null default 1
);
create index idx_field_visits_mr_date on public.field_visits (tenant_id, mr_id, visit_date desc);
create index idx_field_visits_entity on public.field_visits (tenant_id, entity_type, entity_id);
create index idx_field_visits_beat on public.field_visits (tenant_id, beat_id);
create index idx_field_visits_tour_day on public.field_visits (tenant_id, tour_plan_day_id);
call public.apply_tenant_rls('public.field_visits');

-- 30. Joint Work (Manager accompaniment)
create table public.joint_works (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  visit_id         uuid not null references public.field_visits(id) on delete cascade,
  manager_id       uuid not null references public.app_users(id) on delete cascade,
  mr_id            uuid not null references public.app_users(id) on delete cascade,
  joint_work_date  date not null default current_date,
  manager_feedback text,
  rating           integer check (rating between 1 and 5),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  version          bigint not null default 1,
  unique (tenant_id, visit_id, manager_id)
);
create index idx_joint_works_manager on public.joint_works (tenant_id, manager_id);
create index idx_joint_works_mr on public.joint_works (tenant_id, mr_id);
call public.apply_tenant_rls('public.joint_works');

-- 31. Visit Selfies
create table public.visit_selfies (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  visit_id    uuid not null references public.field_visits(id) on delete cascade,
  file_id     uuid not null references public.file_storage(id) on delete cascade,
  captured_at timestamptz not null default now(),
  latitude    double precision,
  longitude   double precision,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  version     bigint not null default 1
);
create index idx_visit_selfies_visit on public.visit_selfies (tenant_id, visit_id);
create index idx_visit_selfies_file on public.visit_selfies (tenant_id, file_id);
call public.apply_tenant_rls('public.visit_selfies');

-- 32. Doctor Call Feedbacks
create table public.doctor_feedbacks (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references public.tenants(id) on delete cascade,
  visit_id           uuid not null references public.field_visits(id) on delete cascade,
  doctor_id          uuid not null references public.doctors(id) on delete cascade,
  feedback_type      text not null default 'positive' check (feedback_type in ('positive','neutral','negative','requested_literature','competitor_price_issue')),
  comments           text,
  next_followup_date date,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  version            bigint not null default 1,
  unique (tenant_id, visit_id)
);
create index idx_doc_feedback_doctor on public.doctor_feedbacks (tenant_id, doctor_id);
call public.apply_tenant_rls('public.doctor_feedbacks');

-- 33. Chemist Call Feedbacks
create table public.chemist_feedbacks (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.tenants(id) on delete cascade,
  visit_id            uuid not null references public.field_visits(id) on delete cascade,
  chemist_id          uuid not null references public.chemists(id) on delete cascade,
  stock_issue         boolean not null default false,
  competitor_activity text,
  comments            text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  version             bigint not null default 1,
  unique (tenant_id, visit_id)
);
create index idx_chem_feedback_chemist on public.chemist_feedbacks (tenant_id, chemist_id);
call public.apply_tenant_rls('public.chemist_feedbacks');

-- 34. Pre-Order Bookings (POB / Field Orders)
create table public.pobs (
  id                     uuid primary key default gen_random_uuid(),
  tenant_id              uuid not null references public.tenants(id) on delete cascade,
  visit_id               uuid references public.field_visits(id) on delete set null,
  mr_id                  uuid not null references public.app_users(id) on delete cascade,
  customer_type          text not null check (customer_type in ('chemist','doctor','hospital')),
  entity_id              uuid not null,
  stockist_id            uuid references public.stockists(id) on delete set null,
  pob_date               date not null default current_date,
  total_amount           numeric(14,2) not null default 0.00,
  status                 text not null default 'booked' check (status in ('draft','booked','delivered','cancelled')),
  expected_delivery_date date,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  deleted_at             timestamptz,
  version                bigint not null default 1
);
create index idx_pobs_mr_date on public.pobs (tenant_id, mr_id, pob_date desc);
create index idx_pobs_customer on public.pobs (tenant_id, customer_type, entity_id);
create index idx_pobs_stockist on public.pobs (tenant_id, stockist_id);
create index idx_pobs_visit on public.pobs (tenant_id, visit_id);
call public.apply_tenant_rls('public.pobs');

-- 35. POB Product Line Items
create table public.pob_products (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  pob_id           uuid not null references public.pobs(id) on delete cascade,
  product_id       uuid not null references public.products(id) on delete cascade,
  quantity         bigint not null check (quantity > 0),
  rate             numeric(14,2) not null default 0.00,
  total_amount     numeric(14,2) not null default 0.00,
  discount_percent numeric(5,2) not null default 0.00,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  version          bigint not null default 1
);
create index idx_pob_products_parent on public.pob_products (tenant_id, pob_id);
create index idx_pob_products_product on public.pob_products (tenant_id, product_id);
call public.apply_tenant_rls('public.pob_products');
