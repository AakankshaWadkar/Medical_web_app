"""Database Schema Invariants Tests.
Verifies:
1. Forced RLS + policies on every tenant table.
2. No tables without `tenant_id` except the approved global platform allowlist.
3. No anon or authenticated permissions/grants on public business tables.
"""

import os

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

ADMIN = os.getenv("ADMIN_DB_URL", "postgresql+asyncpg://postgres:postgres@127.0.0.1:54122/postgres")

GLOBAL_TABLE_ALLOWLIST = {
    "tenants",
    "subscription_plans",
    "permissions",
    "countries",
    "states",
    "cities",
    "pin_codes",
    "currencies",
    "mobile_app_versions",
    "schema_migrations",
}


@pytest.fixture
async def admin_engine():
    engine = create_async_engine(ADMIN)
    yield engine
    await engine.dispose()


async def test_no_tables_without_tenant_id_except_allowlist(admin_engine):
    """Every business table must contain tenant_id unless explicitly allowlisted."""
    query = text("""
        select t.table_name
        from information_schema.tables t
        where t.table_schema = 'public'
          and t.table_type = 'BASE TABLE'
          and not exists (
              select 1
              from information_schema.columns c
              where c.table_schema = 'public'
                and c.table_name = t.table_name
                and c.column_name = 'tenant_id'
          )
    """)
    async with admin_engine.begin() as conn:
        rows = (await conn.execute(query)).scalars().all()

    disallowed = set(rows) - GLOBAL_TABLE_ALLOWLIST
    assert not disallowed, (
        f"Found public tables missing tenant_id without being in allowlist: {disallowed}"
    )


async def test_all_tenant_tables_have_forced_rls(admin_engine):
    """Every tenant table in public schema must have RLS enabled and FORCED."""
    query = text("""
        select c.relname
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relkind = 'r'
          and c.relname not in ('schema_migrations')
          and (not c.relrowsecurity or not c.relforcerowsecurity)
    """)
    async with admin_engine.begin() as conn:
        unforced_tables = (await conn.execute(query)).scalars().all()

    assert not unforced_tables, f"Tables missing ENABLE + FORCE RLS: {unforced_tables}"


async def test_all_tenant_tables_have_rls_policies(admin_engine):
    """Every table with RLS enabled must have at least one policy defined."""
    query = text("""
        select c.relname
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relkind = 'r'
          and c.relname not in ('schema_migrations')
          and not exists (
              select 1
              from pg_policy p
              where p.polrelid = c.oid
          )
    """)
    async with admin_engine.begin() as conn:
        tables_without_policies = (await conn.execute(query)).scalars().all()

    assert not tables_without_policies, f"Tables missing RLS policies: {tables_without_policies}"


async def test_no_anon_or_authenticated_grants_on_public_tables(admin_engine):
    """Clients never touch business tables directly via PostgREST; no grants to anon/authenticated."""
    query = text("""
        select table_name, grantee, privilege_type
        from information_schema.role_table_grants
        where table_schema = 'public'
          and grantee in ('anon', 'authenticated')
          and table_name not in ('schema_migrations')
    """)
    async with admin_engine.begin() as conn:
        leaked_grants = (await conn.execute(query)).all()

    assert not leaked_grants, f"Found unexpected grants to anon/authenticated: {leaked_grants}"
