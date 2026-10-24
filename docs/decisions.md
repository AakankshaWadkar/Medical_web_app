# PharmaSphere Architecture & Implementation Decisions

| Decision | Reason |
|:---|:---|
| Use `Annotated` and ignore B008 in `pyproject.toml` | FastAPI dependency injection idiomatically uses default arguments (`Depends(...)`), which triggers Flake8-bugbear B008. |
| Standardized error response structure `{"code": str, "message": str, "details": any}` | Uniform API contracts ensure frontend/mobile clients handle errors predictably without leaking internal traces. |
| Request-ID middleware using `X-Request-ID` | Correlates logs and API telemetry across client requests without logging sensitive PII. |
| Seed `auth.identities` and `instance_id` in `seed.sql` | Supabase GoTrue authentication requires identity records matching auth.users with `instance_id = '00000000-0000-0000-0000-000000000000'` to authenticate via password grant. |
| Use Supabase Auth Admin REST API for user provisioning and banning | Role app_backend does not have direct table grants on schema auth, ensuring zero bypass of auth security invariants. |
| Avoid SQLAlchemy ForeignKeys on unmapped tables in ORM models | Unmapped tables trigger NoReferencedTableError in async flush; database-level foreign keys already enforce integrity at engine level. |
| Platform CLI `app.cli` connects via admin/postgres role | Tenancy creation requires root tenant insertion and bootstrapping before tenant RLS context exists. |
| Territory assignment uses `territories.manager_id` as assigned field rep/MR, scoped to self for MR and recursive CTE for managers | Conforms to schema comment '-- 10. Sales Territories (Assigned to MR)' and enforces strict hierarchical visibility across territories, doctors, and chemists. |
| Idempotent field writes (visits and POBs) check `activities` by `(tenant_id, idempotency_key)` | Ensures safe mobile offline retries without duplicate entities, calculates server-side totals for POBs, and increments DCR counters. |
| Primary orders enforce strict state machine (`draft -> submitted -> approved -> processing -> dispatched`) with manager/admin approval restriction | Prevents illegal order state skipping and protects order integrity with server-side PTS/PTR/discount calculations. |
| Reporting endpoints query pre-existing database views (`view_mr_performance_summary`, `view_doctor_coverage_metrics`, `view_secondary_sales_aggregates`) with composite-PK mapped models and hierarchical role scoping | Reuses analytical views without mutating schema while preserving tenant isolation and role visibility. |
