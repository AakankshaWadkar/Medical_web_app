# PharmaSphere

Stack: Supabase (Postgres/Auth/Storage) + FastAPI + Flutter (MR app) + React (admin).
Clients talk to FastAPI only. FastAPI connects as `app_backend` and RLS enforces tenant isolation.

## First run
1. `./scripts/bootstrap.sh`   (installs agy skills/plugins)
2. `supabase init` (if no config.toml) -> enable the access-token hook (see end of the migration) -> `supabase start && supabase db reset`
3. `cd apps/api && python -m venv .venv && . .venv/bin/activate && pip install -e ".[dev]"`
4. `pytest` then `uvicorn app.main:app --reload`
5. `agy`, then `/skills` to confirm skills loaded.

First agent prompt: "Brainstorm the Core + Tenancy slice using the pharmasphere-domain and tenant-isolation-rules skills."
