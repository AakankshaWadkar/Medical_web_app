# PharmaSphere: Database Schema Inventory & Migration Strategy

**Specification Version:** 1.0.0  
**Target Database:** Supabase Local Postgres (PostgreSQL 15+)  
**Architecture:** Multi-tenant SaaS combining Pharmaceutical **Sales Force Automation (SFA) + CRM + ERP**  
**Governing Skills:** `pharmasphere-domain`, `tenant-isolation-rules`, `fastapi-conventions` (overriding `saas-multi-tenant`)  
**Scope:** Comprehensive inventory covering all 10 Architectural Layers (212 tables) with resolved single-owner entities, strict tenant isolation, foreign-key dependency ordering, and architectural open questions.

---

## 1. Executive Summary & Mandatory Conventions

PharmaSphere serves pharmaceutical manufacturers and marketing enterprises. Access is strictly divided between **Tenant Admin & Managers (React Web App)** and **Field Medical Representatives (Flutter Mobile App)**.

### Architectural Rules & Invariants
1. **Strict Tenant Isolation:** Flutter and React clients connect strictly through the FastAPI backend (`apps/api`). FastAPI connects to Postgres as role `app_backend` (never `postgres` or `service_role`). `app_backend` has `nobypassrls`.
2. **Tenant ID Propagation:** The tenant identity originates exclusively from the verified Supabase Auth JWT claim `tenant_id`. Every tenant-scoped request transaction executes `set_config('app.tenant_id', <uuid>, true)`.
3. **Table Structure Invariants:** Every tenant-bound table contains:
   - `id uuid primary key default gen_random_uuid()`
   - `tenant_id uuid not null references public.tenants(id) on delete cascade`
   - `created_at timestamptz not null default now()`
   - `updated_at timestamptz not null default now()`
   - `deleted_at timestamptz`
   - `version bigint not null default 1`
4. **RLS Automation:** Every tenant table runs `call public.apply_tenant_rls('public.<table>');` which:
   - Enables and **FORCES** row level security.
   - Creates policy `tenant_isolation` for role `app_backend` (`using (tenant_id = app_tenant_id()) with check (tenant_id = app_tenant_id())`).
   - Creates index `idx_<table>_tenant` on `(tenant_id)`.
   - Attaches trigger `trg_touch` before update to advance `version` and update `updated_at`.
5. **Global Platform Table Allowlist:** Tables without `tenant_id` are limited strictly to:
   - `tenants` (root tenant catalog; protected by `tenant_self` policy)
   - `subscription_plans` (global SaaS tier definitions)
   - `permissions` (global system RBAC permission catalog)
   - `countries`, `states`, `cities`, `pin_codes` (standard ISO geographic masters)
   - `currencies` (ISO currency definitions)
   - `mobile_app_versions` (global mobile build version enforcement)
6. **No PostgREST Client Grants:** Public privileges are stripped: default privileges revoke all from `anon` and `authenticated` roles.
7. **Data Types:** Money is `numeric(14,2)`; timestamps are `timestamptz`; state machines and categories use check constraints (`CHECK (...)`), not Postgres ENUM types (avoiding migration locking).
8. **Indexes:** Every foreign key column is indexed. Composite indexes lead with `tenant_id`.

---

## 2. Duplicate Resolution & Single Ownership Matrix

The input architecture description (`docs/schema-description.docx`) mentioned several entities across multiple layers. In compliance with `pharmasphere-domain` module ownership rules ("one owner per entity, no duplicates"), each duplicate has been resolved to exactly **one owning table**:

| Entity / Duplicate Mentioned | Conflicting Locations in Docs | Single Owning Module & Table | Domain Resolution Rule & Architectural Rationale |
|:---|:---|:---|:---||
| **Attendance** | Layer 6 (MR CRM) & Layer 7 (HR) | **Layer 8 (HR & Payroll)**<br>`public.attendance`<br>`public.attendance_logs` | Owned exclusively by HR. Field MRs are employees (`employees.user_id = app_users.id`). Mobile check-in punches directly into `public.attendance`. CRM never defines a duplicate attendance table. |
| **Leave** | Layer 6 (MR CRM) & Layer 7 (HR) | **Layer 8 (HR & Payroll)**<br>`public.leaves`<br>`public.leave_balances` | Owned exclusively by HR. MR leave applications, balance accruals, and approvals use standard HR leave infrastructure. |
| **Expense** | Layer 6 (MR CRM) & Layer 7 (HR) | **Layer 8 (HR & Payroll)**<br>`public.expenses`<br>`public.expense_claims` | Owned exclusively by HR. Daily travel/allowance vouchers and monthly claim approvals reside in HR. Mobile SFA routes write directly to these tables. |
| **JointWork** | Layer 6 (Doctor CRM, Chemist CRM, MR list) | **Layer 7 (CRM & SFA)**<br>`public.joint_works` | Owned exclusively by CRM. Tracks a Manager accompanying an MR on field visits (`visit_id`, `manager_id`, `mr_id`, rating, coaching feedback). No separate doctor/chemist joint work tables. |
| **GiftInventory** | Layer 2 (Product), Layer 3 (Warehouse), Layer 8 (Marketing) | **Layer 4 (Warehouse & Inventory)**<br>`public.gift_items`<br>`public.gift_inventories`<br>`public.gift_stock_transactions` | Owned exclusively by Warehouse/Inventory as a single physical inventory ledger. Marketing campaigns reference items; MR allocations draw from it; visit distribution is logged in `doctor_gift_distributions`. |
| **QRCode** | Layer 2 (ProductQRCode), Layer 6 (ChemistQRCode), Layer 10 (QR Code) | **Layer 10 (QR & Platform)**<br>`public.qr_codes`<br>`public.qr_code_scans`<br>`public.qr_code_histories` | Single generic polymorphic table `qr_codes` with `(entity_type, entity_id)` columns. Eliminates `ProductQRCode`, `ChemistQRCode`, `DoctorQRCode`. |
| **DoctorVisit vs DoctorCheckIn / CheckOut** | Layer 6 (DoctorVisit, DoctorCheckIn, DoctorCheckOut) | **Layer 7 (CRM & SFA)**<br>`public.field_visits` | Check-in/out timestamps and GPS coordinates are columns on the visit table (`check_in_time`, `check_out_time`, `check_in_latitude`, `check_in_longitude`, `check_out_latitude`, `check_out_longitude`). Check-in and check-out are NOT parallel entities. |
| **VisitSelfie** | Layer 6 (Doctor CRM list) | **Layer 7 (CRM & SFA)**<br>`public.visit_selfies` | Normalized child table of `field_visits`, referencing uploaded image in `public.file_storage` with GPS stamp. |
| **EDetailing** | Layer 6 (Doctor CRM list) | **Layer 7 (CRM & SFA)**<br>`public.e_detailings`<br>`public.e_detailing_slides` | Structured visit interaction tracking MR presentation duration per product slide. |
| **POB (Pre-Order Booking)** | Layer 6 (Doctor POB, Chemist POB) & Layer 9 (Communication) | **Layer 7 (CRM & SFA)**<br>`public.pobs`<br>`public.pob_products` | Owned exclusively by CRM / SFA. Unified order capture from Doctor or Chemist directed to a target Stockist. Layer 9 communication templates dispatch notifications based on POB events. |
| **ChemistAddition** | Layer 6 (Chemist CRM diagram) | **Layer 7 (CRM & SFA)**<br>`public.chemists` | Chemist onboarding by MRs in the field writes directly to `public.chemists` with `status = 'pending_verification'`. No redundant staging table. |
| **ChemistPayment & Collection** | Layer 6 (Chemist CRM list) | **Layer 6 (Sales & Distribution)**<br>`public.collections`<br>`public.customer_payments` | All field money collections by MRs are recorded in `public.collections` and reconciled against invoices in `public.customer_payments`. |
| **RCPA** | Layer 6 (Chemist RCPA) | **Layer 7 (CRM & SFA)**<br>`public.rcpa_audits`<br>`public.rcpa_audit_items` | Prescription audit capturing chemist sales of own products vs competitors for specific doctors. |
| **FileUpload / Document** | Layer 1 (FileStorage), Layer 6 (MRDocument), Layer 7 (HR FileUpload) | **Layer 1 (Core Foundation)**<br>`public.file_storage` | Generic file metadata storage (`entity_type`, `entity_id`, `storage_path`, `content_type`, `file_size_bytes`). Domain-specific business metadata links to `file_storage.id`. |
| **Activity Timeline** | Layer 1, Layer 6 | **Layer 1 (Core Foundation)**<br>`public.activities` | Central append-mostly event log already implemented in `20260101000000_foundation.sql`. Every visit, check-in, POB, feedback, and expense creates or links an Activity row. |
| **Scheme & Promotion** | Layer 2 (Product) & Layer 8 (Marketing) | **Layer 9 (Marketing & Schemes)**<br>`public.schemes`<br>`public.scheme_products`<br>`public.product_promotions` | Owned exclusively by Marketing. Product master contains core catalog items; promotional pricing and bonus slabs are managed as schemes. |
| **Address & Contact Info** | Layer 1 (Branch), Layer 2 (DoctorAddress, ChemistContact), Layer 5 (Supplier) | **Layer 2 (Master Data)**<br>`public.addresses`<br>`public.contacts` | Generic polymorphic address and contact tables storing structured lines, city, state, pin, phone, email, and coordinates for any entity. |

---

## 3. Migration Order Based on Foreign-Key Dependencies

The 212 tables are organized into **12 discrete sequential migration stages**. Each stage has zero circular dependencies and strictly depends only on preceding stages:

| Stage | Tables Count | Direct Dependencies | Major Business Entities Included |
|:---|---:|:---|:---|
| **Stage 01: Core Platform & Foundation** | 17 | None (Base) | tenants, branches, departments, app_users, roles, permissions, activities, file_storage, audit_logs |
| **Stage 02: Geography, Sales Hierarchy & Shared Masters** | 17 | Stage 01 | countries, states, cities, pin_codes, divisions, territories, beats, routes, addresses, contacts |
| **Stage 03: Product Catalog & Medicine Master** | 19 | Stage 01, Stage 02 | categories, brands, generic_medicines, dosage_forms, products, product_packages, product_prices |
| **Stage 04: Warehouses, Batches & Inventory** | 15 | Stage 01, Stage 03 | warehouses, product_batches, inventory_stocks, stock_transactions, gift_items, gift_inventories |
| **Stage 05: Procurement & Suppliers** | 12 | Stage 01, Stage 02, Stage 03, Stage 04 | suppliers, purchase_requisitions, purchase_orders, goods_receipt_notes, purchase_bills |
| **Stage 06: Stockists & Sales (Primary & Secondary)** | 16 | Stage 01, Stage 02, Stage 03, Stage 04, Stage 05 | stockists, primary_orders, primary_invoices, sales_returns, customer_payments, collections |
| **Stage 07: CRM & SFA (Doctors, Chemists, Visits, POB, RCPA)** | 28 | Stage 01, Stage 02, Stage 03, Stage 04, Stage 06 | doctors, chemists, field_visits, joint_works, pobs, rcpa_audits, tour_plans, daily_call_reports |
| **Stage 08: HR, Attendance, Leave, Expense & Payroll** | 19 | Stage 01, Stage 02 | shifts, employees, attendance, leaves, expenses, expense_claims, payrolls, payslips |
| **Stage 09: Marketing, Campaigns, Schemes & Offers** | 12 | Stage 01, Stage 02, Stage 03, Stage 07 | campaigns, schemes, scheme_products, offers, coupons, product_promotions |
| **Stage 10: Communication & Unified QR Codes** | 12 | Stage 01, Stage 07 | notifications, email/sms/whatsapp templates and logs, qr_codes, qr_code_scans |
| **Stage 11: Finance & Accounting Ledger** | 20 | Stage 01, Stage 05, Stage 06, Stage 08 | chart_of_accounts, journal_entries, general_ledgers, customer/supplier ledgers, credit/debit notes |
| **Stage 12: Analytics, Dashboards & External Integrations** | 22 | Stage 01 through Stage 11 | dashboard_widgets, custom_reports, kpi_metrics, api_keys, webhook_endpoints, sync_jobs, mobile_app_versions |
| **Total** | **212** | | |

---

## 4. Complete Table Inventory (212 Tables)

### Stage 01: Core Platform & Foundation

#### 1. `public.tenants`
- **Layer / Module:** Layer 1: Core ERP | Core Platform
- **Purpose:** Root multi-tenant company entity. In a multi-tenant pharma SaaS, each tenant is an independent pharmaceutical enterprise.
- **Key Columns:** `id (uuid pk), name (text), slug (text unique), status (text check: trial, active, suspended, closed)`
- **Foreign Keys:** `None (Root table)`
- **Indexes & Constraints:** `unique(slug), check(status in ('trial','active','suspended','closed')), self-RLS policy for app_backend`

#### 2. `public.branches`
- **Layer / Module:** Layer 1: Core ERP | Core Platform
- **Purpose:** Company physical branch offices, headquarters, and administrative locations.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), name (text), code (text), is_head_office (boolean), address (text), city (text), state (text), pin (text), phone (text)`
- **Foreign Keys:** `tenant_id -> tenants(id) on delete cascade`
- **Indexes & Constraints:** `unique(tenant_id, code), idx_branches_tenant`

#### 3. `public.departments`
- **Layer / Module:** Layer 1: Core ERP | Core Platform
- **Purpose:** Functional departments (Sales, Marketing, HR, Finance, Supply Chain) mapped to branches.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), branch_id (uuid), code (text), name (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), branch_id -> branches(id) on delete cascade`
- **Indexes & Constraints:** `unique(tenant_id, branch_id, code), idx_departments_branch`

#### 4. `public.app_users`
- **Layer / Module:** Layer 1: Core ERP | Core Platform / Auth
- **Purpose:** User directory mapped 1:1 to Supabase auth.users, holding pharma enterprise hierarchy (Admin > Manager > MR).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), auth_user_id (uuid unique), branch_id (uuid), department_id (uuid), app_role (text check: admin, manager, mr), employee_code (text), full_name (text), email (text), phone (text), status (text check: active, invited, suspended), manager_id (uuid)`
- **Foreign Keys:** `tenant_id -> tenants(id), auth_user_id -> auth.users(id), branch_id -> branches(id), department_id -> departments(id), manager_id -> app_users(id)`
- **Indexes & Constraints:** `unique(tenant_id, employee_code), check(app_role in ('admin','manager','mr')), idx_app_users_manager`

#### 5. `public.roles`
- **Layer / Module:** Layer 1: Core ERP | Core RBAC
- **Purpose:** Granular RBAC roles (Administrator, Sales Manager, Medical Representative, Warehouse Manager, Accountant, HR).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text), description (text), is_system (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 6. `public.permissions`
- **Layer / Module:** Layer 1: Core ERP | Core RBAC
- **Purpose:** System-wide discrete permissions catalog (e.g. Doctor.Visit, Sales.CreateInvoice, Expense.Approve).
- **Key Columns:** `id (uuid pk), code (text unique), module (text), description (text)`
- **Foreign Keys:** `None (Global system reference catalog)`
- **Indexes & Constraints:** `unique(code)`

#### 7. `public.user_roles`
- **Layer / Module:** Layer 1: Core ERP | Core RBAC
- **Purpose:** Many-to-many assignment of roles to users.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), user_id (uuid), role_id (uuid)`
- **Foreign Keys:** `tenant_id -> tenants(id), user_id -> app_users(id), role_id -> roles(id)`
- **Indexes & Constraints:** `unique(tenant_id, user_id, role_id)`

#### 8. `public.role_permissions`
- **Layer / Module:** Layer 1: Core ERP | Core RBAC
- **Purpose:** Permission grants per role.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), role_id (uuid), permission_id (uuid)`
- **Foreign Keys:** `tenant_id -> tenants(id), role_id -> roles(id), permission_id -> permissions(id)`
- **Indexes & Constraints:** `unique(tenant_id, role_id, permission_id)`

#### 9. `public.subscription_plans`
- **Layer / Module:** Layer 1: Core ERP | Platform Provisioning
- **Purpose:** SaaS commercial tiers (Starter, Growth, Enterprise). Global platform table allowlisted from tenant_id.
- **Key Columns:** `id (uuid pk), code (text unique), name (text), max_users (integer), max_branches (integer), max_storage_gb (integer), price (numeric(14,2)), billing_cycle (text check: monthly, annual), is_active (boolean)`
- **Foreign Keys:** `None (Global platform table)`
- **Indexes & Constraints:** `unique(code), check(billing_cycle in ('monthly','annual'))`

#### 10. `public.tenant_subscriptions`
- **Layer / Module:** Layer 1: Core ERP | Platform Provisioning
- **Purpose:** Active SaaS subscription plan binding per tenant.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), plan_id (uuid), start_date (timestamptz), end_date (timestamptz), status (text check: active, expired, cancelled, trial), auto_renew (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id), plan_id -> subscription_plans(id)`
- **Indexes & Constraints:** `check(status in ('active','expired','cancelled','trial'))`

#### 11. `public.tenant_settings`
- **Layer / Module:** Layer 1: Core ERP | Core Platform
- **Purpose:** Tenant-specific configuration (financial year start, currency, GST rules, WhatsApp API credentials).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), category (text), setting_key (text), setting_value (text), data_type (text check: string, number, boolean, json)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, category, setting_key)`

#### 12. `public.user_notification_preferences`
- **Layer / Module:** Layer 1: Core ERP | Core Platform
- **Purpose:** User-level channel alert preferences.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), user_id (uuid), email_enabled (boolean), whatsapp_enabled (boolean), push_enabled (boolean), sms_enabled (boolean), daily_summary_enabled (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id), user_id -> app_users(id)`
- **Indexes & Constraints:** `unique(tenant_id, user_id)`

#### 13. `public.file_storage`
- **Layer / Module:** Layer 1: Core ERP | Core Platform
- **Purpose:** Unified platform file storage metadata. Resolves all individual document/file duplicates (doctor selfies, receipts, lab PDFs, payslips).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), module_name (text), entity_type (text), entity_id (uuid), file_name (text), file_path (text), file_size_bytes (bigint), content_type (text), uploaded_by_user_id (uuid)`
- **Foreign Keys:** `tenant_id -> tenants(id), uploaded_by_user_id -> app_users(id)`
- **Indexes & Constraints:** `idx_file_storage_entity on (tenant_id, entity_type, entity_id)`

#### 14. `public.audit_logs`
- **Layer / Module:** Layer 1: Core ERP | Core Platform
- **Purpose:** Security and compliance audit trail tracking all state-changing mutations and logins.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), user_id (uuid), entity_name (text), entity_id (uuid), action (text check: insert, update, delete, login, export), old_values (jsonb), new_values (jsonb), ip_address (text), user_agent (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), user_id -> app_users(id)`
- **Indexes & Constraints:** `idx_audit_logs_entity on (tenant_id, entity_name, entity_id)`

#### 15. `public.login_histories`
- **Layer / Module:** Layer 1: Core ERP | Core Auth
- **Purpose:** User login session history with device and IP logging.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), user_id (uuid), login_at (timestamptz), logout_at (timestamptz), ip_address (text), user_agent (text), device_info (jsonb), status (text check: success, failed)`
- **Foreign Keys:** `tenant_id -> tenants(id), user_id -> app_users(id)`
- **Indexes & Constraints:** `idx_login_histories_user on (tenant_id, user_id, login_at desc)`

#### 16. `public.user_sessions`
- **Layer / Module:** Layer 1: Core ERP | Core Auth
- **Purpose:** Active device sessions and refresh token revocation registry.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), user_id (uuid), token_hash (text), device_name (text), expires_at (timestamptz), is_revoked (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id), user_id -> app_users(id)`
- **Indexes & Constraints:** `idx_user_sessions_token on (tenant_id, token_hash)`

#### 17. `public.activities`
- **Layer / Module:** Layer 1: Core ERP | Core Platform / SFA Timeline
- **Purpose:** Central append-mostly timeline feed for all field events (doctor calls, chemist calls, check-ins, POBs, selfies, feedback).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), mr_id (uuid), activity_type (text), entity_type (text), entity_id (uuid), started_at (timestamptz), ended_at (timestamptz), latitude (double precision), longitude (double precision), payload (jsonb), idempotency_key (uuid unique), client_created_at (timestamptz), received_at (timestamptz)`
- **Foreign Keys:** `tenant_id -> tenants(id), mr_id -> app_users(id)`
- **Indexes & Constraints:** `unique(tenant_id, idempotency_key), idx_activities_mr_time on (tenant_id, mr_id, started_at desc), idx_activities_entity on (tenant_id, entity_type, entity_id)`

### Stage 02: Geography, Sales Hierarchy & Shared Masters

#### 18. `public.countries`
- **Layer / Module:** Layer 2: Master Data | Geography Master
- **Purpose:** ISO standard country directory. Global platform allowlisted reference.
- **Key Columns:** `code (text pk), name (text), phone_code (text)`
- **Foreign Keys:** `None (Global reference)`
- **Indexes & Constraints:** `pk on code`

#### 19. `public.states`
- **Layer / Module:** Layer 2: Master Data | Geography Master
- **Purpose:** States / Provinces with official GST state codes. Global platform reference.
- **Key Columns:** `id (uuid pk), country_code (text), code (text), name (text), gst_state_code (text)`
- **Foreign Keys:** `country_code -> countries(code)`
- **Indexes & Constraints:** `unique(country_code, code)`

#### 20. `public.cities`
- **Layer / Module:** Layer 2: Master Data | Geography Master
- **Purpose:** Districts and cities across states. Global platform reference.
- **Key Columns:** `id (uuid pk), state_id (uuid), name (text), std_code (text)`
- **Foreign Keys:** `state_id -> states(id)`
- **Indexes & Constraints:** `idx_cities_state on (state_id, name)`

#### 21. `public.pin_codes`
- **Layer / Module:** Layer 2: Master Data | Geography Master
- **Purpose:** Postal PIN codes with geographic locality mapping. Global platform reference.
- **Key Columns:** `id (uuid pk), city_id (uuid), state_id (uuid), pin_code (text), area_name (text)`
- **Foreign Keys:** `city_id -> cities(id), state_id -> states(id)`
- **Indexes & Constraints:** `idx_pin_codes_search on (pin_code, city_id)`

#### 22. `public.addresses`
- **Layer / Module:** Layer 2: Master Data | Master Data
- **Purpose:** Polymorphic address directory resolving duplication across branches, stockists, doctors, chemists, and vendors.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), entity_type (text), entity_id (uuid), address_type (text check: billing, shipping, clinic, pharmacy, head_office, residence), line1 (text), line2 (text), city (text), state (text), pin_code (text), country (text), latitude (double precision), longitude (double precision)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `idx_addresses_entity on (tenant_id, entity_type, entity_id)`

#### 23. `public.contacts`
- **Layer / Module:** Layer 2: Master Data | Master Data
- **Purpose:** Polymorphic contact numbers and emails resolving doctor/chemist/stockist contact duplication.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), entity_type (text), entity_id (uuid), contact_type (text check: phone, mobile, email, whatsapp), name (text), value (text), designation (text), is_primary (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `idx_contacts_entity on (tenant_id, entity_type, entity_id)`

#### 24. `public.business_divisions`
- **Layer / Module:** Layer 2: Master Data | Pharma Hierarchy
- **Purpose:** Pharma business operating divisions (e.g. Cardio, Neuro, Critical Care, OTC).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text), description (text), is_active (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 25. `public.sales_channels`
- **Layer / Module:** Layer 2: Master Data | Pharma Hierarchy
- **Purpose:** Sales distribution channels (Trade, Government, Hospital Supply, Institutional).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 26. `public.fiscal_years`
- **Layer / Module:** Layer 2: Master Data | Financial Masters
- **Purpose:** Statutory financial years (e.g. FY 2026-2027).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), name (text), start_date (date), end_date (date), is_closed (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, name)`

#### 27. `public.financial_periods`
- **Layer / Module:** Layer 2: Master Data | Financial Masters
- **Purpose:** Monthly and quarterly accounting and reporting buckets within a fiscal year.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), fiscal_year_id (uuid), period_name (text), start_date (date), end_date (date), is_closed (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id), fiscal_year_id -> fiscal_years(id)`
- **Indexes & Constraints:** `unique(tenant_id, fiscal_year_id, period_name)`

#### 28. `public.payment_terms`
- **Layer / Module:** Layer 2: Master Data | Commercial Masters
- **Purpose:** Standard commercial payment credit periods (Immediate, 7 Days, 21 Days, 30 Days, 60 Days).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text), days (integer), description (text)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 29. `public.currencies`
- **Layer / Module:** Layer 2: Master Data | Financial Masters
- **Purpose:** Standard ISO currency codes. Global platform reference.
- **Key Columns:** `code (text pk), name (text), symbol (text)`
- **Foreign Keys:** `None (Global reference)`
- **Indexes & Constraints:** `pk on code`

#### 30. `public.regions`
- **Layer / Module:** Layer 2: Master Data | Sales Field Hierarchy
- **Purpose:** Top sales geography (e.g. West Zone, North Zone) managed by Zonal / Regional Managers.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text), manager_id (uuid)`
- **Foreign Keys:** `tenant_id -> tenants(id), manager_id -> app_users(id)`
- **Indexes & Constraints:** `unique(tenant_id, code), idx_regions_manager`

#### 31. `public.areas`
- **Layer / Module:** Layer 2: Master Data | Sales Field Hierarchy
- **Purpose:** Area divisions within regions (e.g. Mumbai Metro, Pune Area) managed by Area Sales Managers (ASM).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), region_id (uuid), code (text), name (text), manager_id (uuid)`
- **Foreign Keys:** `tenant_id -> tenants(id), region_id -> regions(id), manager_id -> app_users(id)`
- **Indexes & Constraints:** `unique(tenant_id, code), idx_areas_region`

#### 32. `public.territories`
- **Layer / Module:** Layer 2: Master Data | Sales Field Hierarchy
- **Purpose:** Fundamental field operations territory allocated to a Medical Representative (MR).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), area_id (uuid), code (text), name (text), manager_id (uuid)`
- **Foreign Keys:** `tenant_id -> tenants(id), area_id -> areas(id), manager_id -> app_users(id)`
- **Indexes & Constraints:** `unique(tenant_id, code), idx_territories_area`

#### 33. `public.beats`
- **Layer / Module:** Layer 2: Master Data | Sales Field Hierarchy
- **Purpose:** Day-level field coverage beats grouping doctors and chemists in a localized cluster.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), territory_id (uuid), code (text), name (text), description (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), territory_id -> territories(id)`
- **Indexes & Constraints:** `unique(tenant_id, territory_id, code)`

#### 34. `public.routes`
- **Layer / Module:** Layer 2: Master Data | Sales Field Hierarchy
- **Purpose:** Specific travel route paths connecting stops within a beat.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), beat_id (uuid), code (text), name (text), distance_km (numeric(8,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), beat_id -> beats(id)`
- **Indexes & Constraints:** `unique(tenant_id, beat_id, code)`

### Stage 03: Product Catalog & Medicine Master

#### 35. `public.categories`
- **Layer / Module:** Layer 3: Product Master | Product Catalog
- **Purpose:** Broad product categories (Formulations, Generics, Medical Devices, Nutraceuticals).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text), description (text)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 36. `public.sub_categories`
- **Layer / Module:** Layer 3: Product Master | Product Catalog
- **Purpose:** Sub-classifications under categories.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), category_id (uuid), code (text), name (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), category_id -> categories(id)`
- **Indexes & Constraints:** `unique(tenant_id, category_id, code)`

#### 37. `public.brands`
- **Layer / Module:** Layer 3: Product Master | Product Catalog
- **Purpose:** Commercial pharmaceutical brand umbrella (e.g. Paracip, Azithral, Moxclav).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), division_id (uuid), code (text), name (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), division_id -> business_divisions(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 38. `public.manufacturers`
- **Layer / Module:** Layer 3: Product Master | Product Catalog
- **Purpose:** Contract manufacturers and manufacturing plant licenses.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text), drug_license_no (text)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 39. `public.generic_medicines`
- **Layer / Module:** Layer 3: Product Master | Medicine Master
- **Purpose:** Active Pharmaceutical Ingredients (API) molecules / salt names (e.g. Amoxicillin, Clavulanic Acid, Paracetamol).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text), description (text)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 40. `public.dosage_forms`
- **Layer / Module:** Layer 3: Product Master | Medicine Master
- **Purpose:** Drug pharmaceutical dosage forms (Tablet, Capsule, Syrup, Dry Syrup, Injection, Ointment, Drops).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 41. `public.strengths`
- **Layer / Module:** Layer 3: Product Master | Medicine Master
- **Purpose:** Dosage potency and strength definitions (e.g. 500mg, 625mg, 100ml, 5mcg).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), value (text), unit (text)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, value, unit)`

#### 42. `public.therapeutic_classes`
- **Layer / Module:** Layer 3: Product Master | Medicine Master
- **Purpose:** Medical therapeutic classification (Antibiotic, Analgesic, Anti-inflammatory, Anti-hypertensive).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 43. `public.product_types`
- **Layer / Module:** Layer 3: Product Master | Product Catalog
- **Purpose:** Commercial drug types (Ethical Prescription, Generic, Over-The-Counter OTC, Hospital).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 44. `public.units_of_measure`
- **Layer / Module:** Layer 3: Product Master | Packaging & Inventory Master
- **Purpose:** Units of Measure UOM (Strip, Bottle, Box, Vial, Carton, Ampoule).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text), symbol (text)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 45. `public.hsn_codes`
- **Layer / Module:** Layer 3: Product Master | Taxation Masters
- **Purpose:** Harmonized System of Nomenclature HSN tariff codes for pharmaceutical items.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), hsn_code (text), description (text), default_gst_rate (numeric(5,2))`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, hsn_code)`

#### 46. `public.gst_rates`
- **Layer / Module:** Layer 3: Product Master | Taxation Masters
- **Purpose:** Statutory GST slab breakdown (CGST, SGST, IGST).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), rate_percentage (numeric(5,2)), cgst_percentage (numeric(5,2)), sgst_percentage (numeric(5,2)), igst_percentage (numeric(5,2))`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, rate_percentage)`

#### 47. `public.price_lists`
- **Layer / Module:** Layer 3: Product Master | Pricing Masters
- **Purpose:** Price schedules (Standard Trade, Government Tender, Export, Institutional).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text), currency_code (text), is_default (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 48. `public.products`
- **Layer / Module:** Layer 3: Product Master | Product Catalog
- **Purpose:** Central finished medicine SKU master. Single source of truth for items sold, visited, and sampled.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), division_id (uuid), category_id (uuid), sub_category_id (uuid), brand_id (uuid), manufacturer_id (uuid), dosage_form_id (uuid), therapeutic_class_id (uuid), product_type_id (uuid), uom_id (uuid), hsn_code_id (uuid), product_code (text), name (text), generic_name (text), description (text), is_active (boolean), is_prescription_required (boolean), storage_condition (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), division_id -> business_divisions(id), category_id -> categories(id), sub_category_id -> sub_categories(id), brand_id -> brands(id), manufacturer_id -> manufacturers(id), dosage_form_id -> dosage_forms(id), therapeutic_class_id -> therapeutic_classes(id), product_type_id -> product_types(id), uom_id -> units_of_measure(id), hsn_code_id -> hsn_codes(id)`
- **Indexes & Constraints:** `unique(tenant_id, product_code), idx_products_brand on (tenant_id, brand_id)`

#### 49. `public.compositions`
- **Layer / Module:** Layer 3: Product Master | Medicine Master
- **Purpose:** Active drug ingredient formula and strength breakdown per finished product SKU.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), product_id (uuid), generic_medicine_id (uuid), strength_id (uuid), dosage_ratio (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), product_id -> products(id), generic_medicine_id -> generic_medicines(id), strength_id -> strengths(id)`
- **Indexes & Constraints:** `idx_compositions_product on (tenant_id, product_id)`

#### 50. `public.product_packages`
- **Layer / Module:** Layer 3: Product Master | Packaging Master
- **Purpose:** Hierarchical packing definitions (e.g. 1 Strip = 10 Tabs, 1 Box = 10 Strips, 1 Shipper = 50 Boxes).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), product_id (uuid), packaging_level (text check: primary, secondary, tertiary), items_per_pack (integer), gross_weight_kg (numeric(8,3))`
- **Foreign Keys:** `tenant_id -> tenants(id), product_id -> products(id)`
- **Indexes & Constraints:** `check(packaging_level in ('primary','secondary','tertiary'))`

#### 51. `public.product_prices`
- **Layer / Module:** Layer 3: Product Master | Pricing Masters
- **Purpose:** Commercial pharmaceutical pricing tiers: MRP, PTR (Price to Retailer), PTS (Price to Stockist), PTD (Price to Distributor), PT_DR (Price to Doctor).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), product_id (uuid), price_list_id (uuid), mrp (numeric(14,2)), ptr (numeric(14,2)), pts (numeric(14,2)), ptd (numeric(14,2)), pt_dr (numeric(14,2)), effective_from (timestamptz), effective_to (timestamptz)`
- **Foreign Keys:** `tenant_id -> tenants(id), product_id -> products(id), price_list_id -> price_lists(id)`
- **Indexes & Constraints:** `idx_product_prices_product on (tenant_id, product_id, price_list_id)`

#### 52. `public.product_images`
- **Layer / Module:** Layer 3: Product Master | Product Catalog
- **Purpose:** Product SKU packaging visual assets.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), product_id (uuid), file_id (uuid), is_primary (boolean), display_order (integer)`
- **Foreign Keys:** `tenant_id -> tenants(id), product_id -> products(id), file_id -> file_storage(id)`
- **Indexes & Constraints:** `idx_product_images_product on (tenant_id, product_id)`

#### 53. `public.product_documents`
- **Layer / Module:** Layer 3: Product Master | Product Catalog
- **Purpose:** Regulatory prescribing inserts, clinical trials, and certificates of analysis (CoA).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), product_id (uuid), file_id (uuid), document_type (text check: prescribing_info, clinical_study, certificate_of_analysis, brochure), title (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), product_id -> products(id), file_id -> file_storage(id)`
- **Indexes & Constraints:** `check(document_type in ('prescribing_info','clinical_study','certificate_of_analysis','brochure'))`

### Stage 04: Warehouses, Batches & Inventory

#### 54. `public.warehouses`
- **Layer / Module:** Layer 4: Warehouse & Inventory | Warehouse Management
- **Purpose:** Depots, Carrying & Forwarding (C&F) agencies, and regional stock locations.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), branch_id (uuid), code (text), name (text), warehouse_type (text check: central_depot, cnf, regional, transit), address (text), manager_id (uuid), is_active (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id), branch_id -> branches(id), manager_id -> app_users(id)`
- **Indexes & Constraints:** `unique(tenant_id, code), check(warehouse_type in ('central_depot','cnf','regional','transit'))`

#### 55. `public.warehouse_locations`
- **Layer / Module:** Layer 4: Warehouse & Inventory | Warehouse Management
- **Purpose:** Internal storage bins, racks, shelves, and cold-chain zones.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), warehouse_id (uuid), aisle (text), rack (text), shelf (text), bin_code (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), warehouse_id -> warehouses(id)`
- **Indexes & Constraints:** `unique(tenant_id, warehouse_id, bin_code)`

#### 56. `public.product_batches`
- **Layer / Module:** Layer 4: Warehouse & Inventory | Inventory Management
- **Purpose:** Pharmaceutical batch numbering, manufacturing dates, mandatory expiry dates, and quarantine flags.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), product_id (uuid), batch_number (text), manufacturing_date (date), expiry_date (date), mrp (numeric(14,2)), ptr (numeric(14,2)), cost_price (numeric(14,2)), is_quarantined (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id), product_id -> products(id)`
- **Indexes & Constraints:** `unique(tenant_id, product_id, batch_number), idx_batches_expiry on (tenant_id, expiry_date)`

#### 57. `public.inventory_stocks`
- **Layer / Module:** Layer 4: Warehouse & Inventory | Inventory Management
- **Purpose:** Real-time stock balance per warehouse, SKU, and batch.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), warehouse_id (uuid), product_id (uuid), batch_id (uuid), quantity_on_hand (bigint), quantity_allocated (bigint), quantity_available (bigint), reorder_level (bigint)`
- **Foreign Keys:** `tenant_id -> tenants(id), warehouse_id -> warehouses(id), product_id -> products(id), batch_id -> product_batches(id)`
- **Indexes & Constraints:** `unique(tenant_id, warehouse_id, product_id, batch_id)`

#### 58. `public.stock_transactions`
- **Layer / Module:** Layer 4: Warehouse & Inventory | Inventory Management
- **Purpose:** Immutable double-entry inventory audit ledger recording all physical stock movements.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), warehouse_id (uuid), product_id (uuid), batch_id (uuid), transaction_type (text check: grn, dispatch, transfer_in, transfer_out, adjustment_in, adjustment_out, sample_issue), reference_type (text), reference_id (uuid), quantity (bigint), unit_cost (numeric(14,2)), balance_after (bigint), remarks (text), transaction_date (timestamptz)`
- **Foreign Keys:** `tenant_id -> tenants(id), warehouse_id -> warehouses(id), product_id -> products(id), batch_id -> product_batches(id)`
- **Indexes & Constraints:** `idx_stock_tx_lookup on (tenant_id, warehouse_id, product_id, transaction_date desc)`

#### 59. `public.stock_transfers`
- **Layer / Module:** Layer 4: Warehouse & Inventory | Inventory Management
- **Purpose:** Inter-warehouse stock transfer orders (Depot to C&F).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), transfer_number (text), from_warehouse_id (uuid), to_warehouse_id (uuid), status (text check: draft, in_transit, received, cancelled), dispatch_date (timestamptz), receive_date (timestamptz), requested_by_user_id (uuid), approved_by_user_id (uuid)`
- **Foreign Keys:** `tenant_id -> tenants(id), from_warehouse_id -> warehouses(id), to_warehouse_id -> warehouses(id), requested_by_user_id -> app_users(id), approved_by_user_id -> app_users(id)`
- **Indexes & Constraints:** `unique(tenant_id, transfer_number)`

#### 60. `public.stock_transfer_items`
- **Layer / Module:** Layer 4: Warehouse & Inventory | Inventory Management
- **Purpose:** Item lines for inter-warehouse stock transfer.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), stock_transfer_id (uuid), product_id (uuid), batch_id (uuid), quantity_sent (bigint), quantity_received (bigint), remarks (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), stock_transfer_id -> stock_transfers(id), product_id -> products(id), batch_id -> product_batches(id)`
- **Indexes & Constraints:** `idx_transfer_items_parent on (tenant_id, stock_transfer_id)`

#### 61. `public.stock_adjustments`
- **Layer / Module:** Layer 4: Warehouse & Inventory | Inventory Management
- **Purpose:** Stock write-offs, physical inventory audit differences, and damage entries.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), warehouse_id (uuid), adjustment_number (text), reason (text check: physical_count_diff, damaged, expired, theft), status (text check: draft, approved, rejected), approved_by_user_id (uuid), adjustment_date (timestamptz)`
- **Foreign Keys:** `tenant_id -> tenants(id), warehouse_id -> warehouses(id), approved_by_user_id -> app_users(id)`
- **Indexes & Constraints:** `unique(tenant_id, adjustment_number)`

#### 62. `public.stock_adjustment_items`
- **Layer / Module:** Layer 4: Warehouse & Inventory | Inventory Management
- **Purpose:** Line items for stock reconciliation adjustments.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), stock_adjustment_id (uuid), product_id (uuid), batch_id (uuid), system_quantity (bigint), counted_quantity (bigint), difference_quantity (bigint), unit_cost (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), stock_adjustment_id -> stock_adjustments(id), product_id -> products(id), batch_id -> product_batches(id)`
- **Indexes & Constraints:** `idx_adj_items_parent on (tenant_id, stock_adjustment_id)`

#### 63. `public.stock_reorder_alerts`
- **Layer / Module:** Layer 4: Warehouse & Inventory | Inventory Management
- **Purpose:** Automated warehouse replenishment safety thresholds.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), warehouse_id (uuid), product_id (uuid), min_quantity (bigint), reorder_quantity (bigint), last_alert_date (timestamptz)`
- **Foreign Keys:** `tenant_id -> tenants(id), warehouse_id -> warehouses(id), product_id -> products(id)`
- **Indexes & Constraints:** `unique(tenant_id, warehouse_id, product_id)`

#### 64. `public.gift_items`
- **Layer / Module:** Layer 4: Warehouse & Inventory | Gift & Promotional Item Inventory
- **Purpose:** Promotional reminder items, doctor gifts, medical kits, and executive items. Single owning table.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text), description (text), category (text check: reminder_item, medical_kit, executive_gift, festival_gift), unit_cost (numeric(14,2)), is_active (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 65. `public.gift_inventories`
- **Layer / Module:** Layer 4: Warehouse & Inventory | Gift & Promotional Item Inventory
- **Purpose:** Warehouse physical stock of promotional gift items. Resolves duplicate gift inventory tables.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), warehouse_id (uuid), gift_item_id (uuid), quantity_on_hand (bigint), quantity_allocated (bigint)`
- **Foreign Keys:** `tenant_id -> tenants(id), warehouse_id -> warehouses(id), gift_item_id -> gift_items(id)`
- **Indexes & Constraints:** `unique(tenant_id, warehouse_id, gift_item_id)`

#### 66. `public.gift_stock_transactions`
- **Layer / Module:** Layer 4: Warehouse & Inventory | Gift & Promotional Item Inventory
- **Purpose:** Audit ledger tracking receipt and MR distribution of gift items.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), warehouse_id (uuid), gift_item_id (uuid), transaction_type (text check: purchase, issue_to_mr, adjustment), reference_type (text), reference_id (uuid), quantity (bigint), balance_after (bigint), transaction_date (timestamptz)`
- **Foreign Keys:** `tenant_id -> tenants(id), warehouse_id -> warehouses(id), gift_item_id -> gift_items(id)`
- **Indexes & Constraints:** `idx_gift_tx_lookup on (tenant_id, warehouse_id, gift_item_id, transaction_date desc)`

#### 67. `public.sample_allocations`
- **Layer / Module:** Layer 4: Warehouse & Inventory | Field Allocation
- **Purpose:** Physician sample drug quantities issued to field MRs for doctor sampling.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), mr_id (uuid), product_id (uuid), batch_id (uuid), allocated_quantity (bigint), distributed_quantity (bigint), period_start (date), period_end (date)`
- **Foreign Keys:** `tenant_id -> tenants(id), mr_id -> app_users(id), product_id -> products(id), batch_id -> product_batches(id)`
- **Indexes & Constraints:** `idx_sample_alloc_mr on (tenant_id, mr_id, period_start)`

#### 68. `public.gift_allocations`
- **Layer / Module:** Layer 4: Warehouse & Inventory | Field Allocation
- **Purpose:** Gift item quantities allocated to MRs for doctor relationship building.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), mr_id (uuid), gift_item_id (uuid), allocated_quantity (bigint), distributed_quantity (bigint), period_start (date), period_end (date)`
- **Foreign Keys:** `tenant_id -> tenants(id), mr_id -> app_users(id), gift_item_id -> gift_items(id)`
- **Indexes & Constraints:** `idx_gift_alloc_mr on (tenant_id, mr_id, period_start)`

### Stage 05: Procurement & Suppliers

#### 69. `public.supplier_categories`
- **Layer / Module:** Layer 5: Purchase | Vendor Masters
- **Purpose:** Vendor classifications (API Manufacturer, Contract Formulator, Packaging Supplier).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 70. `public.suppliers`
- **Layer / Module:** Layer 5: Purchase | Vendor Masters
- **Purpose:** Vendor / Supplier directory with statutory drug manufacturing licenses and GST numbers.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), supplier_code (text), name (text), supplier_category_id (uuid), gst_number (text), drug_license_no (text), pan_number (text), payment_term_id (uuid), credit_limit (numeric(14,2)), status (text check: active, blocked, under_review)`
- **Foreign Keys:** `tenant_id -> tenants(id), supplier_category_id -> supplier_categories(id), payment_term_id -> payment_terms(id)`
- **Indexes & Constraints:** `unique(tenant_id, supplier_code)`

#### 71. `public.purchase_requisitions`
- **Layer / Module:** Layer 5: Purchase | Procurement Operations
- **Purpose:** Internal purchase demand requisitions created by plant/warehouse managers.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), requisition_number (text), requested_by_user_id (uuid), department_id (uuid), required_date (date), status (text check: draft, submitted, approved, rejected, ordered), remarks (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), requested_by_user_id -> app_users(id), department_id -> departments(id)`
- **Indexes & Constraints:** `unique(tenant_id, requisition_number)`

#### 72. `public.purchase_requisition_items`
- **Layer / Module:** Layer 5: Purchase | Procurement Operations
- **Purpose:** Product items demanded on purchase requisition.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), requisition_id (uuid), product_id (uuid), requested_quantity (bigint), estimated_rate (numeric(14,2)), purpose (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), requisition_id -> purchase_requisitions(id), product_id -> products(id)`
- **Indexes & Constraints:** `idx_pr_items_parent on (tenant_id, requisition_id)`

#### 73. `public.purchase_orders`
- **Layer / Module:** Layer 5: Purchase | Procurement Operations
- **Purpose:** Official Purchase Orders PO placed with suppliers.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), po_number (text), supplier_id (uuid), warehouse_id (uuid), order_date (date), expected_delivery_date (date), payment_term_id (uuid), subtotal (numeric(14,2)), tax_amount (numeric(14,2)), total_amount (numeric(14,2)), status (text check: draft, issued, partially_received, completed, cancelled), approved_by_user_id (uuid)`
- **Foreign Keys:** `tenant_id -> tenants(id), supplier_id -> suppliers(id), warehouse_id -> warehouses(id), payment_term_id -> payment_terms(id), approved_by_user_id -> app_users(id)`
- **Indexes & Constraints:** `unique(tenant_id, po_number)`

#### 74. `public.purchase_order_items`
- **Layer / Module:** Layer 5: Purchase | Procurement Operations
- **Purpose:** Line items on Purchase Orders.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), purchase_order_id (uuid), product_id (uuid), ordered_quantity (bigint), unit_price (numeric(14,2)), tax_rate (numeric(5,2)), tax_amount (numeric(14,2)), line_total (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), purchase_order_id -> purchase_orders(id), product_id -> products(id)`
- **Indexes & Constraints:** `idx_po_items_parent on (tenant_id, purchase_order_id)`

#### 75. `public.goods_receipt_notes`
- **Layer / Module:** Layer 5: Purchase | Inbound Logistics & QA
- **Purpose:** Goods Receipt Note GRN for inbound consignment receipt and QA inspection.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), grn_number (text), purchase_order_id (uuid), supplier_id (uuid), warehouse_id (uuid), invoice_number (text), invoice_date (date), received_date (timestamptz), status (text check: draft, verified, posted), remarks (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), purchase_order_id -> purchase_orders(id), supplier_id -> suppliers(id), warehouse_id -> warehouses(id)`
- **Indexes & Constraints:** `unique(tenant_id, grn_number)`

#### 76. `public.goods_receipt_items`
- **Layer / Module:** Layer 5: Purchase | Inbound Logistics & QA
- **Purpose:** Batch-level receipt, accepted and rejected quantities based on Certificate of Analysis.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), grn_id (uuid), po_item_id (uuid), product_id (uuid), batch_number (text), mfg_date (date), expiry_date (date), quantity_received (bigint), quantity_accepted (bigint), quantity_rejected (bigint), unit_price (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), grn_id -> goods_receipt_notes(id), po_item_id -> purchase_order_items(id), product_id -> products(id)`
- **Indexes & Constraints:** `idx_grn_items_parent on (tenant_id, grn_id)`

#### 77. `public.purchase_bills`
- **Layer / Module:** Layer 5: Purchase | Accounts Payable
- **Purpose:** Accounts Payable commercial invoices from vendors verified against GRN.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), bill_number (text), supplier_id (uuid), grn_id (uuid), po_id (uuid), bill_date (date), due_date (date), subtotal (numeric(14,2)), tax_amount (numeric(14,2)), discount_amount (numeric(14,2)), total_amount (numeric(14,2)), status (text check: pending, partially_paid, paid, void)`
- **Foreign Keys:** `tenant_id -> tenants(id), supplier_id -> suppliers(id), grn_id -> goods_receipt_notes(id), po_id -> purchase_orders(id)`
- **Indexes & Constraints:** `unique(tenant_id, bill_number)`

#### 78. `public.purchase_bill_items`
- **Layer / Module:** Layer 5: Purchase | Accounts Payable
- **Purpose:** Lines on vendor purchase bills.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), purchase_bill_id (uuid), grn_item_id (uuid), product_id (uuid), quantity (bigint), unit_price (numeric(14,2)), tax_amount (numeric(14,2)), line_total (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), purchase_bill_id -> purchase_bills(id), grn_item_id -> goods_receipt_items(id), product_id -> products(id)`
- **Indexes & Constraints:** `idx_pb_items_parent on (tenant_id, purchase_bill_id)`

#### 79. `public.purchase_returns`
- **Layer / Module:** Layer 5: Purchase | Procurement Operations
- **Purpose:** Debit notes / returns to suppliers for failed QA batches or transit breakages.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), return_number (text), supplier_id (uuid), warehouse_id (uuid), return_date (date), reason (text check: qc_failed, damaged, short_expiry), subtotal (numeric(14,2)), tax_amount (numeric(14,2)), total_amount (numeric(14,2)), status (text check: draft, approved, completed)`
- **Foreign Keys:** `tenant_id -> tenants(id), supplier_id -> suppliers(id), warehouse_id -> warehouses(id)`
- **Indexes & Constraints:** `unique(tenant_id, return_number)`

#### 80. `public.purchase_return_items`
- **Layer / Module:** Layer 5: Purchase | Procurement Operations
- **Purpose:** Batch lines returned to supplier.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), purchase_return_id (uuid), product_id (uuid), batch_id (uuid), quantity (bigint), unit_price (numeric(14,2)), tax_amount (numeric(14,2)), line_total (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), purchase_return_id -> purchase_returns(id), product_id -> products(id), batch_id -> product_batches(id)`
- **Indexes & Constraints:** `idx_pr_return_items on (tenant_id, purchase_return_id)`

### Stage 06: Stockists & Sales (Primary & Secondary)

#### 81. `public.customer_categories`
- **Layer / Module:** Layer 6: Sales | Sales Masters
- **Purpose:** Customer classifications (Stockist, Super Stockist, Direct Retailer, Institutional Hospital).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 82. `public.stockists`
- **Layer / Module:** Layer 6: Sales | Channel Masters
- **Purpose:** Distributor / Stockist master. Central wholesale buyer connecting pharma company to retail pharmacies.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), stockist_code (text), name (text), stockist_type (text check: stockist, super_stockist, distributor), territory_id (uuid), area_id (uuid), gst_no (text), dl_no (text), credit_limit (numeric(14,2)), payment_term_id (uuid), status (text check: active, blocked, inactive)`
- **Foreign Keys:** `tenant_id -> tenants(id), territory_id -> territories(id), area_id -> areas(id), payment_term_id -> payment_terms(id)`
- **Indexes & Constraints:** `unique(tenant_id, stockist_code), idx_stockists_territory on (tenant_id, territory_id)`

#### 83. `public.primary_orders`
- **Layer / Module:** Layer 6: Sales | Primary Sales (Company -> Stockist)
- **Purpose:** Wholesale Sales Orders placed by stockists or captured by managers.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), order_number (text), stockist_id (uuid), division_id (uuid), order_date (date), status (text check: draft, submitted, approved, processing, dispatched, cancelled), payment_term_id (uuid), subtotal (numeric(14,2)), tax_amount (numeric(14,2)), total_amount (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), stockist_id -> stockists(id), division_id -> business_divisions(id), payment_term_id -> payment_terms(id)`
- **Indexes & Constraints:** `unique(tenant_id, order_number)`

#### 84. `public.primary_order_items`
- **Layer / Module:** Layer 6: Sales | Primary Sales
- **Purpose:** SKU order lines on primary sales order.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), primary_order_id (uuid), product_id (uuid), ordered_quantity (bigint), unit_price (numeric(14,2)), discount_percent (numeric(5,2)), tax_amount (numeric(14,2)), line_total (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), primary_order_id -> primary_orders(id), product_id -> products(id)`
- **Indexes & Constraints:** `idx_po_item_parent on (tenant_id, primary_order_id)`

#### 85. `public.primary_invoices`
- **Layer / Module:** Layer 6: Sales | Primary Sales
- **Purpose:** Commercial GST tax invoices issued to stockists for drug dispatches.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), invoice_number (text), primary_order_id (uuid), stockist_id (uuid), invoice_date (date), due_date (date), subtotal (numeric(14,2)), tax_amount (numeric(14,2)), total_amount (numeric(14,2)), status (text check: issued, partially_paid, paid, cancelled)`
- **Foreign Keys:** `tenant_id -> tenants(id), primary_order_id -> primary_orders(id), stockist_id -> stockists(id)`
- **Indexes & Constraints:** `unique(tenant_id, invoice_number)`

#### 86. `public.primary_invoice_items`
- **Layer / Module:** Layer 6: Sales | Primary Sales
- **Purpose:** Invoiced batches, billing rates, and scheme bonus free items.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), primary_invoice_id (uuid), product_id (uuid), batch_id (uuid), quantity (bigint), free_quantity (bigint), unit_price (numeric(14,2)), discount_amount (numeric(14,2)), tax_amount (numeric(14,2)), line_total (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), primary_invoice_id -> primary_invoices(id), product_id -> products(id), batch_id -> product_batches(id)`
- **Indexes & Constraints:** `idx_inv_items_parent on (tenant_id, primary_invoice_id)`

#### 87. `public.primary_sales`
- **Layer / Module:** Layer 6: Sales | Primary Sales Analytics
- **Purpose:** Aggregated primary sales ledger for monthly target tracking.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), stockist_id (uuid), invoice_id (uuid), sale_date (date), total_value (numeric(14,2)), reporting_month (integer), reporting_year (integer)`
- **Foreign Keys:** `tenant_id -> tenants(id), stockist_id -> stockists(id), invoice_id -> primary_invoices(id)`
- **Indexes & Constraints:** `idx_primary_sales_period on (tenant_id, reporting_year, reporting_month)`

#### 88. `public.primary_sales_items`
- **Layer / Module:** Layer 6: Sales | Primary Sales Analytics
- **Purpose:** Granular product revenue attribution on primary sales.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), primary_sales_id (uuid), product_id (uuid), quantity (bigint), rate (numeric(14,2)), total_amount (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), primary_sales_id -> primary_sales(id), product_id -> products(id)`
- **Indexes & Constraints:** `idx_ps_items_parent on (tenant_id, primary_sales_id)`

#### 89. `public.delivery_challans`
- **Layer / Module:** Layer 6: Sales | Outbound Logistics
- **Purpose:** Lorry receipt (LR) and dispatch documentation for pharmaceutical shipments.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), challan_number (text), invoice_id (uuid), warehouse_id (uuid), transporter_name (text), lr_number (text), dispatch_date (timestamptz), delivery_date (timestamptz), status (text check: prepared, dispatched, in_transit, delivered)`
- **Foreign Keys:** `tenant_id -> tenants(id), invoice_id -> primary_invoices(id), warehouse_id -> warehouses(id)`
- **Indexes & Constraints:** `unique(tenant_id, challan_number)`

#### 90. `public.sales_returns`
- **Layer / Module:** Layer 6: Sales | Sales Operations
- **Purpose:** Credit notes and goods return for near-expiry or damaged goods returned from market.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), return_number (text), return_type (text check: saleable, breakage, expired), customer_type (text check: stockist, chemist), entity_id (uuid), warehouse_id (uuid), return_date (date), reason (text), subtotal (numeric(14,2)), tax_amount (numeric(14,2)), total_amount (numeric(14,2)), status (text check: draft, verified, credited)`
- **Foreign Keys:** `tenant_id -> tenants(id), warehouse_id -> warehouses(id)`
- **Indexes & Constraints:** `unique(tenant_id, return_number)`

#### 91. `public.sales_return_items`
- **Layer / Module:** Layer 6: Sales | Sales Operations
- **Purpose:** Returned batch items.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), sales_return_id (uuid), product_id (uuid), batch_id (uuid), quantity (bigint), unit_price (numeric(14,2)), tax_amount (numeric(14,2)), line_total (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), sales_return_id -> sales_returns(id), product_id -> products(id), batch_id -> product_batches(id)`
- **Indexes & Constraints:** `idx_sr_items_parent on (tenant_id, sales_return_id)`

#### 92. `public.customer_payments`
- **Layer / Module:** Layer 6: Sales | Accounts Receivable
- **Purpose:** Money collected from stockists and chemists against invoices.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), receipt_number (text), customer_type (text check: stockist, chemist), entity_id (uuid), payment_date (date), payment_mode (text check: cash, cheque, neft, rtgs, upi), reference_number (text), amount (numeric(14,2)), status (text check: pending, cleared, bounced)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, receipt_number)`

#### 93. `public.payment_allocations`
- **Layer / Module:** Layer 6: Sales | Accounts Receivable
- **Purpose:** Knock-off table allocating payments to open primary invoices.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), payment_id (uuid), invoice_id (uuid), allocated_amount (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), payment_id -> customer_payments(id), invoice_id -> primary_invoices(id)`
- **Indexes & Constraints:** `idx_pay_alloc on (tenant_id, payment_id, invoice_id)`

#### 94. `public.collections`
- **Layer / Module:** Layer 6: Sales | Field SFA Collections
- **Purpose:** Field cheque and payment collections captured by MRs on visits. Resolves chemist payment duplicate.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), mr_id (uuid), customer_type (text check: stockist, chemist), entity_id (uuid), collection_date (date), amount (numeric(14,2)), payment_mode (text check: cheque, cash, online), cheque_number (text), cheque_date (date), status (text check: collected, deposited, verified)`
- **Foreign Keys:** `tenant_id -> tenants(id), mr_id -> app_users(id)`
- **Indexes & Constraints:** `idx_collections_mr on (tenant_id, mr_id, collection_date desc)`

#### 95. `public.credit_limits`
- **Layer / Module:** Layer 6: Sales | Credit Control
- **Purpose:** Outstanding exposure, overdue limits, and credit stops.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), customer_type (text check: stockist, chemist), entity_id (uuid), credit_limit (numeric(14,2)), current_exposure (numeric(14,2)), overdue_amount (numeric(14,2)), status (text check: regular, warning, stopped)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, customer_type, entity_id)`

#### 96. `public.sales_representatives_mapping`
- **Layer / Module:** Layer 6: Sales | Channel Operations
- **Purpose:** Stockist alignment to field MRs and Managers.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), user_id (uuid), stockist_id (uuid), is_primary (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id), user_id -> app_users(id), stockist_id -> stockists(id)`
- **Indexes & Constraints:** `unique(tenant_id, user_id, stockist_id)`

### Stage 07: CRM & SFA (Doctors, Chemists, Visits, POB, RCPA)

#### 97. `public.doctor_specialities`
- **Layer / Module:** Layer 7: CRM | Doctor Master
- **Purpose:** Physician medical specialities (Cardiology, Paediatrics, Orthopaedics, Dermatology).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text), description (text)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 98. `public.doctor_categories`
- **Layer / Module:** Layer 7: CRM | Doctor Master
- **Purpose:** Doctor classification tiers (A+, A, B, C) defining mandatory monthly visit call frequencies.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text), visit_frequency_per_month (integer)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 99. `public.doctor_qualifications`
- **Layer / Module:** Layer 7: CRM | Doctor Master
- **Purpose:** Recognized medical qualifications (MBBS, MD, MS, DM, MCh, DNB).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), abbreviation (text), name (text)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, abbreviation)`

#### 100. `public.hospitals`
- **Layer / Module:** Layer 7: CRM | Institutional Master
- **Purpose:** Hospitals, nursing homes, and polyclinics where doctors consult.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), name (text), hospital_type (text check: government, private_corporate, nursing_home, trust), territory_id (uuid), bed_count (integer), address (text), status (text check: active, closed)`
- **Foreign Keys:** `tenant_id -> tenants(id), territory_id -> territories(id)`
- **Indexes & Constraints:** `idx_hospitals_territory on (tenant_id, territory_id)`

#### 101. `public.doctors`
- **Layer / Module:** Layer 7: CRM | Doctor Master
- **Purpose:** Central Doctor / Prescriber master. Core CRM entity visited by MRs.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), doctor_code (text), name (text), gender (text check: male, female, other), mobile (text), email (text), qualification_id (uuid), speciality_id (uuid), category_id (uuid), doctor_type (text check: consultant, resident, private_practitioner), hospital_id (uuid), visit_frequency (integer), dob (date), anniversary (date), division_id (uuid), territory_id (uuid), area_id (uuid), status (text check: active, transferred, inactive)`
- **Foreign Keys:** `tenant_id -> tenants(id), qualification_id -> doctor_qualifications(id), speciality_id -> doctor_specialities(id), category_id -> doctor_categories(id), hospital_id -> hospitals(id), division_id -> business_divisions(id), territory_id -> territories(id), area_id -> areas(id)`
- **Indexes & Constraints:** `unique(tenant_id, doctor_code), idx_doctors_territory on (tenant_id, territory_id)`

#### 102. `public.doctor_affiliations`
- **Layer / Module:** Layer 7: CRM | Doctor Master
- **Purpose:** Doctor visiting hours and consulting schedules across multiple hospitals/clinics.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), doctor_id (uuid), hospital_id (uuid), visiting_hours (text), notes (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), doctor_id -> doctors(id), hospital_id -> hospitals(id)`
- **Indexes & Constraints:** `unique(tenant_id, doctor_id, hospital_id)`

#### 103. `public.doctor_brand_prescriptions`
- **Layer / Module:** Layer 7: CRM | Doctor Profiling
- **Purpose:** Prescribing habit profiling and monthly potential units per brand.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), doctor_id (uuid), mr_id (uuid), product_id (uuid), prescribing_habit (text check: regular, occasional, trial, non_prescriber), potential_units_per_month (integer), audit_date (date)`
- **Foreign Keys:** `tenant_id -> tenants(id), doctor_id -> doctors(id), mr_id -> app_users(id), product_id -> products(id)`
- **Indexes & Constraints:** `idx_doc_brand_rx on (tenant_id, doctor_id, product_id)`

#### 104. `public.chemist_categories`
- **Layer / Module:** Layer 7: CRM | Chemist Master
- **Purpose:** Retail pharmacy categories (Independent Retail, Chain Pharmacy, Hospital Attached).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text), description (text)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 105. `public.chemists`
- **Layer / Module:** Layer 7: CRM | Chemist Master
- **Purpose:** Central Retail Pharmacy master. Handles MR field chemist additions with status pending_verification.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), chemist_code (text), name (text), contact_person (text), mobile (text), email (text), chemist_type (text check: independent, chain_store, hospital_attached), category_id (uuid), territory_id (uuid), division_id (uuid), visit_frequency (integer), dob (date), anniversary (date), gst_no (text), dl_no (text), status (text check: active, pending_verification, inactive)`
- **Foreign Keys:** `tenant_id -> tenants(id), category_id -> chemist_categories(id), territory_id -> territories(id), division_id -> business_divisions(id)`
- **Indexes & Constraints:** `unique(tenant_id, chemist_code), idx_chemists_territory on (tenant_id, territory_id)`

#### 106. `public.chemist_stockists`
- **Layer / Module:** Layer 7: CRM | Chemist Master
- **Purpose:** Commercial mapping indicating which stockists supply each chemist.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), chemist_id (uuid), stockist_id (uuid), is_preferred (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id), chemist_id -> chemists(id), stockist_id -> stockists(id)`
- **Indexes & Constraints:** `unique(tenant_id, chemist_id, stockist_id)`

#### 107. `public.secondary_sales`
- **Layer / Module:** Layer 7: CRM | Secondary Sales
- **Purpose:** Secondary sales recorded from stockist statements to retail chemists (tertiary demand).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), stockist_id (uuid), chemist_id (uuid), sale_date (date), invoice_no (text), total_value (numeric(14,2)), reporting_month (integer), reporting_year (integer)`
- **Foreign Keys:** `tenant_id -> tenants(id), stockist_id -> stockists(id), chemist_id -> chemists(id)`
- **Indexes & Constraints:** `idx_sec_sales_period on (tenant_id, reporting_year, reporting_month)`

#### 108. `public.secondary_sales_items`
- **Layer / Module:** Layer 7: CRM | Secondary Sales
- **Purpose:** Product SKU lines on secondary sales statement.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), secondary_sales_id (uuid), product_id (uuid), batch_id (uuid), quantity (bigint), free_quantity (bigint), rate (numeric(14,2)), total_amount (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), secondary_sales_id -> secondary_sales(id), product_id -> products(id), batch_id -> product_batches(id)`
- **Indexes & Constraints:** `idx_sec_sales_items on (tenant_id, secondary_sales_id)`

#### 109. `public.tour_plans`
- **Layer / Module:** Layer 7: CRM | Tour Planning
- **Purpose:** Monthly Tour Plan (MTP) submitted by MRs for manager approval.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), mr_id (uuid), plan_month (integer), plan_year (integer), status (text check: draft, submitted, approved, rejected), approved_by_user_id (uuid), approved_at (timestamptz), remarks (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), mr_id -> app_users(id), approved_by_user_id -> app_users(id)`
- **Indexes & Constraints:** `unique(tenant_id, mr_id, plan_month, plan_year)`

#### 110. `public.tour_plan_days`
- **Layer / Module:** Layer 7: CRM | Tour Planning
- **Purpose:** Day-by-day itinerary in monthly tour plan.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), tour_plan_id (uuid), planned_date (date), territory_id (uuid), beat_id (uuid), route_id (uuid), planned_doctor_count (integer), planned_chemist_count (integer), activity_type (text check: field_work, joint_work, transit, conference, meeting, holiday)`
- **Foreign Keys:** `tenant_id -> tenants(id), tour_plan_id -> tour_plans(id), territory_id -> territories(id), beat_id -> beats(id), route_id -> routes(id)`
- **Indexes & Constraints:** `unique(tenant_id, tour_plan_id, planned_date)`

#### 111. `public.field_visits`
- **Layer / Module:** Layer 7: CRM | Field SFA Operations
- **Purpose:** Single unified visit table resolving DoctorVisit, ChemistVisit, CheckIn, CheckOut duplicates. Contains check-in/out GPS and timestamps as columns.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), mr_id (uuid), visit_type (text check: doctor, chemist, stockist, hospital), entity_type (text check: doctors, chemists, stockists, hospitals), entity_id (uuid), beat_id (uuid), route_id (uuid), tour_plan_day_id (uuid), visit_date (date), check_in_time (timestamptz), check_out_time (timestamptz), check_in_latitude (double precision), check_in_longitude (double precision), check_out_latitude (double precision), check_out_longitude (double precision), visit_status (text check: planned, in_progress, completed, missed, cancelled), remarks (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), mr_id -> app_users(id), beat_id -> beats(id), route_id -> routes(id), tour_plan_day_id -> tour_plan_days(id)`
- **Indexes & Constraints:** `idx_field_visits_mr_date on (tenant_id, mr_id, visit_date desc), idx_field_visits_entity on (tenant_id, entity_type, entity_id)`

#### 112. `public.joint_works`
- **Layer / Module:** Layer 7: CRM | Field SFA Operations
- **Purpose:** Single owning table for Manager accompaniment on visits with coaching feedback and ratings.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), visit_id (uuid), manager_id (uuid), mr_id (uuid), joint_work_date (date), manager_feedback (text), rating (integer)`
- **Foreign Keys:** `tenant_id -> tenants(id), visit_id -> field_visits(id), manager_id -> app_users(id), mr_id -> app_users(id)`
- **Indexes & Constraints:** `unique(tenant_id, visit_id, manager_id)`

#### 113. `public.visit_selfies`
- **Layer / Module:** Layer 7: CRM | Field SFA Operations
- **Purpose:** Geotagged photographic verification of MR presence at doctor clinic.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), visit_id (uuid), file_id (uuid), captured_at (timestamptz), latitude (double precision), longitude (double precision)`
- **Foreign Keys:** `tenant_id -> tenants(id), visit_id -> field_visits(id), file_id -> file_storage(id)`
- **Indexes & Constraints:** `idx_visit_selfies_visit on (tenant_id, visit_id)`

#### 114. `public.e_detailings`
- **Layer / Module:** Layer 7: CRM | Digital Detailing
- **Purpose:** Visual aid detailing session duration during doctor call.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), visit_id (uuid), mr_id (uuid), started_at (timestamptz), ended_at (timestamptz), total_duration_seconds (integer)`
- **Foreign Keys:** `tenant_id -> tenants(id), visit_id -> field_visits(id), mr_id -> app_users(id)`
- **Indexes & Constraints:** `idx_edetailing_visit on (tenant_id, visit_id)`

#### 115. `public.e_detailing_slides`
- **Layer / Module:** Layer 7: CRM | Digital Detailing
- **Purpose:** Time spent per brand presentation slide and doctor interest feedback.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), e_detailing_id (uuid), product_id (uuid), slide_number (integer), duration_seconds (integer), doctor_feedback (text check: very_interested, interested, neutral, not_interested)`
- **Foreign Keys:** `tenant_id -> tenants(id), e_detailing_id -> e_detailings(id), product_id -> products(id)`
- **Indexes & Constraints:** `idx_edetailing_slides on (tenant_id, e_detailing_id)`

#### 116. `public.doctor_feedbacks`
- **Layer / Module:** Layer 7: CRM | Field SFA Operations
- **Purpose:** Doctor discussion notes, sample satisfaction, and next follow-up dates.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), visit_id (uuid), doctor_id (uuid), feedback_type (text check: positive, neutral, negative, requested_literature, competitor_price_issue), comments (text), next_followup_date (date)`
- **Foreign Keys:** `tenant_id -> tenants(id), visit_id -> field_visits(id), doctor_id -> doctors(id)`
- **Indexes & Constraints:** `unique(tenant_id, visit_id)`

#### 117. `public.chemist_feedbacks`
- **Layer / Module:** Layer 7: CRM | Field SFA Operations
- **Purpose:** Chemist call notes on competitor schemes and fast-moving brand demands.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), visit_id (uuid), chemist_id (uuid), stock_issue (boolean), competitor_activity (text), comments (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), visit_id -> field_visits(id), chemist_id -> chemists(id)`
- **Indexes & Constraints:** `unique(tenant_id, visit_id)`

#### 118. `public.pobs`
- **Layer / Module:** Layer 7: CRM | Field SFA POB
- **Purpose:** Pre-Order Bookings POB captured during chemist and doctor calls. Single owning table.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), visit_id (uuid), mr_id (uuid), customer_type (text check: chemist, doctor, hospital), entity_id (uuid), stockist_id (uuid), pob_date (date), total_amount (numeric(14,2)), status (text check: draft, booked, delivered, cancelled), expected_delivery_date (date)`
- **Foreign Keys:** `tenant_id -> tenants(id), visit_id -> field_visits(id), mr_id -> app_users(id), stockist_id -> stockists(id)`
- **Indexes & Constraints:** `idx_pobs_mr_date on (tenant_id, mr_id, pob_date desc)`

#### 119. `public.pob_products`
- **Layer / Module:** Layer 7: CRM | Field SFA POB
- **Purpose:** Product lines within POB booking.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), pob_id (uuid), product_id (uuid), quantity (bigint), rate (numeric(14,2)), total_amount (numeric(14,2)), discount_percent (numeric(5,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), pob_id -> pobs(id), product_id -> products(id)`
- **Indexes & Constraints:** `idx_pob_products_parent on (tenant_id, pob_id)`

#### 120. `public.doctor_gift_distributions`
- **Layer / Module:** Layer 7: CRM | Field SFA Operations
- **Purpose:** Gift items handed over to doctor during visit. Deducts from MR gift allocation. Single owning table.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), visit_id (uuid), doctor_id (uuid), gift_item_id (uuid), quantity (integer), acknowledged_by_doctor (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id), visit_id -> field_visits(id), doctor_id -> doctors(id), gift_item_id -> gift_items(id)`
- **Indexes & Constraints:** `idx_doc_gift_dist on (tenant_id, visit_id, gift_item_id)`

#### 121. `public.doctor_sample_distributions`
- **Layer / Module:** Layer 7: CRM | Field SFA Operations
- **Purpose:** Physician drug sample batches handed over to doctor during call.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), visit_id (uuid), doctor_id (uuid), product_id (uuid), batch_id (uuid), quantity (integer)`
- **Foreign Keys:** `tenant_id -> tenants(id), visit_id -> field_visits(id), doctor_id -> doctors(id), product_id -> products(id), batch_id -> product_batches(id)`
- **Indexes & Constraints:** `idx_doc_sample_dist on (tenant_id, visit_id, product_id)`

#### 122. `public.rcpa_audits`
- **Layer / Module:** Layer 7: CRM | Retail Chemist Prescription Audit RCPA
- **Purpose:** Retail Chemist Prescription Audit session tracking doctor prescriptions in chemist retail counters.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), visit_id (uuid), mr_id (uuid), chemist_id (uuid), doctor_id (uuid), audit_date (date), prescription_trend (text check: increasing, steady, declining)`
- **Foreign Keys:** `tenant_id -> tenants(id), visit_id -> field_visits(id), mr_id -> app_users(id), chemist_id -> chemists(id), doctor_id -> doctors(id)`
- **Indexes & Constraints:** `idx_rcpa_audit on (tenant_id, chemist_id, doctor_id, audit_date desc)`

#### 123. `public.rcpa_audit_items`
- **Layer / Module:** Layer 7: CRM | Retail Chemist Prescription Audit RCPA
- **Purpose:** Prescription share comparison between company brand and competitor medicines.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), rcpa_audit_id (uuid), our_product_id (uuid), our_units_prescribed (integer), competitor_brand_name (text), competitor_company (text), competitor_units_prescribed (integer)`
- **Foreign Keys:** `tenant_id -> tenants(id), rcpa_audit_id -> rcpa_audits(id), our_product_id -> products(id)`
- **Indexes & Constraints:** `idx_rcpa_items on (tenant_id, rcpa_audit_id)`

#### 124. `public.daily_call_reports`
- **Layer / Module:** Layer 7: CRM | Daily Reporting DCR
- **Purpose:** Daily Call Report DCR summary submitted at end-of-day by MR for manager sign-off.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), mr_id (uuid), report_date (date), beat_id (uuid), total_calls (integer), doctor_calls (integer), chemist_calls (integer), stockist_calls (integer), total_pob_value (numeric(14,2)), status (text check: draft, submitted, approved, rejected), submitted_at (timestamptz), approved_by_user_id (uuid)`
- **Foreign Keys:** `tenant_id -> tenants(id), mr_id -> app_users(id), beat_id -> beats(id), approved_by_user_id -> app_users(id)`
- **Indexes & Constraints:** `unique(tenant_id, mr_id, report_date)`

#### 125. `public.sales_targets`
- **Layer / Module:** Layer 7: CRM | Target & Achievement
- **Purpose:** Monthly sales and visit quotas assigned to MRs and Managers.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), user_id (uuid), target_type (text check: secondary_sales, primary_sales, doctor_calls, pob_value), target_month (integer), target_year (integer), division_id (uuid), product_id (uuid), target_quantity (bigint), target_amount (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), user_id -> app_users(id), division_id -> business_divisions(id), product_id -> products(id)`
- **Indexes & Constraints:** `idx_targets_user on (tenant_id, user_id, target_year, target_month)`

#### 126. `public.sales_achievements`
- **Layer / Module:** Layer 7: CRM | Target & Achievement
- **Purpose:** Periodic automated computation of percentage target achievement.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), sales_target_id (uuid), achieved_quantity (bigint), achieved_amount (numeric(14,2)), achievement_percentage (numeric(6,2)), computed_at (timestamptz)`
- **Foreign Keys:** `tenant_id -> tenants(id), sales_target_id -> sales_targets(id)`
- **Indexes & Constraints:** `idx_achievements_target on (tenant_id, sales_target_id)`

#### 127. `public.mr_documents`
- **Layer / Module:** Layer 7: CRM | Field SFA Operations
- **Purpose:** Field representative compliance credentials and identity documents.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), mr_id (uuid), document_type (text check: pan, aadhar, driving_license, appointment_letter), title (text), file_id (uuid), expiry_date (date)`
- **Foreign Keys:** `tenant_id -> tenants(id), mr_id -> app_users(id), file_id -> file_storage(id)`
- **Indexes & Constraints:** `idx_mr_docs on (tenant_id, mr_id)`

### Stage 08: HR, Attendance, Leave, Expense & Payroll

#### 128. `public.shifts`
- **Layer / Module:** Layer 8: HR | HR & Shifts
- **Purpose:** Work shift timing configurations.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), name (text), start_time (time), end_time (time), grace_period_minutes (integer), is_night_shift (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, name)`

#### 129. `public.employees`
- **Layer / Module:** Layer 8: HR | HR Core
- **Purpose:** Master employee record. Single owning table for all personnel (Head Office, Plant, Field MRs). Links to app_users.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), user_id (uuid), branch_id (uuid), department_id (uuid), employee_code (text), first_name (text), last_name (text), gender (text check: male, female, other), date_of_birth (date), date_of_joining (date), designation (text), pan_no (text), aadhar_no (text), uan_no (text), bank_name (text), bank_account_no (text), bank_ifsc (text), marital_status (text check: single, married, other), status (text check: active, probation, resigned, terminated)`
- **Foreign Keys:** `tenant_id -> tenants(id), user_id -> app_users(id), branch_id -> branches(id), department_id -> departments(id)`
- **Indexes & Constraints:** `unique(tenant_id, employee_code), unique(tenant_id, user_id)`

#### 130. `public.employee_shifts`
- **Layer / Module:** Layer 8: HR | HR & Shifts
- **Purpose:** Employee-to-shift assignments.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), employee_id (uuid), shift_id (uuid), effective_from (date), effective_to (date)`
- **Foreign Keys:** `tenant_id -> tenants(id), employee_id -> employees(id), shift_id -> shifts(id)`
- **Indexes & Constraints:** `idx_emp_shifts on (tenant_id, employee_id, effective_from)`

#### 131. `public.attendance`
- **Layer / Module:** Layer 8: HR | Attendance
- **Purpose:** Single owning table for daily employee/MR attendance. Mobile check-in records field attendance directly here.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), employee_id (uuid), attendance_date (date), shift_id (uuid), check_in_time (timestamptz), check_out_time (timestamptz), check_in_latitude (double precision), check_in_longitude (double precision), check_out_latitude (double precision), check_out_longitude (double precision), status (text check: present, half_day, absent, on_leave, field_duty, holiday), work_hours (numeric(5,2)), remarks (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), employee_id -> employees(id), shift_id -> shifts(id)`
- **Indexes & Constraints:** `unique(tenant_id, employee_id, attendance_date)`

#### 132. `public.attendance_logs`
- **Layer / Module:** Layer 8: HR | Attendance
- **Purpose:** Biometric or mobile punch telemetry logs.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), attendance_id (uuid), employee_id (uuid), punch_time (timestamptz), punch_type (text check: in, out), latitude (double precision), longitude (double precision), device_info (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), attendance_id -> attendance(id), employee_id -> employees(id)`
- **Indexes & Constraints:** `idx_punch_logs on (tenant_id, employee_id, punch_time desc)`

#### 133. `public.leave_types`
- **Layer / Module:** Layer 8: HR | Leave Management
- **Purpose:** Statutory leave policies (Casual Leave CL, Sick Leave SL, Privilege Leave PL, Maternity).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text), days_per_year (numeric(5,1)), is_paid (boolean), is_encashable (boolean), carry_forward_days (integer)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 134. `public.leave_balances`
- **Layer / Module:** Layer 8: HR | Leave Management
- **Purpose:** Annual entitlement and remaining leave quota per employee.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), employee_id (uuid), leave_type_id (uuid), year (integer), allocated_days (numeric(5,1)), used_days (numeric(5,1)), balance_days (numeric(5,1))`
- **Foreign Keys:** `tenant_id -> tenants(id), employee_id -> employees(id), leave_type_id -> leave_types(id)`
- **Indexes & Constraints:** `unique(tenant_id, employee_id, leave_type_id, year)`

#### 135. `public.leaves`
- **Layer / Module:** Layer 8: HR | Leave Management
- **Purpose:** Single owning table for leave applications and manager approvals.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), employee_id (uuid), leave_type_id (uuid), start_date (date), end_date (date), total_days (numeric(5,1)), reason (text), status (text check: pending, approved, rejected, cancelled), approved_by_employee_id (uuid), approved_at (timestamptz)`
- **Foreign Keys:** `tenant_id -> tenants(id), employee_id -> employees(id), leave_type_id -> leave_types(id), approved_by_employee_id -> employees(id)`
- **Indexes & Constraints:** `idx_leaves_emp_dates on (tenant_id, employee_id, start_date)`

#### 136. `public.holidays`
- **Layer / Module:** Layer 8: HR | HR Masters
- **Purpose:** Company and state-wise public holiday calendar.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), holiday_name (text), holiday_date (date), holiday_type (text check: national, regional, company), is_restricted (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, holiday_date, holiday_name)`

#### 137. `public.expense_categories`
- **Layer / Module:** Layer 8: HR | Expense Management
- **Purpose:** Pharma field expense slabs (Daily Allowance DA, Travel Allowance TA, Hotel Lodging, Fuel).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text), max_daily_limit (numeric(14,2)), requires_receipt (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 138. `public.expense_claims`
- **Layer / Module:** Layer 8: HR | Expense Management
- **Purpose:** Monthly expense bill statement submitted by MR/Employee for manager approval.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), claim_number (text), employee_id (uuid), submission_date (date), claim_period_start (date), claim_period_end (date), total_amount (numeric(14,2)), approved_amount (numeric(14,2)), status (text check: draft, submitted, approved, partially_approved, rejected, paid), approved_by_employee_id (uuid), approved_at (timestamptz), paid_at (timestamptz)`
- **Foreign Keys:** `tenant_id -> tenants(id), employee_id -> employees(id), approved_by_employee_id -> employees(id)`
- **Indexes & Constraints:** `unique(tenant_id, claim_number)`

#### 139. `public.expenses`
- **Layer / Module:** Layer 8: HR | Expense Management
- **Purpose:** Single owning table for daily individual expense vouchers submitted by MRs/Employees. Resolves duplicate expense tables.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), employee_id (uuid), expense_date (date), category_id (uuid), amount (numeric(14,2)), receipt_file_id (uuid), description (text), status (text check: pending, approved, rejected), claim_id (uuid)`
- **Foreign Keys:** `tenant_id -> tenants(id), employee_id -> employees(id), category_id -> expense_categories(id), receipt_file_id -> file_storage(id), claim_id -> expense_claims(id)`
- **Indexes & Constraints:** `idx_expenses_emp_date on (tenant_id, employee_id, expense_date desc)`

#### 140. `public.salary_structures`
- **Layer / Module:** Layer 8: HR | Payroll Management
- **Purpose:** Compensation templates (Executive, Sales Rep, Manager).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text), description (text)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 141. `public.salary_structure_components`
- **Layer / Module:** Layer 8: HR | Payroll Management
- **Purpose:** Salary heads (Basic, HRA, Medical Allowance, PF, ESIC, Professional Tax).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), salary_structure_id (uuid), component_name (text), component_type (text check: earning, deduction), calculation_type (text check: fixed, percentage_of_basic), amount_or_formula (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), salary_structure_id -> salary_structures(id)`
- **Indexes & Constraints:** `idx_sal_components on (tenant_id, salary_structure_id)`

#### 142. `public.employee_salaries`
- **Layer / Module:** Layer 8: HR | Payroll Management
- **Purpose:** Employee contracted CTC package.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), employee_id (uuid), salary_structure_id (uuid), ctc (numeric(14,2)), gross_salary (numeric(14,2)), net_salary (numeric(14,2)), effective_from (date)`
- **Foreign Keys:** `tenant_id -> tenants(id), employee_id -> employees(id), salary_structure_id -> salary_structures(id)`
- **Indexes & Constraints:** `idx_emp_salary on (tenant_id, employee_id, effective_from desc)`

#### 143. `public.payrolls`
- **Layer / Module:** Layer 8: HR | Payroll Management
- **Purpose:** Monthly corporate payroll execution batches.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), payroll_month (integer), payroll_year (integer), total_employees (integer), total_gross (numeric(14,2)), total_deductions (numeric(14,2)), total_net (numeric(14,2)), status (text check: draft, calculated, approved, paid), processed_by_user_id (uuid), processed_at (timestamptz)`
- **Foreign Keys:** `tenant_id -> tenants(id), processed_by_user_id -> app_users(id)`
- **Indexes & Constraints:** `unique(tenant_id, payroll_month, payroll_year)`

#### 144. `public.payslips`
- **Layer / Module:** Layer 8: HR | Payroll Management
- **Purpose:** Individual monthly employee payslips with statutory tax and deduction schedules.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), payroll_id (uuid), employee_id (uuid), gross_pay (numeric(14,2)), total_deductions (numeric(14,2)), net_pay (numeric(14,2)), basic (numeric(14,2)), hra (numeric(14,2)), allowances (numeric(14,2)), pf (numeric(14,2)), esic (numeric(14,2)), professional_tax (numeric(14,2)), tds (numeric(14,2)), payslip_pdf_file_id (uuid)`
- **Foreign Keys:** `tenant_id -> tenants(id), payroll_id -> payrolls(id), employee_id -> employees(id), payslip_pdf_file_id -> file_storage(id)`
- **Indexes & Constraints:** `unique(tenant_id, payroll_id, employee_id)`

#### 145. `public.hr_letters`
- **Layer / Module:** Layer 8: HR | HR Documentation
- **Purpose:** Offer letters, appointment letters, salary revision, and relieving letters.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), employee_id (uuid), letter_type (text check: appointment, appraisal, confirmation, relieving), title (text), issue_date (date), file_id (uuid), issued_by_user_id (uuid)`
- **Foreign Keys:** `tenant_id -> tenants(id), employee_id -> employees(id), file_id -> file_storage(id), issued_by_user_id -> app_users(id)`
- **Indexes & Constraints:** `idx_hr_letters_emp on (tenant_id, employee_id)`

#### 146. `public.company_policies`
- **Layer / Module:** Layer 8: HR | HR Compliance
- **Purpose:** Company conduct policies and employee manuals.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), title (text), category (text), effective_date (date), file_id (uuid), is_active (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id), file_id -> file_storage(id)`
- **Indexes & Constraints:** `idx_company_policies on (tenant_id, category)`

### Stage 09: Marketing, Campaigns, Schemes & Offers

#### 147. `public.campaigns`
- **Layer / Module:** Layer 9: Marketing | Brand Marketing
- **Purpose:** Product launch and seasonal therapeutic marketing campaigns.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text), description (text), start_date (date), end_date (date), budget (numeric(14,2)), status (text check: planned, active, completed, cancelled)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 148. `public.campaign_territories`
- **Layer / Module:** Layer 9: Marketing | Brand Marketing
- **Purpose:** Target territory geographical boundaries for campaigns.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), campaign_id (uuid), territory_id (uuid)`
- **Foreign Keys:** `tenant_id -> tenants(id), campaign_id -> campaigns(id), territory_id -> territories(id)`
- **Indexes & Constraints:** `unique(tenant_id, campaign_id, territory_id)`

#### 149. `public.campaign_products`
- **Layer / Module:** Layer 9: Marketing | Brand Marketing
- **Purpose:** Promoted brand SKUs in marketing campaign.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), campaign_id (uuid), product_id (uuid)`
- **Foreign Keys:** `tenant_id -> tenants(id), campaign_id -> campaigns(id), product_id -> products(id)`
- **Indexes & Constraints:** `unique(tenant_id, campaign_id, product_id)`

#### 150. `public.schemes`
- **Layer / Module:** Layer 9: Marketing | Trade Schemes
- **Purpose:** Single owning table for commercial trade schemes (e.g. 10+1 free, 5% cash discount). Resolves duplicate scheme tables.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), name (text), scheme_type (text check: product_bonus, quantity_discount, value_discount), start_date (date), end_date (date), is_active (boolean), description (text)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 151. `public.scheme_products`
- **Layer / Module:** Layer 9: Marketing | Trade Schemes
- **Purpose:** Product bonus ratios (Buy X units of Product A, get Y units of Product B free). Single owning table.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), scheme_id (uuid), buy_product_id (uuid), buy_quantity (integer), free_product_id (uuid), free_quantity (integer), discount_percentage (numeric(5,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), scheme_id -> schemes(id), buy_product_id -> products(id), free_product_id -> products(id)`
- **Indexes & Constraints:** `idx_scheme_products on (tenant_id, scheme_id)`

#### 152. `public.scheme_slabs`
- **Layer / Module:** Layer 9: Marketing | Trade Schemes
- **Purpose:** Turnover-based slab benefits.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), scheme_id (uuid), min_order_amount (numeric(14,2)), max_order_amount (numeric(14,2)), benefit_type (text check: discount_percent, cash_rebate), benefit_value (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), scheme_id -> schemes(id)`
- **Indexes & Constraints:** `idx_scheme_slabs on (tenant_id, scheme_id)`

#### 153. `public.offers`
- **Layer / Module:** Layer 9: Marketing | Trade Offers
- **Purpose:** Special trade discounts and festival concessions.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code (text), title (text), offer_type (text check: seasonal, clearance, introductory), discount_percent (numeric(5,2)), max_discount (numeric(14,2)), valid_from (timestamptz), valid_to (timestamptz), is_active (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code)`

#### 154. `public.coupons`
- **Layer / Module:** Layer 9: Marketing | Trade Offers
- **Purpose:** Promotional coupon codes for stockist and chemist orders.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), offer_id (uuid), coupon_code (text), max_uses (integer), used_count (integer), valid_from (timestamptz), valid_to (timestamptz), is_active (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id), offer_id -> offers(id)`
- **Indexes & Constraints:** `unique(tenant_id, coupon_code)`

#### 155. `public.coupon_redemptions`
- **Layer / Module:** Layer 9: Marketing | Trade Offers
- **Purpose:** Audit history of coupon redemptions.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), coupon_id (uuid), customer_type (text check: stockist, chemist), entity_id (uuid), order_id (uuid), redeemed_at (timestamptz), discount_amount (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), coupon_id -> coupons(id)`
- **Indexes & Constraints:** `idx_coupon_redemptions on (tenant_id, coupon_id)`

#### 156. `public.product_promotions`
- **Layer / Module:** Layer 9: Marketing | Brand Marketing
- **Purpose:** Special promotional pricing on featured medicines. Single owning table.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), campaign_id (uuid), product_id (uuid), promotion_type (text check: special_price, bundled), promotional_price (numeric(14,2)), start_date (date), end_date (date)`
- **Foreign Keys:** `tenant_id -> tenants(id), campaign_id -> campaigns(id), product_id -> products(id)`
- **Indexes & Constraints:** `idx_prod_promotions on (tenant_id, campaign_id, product_id)`

#### 157. `public.promotional_materials`
- **Layer / Module:** Layer 9: Marketing | Promotional Collateral
- **Purpose:** Physical leave-behinds, doctor literature, posters, and patient education booklets.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), campaign_id (uuid), material_name (text), material_type (text check: brochure, banner, booklet, digital_asset), file_id (uuid), unit_cost (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), campaign_id -> campaigns(id), file_id -> file_storage(id)`
- **Indexes & Constraints:** `idx_promo_materials on (tenant_id, campaign_id)`

#### 158. `public.promotional_material_distributions`
- **Layer / Module:** Layer 9: Marketing | Promotional Collateral
- **Purpose:** Tracking delivery of marketing collateral to doctor clinics and hospitals.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), promotional_material_id (uuid), mr_id (uuid), distributed_to_entity_type (text check: doctors, chemists, hospitals), entity_id (uuid), quantity (integer), distribution_date (date)`
- **Foreign Keys:** `tenant_id -> tenants(id), promotional_material_id -> promotional_materials(id), mr_id -> app_users(id)`
- **Indexes & Constraints:** `idx_promo_dist on (tenant_id, promotional_material_id, distribution_date)`

### Stage 10: Communication & Unified QR Codes

#### 159. `public.notifications`
- **Layer / Module:** Layer 10: Communication | In-App Notifications
- **Purpose:** Real-time in-app user notifications and action reminders.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), user_id (uuid), title (text), message (text), notification_type (text check: tour_plan_approved, target_achieved, visit_reminder, system_alert), entity_type (text), entity_id (uuid), is_read (boolean), read_at (timestamptz)`
- **Foreign Keys:** `tenant_id -> tenants(id), user_id -> app_users(id)`
- **Indexes & Constraints:** `idx_notifications_user on (tenant_id, user_id, is_read, created_at desc)`

#### 160. `public.email_templates`
- **Layer / Module:** Layer 10: Communication | Transactional Email
- **Purpose:** HTML templates for order confirmations, POB summaries, and invoices.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), template_code (text), subject (text), body_html (text), body_text (text)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, template_code)`

#### 161. `public.emails`
- **Layer / Module:** Layer 10: Communication | Transactional Email
- **Purpose:** Outbound email dispatch history and delivery status.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), to_email (text), subject (text), body (text), entity_type (text), entity_id (uuid), status (text check: queued, sent, failed), error_message (text), sent_at (timestamptz)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `idx_emails_status on (tenant_id, status, sent_at desc)`

#### 162. `public.sms_templates`
- **Layer / Module:** Layer 10: Communication | SMS Gateway
- **Purpose:** TRAI/DLT-registered transactional SMS templates.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), template_code (text), sender_id (text), template_text (text), dlt_template_id (text)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, template_code)`

#### 163. `public.sms`
- **Layer / Module:** Layer 10: Communication | SMS Gateway
- **Purpose:** Outbound SMS dispatch log.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), recipient_phone (text), message (text), dlt_template_id (text), entity_type (text), entity_id (uuid), status (text check: queued, sent, delivered, failed), gateway_response (text), sent_at (timestamptz)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `idx_sms_status on (tenant_id, status, sent_at desc)`

#### 164. `public.whatsapp_templates`
- **Layer / Module:** Layer 10: Communication | WhatsApp Cloud API
- **Purpose:** Meta-approved WhatsApp Cloud API templates for sending POB and invoice PDF links.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), template_name (text), category (text check: utility, marketing), language (text), header (text), body (text), footer (text), buttons (jsonb)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, template_name, language)`

#### 165. `public.whatsapp`
- **Layer / Module:** Layer 10: Communication | WhatsApp Cloud API
- **Purpose:** WhatsApp outbound messaging history.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), recipient_phone (text), template_id (uuid), payload (jsonb), entity_type (text), entity_id (uuid), status (text check: sent, delivered, read, failed), sent_at (timestamptz)`
- **Foreign Keys:** `tenant_id -> tenants(id), template_id -> whatsapp_templates(id)`
- **Indexes & Constraints:** `idx_whatsapp_status on (tenant_id, status, sent_at desc)`

#### 166. `public.push_notifications`
- **Layer / Module:** Layer 10: Communication | Mobile Push
- **Purpose:** Firebase Cloud Messaging FCM alerts delivered to MR Flutter mobile devices.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), user_id (uuid), title (text), body (text), device_token (text), data_payload (jsonb), status (text check: sent, failed), sent_at (timestamptz)`
- **Foreign Keys:** `tenant_id -> tenants(id), user_id -> app_users(id)`
- **Indexes & Constraints:** `idx_push_user on (tenant_id, user_id, sent_at desc)`

#### 167. `public.communication_logs`
- **Layer / Module:** Layer 10: Communication | Omnichannel Trail
- **Purpose:** Unified omnichannel communication trail.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), channel (text check: email, sms, whatsapp, push), direction (text check: outbound, inbound), recipient (text), status (text), payload (jsonb)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `idx_comm_logs on (tenant_id, channel, created_at desc)`

#### 168. `public.qr_codes`
- **Layer / Module:** Layer 10: QR Code | Unified QR Master
- **Purpose:** Single generic polymorphic QR Code master resolving ProductQRCode, ChemistQRCode, and DoctorQRCode duplicates.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), code_value (text unique), entity_type (text check: product, batch, doctor, chemist, equipment), entity_id (uuid), qr_type (text check: product_verification, master_id, promotional), is_active (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, code_value), idx_qr_codes_entity on (tenant_id, entity_type, entity_id)`

#### 169. `public.qr_code_scans`
- **Layer / Module:** Layer 10: QR Code | Unified QR Master
- **Purpose:** Real-time scan logs, anti-counterfeit checks, and geolocation tracking.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), qr_code_id (uuid), scanned_by_user_id (uuid), scan_time (timestamptz), latitude (double precision), longitude (double precision), device_info (jsonb)`
- **Foreign Keys:** `tenant_id -> tenants(id), qr_code_id -> qr_codes(id), scanned_by_user_id -> app_users(id)`
- **Indexes & Constraints:** `idx_qr_scans_code on (tenant_id, qr_code_id, scan_time desc)`

#### 170. `public.qr_code_histories`
- **Layer / Module:** Layer 10: QR Code | Unified QR Master
- **Purpose:** Lifecycle changes, deactivations, and reassignments of QR codes.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), qr_code_id (uuid), action (text check: generated, activated, deactivated, reassigned), changed_by_user_id (uuid), change_notes (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), qr_code_id -> qr_codes(id), changed_by_user_id -> app_users(id)`
- **Indexes & Constraints:** `idx_qr_histories on (tenant_id, qr_code_id)`

### Stage 11: Finance & Accounting Ledger

#### 171. `public.account_groups`
- **Layer / Module:** Finance | General Ledger Masters
- **Purpose:** Statutory accounting groups (Current Assets, Fixed Assets, Current Liabilities, Operating Revenue, Direct Expenses).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), group_code (text), group_name (text), category (text check: asset, liability, equity, income, expense)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, group_code)`

#### 172. `public.chart_of_accounts`
- **Layer / Module:** Finance | General Ledger Masters
- **Purpose:** Hierarchical Chart of Accounts ledger codes.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), account_code (text), account_name (text), account_type (text), account_group_id (uuid), parent_id (uuid), is_active (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id), account_group_id -> account_groups(id), parent_id -> chart_of_accounts(id)`
- **Indexes & Constraints:** `unique(tenant_id, account_code)`

#### 173. `public.tax_masters`
- **Layer / Module:** Finance | Tax Masters
- **Purpose:** Tax ledger configurations (Output CGST, Output SGST, Input Tax Credit, TDS 194C).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), tax_code (text), tax_name (text), rate (numeric(5,2)), tax_type (text check: gst, tds, tcs, cess)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, tax_code)`

#### 174. `public.tds_sections`
- **Layer / Module:** Finance | Tax Masters
- **Purpose:** Income Tax Tax-Deducted-at-Source TDS sections (194C, 194J, 194H, 194Q).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), section_code (text), description (text), rate_individual (numeric(5,2)), rate_corporate (numeric(5,2))`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, section_code)`

#### 175. `public.bank_accounts`
- **Layer / Module:** Finance | Banking Operations
- **Purpose:** Corporate bank accounts and cash management.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), bank_name (text), account_number (text), ifsc_code (text), branch_name (text), opening_balance (numeric(14,2)), current_balance (numeric(14,2)), is_active (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, account_number)`

#### 176. `public.bank_transactions`
- **Layer / Module:** Finance | Banking Operations
- **Purpose:** Bank deposits, withdrawals, and RTGS/NEFT transfers.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), bank_account_id (uuid), transaction_date (date), transaction_type (text check: deposit, withdrawal, transfer), reference_no (text), amount (numeric(14,2)), balance_after (numeric(14,2)), status (text check: cleared, pending, reconciled)`
- **Foreign Keys:** `tenant_id -> tenants(id), bank_account_id -> bank_accounts(id)`
- **Indexes & Constraints:** `idx_bank_tx on (tenant_id, bank_account_id, transaction_date desc)`

#### 177. `public.bank_reconciliations`
- **Layer / Module:** Finance | Banking Operations
- **Purpose:** Periodic bank reconciliation statement audits.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), bank_account_id (uuid), statement_date (date), statement_balance (numeric(14,2)), book_balance (numeric(14,2)), difference (numeric(14,2)), status (text check: balanced, discrepancy)`
- **Foreign Keys:** `tenant_id -> tenants(id), bank_account_id -> bank_accounts(id)`
- **Indexes & Constraints:** `idx_bank_recon on (tenant_id, bank_account_id, statement_date)`

#### 178. `public.journal_entries`
- **Layer / Module:** Finance | General Ledger Operations
- **Purpose:** Double-entry accounting journal vouchers.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), entry_number (text), entry_date (date), reference_type (text), reference_id (uuid), narration (text), status (text check: draft, posted, voided), posted_by_user_id (uuid), posted_at (timestamptz)`
- **Foreign Keys:** `tenant_id -> tenants(id), posted_by_user_id -> app_users(id)`
- **Indexes & Constraints:** `unique(tenant_id, entry_number)`

#### 179. `public.journal_entry_lines`
- **Layer / Module:** Finance | General Ledger Operations
- **Purpose:** Debit and credit lines balancing each journal voucher.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), journal_entry_id (uuid), account_id (uuid), debit_amount (numeric(14,2)), credit_amount (numeric(14,2)), narration (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), journal_entry_id -> journal_entries(id), account_id -> chart_of_accounts(id)`
- **Indexes & Constraints:** `idx_je_lines on (tenant_id, journal_entry_id)`

#### 180. `public.general_ledgers`
- **Layer / Module:** Finance | General Ledger Operations
- **Purpose:** Real-time posted general ledger transaction stream.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), account_id (uuid), transaction_date (date), journal_entry_id (uuid), debit (numeric(14,2)), credit (numeric(14,2)), balance (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), account_id -> chart_of_accounts(id), journal_entry_id -> journal_entries(id)`
- **Indexes & Constraints:** `idx_gl_account_date on (tenant_id, account_id, transaction_date desc)`

#### 181. `public.customer_ledgers`
- **Layer / Module:** Finance | Sub-Ledgers
- **Purpose:** Accounts Receivable sub-ledger per stockist and chemist.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), customer_type (text check: stockist, chemist), entity_id (uuid), transaction_date (date), reference_type (text), reference_id (uuid), debit (numeric(14,2)), credit (numeric(14,2)), running_balance (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `idx_cust_ledger on (tenant_id, customer_type, entity_id, transaction_date desc)`

#### 182. `public.supplier_ledgers`
- **Layer / Module:** Finance | Sub-Ledgers
- **Purpose:** Accounts Payable sub-ledger per material and drug supplier.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), supplier_id (uuid), transaction_date (date), reference_type (text), reference_id (uuid), debit (numeric(14,2)), credit (numeric(14,2)), running_balance (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), supplier_id -> suppliers(id)`
- **Indexes & Constraints:** `idx_supp_ledger on (tenant_id, supplier_id, transaction_date desc)`

#### 183. `public.tds_deductions`
- **Layer / Module:** Finance | Statutory Compliance
- **Purpose:** TDS withheld on supplier payments pending challan deposit.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), bill_id (uuid), supplier_id (uuid), section_id (uuid), base_amount (numeric(14,2)), tds_amount (numeric(14,2)), payment_status (text check: deducted, deposited)`
- **Foreign Keys:** `tenant_id -> tenants(id), bill_id -> purchase_bills(id), supplier_id -> suppliers(id), section_id -> tds_sections(id)`
- **Indexes & Constraints:** `idx_tds_deductions on (tenant_id, supplier_id, section_id)`

#### 184. `public.gst_returns`
- **Layer / Module:** Finance | Statutory Compliance
- **Purpose:** Monthly GSTR-1 outward and GSTR-3B tax return reconciliation batches.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), return_type (text check: gstr1, gstr3b, gstr9), return_period (text), filing_date (date), ack_number (text), status (text check: draft, filed)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, return_type, return_period)`

#### 185. `public.credit_notes`
- **Layer / Module:** Finance | Adjustments
- **Purpose:** Financial credit notes issued to customers for trade discounts or price differences.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), credit_note_number (text), invoice_id (uuid), customer_type (text check: stockist, chemist), entity_id (uuid), date (date), amount (numeric(14,2)), reason (text), status (text check: draft, approved, adjusted)`
- **Foreign Keys:** `tenant_id -> tenants(id), invoice_id -> primary_invoices(id)`
- **Indexes & Constraints:** `unique(tenant_id, credit_note_number)`

#### 186. `public.credit_note_items`
- **Layer / Module:** Finance | Adjustments
- **Purpose:** Product lines on credit notes.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), credit_note_id (uuid), product_id (uuid), quantity (bigint), rate (numeric(14,2)), tax_amount (numeric(14,2)), line_total (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), credit_note_id -> credit_notes(id), product_id -> products(id)`
- **Indexes & Constraints:** `idx_cn_items on (tenant_id, credit_note_id)`

#### 187. `public.debit_notes`
- **Layer / Module:** Finance | Adjustments
- **Purpose:** Financial debit notes raised against vendors for price corrections or returns.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), debit_note_number (text), bill_id (uuid), supplier_id (uuid), date (date), amount (numeric(14,2)), reason (text), status (text check: draft, approved, adjusted)`
- **Foreign Keys:** `tenant_id -> tenants(id), bill_id -> purchase_bills(id), supplier_id -> suppliers(id)`
- **Indexes & Constraints:** `unique(tenant_id, debit_note_number)`

#### 188. `public.debit_note_items`
- **Layer / Module:** Finance | Adjustments
- **Purpose:** Product lines on debit notes.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), debit_note_id (uuid), product_id (uuid), quantity (bigint), rate (numeric(14,2)), tax_amount (numeric(14,2)), line_total (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), debit_note_id -> debit_notes(id), product_id -> products(id)`
- **Indexes & Constraints:** `idx_dn_items on (tenant_id, debit_note_id)`

#### 189. `public.cheque_books`
- **Layer / Module:** Finance | Banking Operations
- **Purpose:** Registered physical cheque books.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), bank_account_id (uuid), cheque_book_number (text), start_cheque_no (text), end_cheque_no (text), is_active (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id), bank_account_id -> bank_accounts(id)`
- **Indexes & Constraints:** `unique(tenant_id, bank_account_id, cheque_book_number)`

#### 190. `public.cheque_leaves`
- **Layer / Module:** Finance | Banking Operations
- **Purpose:** Individual leaf issuance and clearance audit.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), cheque_book_id (uuid), cheque_number (text), status (text check: available, issued, cleared, bounced, cancelled), issued_to (text), issue_date (date), clearance_date (date)`
- **Foreign Keys:** `tenant_id -> tenants(id), cheque_book_id -> cheque_books(id)`
- **Indexes & Constraints:** `unique(tenant_id, cheque_book_id, cheque_number)`

### Stage 12: Analytics, Dashboards & External Integrations

#### 191. `public.dashboard_widgets`
- **Layer / Module:** Dashboard & Reports | BI & Analytics
- **Purpose:** Pre-built analytics chart definitions.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), widget_code (text), name (text), widget_type (text check: metric_card, bar_chart, pie_chart, table), default_config (jsonb)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, widget_code)`

#### 192. `public.user_dashboard_layouts`
- **Layer / Module:** Dashboard & Reports | BI & Analytics
- **Purpose:** Configured user dashboard positions.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), user_id (uuid), layout_config (jsonb), is_default (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id), user_id -> app_users(id)`
- **Indexes & Constraints:** `unique(tenant_id, user_id)`

#### 193. `public.custom_reports`
- **Layer / Module:** Dashboard & Reports | Reporting Engine
- **Purpose:** User-defined ad-hoc SQL / analytical report definitions.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), report_code (text), name (text), description (text), query_definition (text), parameters_schema (jsonb), created_by_user_id (uuid)`
- **Foreign Keys:** `tenant_id -> tenants(id), created_by_user_id -> app_users(id)`
- **Indexes & Constraints:** `unique(tenant_id, report_code)`

#### 194. `public.report_schedules`
- **Layer / Module:** Dashboard & Reports | Reporting Engine
- **Purpose:** Cron-scheduled automated dispatch of reports via email.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), report_id (uuid), schedule_cron (text), recipient_emails (text[]), format (text check: excel, pdf, csv), is_active (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id), report_id -> custom_reports(id)`
- **Indexes & Constraints:** `idx_report_schedules on (tenant_id, report_id)`

#### 195. `public.report_executions`
- **Layer / Module:** Dashboard & Reports | Reporting Engine
- **Purpose:** Execution history and exported artifact files.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), report_id (uuid), executed_by_user_id (uuid), executed_at (timestamptz), execution_time_ms (integer), status (text check: success, failed), result_file_id (uuid)`
- **Foreign Keys:** `tenant_id -> tenants(id), report_id -> custom_reports(id), executed_by_user_id -> app_users(id), result_file_id -> file_storage(id)`
- **Indexes & Constraints:** `idx_report_exec on (tenant_id, report_id, executed_at desc)`

#### 196. `public.kpi_metrics`
- **Layer / Module:** Dashboard & Reports | KPI Analytics
- **Purpose:** Key performance indicator definitions (DCR compliance rate, strike rate, secondary growth).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), kpi_code (text), name (text), category (text check: sales, field_force, financial, inventory), formula_description (text), target_value (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, kpi_code)`

#### 197. `public.kpi_snapshots`
- **Layer / Module:** Dashboard & Reports | KPI Analytics
- **Purpose:** Pre-computed historical KPI values for dashboard trends.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), kpi_id (uuid), snapshot_date (date), entity_type (text), entity_id (uuid), metric_value (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), kpi_id -> kpi_metrics(id)`
- **Indexes & Constraints:** `idx_kpi_snapshots on (tenant_id, kpi_id, snapshot_date desc)`

#### 198. `public.mr_performance_summaries`
- **Layer / Module:** Dashboard & Reports | Field SFA Analytics
- **Purpose:** Daily rollups of field MR productivity metrics.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), mr_id (uuid), summary_date (date), total_visits (integer), pob_value (numeric(14,2)), rcpa_count (integer), target_achievement_rate (numeric(5,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), mr_id -> app_users(id)`
- **Indexes & Constraints:** `unique(tenant_id, mr_id, summary_date)`

#### 199. `public.doctor_coverage_metrics`
- **Layer / Module:** Dashboard & Reports | Field SFA Analytics
- **Purpose:** Monthly territory doctor coverage and call average percentages.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), territory_id (uuid), month (integer), year (integer), total_doctors (integer), visited_doctors (integer), coverage_percentage (numeric(5,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), territory_id -> territories(id)`
- **Indexes & Constraints:** `unique(tenant_id, territory_id, month, year)`

#### 200. `public.secondary_sales_aggregates`
- **Layer / Module:** Dashboard & Reports | Sales Analytics
- **Purpose:** Pre-aggregated monthly brand sales by territory for fast heatmaps.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), territory_id (uuid), product_id (uuid), month (integer), year (integer), total_quantity (bigint), total_value (numeric(14,2))`
- **Foreign Keys:** `tenant_id -> tenants(id), territory_id -> territories(id), product_id -> products(id)`
- **Indexes & Constraints:** `unique(tenant_id, territory_id, product_id, month, year)`

#### 201. `public.api_keys`
- **Layer / Module:** API & Integration | API Gateway
- **Purpose:** Third-party machine-to-machine API credentials (WMS, ERP, mobile sync).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), key_name (text), key_prefix (text), hashed_key (text), scopes (text[]), expires_at (timestamptz), is_revoked (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, key_prefix)`

#### 202. `public.api_request_logs`
- **Layer / Module:** API & Integration | API Gateway
- **Purpose:** Telemetry and rate limiting logs for external API calls.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), api_key_id (uuid), endpoint (text), method (text), status_code (integer), ip_address (text), response_time_ms (integer), created_at (timestamptz)`
- **Foreign Keys:** `tenant_id -> tenants(id), api_key_id -> api_keys(id)`
- **Indexes & Constraints:** `idx_api_logs on (tenant_id, api_key_id, created_at desc)`

#### 203. `public.webhook_endpoints`
- **Layer / Module:** API & Integration | Webhooks
- **Purpose:** External HTTPS callback subscriptions for real-time events.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), target_url (text), secret (text), events (text[]), is_active (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `idx_webhooks_active on (tenant_id, is_active)`

#### 204. `public.webhook_deliveries`
- **Layer / Module:** API & Integration | Webhooks
- **Purpose:** Webhook dispatch delivery attempts, status codes, and retry counts.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), webhook_endpoint_id (uuid), event_type (text), payload (jsonb), status_code (integer), attempt_count (integer), response_body (text), delivered_at (timestamptz)`
- **Foreign Keys:** `tenant_id -> tenants(id), webhook_endpoint_id -> webhook_endpoints(id)`
- **Indexes & Constraints:** `idx_webhook_deliveries on (tenant_id, webhook_endpoint_id, delivered_at desc)`

#### 205. `public.external_system_integrations`
- **Layer / Module:** API & Integration | Enterprise ERP Connectors
- **Purpose:** Pre-configured connectors to SAP, Tally, Marg ERP, Busy, and Oracle.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), system_name (text), system_type (text check: sap, tally, marg, custom_rest), auth_type (text check: oauth2, api_key, basic), connection_config (jsonb), is_active (boolean)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, system_name)`

#### 206. `public.integration_sync_jobs`
- **Layer / Module:** API & Integration | Enterprise ERP Connectors
- **Purpose:** Data sync batches (e.g. Inward primary invoices from SAP).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), integration_id (uuid), sync_entity (text), sync_direction (text check: inbound, outbound), status (text check: running, success, failed), started_at (timestamptz), completed_at (timestamptz), records_processed (integer), error_log (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), integration_id -> external_system_integrations(id)`
- **Indexes & Constraints:** `idx_sync_jobs on (tenant_id, integration_id, started_at desc)`

#### 207. `public.integration_mappings`
- **Layer / Module:** API & Integration | Enterprise ERP Connectors
- **Purpose:** Field translation dictionaries between external ERP codes and internal UUIDs.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), integration_id (uuid), entity_name (text), local_field (text), external_field (text), transformation_rule (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), integration_id -> external_system_integrations(id)`
- **Indexes & Constraints:** `idx_int_mappings on (tenant_id, integration_id, entity_name)`

#### 208. `public.integration_event_queues`
- **Layer / Module:** API & Integration | Enterprise ERP Connectors
- **Purpose:** Guaranteed delivery outbound event queue for third-party ERP integration.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), integration_id (uuid), event_name (text), payload (jsonb), status (text check: pending, processed, failed), retry_count (integer), error_message (text)`
- **Foreign Keys:** `tenant_id -> tenants(id), integration_id -> external_system_integrations(id)`
- **Indexes & Constraints:** `idx_event_queue on (tenant_id, integration_id, status)`

#### 209. `public.export_jobs`
- **Layer / Module:** API & Integration | Data Portability
- **Purpose:** Asynchronous Excel/CSV data export worker jobs.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), user_id (uuid), export_type (text), format (text check: excel, csv), status (text check: pending, completed, failed), file_id (uuid), error_message (text), completed_at (timestamptz)`
- **Foreign Keys:** `tenant_id -> tenants(id), user_id -> app_users(id), file_id -> file_storage(id)`
- **Indexes & Constraints:** `idx_export_jobs on (tenant_id, user_id, created_at desc)`

#### 210. `public.import_jobs`
- **Layer / Module:** API & Integration | Data Portability
- **Purpose:** Bulk master onboarding jobs (Doctor list, Chemist master, Stockist Excel uploads).
- **Key Columns:** `id (uuid pk), tenant_id (uuid), user_id (uuid), import_type (text), file_id (uuid), status (text check: validating, processing, completed, failed), total_rows (integer), success_rows (integer), failed_rows (integer), error_log (jsonb)`
- **Foreign Keys:** `tenant_id -> tenants(id), user_id -> app_users(id), file_id -> file_storage(id)`
- **Indexes & Constraints:** `idx_import_jobs on (tenant_id, user_id, created_at desc)`

#### 211. `public.data_sync_checkpoints`
- **Layer / Module:** API & Integration | Mobile Offline Sync
- **Purpose:** Mobile delta sync watermarks tracking device synchronization state.
- **Key Columns:** `id (uuid pk), tenant_id (uuid), entity_name (text), device_id (text), last_synced_at (timestamptz), last_version (bigint)`
- **Foreign Keys:** `tenant_id -> tenants(id)`
- **Indexes & Constraints:** `unique(tenant_id, entity_name, device_id)`

#### 212. `public.mobile_app_versions`
- **Layer / Module:** API & Integration | Mobile Platform
- **Purpose:** Global minimum and recommended Flutter mobile app version matrix. Global platform table.
- **Key Columns:** `id (uuid pk), platform (text check: android, ios), min_version (text), latest_version (text), force_update (boolean), release_notes (text), release_date (date)`
- **Foreign Keys:** `None (Global platform table allowlisted from tenant_id)`
- **Indexes & Constraints:** `unique(platform)`

---

## 5. Architectural Open Questions

As instructed, the following open questions and architectural design considerations are listed here for your review and direction:

1. **Field Visits: Unified `field_visits` vs Split `doctor_visits` and `chemist_visits`**
   - *Current Design in Inventory:* Unified `public.field_visits` with `visit_type in ('doctor', 'chemist', 'stockist', 'hospital')` and `(entity_type, entity_id)` polymorphic links. This allows a single check-in/out engine, geotagging, selfie verification, and joint work logic for all field touchpoints.
   - *Alternative:* Separate tables `doctor_visits` and `chemist_visits`. We recommend the unified `field_visits` table because MRs perform composite beat visits (often visiting a doctor and adjacent chemist in one go), and daily call reports aggregate all call types uniformly.

2. **Platform Masters: Multi-Tenant vs Shared System Catalog**
   - For standard reference masters like `doctor_specialities`, `doctor_qualifications`, and `dosage_forms`, should tenants be able to add custom values (requiring `tenant_id` on each record), or should they be global platform seeded catalogs? Currently, they are modeled as tenant-scoped tables with system defaults seeded during tenant onboarding.

3. **Secondary Sales Data Ingestion Format**
   - In the Indian pharmaceutical industry, secondary sales (stockist sales to retail chemists) are reported monthly via EDI, Excel statements, or third-party platforms (e.g. Pharmarack, AWACS). `public.secondary_sales` supports both manual statement entry and automated batch sync via `import_jobs`.

4. **Activity Feed vs Transactional Audit**
   - The foundation migration includes `public.activities` (business timeline feed for mobile MRs) and `public.audit_logs` (security change capture). We propose maintaining this split: `activities` is high-level, business-oriented, and offline-synced to mobile; `audit_logs` is low-level, capturing JSON diffs of SQL mutations for compliance.

5. **Storage of Medical Prescriptions (Doctor Rx Potential)**
   - For doctor prescription monitoring, `doctor_brand_prescriptions` captures estimated monthly units per brand. Does the platform require storing actual patient prescription images (which incurs HIPAA / DISHA medical data privacy compliance), or purely the aggregated prescriber volume audit? Current schema restricts this to prescriber volume audits to avoid sensitive patient health information (PHI).

