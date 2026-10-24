-- Migration: 20260102000000_core_tenancy_extensions.sql
-- Stage (a): Core platform + Tenancy extensions

-- 1. Extend tenants table with company profile fields
alter table public.tenants drop constraint if exists tenants_status_check;
alter table public.tenants add constraint tenants_status_check check (status in ('trial','active','suspended','closed'));

alter table public.tenants
  add column if not exists company_code text,
  add column if not exists legal_name text,
  add column if not exists gst_no text,
  add column if not exists drug_license_no text,
  add column if not exists pan_no text,
  add column if not exists email text,
  add column if not exists phone text,
  add column if not exists website text,
  add column if not exists address text,
  add column if not exists city text,
  add column if not exists state text,
  add column if not exists pincode text,
  add column if not exists currency text not null default 'INR';

-- 2. Branches table
create table public.branches (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  name           text not null,
  code           text not null,
  is_head_office boolean not null default false,
  address        text,
  city           text,
  state          text,
  pincode        text,
  phone          text,
  email          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  version        bigint not null default 1,
  unique (tenant_id, code)
);
create index idx_branches_tenant on public.branches (tenant_id);
call public.apply_tenant_rls('public.branches');

-- 3. Departments table
create table public.departments (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  branch_id   uuid references public.branches(id) on delete cascade,
  code        text not null,
  name        text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  version     bigint not null default 1,
  unique (tenant_id, branch_id, code)
);
create index idx_departments_branch on public.departments (tenant_id, branch_id);
call public.apply_tenant_rls('public.departments');

-- 4. Extend app_users with employee/organization fields
alter table public.app_users drop constraint if exists app_users_tenant_id_fkey;
alter table public.app_users add constraint app_users_tenant_id_fkey foreign key (tenant_id) references public.tenants(id) on delete cascade;

alter table public.app_users
  add column if not exists employee_code text,
  add column if not exists phone text,
  add column if not exists branch_id uuid references public.branches(id) on delete set null,
  add column if not exists department_id uuid references public.departments(id) on delete set null,
  add column if not exists status text not null default 'active' check (status in ('active','invited','suspended'));

create index if not exists idx_app_users_branch on public.app_users (tenant_id, branch_id);
create index if not exists idx_app_users_department on public.app_users (tenant_id, department_id);

-- 5. Global Subscription Plans (Allowlisted global platform table)
create table public.subscription_plans (
  id             uuid primary key default gen_random_uuid(),
  code           text not null unique,
  name           text not null,
  max_users      integer not null default 10,
  max_branches   integer not null default 1,
  max_storage_gb integer not null default 5,
  price          numeric(14,2) not null default 0.00,
  billing_cycle  text not null default 'monthly' check (billing_cycle in ('monthly','annual')),
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
alter table public.subscription_plans enable row level security;
alter table public.subscription_plans force row level security;
create policy plan_read on public.subscription_plans for select to app_backend using (is_active = true);

-- 6. Tenant Subscriptions (CompanySubscription)
create table public.company_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  plan_id     uuid not null references public.subscription_plans(id),
  start_date  timestamptz not null default now(),
  end_date    timestamptz not null,
  status      text not null default 'active' check (status in ('trial','active','expired','cancelled')),
  auto_renew  boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  version     bigint not null default 1
);
create index idx_company_subs_plan on public.company_subscriptions (tenant_id, plan_id);
call public.apply_tenant_rls('public.company_subscriptions');

-- 7. Roles table (Tenant-scoped)
create table public.roles (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  code        text not null,
  name        text not null,
  description text,
  is_system   boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  version     bigint not null default 1,
  unique (tenant_id, code)
);
call public.apply_tenant_rls('public.roles');

-- 8. Permissions catalog (Allowlisted global table)
create table public.permissions (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,
  module      text not null,
  description text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table public.permissions enable row level security;
alter table public.permissions force row level security;
create policy perm_read on public.permissions for select to app_backend using (true);

-- 9. User Roles bridge
create table public.user_roles (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  user_id     uuid not null references public.app_users(id) on delete cascade,
  role_id     uuid not null references public.roles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  version     bigint not null default 1,
  unique (tenant_id, user_id, role_id)
);
create index idx_user_roles_user on public.user_roles (tenant_id, user_id);
create index idx_user_roles_role on public.user_roles (tenant_id, role_id);
call public.apply_tenant_rls('public.user_roles');

-- 10. Role Permissions bridge
create table public.role_permissions (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  role_id        uuid not null references public.roles(id) on delete cascade,
  permission_id  uuid not null references public.permissions(id) on delete cascade,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  version        bigint not null default 1,
  unique (tenant_id, role_id, permission_id)
);
create index idx_role_perms_role on public.role_permissions (tenant_id, role_id);
create index idx_role_perms_perm on public.role_permissions (tenant_id, permission_id);
call public.apply_tenant_rls('public.role_permissions');

-- 11. Tenant Settings
create table public.tenant_settings (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenants(id) on delete cascade,
  category      text not null,
  setting_key   text not null,
  setting_value text not null,
  data_type     text not null default 'string' check (data_type in ('string','number','boolean','json')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  version       bigint not null default 1,
  unique (tenant_id, category, setting_key)
);
call public.apply_tenant_rls('public.tenant_settings');

-- 12. User Notification Preferences
create table public.user_notification_preferences (
  id                   uuid primary key default gen_random_uuid(),
  tenant_id            uuid not null references public.tenants(id) on delete cascade,
  user_id              uuid not null references public.app_users(id) on delete cascade,
  email_enabled        boolean not null default true,
  whatsapp_enabled     boolean not null default true,
  push_enabled         boolean not null default true,
  sms_enabled          boolean not null default true,
  daily_summary_enabled boolean not null default true,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz,
  version              bigint not null default 1,
  unique (tenant_id, user_id)
);
create index idx_user_notif_pref_user on public.user_notification_preferences (tenant_id, user_id);
call public.apply_tenant_rls('public.user_notification_preferences');

-- 13. File Storage
create table public.file_storage (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.tenants(id) on delete cascade,
  module_name         text not null,
  entity_type         text not null,
  entity_id           uuid,
  file_name           text not null,
  file_path           text not null,
  file_size_bytes     bigint not null default 0,
  content_type        text not null,
  uploaded_by_user_id uuid references public.app_users(id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  version             bigint not null default 1
);
create index idx_file_storage_entity on public.file_storage (tenant_id, entity_type, entity_id);
create index idx_file_storage_uploader on public.file_storage (tenant_id, uploaded_by_user_id);
call public.apply_tenant_rls('public.file_storage');

-- 14. Audit Logs
create table public.audit_logs (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  user_id     uuid references public.app_users(id) on delete set null,
  entity_name text not null,
  entity_id   uuid,
  action      text not null check (action in ('insert','update','delete','login','export')),
  old_values  jsonb,
  new_values  jsonb,
  ip_address  text,
  user_agent  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  version     bigint not null default 1
);
create index idx_audit_logs_entity on public.audit_logs (tenant_id, entity_name, entity_id);
create index idx_audit_logs_user on public.audit_logs (tenant_id, user_id, created_at desc);
call public.apply_tenant_rls('public.audit_logs');

-- 15. Login Histories (RefreshToken skipped as Supabase Auth owns it)
create table public.login_histories (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  user_id     uuid not null references public.app_users(id) on delete cascade,
  login_at    timestamptz not null default now(),
  logout_at   timestamptz,
  ip_address  text,
  user_agent  text,
  device_info jsonb not null default '{}'::jsonb,
  status      text not null default 'success' check (status in ('success','failed')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  version     bigint not null default 1
);
create index idx_login_histories_user on public.login_histories (tenant_id, user_id, login_at desc);
call public.apply_tenant_rls('public.login_histories');

-- 16. User Sessions
create table public.user_sessions (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  user_id     uuid not null references public.app_users(id) on delete cascade,
  token_hash  text not null,
  device_name text,
  expires_at  timestamptz not null,
  is_revoked  boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  version     bigint not null default 1
);
create index idx_user_sessions_user on public.user_sessions (tenant_id, user_id);
create index idx_user_sessions_token on public.user_sessions (tenant_id, token_hash);
call public.apply_tenant_rls('public.user_sessions');
