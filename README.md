# PharmaSphere

Multi-tenant pharmaceutical Sales Force Automation (SFA), CRM, and ERP SaaS platform.

**Status:** Database schema (PostgreSQL 17 with RLS, 8 migrations, 190 tables, 3 views, seed data) and FastAPI backend (`apps/api` with 42 endpoints, 48 passing tests) are implemented; Admin Web Portal (`apps/web`) and MR Mobile App (`apps/mobile`) are planned.

## Tech Stack

| Layer | Technology | Status |
|:---|:---|:---|
| Database & Auth | Supabase (PostgreSQL 17, Row-Level Security, GoTrue Auth) | Implemented |
| Backend API | FastAPI (Python 3.12, SQLAlchemy 2.0 Async, asyncpg) | Implemented |
| Admin Web Portal | React | Planned |
| MR Mobile App | Flutter | Planned |

## Architecture

```text
Clients (React Web / Flutter Mobile)
       │ HTTP / JSON (Bearer JWT)
       ▼
FastAPI Backend (apps/api)
       │ asyncpg (role: app_backend, tenant_session: app.tenant_id = <uuid>)
       ▼
PostgreSQL Database (Supabase)
       └── Row-Level Security (RLS isolates tenants by tenant_id)
```

- Clients call the FastAPI backend only; direct PostgREST client access is revoked.
- FastAPI authenticates requests via Supabase Auth JWTs and connects to Postgres as role `app_backend` (`NOBYPASSRLS`).
- Every tenant-scoped request sets transaction-local `app.tenant_id = <tenant_uuid>`.
- PostgreSQL Row-Level Security (RLS) isolates tenant data at the database level by `tenant_id`.

## Repository Layout

```text
pharmasphere/
├── .agents/       # Agent skills, domain rules, and multi-tenancy conventions
├── apps/
│   └── api/       # FastAPI backend, domain modules, and pytest suite
├── docs/          # Architecture decisions, ERD, API status, and schema inventory
├── scripts/       # Developer automation and documentation scripts
└── supabase/      # Supabase configuration, SQL migrations, and seed data
```

## Prerequisites

- **Docker Desktop** (running): `docker info`
- **Node.js** (v20+): `node -v`
- **Python** (3.12+): `python --version` (or `py -3.12 --version`)
- **Git**: `git --version`

## Quick Start

For detailed step-by-step onboarding, see [docs/TEAM_SETUP.md](docs/TEAM_SETUP.md).

### 1. Start Database & Dependencies

```powershell
git clone <repo-url>
cd team-repo
npm install
npx supabase start
npx supabase db reset
```

### 2. Set Up API Backend & Run Tests

PowerShell:
```powershell
cd apps/api
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -e ".[dev]"
pytest
uvicorn app.main:app --reload --port 8000
```

Bash equivalent:
```bash
cd apps/api
python3.12 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
pytest
uvicorn app.main:app --reload --port 8000
```

Open interactive API documentation in your browser: [http://127.0.0.1:8000/docs](http://127.0.0.1:8000/docs).

### Local Service Ports

- **FastAPI Backend:** `http://127.0.0.1:8000` (docs: `/docs`)
- **Supabase Studio:** `http://127.0.0.1:54123` (configured in [supabase/config.toml](supabase/config.toml))
- **PostgreSQL Database:** `127.0.0.1:54122` (DB `postgres`, role `app_backend`)
- **Supabase API Gateway (Kong):** `http://127.0.0.1:54121`

## Demo Data

Local seeding creates a pre-configured tenant and hierarchical test accounts:

- **Demo Tenant:** Apex Pharma Solutions Ltd (`apex-pharma`, ID: `00000000-0000-0000-0000-000000000001`)
- **Admin User:** `admin@apexpharma.com`
- **Manager Users:** `vikram.manager@apexpharma.com`, `suresh.manager@apexpharma.com`
- **Medical Representatives (MRs):** `amit.mr@apexpharma.com`, `pooja.mr@apexpharma.com`, `rohan.mr@apexpharma.com`, `neha.mr@apexpharma.com`

*Passwords and credentials are documented in [supabase/seed.sql](supabase/seed.sql) and [docs/TEAM_SETUP.md](docs/TEAM_SETUP.md). Never print or commit plaintext credentials.*

## Working with the Database

- **Never edit merged migrations:** Existing files in `supabase/migrations/` are immutable sources of truth.
- **Add new migrations via CLI:** Create new schema migrations with `npx supabase migration new <migration_name>`.
- **Enforce tenant RLS:** Every tenant-bound table must call `call public.apply_tenant_rls('public.<table_name>');` to force RLS, create tenant isolation policies, and add `idx_<table_name>_tenant`.
- **Views use security_invoker:** All database views must define `with (security_invoker = true)` so querying callers execute under underlying table RLS policies.
- **Run tests before pushing:** Run `pytest` in `apps/api` to verify schema invariants and tenant isolation before committing or pushing.

## Team Workflow

- **Branch per task:** Create a dedicated branch for each feature or bug fix (`git switch -c feature/<task-name>`).
- **Pull request & review:** Open a PR against `main`; changes require peer review and passing CI checks.
- **No direct push to main:** The `main` branch is protected; all code must merge via approved PRs.

## Documentation Index

| Document | Purpose |
|:---|:---|
| [docs/TEAM_SETUP.md](docs/TEAM_SETUP.md) | Developer onboarding, setup commands, and architecture walkthrough |
| [docs/PROJECT_CONTEXT.md](docs/PROJECT_CONTEXT.md) | System architecture overview, security invariants, and stage delivery status |
| [docs/API_STATUS.md](docs/API_STATUS.md) | Inventory of implemented API endpoints, allowed roles, and test coverage |
| [docs/decisions.md](docs/decisions.md) | Architecture, database schema, and security decision log |
| [docs/erd.md](docs/erd.md) | Entity Relationship Diagram and relational database schema specification |
| [docs/FILE_MAP.md](docs/FILE_MAP.md) | Repository directory structure map and file descriptions |
| [docs/schema-description.md](docs/schema-description.md) | Functional descriptions of domain layers, business entities, and workflows |
| [docs/schema-inventory.md](docs/schema-inventory.md) | Complete inventory of database tables, columns, constraints, and indexes |

## Troubleshooting

1. **Docker daemon not running:**
   - *Problem:* `npx supabase start` fails with daemon connection errors.
   - *Fix:* Ensure Docker Desktop is launched and running (`docker info`).
2. **Port already allocated:**
   - *Problem:* Service fails to bind because port 54121, 54122, 54123, or 8000 is occupied.
   - *Fix:* Identify the process with `Get-NetTCPConnection -LocalPort <port>` (PowerShell) or `lsof -i :<port>` (bash) and terminate it, or verify existing containers with `docker ps`.
3. **401 Unauthorized on `/v1/me` (Auth hook not enabled):**
   - *Problem:* Requests to `/v1/me` fail with 401 Unauthorized or missing tenant claims.
   - *Fix:* Verify `[auth.hook.custom_access_token]` is enabled in [supabase/config.toml](supabase/config.toml) (`enabled = true`, URI `pg-functions://postgres/public/custom_access_token_hook`), then run `npx supabase db reset`.
