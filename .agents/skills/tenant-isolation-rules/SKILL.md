---
name: tenant-isolation-rules
description: MANDATORY when creating tables, migrations, queries, endpoints, or storage paths. Enforces tenant isolation with Postgres RLS on Supabase while FastAPI connects directly.
---

# Tenant isolation rules

Architecture: Flutter/React call FastAPI only. FastAPI connects to Supabase Postgres as role `app_backend` (NOT postgres/service_role, which bypass RLS). The tenant id comes from the verified JWT claim `tenant_id`, never from request body/query.

## Every tenant table
1. Columns: `id uuid pk default gen_random_uuid()`, `tenant_id uuid not null references tenants(id)`, `created_at`, `updated_at`, `deleted_at`, `version bigint default 1`.
2. After creating it, run `call apply_tenant_rls('public.<table>');` (enables + FORCES RLS, adds policy and tenant_id index).
3. Composite indexes start with `tenant_id`. Unique constraints include `tenant_id`.
4. `anon` and `authenticated` roles must have NO grants on business tables (clients never use PostgREST for business data).

## Request path
- `get_principal` verifies the Supabase JWT. `tenant_session` opens a transaction and runs `set_config('app.tenant_id', <uuid>, true)` (transaction-local).
- Never use a session outside `tenant_session`. Never use a superuser connection in request handlers. Admin/cross-tenant jobs use a separate, explicitly named module and role.
- Storage object paths start with `{tenant_id}/`.

## Required tests (block merge if missing)
- Tenant A cannot read, update, or delete tenant B rows.
- Insert with a foreign `tenant_id` is rejected by `WITH CHECK`.
- With no `app.tenant_id` set, queries return zero rows.
