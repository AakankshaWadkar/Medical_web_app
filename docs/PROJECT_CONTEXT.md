# PharmaSphere Project Context

A one-page summary of system architecture, organization, rules, execution instructions, and implementation status.

---

## 1. Architecture Overview
- **Product:** Multi-tenant SaaS for pharmaceutical Sales Force Automation (SFA), CRM, and ERP.
- **Client Tier:** React Web App (Admins/Managers) and Flutter Mobile App (Field Medical Representatives).
- **Backend API:** FastAPI (Python 3.12, Pydantic v2, SQLAlchemy 2.0 Async, asyncpg).
- **Database & Auth:** Supabase Local Postgres with Row Level Security (RLS) and Supabase Auth.
- **Security Invariant:** FastAPI connects strictly as Postgres role `app_backend` (`nobypassrls`). Every tenant-scoped request runs inside `tenant_session` setting transaction-local `app.tenant_id = <tenant_uuid>`. Clients never connect to PostgREST directly.

---

## 2. Directory Structure Map
```
pharmasphere/
├── .agents/skills/            # Domain knowledge, isolation rules, conventions
├── docs/                      # ERD, decisions, schema inventory, project context
├── supabase/
│   ├── migrations/            # Source of truth SQL migrations (20260101 - 20260108)
│   ├── seed.sql               # Demo tenant, admin, managers, MRs, catalog, field data
├── apps/
│   └── api/
│       ├── app/
│       │   ├── core/          # config, db, auth, errors, pagination, middleware
│       │   ├── modules/       # Domain modules: users, masters, field, orders, reports
│       │   ├── cli.py         # Platform CLI (tenant provisioning)
│       │   └── main.py        # FastAPI entrypoint
│       ├── tests/             # Pytest test suite (invariants, isolation, endpoints)
│       └── pyproject.toml     # Dependencies and tooling config (ruff, pytest)
```

---

## 3. How to Run & Test
- **Start Supabase:** `npx supabase start`
- **Reset DB with seed:** `npx supabase db reset`
- **Run Backend:** `cd apps/api && .venv\Scripts\uvicorn app.main:app --reload --port 8000`
- **Run Tests:** `cd apps/api && .venv\Scripts\pytest`
- **Lint & Format Check:** `cd apps/api && .venv\Scripts\ruff check . && .venv\Scripts\ruff format --check .`

---

## 4. Key Rules & Invariants
1. **Schema Immutability:** Never modify existing migrations. Single source of truth is `supabase/migrations`.
2. **Tenant ID Propagation:** Tenant ID is extracted strictly from verified Supabase JWT claims (`tenant_id`), never from query strings or request payloads.
3. **Hierarchy & Scoped Authorization:**
   - **Admin:** Full tenant visibility.
   - **Manager:** Visibility over self and all subordinates via recursive CTE on `manager_id`.
   - **MR:** Scoped to self and assigned territories.
4. **API Standards:**
   - Standard error response: `{"code": str, "message": str, "details": any}`.
   - Idempotent writes via `(tenant_id, idempotency_key)`.
   - Pagination on all lists with max page bounds.
   - Timestamps in UTC (`timestamptz`), currency in `Decimal`.
   - Structured logging without PII (no doctor names, phones, tokens).

---

## 5. Current Implementation Status
- **Stage 1 (Foundation):** COMPLETED. Core config, async DB session with transaction-local tenant context, JWT verification with JWKS/HS256 fallback, Principal extraction, require_roles RBAC, uniform error response handlers, pagination helpers, /healthz, /v1/me, request-id middleware, and platform CLI `python -m app.cli create-tenant`.
- **Stage 2 (Users):** COMPLETED. Admin-only user management (/v1/users): create, list with role/status/search filters, get by ID, patch updates, and deactivation with automatic Supabase Auth login ban and comprehensive audit logging. Fully tested with isolation and real HTTP tests.
- **Stage 3 (Masters):** COMPLETED. Full master data management for sales territories, MR territory assignment (`/v1/territories/{id}/assign-mr`), doctors master, chemists master, and finished products catalog. Implemented role-based visibility scoping (Admin sees all tenant masters, Manager sees territories/doctors/chemists in self/subordinate team hierarchy via recursive CTE, MR sees only their assigned territories and doctors/chemists in those territories).
- **Stage 4 (Field Work):** COMPLETED. Implemented MR field operations including visit check-in (with time & GPS, territory boundary verification), visit check-out, doctor feedback, chemist feedback, pre-order bookings (POB) with server-side pricing from PTR/discounts, activity timeline tracking with strict client `idempotency_key` deduplication, and Daily Call Report (DCR) automatic rollups and read endpoint.
- **Stage 5 (Orders):** COMPLETED. Implemented primary wholesale orders (`/v1/orders/primary`) and secondary chemist sales statements (`/v1/orders/secondary`). Features server-side total/tax/discount computation from product master prices (PTS/PTR), and enforces a strict status state machine (`draft -> submitted -> approved -> processing -> dispatched`) with manager/admin approval safeguards.
- **Stage 6 (Reports):** COMPLETED. Analytical reporting endpoints querying database views: MR performance summary (`/v1/reports/mr-performance`), doctor coverage metrics (`/v1/reports/doctor-coverage`), and secondary sales aggregates (`/v1/reports/secondary-sales`). All reporting endpoints feature role-scoped access control and date/period filtering.
