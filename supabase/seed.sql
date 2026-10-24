-- ============================================================================
-- PharmaSphere Seed Data (Local Development & Demo Platform)
-- 1 Admin, 2 Managers (RSMs), 4 Medical Representatives (MRs)
-- Sales Hierarchy, CRM Masters, Doctors, Chemists, Stockists, Products & Operations
-- ============================================================================

-- 0. Set local dev role password
alter role app_backend password 'app_backend_dev';

--------------------------------------------------------------------------------
-- 1. Global Platform Masters (Allowlisted)
--------------------------------------------------------------------------------

-- Subscription Plans
insert into public.subscription_plans (id, code, name, max_users, max_branches, max_storage_gb, price, billing_cycle, is_active)
values
  ('00000000-0000-0000-0000-000000000101', 'enterprise', 'Enterprise Pharma Suite', 100, 10, 50, 15000.00, 'monthly', true)
on conflict (code) do nothing;

-- Countries
insert into public.countries (code, name, phone_code)
values
  ('IN', 'India', '+91')
on conflict (code) do nothing;

-- States
insert into public.states (id, country_code, code, name, gst_state_code)
values
  ('00000000-0000-0000-0000-000000000201', 'IN', 'MH', 'Maharashtra', '27'),
  ('00000000-0000-0000-0000-000000000202', 'IN', 'DL', 'Delhi', '07')
on conflict (country_code, code) do nothing;

-- Cities
insert into public.cities (id, state_id, name, std_code)
values
  ('00000000-0000-0000-0000-000000000211', '00000000-0000-0000-0000-000000000201', 'Mumbai', '022'),
  ('00000000-0000-0000-0000-000000000212', '00000000-0000-0000-0000-000000000201', 'Pune', '020'),
  ('00000000-0000-0000-0000-000000000213', '00000000-0000-0000-0000-000000000202', 'New Delhi', '011')
on conflict (id) do nothing;

-- Pin Codes
insert into public.pin_codes (id, city_id, state_id, pin_code, area_name)
values
  ('00000000-0000-0000-0000-000000000221', '00000000-0000-0000-0000-000000000211', '00000000-0000-0000-0000-000000000201', '400001', 'Fort'),
  ('00000000-0000-0000-0000-000000000222', '00000000-0000-0000-0000-000000000211', '00000000-0000-0000-0000-000000000201', '400014', 'Dadar'),
  ('00000000-0000-0000-0000-000000000223', '00000000-0000-0000-0000-000000000211', '00000000-0000-0000-0000-000000000201', '400050', 'Bandra'),
  ('00000000-0000-0000-0000-000000000224', '00000000-0000-0000-0000-000000000212', '00000000-0000-0000-0000-000000000201', '411038', 'Kothrud'),
  ('00000000-0000-0000-0000-000000000225', '00000000-0000-0000-0000-000000000213', '00000000-0000-0000-0000-000000000202', '110001', 'Connaught Place')
on conflict (id) do nothing;

-- Mobile App Versions
insert into public.mobile_app_versions (id, platform, min_version, latest_version, force_update, release_notes)
values
  ('00000000-0000-0000-0000-000000000231', 'android', '1.0.0', '1.2.0', false, 'Field visit check-in and offline POB order enhancements'),
  ('00000000-0000-0000-0000-000000000232', 'ios', '1.0.0', '1.2.0', false, 'iOS performance optimization and battery efficiency')
on conflict (platform) do nothing;


--------------------------------------------------------------------------------
-- 2. Demo Company / Tenant
--------------------------------------------------------------------------------

insert into public.tenants (
  id, name, slug, company_code, legal_name, gst_no, drug_license_no,
  email, phone, website, address, city, state, pincode, currency
)
values (
  '00000000-0000-0000-0000-000000000001',
  'Apex Pharma Solutions Ltd',
  'apex-pharma',
  'APEX',
  'Apex Pharma Solutions Private Limited',
  '27AAAAA0000A1Z5',
  'MH-TZ1-123456',
  'contact@apexpharma.com',
  '+91 22 2400 1234',
  'https://www.apexpharma.com',
  'Apex House, Dr. E Moses Road, Worli',
  'Mumbai',
  'Maharashtra',
  '400018',
  'INR'
)
on conflict (id) do nothing;

-- Company Subscription
insert into public.company_subscriptions (
  id, tenant_id, plan_id, status, start_date, end_date, auto_renew
)
values (
  '00000000-0000-0000-0000-000000000111',
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000101',
  'active',
  now() - interval '30 days',
  now() + interval '335 days',
  true
)
on conflict (id) do nothing;

-- Branches & Departments
insert into public.branches (id, tenant_id, code, name, is_head_office, city, state)
values
  ('00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000001', 'HQ-MUM', 'Mumbai Corporate Head Office', true, 'Mumbai', 'Maharashtra')
on conflict (tenant_id, code) do nothing;

insert into public.departments (id, tenant_id, branch_id, code, name)
values
  ('00000000-0000-0000-0000-000000000311', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000301', 'SALES', 'Field Sales & Commercial Operations')
on conflict (tenant_id, branch_id, code) do nothing;


--------------------------------------------------------------------------------
-- 3. Users: 1 Admin, 2 Managers, 4 MRs
--------------------------------------------------------------------------------

-- Supabase auth.users entries (passwords: Password123!)
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  email_change_token_current, phone_change, phone_change_token, reauthentication_token
)
values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@apexpharma.com', crypt('Password123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Rajesh Sharma"}', now(), now(), '', '', '', '', '', '', '', ''),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'vikram.manager@apexpharma.com', crypt('Password123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Vikram Malhotra"}', now(), now(), '', '', '', '', '', '', '', ''),
  ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'suresh.manager@apexpharma.com', crypt('Password123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Suresh Iyer"}', now(), now(), '', '', '', '', '', '', '', ''),
  ('10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'amit.mr@apexpharma.com', crypt('Password123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Amit Kumar"}', now(), now(), '', '', '', '', '', '', '', ''),
  ('10000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pooja.mr@apexpharma.com', crypt('Password123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Pooja Patil"}', now(), now(), '', '', '', '', '', '', '', ''),
  ('10000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rohan.mr@apexpharma.com', crypt('Password123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Rohan Deshmukh"}', now(), now(), '', '', '', '', '', '', '', ''),
  ('10000000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'neha.mr@apexpharma.com', crypt('Password123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Neha Verma"}', now(), now(), '', '', '', '', '', '', '', '')
on conflict (id) do nothing;

-- Supabase auth.identities entries
insert into auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
values
  ('10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', json_build_object('sub', '10000000-0000-0000-0000-000000000001', 'email', 'admin@apexpharma.com'), 'email', '10000000-0000-0000-0000-000000000001', now(), now(), now()),
  ('10000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', json_build_object('sub', '10000000-0000-0000-0000-000000000002', 'email', 'vikram.manager@apexpharma.com'), 'email', '10000000-0000-0000-0000-000000000002', now(), now(), now()),
  ('10000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000003', json_build_object('sub', '10000000-0000-0000-0000-000000000003', 'email', 'suresh.manager@apexpharma.com'), 'email', '10000000-0000-0000-0000-000000000003', now(), now(), now()),
  ('10000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000004', json_build_object('sub', '10000000-0000-0000-0000-000000000004', 'email', 'amit.mr@apexpharma.com'), 'email', '10000000-0000-0000-0000-000000000004', now(), now(), now()),
  ('10000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000005', json_build_object('sub', '10000000-0000-0000-0000-000000000005', 'email', 'pooja.mr@apexpharma.com'), 'email', '10000000-0000-0000-0000-000000000005', now(), now(), now()),
  ('10000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000006', json_build_object('sub', '10000000-0000-0000-0000-000000000006', 'email', 'rohan.mr@apexpharma.com'), 'email', '10000000-0000-0000-0000-000000000006', now(), now(), now()),
  ('10000000-0000-0000-0000-000000000007', '10000000-0000-0000-0000-000000000007', json_build_object('sub', '10000000-0000-0000-0000-000000000007', 'email', 'neha.mr@apexpharma.com'), 'email', '10000000-0000-0000-0000-000000000007', now(), now(), now())
on conflict (provider, provider_id) do nothing;

-- Public app_users
insert into public.app_users (id, tenant_id, auth_user_id, app_role, full_name, phone, manager_id, branch_id, department_id, status)
values
  -- 1 Admin
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'admin', 'Rajesh Sharma', '+91 98200 11001', null, '00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000311', 'active'),
  -- 2 Managers
  ('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 'manager', 'Vikram Malhotra', '+91 98200 11002', '20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000311', 'active'),
  ('20000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003', 'manager', 'Suresh Iyer', '+91 98200 11003', '20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000311', 'active'),
  -- 4 Medical Representatives (MRs)
  ('20000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000004', 'mr', 'Amit Kumar', '+91 98200 11004', '20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000311', 'active'),
  ('20000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000005', 'mr', 'Pooja Patil', '+91 98200 11005', '20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000311', 'active'),
  ('20000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000006', 'mr', 'Rohan Deshmukh', '+91 98200 11006', '20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000311', 'active'),
  ('20000000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000007', 'mr', 'Neha Verma', '+91 98200 11007', '20000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000311', 'active')
on conflict (id) do nothing;


--------------------------------------------------------------------------------
-- 4. Sales Hierarchy (Divisions, Regions, Areas, Territories, Beats, Routes)
--------------------------------------------------------------------------------

insert into public.business_divisions (id, tenant_id, code, name, description)
values
  ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'CARDIO', 'Cardio-Diabetic Division', 'Hypertension, Lipid and Glycemic control therapies'),
  ('30000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'GASTRO', 'Gastro-Care Division', 'PPI, Antacids and Gastrointestinal motility products')
on conflict (tenant_id, code) do nothing;

insert into public.regions (id, tenant_id, code, name)
values
  ('30000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001', 'REG-WEST', 'West India Region'),
  ('30000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000001', 'REG-NORTH', 'North India Region')
on conflict (tenant_id, code) do nothing;

insert into public.areas (id, tenant_id, region_id, code, name)
values
  ('30000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000011', 'AREA-MUM', 'Mumbai Metro Area'),
  ('30000000-0000-0000-0000-000000000022', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000011', 'AREA-PUN', 'Pune Area'),
  ('30000000-0000-0000-0000-000000000023', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000012', 'AREA-DEL', 'Delhi NCR Area')
on conflict (tenant_id, code) do nothing;

insert into public.territories (id, tenant_id, area_id, code, name, manager_id)
values
  ('30000000-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000021', 'TERR-MUM-C', 'Mumbai Central Territory', '20000000-0000-0000-0000-000000000004'),
  ('30000000-0000-0000-0000-000000000032', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000021', 'TERR-MUM-W', 'Mumbai West Territory', '20000000-0000-0000-0000-000000000005'),
  ('30000000-0000-0000-0000-000000000033', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000022', 'TERR-PUN-C', 'Pune City Territory', '20000000-0000-0000-0000-000000000006'),
  ('30000000-0000-0000-0000-000000000034', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000023', 'TERR-DEL-S', 'Delhi South Territory', '20000000-0000-0000-0000-000000000007')
on conflict (tenant_id, code) do nothing;

insert into public.beats (id, tenant_id, territory_id, code, name)
values
  ('30000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000031', 'BEAT-DADAR', 'Dadar - Parel Hospital Belt'),
  ('30000000-0000-0000-0000-000000000042', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000032', 'BEAT-BANDRA', 'Bandra - Khar Medical Zone'),
  ('30000000-0000-0000-0000-000000000043', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000033', 'BEAT-KOTHRUD', 'Kothrud - Deccan Gymkhana'),
  ('30000000-0000-0000-0000-000000000044', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000034', 'BEAT-CP', 'Connaught Place - AIIMS Belt')
on conflict (tenant_id, territory_id, code) do nothing;

insert into public.routes (id, tenant_id, beat_id, code, name)
values
  ('30000000-0000-0000-0000-000000000051', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000041', 'RT-DADAR-01', 'Dadar Station to KEM Hospital Corridor')
on conflict (tenant_id, beat_id, code) do nothing;


--------------------------------------------------------------------------------
-- 5. CRM Masters (Doctor & Chemist Classifications, Hospitals)
--------------------------------------------------------------------------------

insert into public.doctor_specialities (id, tenant_id, code, name, description)
values
  ('40000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'CARDIO', 'Cardiology', 'Interventional and Clinical Cardiologists'),
  ('40000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'DIABETES', 'Diabetology / Endocrinology', 'Diabetes and Metabolic Care Specialists'),
  ('40000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'GEN_MED', 'General Medicine', 'Consulting Physicians and General Practitioners')
on conflict (tenant_id, code) do nothing;

insert into public.doctor_categories (id, tenant_id, code, name, visit_frequency_per_month)
values
  ('40000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001', 'A_PLUS', 'A+ Super Core (4 calls/mo)', 4),
  ('40000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000001', 'A_CORE', 'A Core (2 calls/mo)', 2),
  ('40000000-0000-0000-0000-000000000013', '00000000-0000-0000-0000-000000000001', 'B_REGULAR', 'B Regular (1 call/mo)', 1)
on conflict (tenant_id, code) do nothing;

insert into public.doctor_qualifications (id, tenant_id, abbreviation, name)
values
  ('40000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000001', 'MD', 'Doctor of Medicine'),
  ('40000000-0000-0000-0000-000000000022', '00000000-0000-0000-0000-000000000001', 'DM', 'Doctorate of Medicine (Super-Speciality)'),
  ('40000000-0000-0000-0000-000000000023', '00000000-0000-0000-0000-000000000001', 'MBBS', 'Bachelor of Medicine and Surgery')
on conflict (tenant_id, abbreviation) do nothing;

insert into public.hospitals (id, tenant_id, territory_id, name, hospital_type, bed_count, address, status)
values
  ('40000000-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000031', 'KEM Hospital & Research Centre', 'government', 1800, 'Acharya Donde Marg, Parel, Mumbai', 'active'),
  ('40000000-0000-0000-0000-000000000032', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000032', 'Lilavati Hospital & Research Centre', 'private_corporate', 320, 'A-791, Bandra Reclamation, Bandra West, Mumbai', 'active')
on conflict (id) do nothing;

-- Doctors
insert into public.doctors (id, tenant_id, doctor_code, name, speciality_id, category_id, qualification_id, territory_id, mobile, email, visit_frequency, status)
values
  ('40000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000001', 'DOC-001', 'Dr. Arvind Mehta', '40000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000011', '40000000-0000-0000-0000-000000000022', '30000000-0000-0000-0000-000000000031', '+91 98201 22001', 'arvind.mehta@kem.edu', 4, 'active'),
  ('40000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000001', 'DOC-002', 'Dr. Sneha Joshi', '40000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000012', '40000000-0000-0000-0000-000000000021', '30000000-0000-0000-0000-000000000032', '+91 98201 22002', 'sneha.joshi@lilavati.org', 2, 'active'),
  ('40000000-0000-0000-0000-000000000103', '00000000-0000-0000-0000-000000000001', 'DOC-003', 'Dr. Prakash Kulkarni', '40000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000011', '40000000-0000-0000-0000-000000000022', '30000000-0000-0000-0000-000000000033', '+91 98201 22003', 'prakash.kulkarni@rubyhall.com', 4, 'active'),
  ('40000000-0000-0000-0000-000000000104', '00000000-0000-0000-0000-000000000001', 'DOC-004', 'Dr. Alok Aggarwal', '40000000-0000-0000-0000-000000000003', '40000000-0000-0000-0000-000000000013', '40000000-0000-0000-0000-000000000021', '30000000-0000-0000-0000-000000000034', '+91 98201 22004', 'alok.aggarwal@maxhealthcare.com', 1, 'active')
on conflict (tenant_id, doctor_code) do nothing;

-- Chemist Categories
insert into public.chemist_categories (id, tenant_id, code, name, description)
values
  ('40000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-000000000001', 'RETAIL', 'Independent Retail Chemist', 'High prescription fulfillment retail counter'),
  ('40000000-0000-0000-0000-000000000202', '00000000-0000-0000-0000-000000000001', 'HOSPITAL_ATTACHED', 'Hospital Attached Pharmacy', 'In-premise round-the-clock hospital pharmacy')
on conflict (tenant_id, code) do nothing;

-- Stockists
insert into public.stockists (id, tenant_id, territory_id, stockist_code, name, stockist_type, gst_no, dl_no, credit_limit, status)
values
  ('40000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000031', 'STK-MUM-01', 'Apex Western Distributors Pvt Ltd', 'super_stockist', '27AABCU9603R1ZX', 'MH-TZ-20B-1122', 1000000.00, 'active'),
  ('40000000-0000-0000-0000-000000000302', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000033', 'STK-PUN-01', 'Poona Pharma Agencies', 'stockist', '27AABCP1234M1ZY', 'MH-PUN-20B-3344', 800000.00, 'active'),
  ('40000000-0000-0000-0000-000000000303', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000034', 'STK-DEL-01', 'Capital Drug Distributors', 'distributor', '07AABCD5678Q1ZZ', 'DL-DEL-20B-5566', 1200000.00, 'active')
on conflict (tenant_id, stockist_code) do nothing;

-- Chemists
insert into public.chemists (id, tenant_id, territory_id, category_id, chemist_code, name, contact_person, mobile, status)
values
  ('40000000-0000-0000-0000-000000000401', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000031', '40000000-0000-0000-0000-000000000201', 'CHM-001', 'Dadar LifeCare Chemist', 'Ramesh Shah', '+91 98202 33001', 'active'),
  ('40000000-0000-0000-0000-000000000402', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000032', '40000000-0000-0000-0000-000000000201', 'CHM-002', 'Bandra Medical Stores', 'Kishore Gupta', '+91 98202 33002', 'active'),
  ('40000000-0000-0000-0000-000000000403', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000033', '40000000-0000-0000-0000-000000000201', 'CHM-003', 'Kothrud Apollo Pharmacy', 'Sachin Jadhav', '+91 98202 33003', 'active'),
  ('40000000-0000-0000-0000-000000000404', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000034', '40000000-0000-0000-0000-000000000201', 'CHM-004', 'Connaught Medicos', 'Vipin Mehra', '+91 98202 33004', 'active')
on conflict (tenant_id, chemist_code) do nothing;

-- Chemist-Stockist Mapping
insert into public.chemist_stockists (id, tenant_id, chemist_id, stockist_id, is_preferred)
values
  ('40000000-0000-0000-0000-000000000501', '00000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000401', '40000000-0000-0000-0000-000000000301', true),
  ('40000000-0000-0000-0000-000000000502', '00000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000402', '40000000-0000-0000-0000-000000000301', true),
  ('40000000-0000-0000-0000-000000000503', '00000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000403', '40000000-0000-0000-0000-000000000302', true),
  ('40000000-0000-0000-0000-000000000504', '00000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000404', '40000000-0000-0000-0000-000000000303', true)
on conflict (tenant_id, chemist_id, stockist_id) do nothing;


--------------------------------------------------------------------------------
-- 6. Products, Brands, Batches & Warehouse Inventory
--------------------------------------------------------------------------------

insert into public.categories (id, tenant_id, code, name)
values
  ('50000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'CAT-CARDIO', 'Cardiovascular Formulations'),
  ('50000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'CAT-ANTI-DIAB', 'Anti-Diabetic Formulations')
on conflict (tenant_id, code) do nothing;

insert into public.brands (id, tenant_id, code, name)
values
  ('50000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001', 'BRD-CARDIOSTEP', 'Cardiostep'),
  ('50000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000001', 'BRD-DIABAGARD', 'DiabaGard')
on conflict (tenant_id, code) do nothing;

insert into public.units_of_measure (id, tenant_id, code, name, symbol)
values
  ('50000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000001', 'STRIP10', 'Strip of 10 Tablets', '10T'),
  ('50000000-0000-0000-0000-000000000022', '00000000-0000-0000-0000-000000000001', 'BOX100', 'Box of 10 Strips', '100T')
on conflict (tenant_id, code) do nothing;

insert into public.products (
  id, tenant_id, division_id, category_id, brand_id, uom_id,
  product_code, name, generic_name, description, mrp, ptr, pts, is_active, is_prescription_required
)
values
  ('50000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000011', '50000000-0000-0000-0000-000000000021', 'PROD-CD-01', 'Cardiostep 50mg', 'Atenolol 50mg', 'Cardio-selective beta blocker for hypertension', 120.00, 85.71, 77.14, true, true),
  ('50000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000011', '50000000-0000-0000-0000-000000000021', 'PROD-CD-02', 'Cardiostep AM', 'Atenolol 50mg + Amlodipine 5mg', 'Dual mechanism anti-hypertensive therapy', 185.00, 132.14, 118.93, true, true),
  ('50000000-0000-0000-0000-000000000103', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000012', '50000000-0000-0000-0000-000000000021', 'PROD-DG-01', 'DiabaGard M 500', 'Metformin Hydrochloride 500mg SR', 'First-line sustained-release biguanide', 95.00, 67.86, 61.07, true, true),
  ('50000000-0000-0000-0000-000000000104', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000012', '50000000-0000-0000-0000-000000000021', 'PROD-DG-02', 'DiabaGard G2', 'Glimepiride 2mg + Metformin 500mg SR', 'Dual action anti-hyperglycemic combination', 160.00, 114.28, 102.85, true, true)
on conflict (tenant_id, product_code) do nothing;

insert into public.warehouses (id, tenant_id, code, name, warehouse_type, address, is_active)
values
  ('50000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-000000000001', 'WH-MUM', 'Bhiwandi Central C&F Hub', 'cnf', 'Plot 42, Indian Corporation Logistics Park, Bhiwandi, Thane, Maharashtra', true)
on conflict (tenant_id, code) do nothing;

insert into public.product_batches (
  id, tenant_id, product_id, batch_number, manufacturing_date, expiry_date,
  mrp, ptr, cost_price, is_quarantined
)
values
  ('50000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000101', 'CS50-26A', '2026-01-01', '2027-12-31', 120.00, 85.71, 55.00, false),
  ('50000000-0000-0000-0000-000000000302', '00000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000103', 'DM50-26A', '2026-01-01', '2027-12-31', 95.00, 67.86, 42.00, false)
on conflict (tenant_id, product_id, batch_number) do nothing;

insert into public.inventory_stocks (
  id, tenant_id, warehouse_id, product_id, batch_id,
  quantity_on_hand, quantity_allocated, quantity_available
)
values
  ('50000000-0000-0000-0000-000000000401', '00000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000201', '50000000-0000-0000-0000-000000000101', '50000000-0000-0000-0000-000000000301', 5000, 0, 5000),
  ('50000000-0000-0000-0000-000000000402', '00000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000201', '50000000-0000-0000-0000-000000000103', '50000000-0000-0000-0000-000000000302', 4500, 0, 4500)
on conflict (tenant_id, warehouse_id, product_id, batch_id) do nothing;


--------------------------------------------------------------------------------
-- 7. Field Operations: Tour Plan, Visits, and Sample POB Order
--------------------------------------------------------------------------------

-- Tour Plan for MR Amit Kumar
insert into public.tour_plans (
  id, tenant_id, mr_id, plan_month, plan_year,
  status, approved_by_user_id, approved_at, remarks
)
values (
  '60000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000004',
  10,
  2026,
  'approved',
  '20000000-0000-0000-0000-000000000002',
  now() - interval '4 days',
  'Monthly tour plan approved for Dadar-Parel hospital territory'
)
on conflict (tenant_id, mr_id, plan_month, plan_year) do nothing;

insert into public.tour_plan_days (
  id, tenant_id, tour_plan_id, planned_date, beat_id, activity_type
)
values (
  '60000000-0000-0000-0000-000000000011',
  '00000000-0000-0000-0000-000000000001',
  '60000000-0000-0000-0000-000000000001',
  current_date,
  '30000000-0000-0000-0000-000000000041',
  'field_work'
)
on conflict (tenant_id, tour_plan_id, planned_date) do nothing;

-- 1 Doctor Call by Amit Kumar
insert into public.field_visits (
  id, tenant_id, mr_id, visit_type, entity_type, entity_id, beat_id,
  tour_plan_day_id, visit_date, check_in_time, check_out_time,
  check_in_latitude, check_in_longitude, check_out_latitude, check_out_longitude,
  visit_status, remarks
)
values (
  '60000000-0000-0000-0000-000000000101',
  '00000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000004',
  'doctor',
  'doctors',
  '40000000-0000-0000-0000-000000000101',
  '30000000-0000-0000-0000-000000000041',
  '60000000-0000-0000-0000-000000000011',
  current_date,
  now() - interval '2 hours',
  now() - interval '1 hour 40 minutes',
  19.0178,
  72.8478,
  19.0179,
  72.8479,
  'completed',
  'Detailed discussion on Cardiostep 50mg efficacy in young hypertensives. Doctor was receptive.'
)
on conflict (id) do nothing;

-- 1 Chemist Call by Amit Kumar with POB Order
insert into public.field_visits (
  id, tenant_id, mr_id, visit_type, entity_type, entity_id, beat_id,
  tour_plan_day_id, visit_date, check_in_time, check_out_time,
  check_in_latitude, check_in_longitude, check_out_latitude, check_out_longitude,
  visit_status, remarks
)
values (
  '60000000-0000-0000-0000-000000000102',
  '00000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000004',
  'chemist',
  'chemists',
  '40000000-0000-0000-0000-000000000401',
  '30000000-0000-0000-0000-000000000041',
  '60000000-0000-0000-0000-000000000011',
  current_date,
  now() - interval '1 hour 30 minutes',
  now() - interval '1 hour 10 minutes',
  19.0182,
  72.8485,
  19.0182,
  72.8485,
  'completed',
  'Booked POB order for Cardiostep 50mg. Verified stock availability with Apex Western Distributors.'
)
on conflict (id) do nothing;

-- POB Order from Dadar LifeCare Chemist
insert into public.pobs (
  id, tenant_id, visit_id, mr_id, customer_type, entity_id,
  stockist_id, pob_date, total_amount, status, expected_delivery_date
)
values (
  '60000000-0000-0000-0000-000000000201',
  '00000000-0000-0000-0000-000000000001',
  '60000000-0000-0000-0000-000000000102',
  '20000000-0000-0000-0000-000000000004',
  'chemist',
  '40000000-0000-0000-0000-000000000401',
  '40000000-0000-0000-0000-000000000301',
  current_date,
  1714.20,
  'booked',
  current_date + interval '2 days'
)
on conflict (id) do nothing;

insert into public.pob_products (
  id, tenant_id, pob_id, product_id, quantity, rate, total_amount
)
values (
  '60000000-0000-0000-0000-000000000301',
  '00000000-0000-0000-0000-000000000001',
  '60000000-0000-0000-0000-000000000201',
  '50000000-0000-0000-0000-000000000101',
  20,
  85.71,
  1714.20
)
on conflict (id) do nothing;
