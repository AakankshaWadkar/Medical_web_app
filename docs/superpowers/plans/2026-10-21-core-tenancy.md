# Core + Tenancy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Core + Tenancy slice, including branch schema migration, platform super-admin tenant provisioning, and tenant-scoped user management with role hierarchy (`admin > manager > mr`) and email invites.

**Architecture:** Strict separation between platform administration and tenant operations. Platform provisioning operates via a dedicated elevated database session and Supabase Auth admin client in `app/platform`. All tenant-facing endpoints in `app/modules/core` execute strictly as the `app_backend` role within `tenant_session`, protected by PostgreSQL Row-Level Security.

**Tech Stack:** Python 3.12, FastAPI, SQLAlchemy 2.0 (asyncio + asyncpg), Supabase Auth Admin REST API, Pydantic v2, Pytest (pytest-asyncio).

**Spec:** Assisted B2B onboarding specification agreed during brainstorming:
1. Platform super-admin creates tenant (company name, slug, first admin name, email).
2. Provisions tenant row (status: active/trial) and one default head-office branch.
3. Provisions first Admin via Supabase Auth Admin API and records `app_users` row (`app_role='admin'`).
4. Tenant Admin invites Managers and MRs via email through the web API.
5. User hierarchy enforces `admin > manager > mr` with `manager_id`.
6. User deactivation soft-deletes (`deleted_at = now()`) and reassigns subordinate direct reports.

## Global Constraints

- Python floor: `>=3.12`
- Every tenant table has: `id uuid pk default gen_random_uuid()`, `tenant_id uuid not null references tenants(id)`, `created_at`, `updated_at`, `deleted_at`, `version bigint default 1`.
- Every tenant table must execute `call public.apply_tenant_rls('public.<table>');`.
- Database connections for tenant endpoints must use `statement_cache_size=0`.
- Platform admin operations must live exclusively in `app/platform/`, completely decoupled from tenant modules.
- Endpoints must be versioned (`/v1/...` for tenant endpoints, `/internal/platform/...` for super-admin).
- Error responses must follow `{ "code": str, "message": str, "details": dict | list | None }`.

## Review Focus

1. **Unauthenticated or non-platform request to tenant provisioning:** Calling `POST /internal/platform/tenants` with missing or invalid `X-Platform-Admin-Key` returns `401 Unauthorized`. (Pinned to Task 2)
2. **Role escalation on user invite:** A non-admin user (`manager` or `mr`) attempting `POST /v1/core/users/invite` receives `403 Forbidden`. (Pinned to Task 4)
3. **Deactivating manager with active subordinates without reassignment:** Calling `PATCH /v1/core/users/{id}/deactivate` on a manager who has reporting MRs without supplying `reassign_to_user_id` returns `422 Unprocessable Entity`. (Pinned to Task 4)
4. **Cross-tenant manager assignment:** An Admin attempting to invite an MR with a `manager_id` belonging to a different tenant receives `404 Not Found` (manager not visible in tenant context). (Pinned to Task 4)
5. **Cross-tenant data leakage:** User listing on `GET /v1/core/users` for Tenant A returns zero users from Tenant B. (Pinned to Task 4)

---

### Task 1: Branches Migration & Tenant Status Extension

**Files:**
- Create: `supabase/migrations/20260102000000_core_branches.sql`
- Test: `apps/api/tests/test_branches_migration.py`

**Interfaces:**
- Consumes: `public.tenants`, `public.apply_tenant_rls` from `supabase/migrations/20260101000000_foundation.sql`.
- Produces: `public.branches` table with tenant isolation and RLS policies enforced.

- [ ] **Step 1: Write the failing test**

Create `apps/api/tests/test_branches_migration.py`:
```python
import os
import uuid
import pytest
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
from sqlalchemy.ext.asyncio import create_async_engine

ADMIN = os.getenv("ADMIN_DB_URL", "postgresql+asyncpg://postgres:postgres@127.0.0.1:54122/postgres")
APP = os.getenv("APP_DB_URL", "postgresql+asyncpg://app_backend:app_backend_dev@127.0.0.1:54122/postgres")

@pytest.fixture
async def two_tenants_with_branches():
    admin = create_async_engine(ADMIN)
    t1, t2 = uuid.uuid4(), uuid.uuid4()
    async with admin.begin() as c:
        for t in (t1, t2):
            await c.execute(
                text("insert into tenants(id, name, slug, status) values (:i, :n, :s, 'trial')"),
                {"i": t, "n": f"T-{t}", "s": f"slug-{t}"},
            )
            await c.execute(
                text("insert into branches(tenant_id, name, code, is_head_office) values (:t, 'Head Office', 'HO', true)"),
                {"t": t},
            )
    yield t1, t2
    async with admin.begin() as c:
        await c.execute(text("delete from branches where tenant_id in (:a, :b)"), {"a": t1, "b": t2})
        await c.execute(text("delete from tenants where id in (:a, :b)"), {"a": t1, "b": t2})
    await admin.dispose()

async def test_tenant_sees_only_own_branches(two_tenants_with_branches):
    t1, t2 = two_tenants_with_branches
    app = create_async_engine(APP, connect_args={"statement_cache_size": 0})
    async with app.begin() as c:
        await c.execute(text("select set_config('app.tenant_id', :t, true)"), {"t": str(t1)})
        rows = (await c.execute(text("select name, code, is_head_office from branches"))).all()
    assert len(rows) == 1
    assert rows[0].code == "HO"
    await app.dispose()

async def test_branch_duplicate_code_in_same_tenant_fails(two_tenants_with_branches):
    t1, _ = two_tenants_with_branches
    app = create_async_engine(APP, connect_args={"statement_cache_size": 0})
    with pytest.raises(DBAPIError):
        async with app.begin() as c:
            await c.execute(text("select set_config('app.tenant_id', :t, true)"), {"t": str(t1)})
            await c.execute(
                text("insert into branches(tenant_id, name, code) values (:t, 'Branch 2', 'HO')"),
                {"t": t1},
            )
    await app.dispose()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/api && .\.venv\Scripts\pytest tests/test_branches_migration.py -v`
Expected: FAIL with relation "branches" does not exist.

- [ ] **Step 3: Implement migration in `supabase/migrations/20260102000000_core_branches.sql`**

```sql
-- Extend tenants status check to include 'trial'
alter table public.tenants drop constraint if exists tenants_status_check;
alter table public.tenants add constraint tenants_status_check check (status in ('trial','active','suspended','closed'));

-- Core: branches
create table public.branches (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  name           text not null,
  code           text not null,
  is_head_office boolean not null default false,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  version        bigint not null default 1,
  unique (tenant_id, code)
);

create index idx_branches_tenant on public.branches (tenant_id);
call public.apply_tenant_rls('public.branches');
```

Apply migration via: `npx supabase db reset`

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/api && .\.venv\Scripts\pytest tests/test_branches_migration.py -v`
Expected: PASS (2 passed)

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260102000000_core_branches.sql apps/api/tests/test_branches_migration.py
git commit -m "feat(db): add branches table and update tenant status constraint"
```

---

### Task 2: Platform Admin Tenant Provisioning

**Files:**
- Create: `apps/api/app/platform/__init__.py`
- Create: `apps/api/app/platform/db.py`
- Create: `apps/api/app/platform/schemas.py`
- Create: `apps/api/app/platform/auth_client.py`
- Create: `apps/api/app/platform/service.py`
- Create: `apps/api/app/platform/router.py`
- Modify: `apps/api/app/core/config.py`
- Test: `apps/api/tests/test_platform_admin.py`

**Interfaces:**
- Consumes:
  - `ADMIN_DB_URL` and `SUPABASE_SERVICE_ROLE_KEY` from settings.
- Produces:
  - `provision_tenant(admin_session, auth_client, data: TenantCreateRequest) -> TenantCreateResponse`
  - `POST /internal/platform/tenants` (requires `X-Platform-Admin-Key` header matching `settings.platform_admin_key`)

- [ ] **Step 1: Write the failing test**

Create `apps/api/tests/test_platform_admin.py`:
```python
import pytest
from httpx import ASGITransport, AsyncClient
from app.main import app
from app.core.config import settings

@pytest.mark.asyncio
async def test_platform_provisioning_requires_key():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post("/internal/platform/tenants", json={"name": "A", "slug": "a", "admin_name": "Adm", "admin_email": "a@x.com"})
    assert res.status_code == 401

@pytest.mark.asyncio
async def test_platform_provisions_tenant_and_admin(monkeypatch):
    test_key = "secret-platform-key"
    monkeypatch.setattr(settings, "platform_admin_key", test_key)

    async def fake_invite(email: str, data: dict):
        return "11111111-1111-1111-1111-111111111111"

    from app.platform import auth_client
    monkeypatch.setattr(auth_client, "invite_admin_user", fake_invite)

    payload = {
        "name": "Apex Pharma",
        "slug": "apex-pharma",
        "admin_name": "John Doe",
        "admin_email": "john@apexpharma.com"
    }

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post(
            "/internal/platform/tenants",
            json=payload,
            headers={"X-Platform-Admin-Key": test_key}
        )
    assert res.status_code == 201
    data = res.json()
    assert data["name"] == "Apex Pharma"
    assert data["slug"] == "apex-pharma"
    assert data["head_office_branch"]["name"] == "Head Office"
    assert data["admin"]["email"] == "john@apexpharma.com"
    assert data["admin"]["role"] == "admin"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/api && .\.venv\Scripts\pytest tests/test_platform_admin.py -v`
Expected: FAIL with 404 Not Found (router not yet mounted or defined).

- [ ] **Step 3: Implement Platform Admin provisioning**

1. Update `apps/api/app/core/config.py`:
   - Add `admin_database_url: str = "postgresql+asyncpg://postgres:postgres@127.0.0.1:54122/postgres"`
   - Add `supabase_service_role_key: str = ""`
   - Add `platform_admin_key: str = "dev-platform-admin-secret"`
2. Implement `apps/api/app/platform/db.py`:
   - Create separate `admin_engine = create_async_engine(settings.admin_database_url, ...)`
   - Create `AdminSessionLocal = async_sessionmaker(admin_engine, expire_on_commit=False)`
   - Dependency: `get_admin_session() -> AsyncIterator[AsyncSession]`
3. Implement `apps/api/app/platform/auth_client.py`:
   - `async def invite_admin_user(email: str, user_metadata: dict) -> str`
   - Calls Supabase Auth Admin REST endpoint `POST {settings.supabase_url}/auth/v1/invite` with Bearer `{settings.supabase_service_role_key}` and returns the generated `user_id`.
4. Implement `apps/api/app/platform/schemas.py`:
   - `TenantCreateRequest`: `name: str`, `slug: str`, `admin_name: str`, `admin_email: EmailStr`
   - `TenantCreateResponse`: `id: UUID`, `name: str`, `slug: str`, `status: str`, `head_office_branch: dict`, `admin: dict`
5. Implement `apps/api/app/platform/service.py`:
   - `async def provision_tenant(session: AsyncSession, data: TenantCreateRequest) -> TenantCreateResponse`:
     - Inserts into `public.tenants`.
     - Inserts into `public.branches` with `code="HO"`, `is_head_office=True`.
     - Calls `invite_admin_user`.
     - Inserts into `public.app_users` with `app_role="admin"`, `auth_user_id`.
6. Implement `apps/api/app/platform/router.py`:
   - Check `X-Platform-Admin-Key` header.
   - Endpoint: `POST /internal/platform/tenants`.
7. Mount router in `apps/api/app/main.py`:
   - `app.include_router(platform_router, prefix="/internal/platform", tags=["Platform Admin"])`

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/api && .\.venv\Scripts\pytest tests/test_platform_admin.py -v`
Expected: PASS (2 passed)

- [ ] **Step 5: Commit**

```bash
git add apps/api/app/platform apps/api/app/core/config.py apps/api/app/main.py apps/api/tests/test_platform_admin.py
git commit -m "feat(platform): implement assisted tenant onboarding endpoint"
```

---

### Task 3: Tenant Core Models & Tenant Profile Endpoint

**Files:**
- Create: `apps/api/app/modules/core/__init__.py`
- Create: `apps/api/app/modules/core/models.py`
- Create: `apps/api/app/modules/core/schemas.py`
- Create: `apps/api/app/modules/core/service.py`
- Create: `apps/api/app/modules/core/router.py`
- Modify: `apps/api/app/main.py`
- Test: `apps/api/tests/test_core_tenant.py`

**Interfaces:**
- Consumes: `tenant_session`, `Principal`, `require_roles` from `app.core`.
- Produces:
  - `GET /v1/core/tenant` -> `TenantDetailResponse` (current tenant details, status, and active branches).

- [ ] **Step 1: Write the failing test**

Create `apps/api/tests/test_core_tenant.py`:
```python
import uuid
import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine
import jwt
from app.main import app
from app.core.config import settings

@pytest.fixture
async def seeded_tenant():
    admin = create_async_engine(settings.admin_database_url)
    t_id = uuid.uuid4()
    u_id = uuid.uuid4()
    async with admin.begin() as c:
        await c.execute(text("insert into tenants (id, name, slug, status) values (:t, 'Pharma Corp', 'pharma-corp', 'active')"), {"t": t_id})
        await c.execute(text("insert into branches (tenant_id, name, code, is_head_office) values (:t, 'HQ', 'HO', true)"), {"t": t_id})
    yield t_id, u_id
    async with admin.begin() as c:
        await c.execute(text("delete from branches where tenant_id = :t"), {"t": t_id})
        await c.execute(text("delete from tenants where id = :t"), {"t": t_id})
    await admin.dispose()

@pytest.mark.asyncio
async def test_get_tenant_profile(seeded_tenant, monkeypatch):
    t_id, u_id = seeded_tenant
    token = jwt.encode(
        {"sub": str(u_id), "tenant_id": str(t_id), "app_role": "admin", "exp": 9999999999, "aud": "authenticated"},
        "super-secret-jwt-token-with-at-least-32-characters-long",
        algorithm="HS256"
    )
    monkeypatch.setattr(settings, "supabase_jwt_secret", "super-secret-jwt-token-with-at-least-32-characters-long")

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.get("/v1/core/tenant", headers={"Authorization": f"Bearer {token}"})
    assert res.status_code == 200
    data = res.json()
    assert data["name"] == "Pharma Corp"
    assert data["slug"] == "pharma-corp"
    assert len(data["branches"]) == 1
    assert data["branches"][0]["code"] == "HO"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/api && .\.venv\Scripts\pytest tests/test_core_tenant.py -v`
Expected: FAIL with 404 Not Found.

- [ ] **Step 3: Implement Core Models and Tenant Profile Endpoint**

1. Implement `apps/api/app/modules/core/models.py`:
   - Declare Base, `TenantModel`, `BranchModel`, `AppUserModel` mirroring schema.
2. Implement `apps/api/app/modules/core/schemas.py`:
   - `BranchResponse`: `id: UUID`, `name: str`, `code: str`, `is_head_office: bool`
   - `TenantDetailResponse`: `id: UUID`, `name: str`, `slug: str`, `status: str`, `branches: list[BranchResponse]`
3. Implement `apps/api/app/modules/core/service.py`:
   - `async def get_current_tenant_profile(session: AsyncSession) -> TenantDetailResponse`:
     - Queries `TenantModel` and `BranchModel` (filtered automatically by PostgreSQL RLS).
4. Implement `apps/api/app/modules/core/router.py`:
   - `GET /v1/core/tenant`: depends on `tenant_session` and `get_principal`.
5. Mount `core_router` in `apps/api/app/main.py`:
   - `app.include_router(core_router, prefix="/v1/core", tags=["Core"])`

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/api && .\.venv\Scripts\pytest tests/test_core_tenant.py -v`
Expected: PASS (1 passed)

- [ ] **Step 5: Commit**

```bash
git add apps/api/app/modules/core apps/api/app/main.py apps/api/tests/test_core_tenant.py
git commit -m "feat(core): add models and tenant profile endpoint"
```

---

### Task 4: Team Management (Invite, Hierarchy, Deactivation & Reassignment)

**Files:**
- Modify: `apps/api/app/modules/core/schemas.py`
- Modify: `apps/api/app/modules/core/service.py`
- Modify: `apps/api/app/modules/core/router.py`
- Test: `apps/api/tests/test_core_users.py`

**Interfaces:**
- Consumes:
  - `require_roles("admin")`, `tenant_session`, `Principal`
  - Supabase Auth admin API via `invite_user_by_email`
- Produces:
  - `GET /v1/core/users` (list active team members with optional `role` and `manager_id` filters)
  - `POST /v1/core/users/invite` (admin invites Manager or MR with hierarchy validation)
  - `PATCH /v1/core/users/{user_id}/deactivate` (admin deactivates user, soft deletes, reassigns subordinates)

- [ ] **Step 1: Write the failing tests**

Create `apps/api/tests/test_core_users.py`:
- Test 1: Non-admin cannot invite users (Review Focus 2 -> 403 Forbidden).
- Test 2: Admin invites a Manager (`role='manager'`) successfully (receives 201).
- Test 3: Admin invites an MR (`role='mr'`, `manager_id=manager_id`) successfully (receives 201).
- Test 4: Admin invites MR with cross-tenant manager_id (Review Focus 4 -> 404 Not Found).
- Test 5: List users returns invited users and omits users from other tenants (Review Focus 5).
- Test 6: Deactivating manager with subordinates without reassignment fails (Review Focus 3 -> 422 Unprocessable Entity).
- Test 7: Deactivating manager with `reassign_to_user_id` reassigns direct reports and sets `deleted_at`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/api && .\.venv\Scripts\pytest tests/test_core_users.py -v`
Expected: FAIL (endpoints do not exist).

- [ ] **Step 3: Implement Team Management**

1. In `apps/api/app/modules/core/schemas.py`:
   - `UserInviteRequest`: `email: EmailStr`, `full_name: str`, `role: Literal['manager', 'mr']`, `manager_id: UUID | None = None`
   - `UserResponse`: `id: UUID`, `email: str | None`, `full_name: str`, `role: str`, `manager_id: UUID | None`, `created_at: datetime`
   - `UserDeactivateRequest`: `reassign_to_user_id: UUID | None = None`
2. In `apps/api/app/modules/core/service.py`:
   - `async def list_users(session: AsyncSession, role: str | None = None, manager_id: UUID | None = None) -> list[UserResponse]`
   - `async def invite_team_member(session: AsyncSession, principal: Principal, req: UserInviteRequest) -> UserResponse`:
     - If `req.role == 'mr'` and `req.manager_id`: verify `manager_id` belongs to current tenant and is active (`deleted_at is null`).
     - Trigger Supabase invite email.
     - Insert into `public.app_users`.
   - `async def deactivate_user(session: AsyncSession, principal: Principal, user_id: UUID, req: UserDeactivateRequest) -> None`:
     - Check for subordinate users (`where manager_id = :user_id and deleted_at is null`).
     - If subordinates exist and `not req.reassign_to_user_id`, raise `HTTPException(422, "Must specify reassign_to_user_id when deactivating a manager with active subordinates")`.
     - If `req.reassign_to_user_id`: verify replacement user exists in tenant. Reassign: `update app_users set manager_id = :replacement where manager_id = :user_id`.
     - Soft delete target: `update app_users set deleted_at = now() where id = :user_id`.
3. In `apps/api/app/modules/core/router.py`:
   - `GET /v1/core/users`: `list_users`
   - `POST /v1/core/users/invite`: `invite_team_member` (`dependencies=[Depends(require_roles("admin"))]`)
   - `PATCH /v1/core/users/{user_id}/deactivate`: `deactivate_user` (`dependencies=[Depends(require_roles("admin"))]`)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/api && .\.venv\Scripts\pytest tests/test_core_users.py -v`
Expected: PASS (all tests pass)

- [ ] **Step 5: Commit**

```bash
git add apps/api/app/modules/core apps/api/tests/test_core_users.py
git commit -m "feat(core): implement user invite, hierarchy, and deactivation with reassignment"
```

---

### Task 5: Full Suite Verification & Code Quality

**Files:**
- Modify: `apps/api/pyproject.toml` (if lint rules need tweaking)
- Test: Full test suite

**Interfaces:**
- Consumes: All modules and tests created in Tasks 1-4.
- Produces: Green test suite and zero ruff lint errors.

- [ ] **Step 1: Run full test suite with clean DB reset**

Run:
```bash
npx supabase db reset
cd apps/api && .\.venv\Scripts\pytest -v
```
Expected: PASS (all tests pass, 100% green)

- [ ] **Step 2: Run ruff check and formatting**

Run:
```bash
cd apps/api && .\.venv\Scripts\ruff check .
cd apps/api && .\.venv\Scripts\ruff format --check .
```
Expected: All checks pass with 0 errors.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: verify test suite and code formatting for core-tenancy slice"
```
