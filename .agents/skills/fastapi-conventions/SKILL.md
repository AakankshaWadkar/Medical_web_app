---
name: fastapi-conventions
description: Use when writing or reviewing FastAPI backend code in apps/api: structure, async SQLAlchemy, auth, errors, tests, migrations.
---

# FastAPI conventions

- Python 3.12, FastAPI, Pydantic v2, SQLAlchemy 2.0 async + asyncpg, pytest + pytest-asyncio, ruff.
- Layout: `app/core` (config, db, auth), `app/modules/<module>/{router,schemas,models,service}.py`. One module per owner in the domain skill.
- Routers are thin; business logic in `service.py`; DB access only through the tenant-scoped session.
- **Migrations: Supabase CLI SQL migrations in `supabase/migrations` are the single source of truth.** Do NOT use Alembic autogenerate; SQLAlchemy models mirror the schema by hand.
- Supabase pooler (transaction mode) does not support prepared statements: keep `statement_cache_size=0`.
- API: versioned `/v1`, cursor pagination, error body `{code, message, details}`, RBAC via `require_roles(...)`, AuditLog row for sensitive mutations.
- Secrets only via env/secret manager; never commit `.env`. Log without PII (doctor data).
- Every endpoint ships with tests, including a tenant-isolation test.
