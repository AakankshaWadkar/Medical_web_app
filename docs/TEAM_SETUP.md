# PharmaSphere: Team Setup Guide

Read this top to bottom once. Every command is meant to be copy-pasted. Commands are **Windows PowerShell** unless marked *(macOS/Linux)*. If a step fails, jump to **Troubleshooting** at the end.

## 1. What this project is

A multi-tenant SaaS for pharma sales teams. Medical Representatives (MRs) log doctor and chemist visits, orders and feedback from a mobile app. Company admins and managers see reports in a web panel.

| Part | Technology | Owner |
|---|---|---|
| Database | PostgreSQL via Supabase (runs locally in Docker) | DB owner |
| Backend API | FastAPI (Python) | DB owner |
| Admin web | React | frontend dev |
| MR mobile app | Flutter | mobile dev |

**What exists today:** the full database schema (about 190 tables in 10 layers), seed data, tenant-isolation tests, and the API skeleton. The REST endpoints are still to be built.

## 2. How the database works (read this first)

- **Supabase** here just means Postgres + an Auth system + a browser SQL tool (Studio), all run locally by the Supabase CLI in Docker. Nothing runs in the cloud yet.
- **The schema lives in SQL files** in `supabase/migrations/`, applied in filename order. They are the source of truth. We do **not** use Alembic or an ORM to create tables.
- **Multi-tenancy:** every table has a `tenant_id` (one tenant = one pharma company). **Row-Level Security (RLS)** makes Postgres return only rows matching the current tenant. This is the one unusual part of the design:
  - The API connects as the Postgres role `app_backend`, which cannot bypass RLS.
  - For each request the API runs `select set_config('app.tenant_id', '<uuid>', true)`, and the RLS policy compares `tenant_id` to that value.
  - Each tenant table gets its policy from one helper: `call public.apply_tenant_rls('public.<table>');`
  - The browser and mobile apps never read tables directly; they call FastAPI only.
- **Views** (`view_*`) must be created with `security_invoker = true`, otherwise they run as the owner and bypass RLS.
- **Auth:** Supabase Auth issues the login JWT. A hook adds `tenant_id` and `app_role` (admin / manager / mr) to it.

## 3. Folder map

```
supabase/migrations/   all schema SQL, in order  <- the important folder
supabase/seed.sql      demo data, loaded by `db reset`
supabase/config.toml   local Supabase settings (includes the auth hook)
apps/api/              FastAPI app and tests
docs/erd.md            ER diagrams, one per layer
docs/schema-description.md   original requirements
docs/schema-inventory.md     final table list and decisions
.agents/skills/        project rules for AI coding agents (can be ignored if you don't use one)
scripts/               helper scripts
```

## 4. Install the prerequisites (once)

| Tool | Check command | Notes |
|---|---|---|
| Docker | `docker ps` | Docker Desktop must be **running**. |
| Node 20+ | `node -v` | Needed for the Supabase CLI via `npx`. |
| Python 3.12+ | `python3 --version` | For the API and tests. |
| Git | `git --version` | |
| psql (optional) | `psql --version` | Or use DBeaver / any SQL client. |

## 5. First-time setup

```powershell
git clone https://github.com/AakankshaWadkar/Medical_web_app.git
cd Medical_web_app
git checkout main
git pull

npm install                      # installs the Supabase CLI into the project
npx supabase start               # first run downloads images (several minutes)
npx supabase db reset            # applies every migration + seed.sql
```

`db reset` should end without errors. Then:

```powershell
cd apps\api
python -m venv .venv
.venv\Scripts\Activate.ps1      # if blocked: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
pip install -e ".[dev]"
pytest                           # expect all tests to pass
```

*(macOS/Linux)*: `python3 -m venv .venv && source .venv/bin/activate`.

Create your local settings file: copy `.env.example` to `.env` (`Copy-Item .env.example .env`) and fill in the values from `npx supabase status`. Never commit `.env`.

## 6. Look at the database

Run `npx supabase status` to print URLs and keys. The ones you need:

| What | Value |
|---|---|
| Studio (browser UI) | http://localhost:54323 |
| Postgres host/port | `127.0.0.1` : `54322` |
| Admin user (sees everything) | `postgres` / `postgres` |
| API user (what FastAPI uses; RLS applies) | `app_backend` / `app_backend_dev` |
| Database name | `postgres` |

In Studio open **Table Editor** (browse tables) and **SQL Editor** (run queries). Or connect DBeaver / psql with the values above.

Useful first queries (as `postgres`):

```sql
select count(*) from information_schema.tables
where table_schema='public' and table_type='BASE TABLE';      -- number of tables

select id, name from tenants;                                  -- demo tenant

select relname, reloptions from pg_class c
join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='v';                    -- views must show security_invoker=true
```

## 7. See RLS working (5 minutes, worth doing)

Connect as the API user with DBeaver (or any SQL client; or `psql` if installed): host `127.0.0.1`, port `54322`, database `postgres`, user `app_backend`, password `app_backend_dev`. Studio always connects as `postgres`, so use a separate client for this check.

```text
psql "postgresql://app_backend:app_backend_dev@127.0.0.1:54322/postgres"
```

```sql
-- no tenant set: sees nothing
select count(*) from doctors;                -- 0

begin;
select set_config('app.tenant_id', '<tenant uuid from the tenants query above>', true);
select count(*) from doctors;                -- only that tenant's doctors
rollback;
```

Connected as `postgres` you see every tenant's rows; connected as `app_backend` you see only the tenant you set. That difference is the entire isolation model.

## 8. Test a real login

Demo users (created by `seed.sql`):

| Role | Email |
|---|---|
| Admin | admin@apexpharma.com |
| Manager | vikram.manager@apexpharma.com, suresh.manager@apexpharma.com |
| MRs | four users, see `supabase/seed.sql` |

Password for all demo users: `<SEED_PASSWORD>`  (local dev only).

```powershell
# the anon key is printed by `npx supabase status`
$body = @{ email = "admin@apexpharma.com"; password = "<SEED_PASSWORD>" } | ConvertTo-Json
$r = Invoke-RestMethod -Method Post `
  -Uri "http://127.0.0.1:54321/auth/v1/token?grant_type=password" `
  -Headers @{ apikey = "<ANON_KEY>" } -ContentType "application/json" -Body $body
$token = $r.access_token
$token
```

Decoding `$token` (jwt.io works) should show `tenant_id` and `app_role`. Then, in one terminal, start the API (venv activated, inside `apps\api`):

```powershell
uvicorn app.main:app --reload
```

and in a second terminal call it:

```powershell
Invoke-RestMethod -Uri http://127.0.0.1:8000/v1/me -Headers @{ Authorization = "Bearer $token" }
```

Expected: the tenant name and role `admin`. API docs are at http://127.0.0.1:8000/docs.

## 9. Rules for changing the database

1. **Never edit a migration that is already merged to `main`.** Add a new one: `npx supabase migration new <short_name>`, write SQL in the new file, then `npx supabase db reset` to test.
2. Every new tenant table needs `tenant_id`, `created_at`, `updated_at`, `deleted_at`, `version`, an index on every foreign key, and a `call public.apply_tenant_rls('public.<table>');` line.
3. Create views `WITH (security_invoker = true)`.
4. Run the whole test suite before every push. Tests check that no table is missing RLS.
5. Never commit `.env` files, real keys, or passwords. Demo seed passwords are for local use only.
6. Don't use `supabase db push --include-seed` against any shared or hosted project.

## 10. Git workflow (team of 3–4, no CI)

```powershell
git checkout main
git pull
git checkout -b db/<short-description>      # one branch per task
# ... make changes, run `npx supabase db reset` and `pytest` ...
git status                                  # check: no .env, no keys
git add -A
git commit -m "Short, clear message"
git push -u origin db/<short-description>
```

Open a pull request on GitHub, ask a teammate to review, merge it, then everyone runs `git pull`. Keep branches short-lived. Tell the team before adding a migration so two people don't change the same table at once.

Folder ownership keeps conflicts rare: DB and API in `supabase/` and `apps/api/`, web in `apps/admin-web/`, mobile in `apps/mr-mobile/`.

## 11. Good review topics for the data engineer

Fresh eyes on the SQL are valuable. Please look at:
- Missing indexes (especially composite indexes that should start with `tenant_id`) and foreign keys without indexes.
- Constraints: nullability, check constraints, unique keys that should include `tenant_id`.
- Normalization problems and duplicated concepts across layers.
- Table and column naming consistency, and identifiers near the 63-character limit.
- The reporting views: correctness and performance.
- Anything in `docs/schema-inventory.md` that contradicts the requirements.

Record findings as GitHub issues or comments on the pull request.

## 12. Troubleshooting

| Problem | Fix |
|---|---|
| `Cannot connect to the Docker daemon` | Start Docker Desktop and retry. |
| `port is already allocated` | Another Supabase or Postgres is running. `npx supabase stop`, or stop the other service. |
| `db reset` fails with a SQL error | Read the first error line (it names the file and line). Don't edit merged migrations; tell the team. |
| `pytest` can't connect | Is `npx supabase start` running? Did `db reset` finish and set the `app_backend` password (done by `seed.sql`)? |
| `/v1/me` returns 401 | The token lacks `tenant_id`: the auth hook isn't enabled in `supabase/config.toml` (look for `[auth.hook.custom_access_token]`), then `npx supabase stop && npx supabase start`. |
| `psql` not found | Use Studio's SQL Editor or DBeaver instead. |
| `Activate.ps1 cannot be loaded` | Run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` once, then retry. |
| `curl` behaves oddly in PowerShell | `curl` is an alias for `Invoke-WebRequest`; use `Invoke-RestMethod` as shown, or `curl.exe`. |
| Everything is weird | `npx supabase stop --no-backup && npx supabase start && npx supabase db reset` gives a clean slate. |
