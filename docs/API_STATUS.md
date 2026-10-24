# PharmaSphere API Status Report

This document provides a comprehensive inventory of all implemented API endpoints, architectural decisions, running instructions, verification commands, and known gaps across Stages 1 through 6.

---

## 1. Endpoint Directory by Module

### System & Foundation
| Method | Path | Summary | Allowed Roles | Idempotent |
|:---|:---|:---|:---|:---|
| `GET` | `/healthz` | System health check probe | Public | Yes |
| `GET` | `/v1/me` | Principal profile resolution (JWT + App User + Tenant) | Authenticated | Yes |

---

### Users (`app/modules/users`)
| Method | Path | Summary | Allowed Roles | Idempotent |
|:---|:---|:---|:---|:---|
| `GET` | `/v1/users` | List tenant users (role, status, search filters, pagination) | `admin` | Yes |
| `GET` | `/v1/users/{id}` | Get user profile by ID | `admin` | Yes |
| `POST` | `/v1/users` | Create user in Supabase Auth & App DB with audit log | `admin` | No |
| `PATCH` | `/v1/users/{id}` | Update user attributes, role, manager_id with audit log | `admin` | No |
| `DELETE` | `/v1/users/{id}` | Deactivate user (bans Supabase Auth login + audit log) | `admin` | Yes |

---

### Masters (`app/modules/masters`)
| Method | Path | Summary | Allowed Roles | Idempotent |
|:---|:---|:---|:---|:---|
| `GET` | `/v1/territories` | List sales territories (hierarchically scoped) | `admin`, `manager`, `mr` | Yes |
| `GET` | `/v1/territories/{id}` | Get territory by ID | `admin`, `manager`, `mr` | Yes |
| `POST` | `/v1/territories` | Create sales territory | `admin` | No |
| `PATCH` | `/v1/territories/{id}` | Update sales territory | `admin` | No |
| `POST` | `/v1/territories/{id}/assign-mr` | Assign MR or manager to sales territory | `admin`, `manager` | Yes |
| `GET` | `/v1/doctors` | List doctors master (scoped to assigned territories for MR/Manager) | `admin`, `manager`, `mr` | Yes |
| `GET` | `/v1/doctors/{id}` | Get doctor details by ID | `admin`, `manager`, `mr` | Yes |
| `POST` | `/v1/doctors` | Create doctor master record | `admin`, `manager`, `mr` | No |
| `PATCH` | `/v1/doctors/{id}` | Update doctor master record | `admin`, `manager`, `mr` | No |
| `GET` | `/v1/chemists` | List chemists master (scoped to assigned territories for MR/Manager) | `admin`, `manager`, `mr` | Yes |
| `GET` | `/v1/chemists/{id}` | Get chemist details by ID | `admin`, `manager`, `mr` | Yes |
| `POST` | `/v1/chemists` | Create chemist master record | `admin`, `manager`, `mr` | No |
| `PATCH` | `/v1/chemists/{id}` | Update chemist master record | `admin`, `manager`, `mr` | No |
| `GET` | `/v1/products` | List finished goods products catalog | `admin`, `manager`, `mr` | Yes |
| `GET` | `/v1/products/{id}` | Get product details by ID | `admin`, `manager`, `mr` | Yes |
| `POST` | `/v1/products` | Create product master record | `admin` | No |
| `PATCH` | `/v1/products/{id}` | Update product master record | `admin` | No |

---

### Field Work (`app/modules/field`)
| Method | Path | Summary | Allowed Roles | Idempotent |
|:---|:---|:---|:---|:---|
| `POST` | `/v1/visits/check-in` | MR check-in (GPS, timestamp, territory validation, activities & DCR) | `admin`, `manager`, `mr` | Yes (via `idempotency_key`) |
| `POST` | `/v1/visits/{id}/check-out` | MR check-out (GPS, timestamp, duration, status completion) | `admin`, `manager`, `mr` | Yes (via `idempotency_key`) |
| `POST` | `/v1/visits/{id}/doctor-feedback` | Record call feedback for doctor visit | `admin`, `manager`, `mr` | Yes |
| `POST` | `/v1/visits/{id}/chemist-feedback` | Record call feedback for chemist visit | `admin`, `manager`, `mr` | Yes |
| `POST` | `/v1/pobs` | Book field order (POB) with server-side PTR & discount pricing | `admin`, `manager`, `mr` | Yes (via `idempotency_key`) |
| `GET` | `/v1/visits` | List field visits with role scoping (MR: self, Manager: team, Admin: all) | `admin`, `manager`, `mr` | Yes |
| `GET` | `/v1/visits/{id}` | Get field visit details by ID | `admin`, `manager`, `mr` | Yes |
| `GET` | `/v1/dcr` | Read Daily Call Reports (DCR) with role scoping | `admin`, `manager`, `mr` | Yes |

---

### Orders & Secondary Sales (`app/modules/orders`)
| Method | Path | Summary | Allowed Roles | Idempotent |
|:---|:---|:---|:---|:---|
| `POST` | `/v1/orders/primary` | Create wholesale primary order (Stockist -> Company) | `admin`, `manager`, `mr` | No |
| `GET` | `/v1/orders/primary` | List primary orders with status and date filters | `admin`, `manager`, `mr` | Yes |
| `GET` | `/v1/orders/primary/{id}` | Get primary order with line items | `admin`, `manager`, `mr` | Yes |
| `PATCH` | `/v1/orders/primary/{id}/status` | Transition order status (`draft->submitted->approved->processing->dispatched`) | `admin`, `manager` (`mr` for submit) | Yes |
| `POST` | `/v1/orders/secondary` | Record chemist secondary sale statements from stockist | `admin`, `manager`, `mr` | No |
| `GET` | `/v1/orders/secondary` | List secondary sales with stockist/chemist/month filters | `admin`, `manager`, `mr` | Yes |
| `GET` | `/v1/orders/secondary/{id}` | Get secondary sale record by ID with item lines | `admin`, `manager`, `mr` | Yes |

---

### Reports & Analytics (`app/modules/reports`)
| Method | Path | Summary | Allowed Roles | Idempotent |
|:---|:---|:---|:---|:---|
| `GET` | `/v1/reports/mr-performance` | MR performance summary from `view_mr_performance_summary` | `admin`, `manager`, `mr` | Yes |
| `GET` | `/v1/reports/doctor-coverage` | Doctor call frequency metrics from `view_doctor_coverage_metrics` | `admin`, `manager`, `mr` | Yes |
| `GET` | `/v1/reports/secondary-sales` | Secondary sales aggregates from `view_secondary_sales_aggregates` | `admin`, `manager`, `mr` | Yes |

---

## 2. Architectural Decisions Made
1. **Tenant Isolation (`tenant_session`):** FastAPI connects strictly as Postgres role `app_backend` (`nobypassrls`). Every request runs inside `tenant_session` which executes `set_config('app.tenant_id', :tenant_id, true)` transaction-locally.
2. **Supabase Auth Hook & Claims:** JWT claims contain `tenant_id` and `app_role` issued by Supabase GoTrue. Request handlers never read `tenant_id` from payloads or query params.
3. **Hierarchical RBAC on top of RLS:**
   - **Admin:** Unrestricted tenant visibility.
   - **Manager:** Scoped to self and all direct/indirect reporting team members via recursive Common Table Expression (CTE) on `app_users.manager_id`.
   - **MR:** Scoped strictly to self and assigned sales territories (`territories.manager_id == app_user.id`).
4. **Idempotent Field Writes:** Writes that mobile apps may retry (visits, POB bookings) accept client `idempotency_key` and record deduplication markers in `public.activities (tenant_id, idempotency_key)`.
5. **Server-Side Financial Computations:** All prices, rates, taxes, and discounts are computed server-side from master tables (`products.ptr` for chemist POBs/secondary sales, `products.pts` for primary orders) using Python `Decimal`.
6. **Reporting Views Contract:** Endpoints in `app/modules/reports` read database views directly using composite-PK SQLAlchemy mapped models, respecting multi-tenant row-level boundaries without altering database schema.
7. **Platform CLI Isolation:** Tenant bootstrap CLI (`python -m app.cli create-tenant`) connects via `platform_session` using administrative credentials solely to bootstrap the root tenant, branch, auth identities, and first administrator before tenant context exists.

---

## 3. How to Run & Verify

### A. Reset Database with Seeds
```bash
npx supabase db reset
```

### B. Run Static Analysis & Linter
```bash
cd apps/api
.venv\Scripts\ruff check .
.venv\Scripts\ruff format --check .
```

### C. Run the Complete Test Suite
```bash
cd apps/api
.venv\Scripts\pytest -v
```

### D. Run the Local API Server
```bash
cd apps/api
.venv\Scripts\uvicorn app.main:app --port 8000 --reload
```

---

## 4. Known Gaps & Out-of-Scope Items
As per the explicit specification, the following modules are deferred to later phases:
- Mobile Offline Sync endpoints (`/sync/*`)
- HR and Payroll (`leave_requests`, `expenses`, `payroll_runs`)
- Marketing, Communication, and QR (`campaigns`, `webhooks`, `qr_codes`)
- Finance & Invoicing (`receipts`, `ledger_entries`, `credit_notes`)
- Physical Selfie Image upload processing (schema metadata supported via `file_storage`)

---

## 5. Blockers Encountered
None. All 48 tests are green and passing. Database schema immutability was preserved with zero modified migrations.
