-- PharmaSphere foundation: tenancy, backend role, RLS helper, auth hook, Activity.
-- UNTESTED TEMPLATE: run `supabase start && supabase db reset` and the isolation tests before relying on it.

-- ============ Backend role (FastAPI connects as this; it must NOT bypass RLS) ============
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'app_backend') then
    create role app_backend login nobypassrls;
  end if;
end $$;
-- Set the password out-of-band (never in a migration):  alter role app_backend password '<secret>';

grant usage on schema public to app_backend;
alter default privileges in schema public grant select, insert, update, delete on tables to app_backend;
alter default privileges in schema public grant usage, select on sequences to app_backend;

-- Clients never touch business tables through PostgREST: strip default Supabase grants.
alter default privileges in schema public revoke all on tables from anon, authenticated;
revoke all on all tables in schema public from anon, authenticated;

-- ============ Tenant context ============
create or replace function public.app_tenant_id() returns uuid
language sql stable as $$
  select nullif(current_setting('app.tenant_id', true), '')::uuid
$$;

create or replace function public.touch_row() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  new.version := coalesce(old.version, 0) + 1;
  return new;
end $$;

-- One call per tenant table: enable + FORCE RLS, policy, tenant index, touch trigger.
create or replace procedure public.apply_tenant_rls(p_table regclass)
language plpgsql as $$
declare v_name text := (select relname from pg_class where oid = p_table);
begin
  execute format('alter table %s enable row level security', p_table);
  execute format('alter table %s force row level security', p_table);
  execute format('drop policy if exists tenant_isolation on %s', p_table);
  execute format(
    'create policy tenant_isolation on %s for all to app_backend
       using (tenant_id = (select public.app_tenant_id()))
       with check (tenant_id = (select public.app_tenant_id()))', p_table);
  execute format('create index if not exists %I on %s (tenant_id)', 'idx_' || v_name || '_tenant', p_table);
  execute format('drop trigger if exists trg_touch on %s', p_table);
  execute format('create trigger trg_touch before update on %s for each row execute function public.touch_row()', p_table);
end $$;

-- ============ Core tables ============
create table public.tenants (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  slug        text not null unique,
  status      text not null default 'active' check (status in ('active','suspended','closed')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
-- tenants has no tenant_id; the backend reads only its own row.
alter table public.tenants enable row level security;
alter table public.tenants force row level security;
create policy tenant_self on public.tenants for select to app_backend
  using (id = (select public.app_tenant_id()));

create table public.app_users (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenants(id),
  auth_user_id  uuid not null unique references auth.users(id) on delete cascade,
  app_role      text not null check (app_role in ('admin','manager','mr')),
  full_name     text not null,
  manager_id    uuid references public.app_users(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  version       bigint not null default 1
);
call public.apply_tenant_rls('public.app_users');

-- Central field-force timeline (visits, check-ins, POBs, gifts, feedback...).
create table public.activities (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id),
  mr_id            uuid not null references public.app_users(id),
  activity_type    text not null,           -- e.g. doctor_visit, chemist_visit, check_in, pob, gift, feedback
  entity_type      text,                    -- doctors | chemists | ...
  entity_id        uuid,
  started_at       timestamptz not null,
  ended_at         timestamptz,
  latitude         double precision,
  longitude        double precision,
  payload          jsonb not null default '{}'::jsonb,
  idempotency_key  uuid not null,
  client_created_at timestamptz,
  received_at      timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  version          bigint not null default 1,
  unique (tenant_id, idempotency_key)
);
create index idx_activities_mr_time on public.activities (tenant_id, mr_id, started_at desc);
create index idx_activities_entity  on public.activities (tenant_id, entity_type, entity_id);
call public.apply_tenant_rls('public.activities');

-- ============ Supabase Auth hook: put tenant_id + app_role into the JWT ============
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb language plpgsql stable as $$
declare
  claims jsonb := event->'claims';
  u record;
begin
  select tenant_id, app_role into u
  from public.app_users
  where auth_user_id = (event->>'user_id')::uuid and deleted_at is null;

  if found then
    claims := jsonb_set(claims, '{tenant_id}', to_jsonb(u.tenant_id::text));
    claims := jsonb_set(claims, '{app_role}',  to_jsonb(u.app_role));
  end if;
  return jsonb_set(event, '{claims}', claims);
end $$;

grant usage on schema public to supabase_auth_admin;
grant execute on function public.custom_access_token_hook to supabase_auth_admin;
revoke execute on function public.custom_access_token_hook from authenticated, anon, public;
grant select on public.app_users to supabase_auth_admin;
create policy auth_hook_read on public.app_users for select to supabase_auth_admin using (true);
-- Enable in supabase/config.toml:
--   [auth.hook.custom_access_token]
--   enabled = true
--   uri = "pg-functions://postgres/public/custom_access_token_hook"
