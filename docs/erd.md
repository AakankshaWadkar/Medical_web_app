# PharmaSphere Entity-Relationship Diagrams (ERD)

This document provides comprehensive Entity-Relationship Diagrams for **PharmaSphere**, a multi-tenant pharmaceutical Sales Force Automation (SFA), Customer Relationship Management (CRM), and Enterprise Resource Planning (ERP) platform.

All tenant-scoped tables implement strict **Row-Level Security (RLS)** forced at the database engine level via `call public.apply_tenant_rls('public.<table>')` and contain mandatory audit columns (`created_at`, `updated_at`, `deleted_at`, `version`).

---

## Table of Contents
1. [Layer 1: Core Platform & Foundation](#layer-1-core-platform--foundation)
2. [Layer 2: Geography, Master Data & Sales Hierarchy](#layer-2-geography-master-data--sales-hierarchy)
3. [Layer 3: Product Catalog & Medicine Master](#layer-3-product-catalog--medicine-master)
4. [Layer 4: Warehouses, Batches & Inventory Ledger](#layer-4-warehouses-batches--inventory-ledger)
5. [Layer 5: Procurement & Suppliers (Proposed)](#layer-5-procurement--suppliers-proposed)
6. [Layer 6: Sales & Distribution (Primary Sales & Collections)](#layer-6-sales--distribution-primary-sales--collections)
7. [Layer 7: CRM & Field SFA Operations (Visits, POB, RCPA, DCR)](#layer-7-crm--field-sfa-operations-visits-pob-rcpa-dcr)
8. [Layer 8: HR, Attendance, Leave, Expense & Payroll](#layer-8-hr-attendance-leave-expense--payroll)
9. [Layer 9: Marketing, Campaigns, Schemes & Offers](#layer-9-marketing-campaigns-schemes--offers)
10. [Layer 10: Communication, Unified QR Codes, Finance & Integration](#layer-10-communication-unified-qr-codes-finance--integration)

---

## Layer 1: Core Platform & Foundation

Layer 1 establishes company multi-tenancy, user identity (`app_users` mapped to Supabase `auth.users`), role-based access control (RBAC), multi-branch organizational units, subscription tiering, and central audit/file tracking.

```mermaid
erDiagram
    SUBSCRIPTION_PLANS ||--o{ COMPANY_SUBSCRIPTIONS : "provisions"
    TENANTS ||--o{ COMPANY_SUBSCRIPTIONS : "subscribes"
    TENANTS ||--o{ BRANCHES : "operates"
    TENANTS ||--o{ DEPARTMENTS : "contains"
    BRANCHES ||--o{ DEPARTMENTS : "houses"
    TENANTS ||--o{ APP_USERS : "employs"
    APP_USERS ||--o{ APP_USERS : "manages"
    BRANCHES ||--o{ APP_USERS : "assigns"
    DEPARTMENTS ||--o{ APP_USERS : "assigns"
    TENANTS ||--o{ ROLES : "defines"
    ROLES ||--o{ USER_ROLES : "grants"
    APP_USERS ||--o{ USER_ROLES : "possesses"
    ROLES ||--o{ ROLE_PERMISSIONS : "binds"
    PERMISSIONS ||--o{ ROLE_PERMISSIONS : "applies"
    TENANTS ||--o{ TENANT_SETTINGS : "configures"
    APP_USERS ||--o{ USER_NOTIFICATION_PREFERENCES : "customizes"
    TENANTS ||--o{ FILE_STORAGE : "stores"
    TENANTS ||--o{ AUDIT_LOGS : "records"
    APP_USERS ||--o{ LOGIN_HISTORIES : "tracks"
    APP_USERS ||--o{ USER_SESSIONS : "authenticates"
    APP_USERS ||--o{ ACTIVITIES : "emits"

    TENANTS {
        uuid id PK
        text name
        text slug
        text company_code
        text legal_name
        text gst_no
        text drug_license_no
        text currency
    }

    SUBSCRIPTION_PLANS {
        uuid id PK
        text code UK
        text name
        integer max_users
        numeric price
        text billing_cycle
    }

    COMPANY_SUBSCRIPTIONS {
        uuid id PK
        uuid tenant_id FK
        uuid plan_id FK
        timestamptz start_date
        timestamptz end_date
        text status
    }

    APP_USERS {
        uuid id PK
        uuid tenant_id FK
        uuid auth_user_id UK
        text app_role
        text full_name
        text phone
        uuid manager_id FK
        uuid branch_id FK
        uuid department_id FK
        text status
    }

    BRANCHES {
        uuid id PK
        uuid tenant_id FK
        text code
        text name
        boolean is_head_office
        text city
        text state
    }

    DEPARTMENTS {
        uuid id PK
        uuid tenant_id FK
        uuid branch_id FK
        text code
        text name
    }
```

---

## Layer 2: Geography, Master Data & Sales Hierarchy

Layer 2 defines normalized geographical masters (Country, State, City, Pin Code) and models the hierarchical commercial sales hierarchy (Business Division $\to$ Region $\to$ Area $\to$ Territory $\to$ Beat $\to$ Route) down to polymorphic addresses and contacts.

```mermaid
erDiagram
    COUNTRIES ||--o{ STATES : "contains"
    STATES ||--o{ CITIES : "contains"
    CITIES ||--o{ PIN_CODES : "indexes"
    STATES ||--o{ PIN_CODES : "contains"

    TENANTS ||--o{ BUSINESS_DIVISIONS : "operates"
    TENANTS ||--o{ REGIONS : "divides"
    REGIONS ||--o{ AREAS : "subdivides"
    AREAS ||--o{ TERRITORIES : "assigns"
    TERRITORIES ||--o{ BEATS : "schedules"
    BEATS ||--o{ ROUTES : "navigates"

    TENANTS ||--o{ ADDRESSES : "geocodes"
    TENANTS ||--o{ CONTACTS : "reaches"
    TENANTS ||--o{ SALES_CHANNELS : "routes"
    TENANTS ||--o{ FISCAL_YEARS : "tracks"
    FISCAL_YEARS ||--o{ FINANCIAL_PERIODS : "segments"

    BUSINESS_DIVISIONS {
        uuid id PK
        uuid tenant_id FK
        text code
        text name
    }

    REGIONS {
        uuid id PK
        uuid tenant_id FK
        text code
        text name
    }

    AREAS {
        uuid id PK
        uuid tenant_id FK
        uuid region_id FK
        text code
        text name
    }

    TERRITORIES {
        uuid id PK
        uuid tenant_id FK
        uuid area_id FK
        text code
        text name
    }

    BEATS {
        uuid id PK
        uuid tenant_id FK
        uuid territory_id FK
        text code
        text name
    }

    ROUTES {
        uuid id PK
        uuid tenant_id FK
        uuid beat_id FK
        text code
        text name
    }
```

---

## Layer 3: Product Catalog & Medicine Master

Layer 3 encapsulates pharmaceutical formulations, therapeutic classifications, generic composition ratios, packaging specifications, scheduled drug compliance, price lists (MRP, PTR, PTS), and regulatory drug licenses.

```mermaid
erDiagram
    TENANTS ||--o{ CATEGORIES : "classifies"
    CATEGORIES ||--o{ SUB_CATEGORIES : "narrows"
    TENANTS ||--o{ BRANDS : "markets"
    TENANTS ||--o{ GENERIC_MEDICINES : "formulates"
    TENANTS ||--o{ DOSAGE_FORMS : "mfg_form"
    TENANTS ||--o{ THERAPEUTIC_CLASSES : "categorizes"
    TENANTS ||--o{ UNITS_OF_MEASURE : "measures"
    TENANTS ||--o{ HSN_CODES : "taxes"

    TENANTS ||--o{ PRODUCTS : "catalogs"
    BUSINESS_DIVISIONS ||--o{ PRODUCTS : "promotes"
    CATEGORIES ||--o{ PRODUCTS : "contains"
    BRANDS ||--o{ PRODUCTS : "brands"
    UNITS_OF_MEASURE ||--o{ PRODUCTS : "packages"

    PRODUCTS ||--o{ COMPOSITIONS : "blends"
    GENERIC_MEDICINES ||--o{ COMPOSITIONS : "active_ingredient"
    PRODUCTS ||--o{ PRODUCT_PACKAGES : "packs"
    PRODUCTS ||--o{ PRODUCT_PRICES : "prices"
    PRICE_LISTS ||--o{ PRODUCT_PRICES : "schedules"
    PRODUCTS ||--o{ PRODUCT_IMAGES : "visualizes"
    PRODUCTS ||--o{ PRODUCT_DOCUMENTS : "complies"

    PRODUCTS {
        uuid id PK
        uuid tenant_id FK
        uuid division_id FK
        uuid category_id FK
        uuid brand_id FK
        uuid uom_id FK
        text product_code UK
        text name
        text generic_name
        numeric mrp
        numeric ptr
        numeric pts
        boolean is_active
        boolean is_prescription_required
    }

    COMPOSITIONS {
        uuid id PK
        uuid tenant_id FK
        uuid product_id FK
        uuid generic_id FK
        numeric strength_value
        text strength_unit
    }

    PRICE_LISTS {
        uuid id PK
        uuid tenant_id FK
        text code UK
        text name
        date effective_from
    }
```

---

## Layer 4: Warehouses, Batches & Inventory Ledger

Layer 4 governs C&F depots, central warehouses, manufacturing drug batch tracking (expiry, manufacturing, quarantine), real-time stock balances, stock transaction ledgers, inter-warehouse transfers, stock adjustments, gift merchandise inventory, and MR promotional sample allocations.

```mermaid
erDiagram
    TENANTS ||--o{ WAREHOUSES : "operates"
    WAREHOUSES ||--o{ WAREHOUSE_LOCATIONS : "partitions"
    PRODUCTS ||--o{ PRODUCT_BATCHES : "produces"
    
    WAREHOUSES ||--o{ INVENTORY_STOCKS : "stores"
    PRODUCTS ||--o{ INVENTORY_STOCKS : "quantifies"
    PRODUCT_BATCHES ||--o{ INVENTORY_STOCKS : "differentiates"

    INVENTORY_STOCKS ||--o{ STOCK_TRANSACTIONS : "mutates"
    WAREHOUSES ||--o{ STOCK_TRANSFERS : "dispatches_from"
    WAREHOUSES ||--o{ STOCK_TRANSFERS : "receives_at"
    STOCK_TRANSFERS ||--o{ STOCK_TRANSFER_ITEMS : "details"

    TENANTS ||--o{ GIFT_ITEMS : "procures"
    GIFT_ITEMS ||--o{ GIFT_INVENTORIES : "stocks"
    GIFT_ITEMS ||--o{ GIFT_STOCK_TRANSACTIONS : "journals"
    APP_USERS ||--o{ SAMPLE_ALLOCATIONS : "allocates_to"
    APP_USERS ||--o{ GIFT_ALLOCATIONS : "allocates_to"

    WAREHOUSES {
        uuid id PK
        uuid tenant_id FK
        text code UK
        text name
        text warehouse_type
        text address
        boolean is_active
    }

    PRODUCT_BATCHES {
        uuid id PK
        uuid tenant_id FK
        uuid product_id FK
        text batch_number
        date manufacturing_date
        date expiry_date
        numeric mrp
        numeric ptr
        numeric cost_price
        boolean is_quarantined
    }

    INVENTORY_STOCKS {
        uuid id PK
        uuid tenant_id FK
        uuid warehouse_id FK
        uuid product_id FK
        uuid batch_id FK
        bigint quantity_on_hand
        bigint quantity_allocated
        bigint quantity_available
    }

    GIFT_ITEMS {
        uuid id PK
        uuid tenant_id FK
        text code UK
        text name
        numeric unit_cost
    }
```

---

## Layer 5: Procurement & Suppliers (Proposed)

Layer 5 manages active pharmaceutical ingredient (API) and packaging material suppliers, purchase requisitions, supplier purchase orders (PO), goods receipt notes (GRN), quality inspection, purchase bills, and vendor debit returns.

```mermaid
erDiagram
    TENANTS ||--o{ SUPPLIER_CATEGORIES : "classifies"
    SUPPLIER_CATEGORIES ||--o{ SUPPLIERS : "contains"
    TENANTS ||--o{ SUPPLIERS : "onboards"

    SUPPLIERS ||--o{ PURCHASE_REQUISITIONS : "targets"
    PURCHASE_REQUISITIONS ||--o{ PURCHASE_REQUISITION_ITEMS : "items"
    PRODUCTS ||--o{ PURCHASE_REQUISITION_ITEMS : "orders"

    SUPPLIERS ||--o{ PURCHASE_ORDERS : "issues_to"
    PURCHASE_REQUISITIONS ||--o{ PURCHASE_ORDERS : "converts_to"
    PURCHASE_ORDERS ||--o{ PURCHASE_ORDER_ITEMS : "specifies"

    PURCHASE_ORDERS ||--o{ GOODS_RECEIPT_NOTES : "fulfills"
    WAREHOUSES ||--o{ GOODS_RECEIPT_NOTES : "delivers_to"
    GOODS_RECEIPT_NOTES ||--o{ GOODS_RECEIPT_ITEMS : "verifies"

    GOODS_RECEIPT_NOTES ||--o{ PURCHASE_BILLS : "bills"
    PURCHASE_BILLS ||--o{ PURCHASE_BILL_ITEMS : "itemizes"
    PURCHASE_BILLS ||--o{ PURCHASE_RETURNS : "debits"
    PURCHASE_RETURNS ||--o{ PURCHASE_RETURN_ITEMS : "returns"

    SUPPLIERS {
        uuid id PK
        uuid tenant_id FK
        text supplier_code UK
        text name
        text gst_no
        text contact_person
        numeric credit_limit
    }

    PURCHASE_ORDERS {
        uuid id PK
        uuid tenant_id FK
        text po_number UK
        uuid supplier_id FK
        date order_date
        numeric total_amount
        text status
    }

    GOODS_RECEIPT_NOTES {
        uuid id PK
        uuid tenant_id FK
        text grn_number UK
        uuid po_id FK
        uuid warehouse_id FK
        date receipt_date
        text status
    }
```

---

## Layer 6: Sales & Distribution (Primary Sales & Collections)

Layer 6 covers stockists and distributors, customer credit limits, distributor primary purchase orders, delivery challans, GST commercial tax invoices, sales returns, and field money collections.

```mermaid
erDiagram
    TENANTS ||--o{ CUSTOMER_CATEGORIES : "segments"
    CUSTOMER_CATEGORIES ||--o{ STOCKISTS : "categorizes"
    TERRITORIES ||--o{ STOCKISTS : "covers"
    
    STOCKISTS ||--o{ PRIMARY_ORDERS : "places"
    PRIMARY_ORDERS ||--o{ PRIMARY_ORDER_ITEMS : "contains"
    PRODUCTS ||--o{ PRIMARY_ORDER_ITEMS : "bills"

    PRIMARY_ORDERS ||--o{ DELIVERY_CHALLANS : "ships"
    PRIMARY_ORDERS ||--o{ PRIMARY_INVOICES : "invoices"
    PRIMARY_INVOICES ||--o{ PRIMARY_INVOICE_ITEMS : "lines"

    STOCKISTS ||--o{ SALES_RETURNS : "returns"
    SALES_RETURNS ||--o{ SALES_RETURN_ITEMS : "lines"

    STOCKISTS ||--o{ CUSTOMER_PAYMENTS : "pays"
    PRIMARY_INVOICES ||--o{ PAYMENT_ALLOCATIONS : "clears"
    CUSTOMER_PAYMENTS ||--o{ PAYMENT_ALLOCATIONS : "settles"

    APP_USERS ||--o{ COLLECTIONS : "collects"
    STOCKISTS ||--o{ COLLECTIONS : "pays_mr"
    STOCKISTS ||--o{ CREDIT_LIMITS : "controls"

    STOCKISTS {
        uuid id PK
        uuid tenant_id FK
        uuid territory_id FK
        text stockist_code UK
        text name
        text stockist_type
        numeric credit_limit
        text status
    }

    PRIMARY_ORDERS {
        uuid id PK
        uuid tenant_id FK
        uuid stockist_id FK
        text order_number UK
        date order_date
        numeric total_amount
        text status
    }

    PRIMARY_INVOICES {
        uuid id PK
        uuid tenant_id FK
        uuid order_id FK
        uuid stockist_id FK
        text invoice_number UK
        date invoice_date
        numeric total_amount
        numeric paid_amount
        text payment_status
    }

    COLLECTIONS {
        uuid id PK
        uuid tenant_id FK
        uuid mr_id FK
        uuid stockist_id FK
        date collection_date
        numeric amount
        text payment_mode
        text status
    }
```

---

## Layer 7: CRM & Field SFA Operations (Visits, POB, RCPA, DCR)

Layer 7 is the core operational field slice for Medical Representatives (MRs). It models Doctors, Retail Chemists, consulting Hospitals, Monthly Tour Plans (MTP), Geotagged Field Visits with Selfie Verification, Pre-Order Bookings (POBs), E-Detailing slide presentations, Sample/Gift handovers, Retail Chemist Prescription Audits (RCPA), Daily Call Reports (DCR), and Target Achievements.

```mermaid
erDiagram
    DOCTOR_SPECIALITIES ||--o{ DOCTORS : "specializes"
    DOCTOR_CATEGORIES ||--o{ DOCTORS : "classifies"
    DOCTOR_QUALIFICATIONS ||--o{ DOCTORS : "graduates"
    HOSPITALS ||--o{ DOCTORS : "consults_at"
    TERRITORIES ||--o{ DOCTORS : "located_in"

    CHEMIST_CATEGORIES ||--o{ CHEMISTS : "classifies"
    TERRITORIES ||--o{ CHEMISTS : "located_in"
    CHEMISTS ||--o{ CHEMIST_STOCKISTS : "purchases_via"
    STOCKISTS ||--o{ CHEMIST_STOCKISTS : "supplies"

    APP_USERS ||--o{ TOUR_PLANS : "submits"
    TOUR_PLANS ||--o{ TOUR_PLAN_DAYS : "schedules"
    BEATS ||--o{ TOUR_PLAN_DAYS : "assigns"

    APP_USERS ||--o{ FIELD_VISITS : "executes"
    TOUR_PLAN_DAYS ||--o{ FIELD_VISITS : "corresponds"
    FIELD_VISITS ||--o{ VISIT_SELFIES : "geotags"
    FIELD_VISITS ||--o{ JOINT_WORKS : "accompanies"
    FIELD_VISITS ||--o{ DOCTOR_FEEDBACKS : "captures"
    FIELD_VISITS ||--o{ CHEMIST_FEEDBACKS : "captures"

    FIELD_VISITS ||--o{ POBS : "books_during"
    APP_USERS ||--o{ POBS : "generates"
    POBS ||--o{ POB_PRODUCTS : "lines"
    PRODUCTS ||--o{ POB_PRODUCTS : "orders"

    FIELD_VISITS ||--o{ E_DETAILINGS : "presents"
    E_DETAILINGS ||--o{ E_DETAILING_SLIDES : "audits"
    PRODUCTS ||--o{ E_DETAILING_SLIDES : "showcases"

    FIELD_VISITS ||--o{ DOCTOR_GIFT_DISTRIBUTIONS : "gives"
    GIFT_ITEMS ||--o{ DOCTOR_GIFT_DISTRIBUTIONS : "gifts"
    FIELD_VISITS ||--o{ DOCTOR_SAMPLE_DISTRIBUTIONS : "samples"
    PRODUCTS ||--o{ DOCTOR_SAMPLE_DISTRIBUTIONS : "samples"

    FIELD_VISITS ||--o{ RCPA_AUDITS : "conducts"
    CHEMISTS ||--o{ RCPA_AUDITS : "audits_at"
    DOCTORS ||--o{ RCPA_AUDITS : "monitors_rx"
    RCPA_AUDITS ||--o{ RCPA_AUDIT_ITEMS : "compares"

    APP_USERS ||--o{ DAILY_CALL_REPORTS : "submits_eod"
    APP_USERS ||--o{ SALES_TARGETS : "assigned_quota"
    SALES_TARGETS ||--o{ SALES_ACHIEVEMENTS : "tracks_pct"

    DOCTORS {
        uuid id PK
        uuid tenant_id FK
        text doctor_code UK
        text name
        uuid speciality_id FK
        uuid category_id FK
        uuid territory_id FK
        integer visit_frequency
        text status
    }

    CHEMISTS {
        uuid id PK
        uuid tenant_id FK
        text chemist_code UK
        text name
        uuid territory_id FK
        text contact_person
        text mobile
        text status
    }

    FIELD_VISITS {
        uuid id PK
        uuid tenant_id FK
        uuid mr_id FK
        text visit_type
        text entity_type
        uuid entity_id
        date visit_date
        timestamptz check_in_time
        timestamptz check_out_time
        double_precision check_in_latitude
        double_precision check_in_longitude
        text visit_status
    }

    POBS {
        uuid id PK
        uuid tenant_id FK
        uuid visit_id FK
        uuid mr_id FK
        text customer_type
        uuid entity_id
        uuid stockist_id FK
        date pob_date
        numeric total_amount
        text status
    }

    DAILY_CALL_REPORTS {
        uuid id PK
        uuid tenant_id FK
        uuid mr_id FK
        date report_date
        integer total_calls
        integer doctor_calls
        integer chemist_calls
        numeric total_pob_value
        text status
    }
```

---

## Layer 8: HR, Attendance, Leave, Expense & Payroll

Layer 8 provides employee personnel management, biometric and mobile GPS punch attendance, annual statutory leave allowances, field Daily Allowance / Travel Allowance (DA/TA) expense vouchers and claims, salary compensation structures, monthly payroll runs, and generated employee payslips.

```mermaid
erDiagram
    TENANTS ||--o{ SHIFTS : "defines"
    APP_USERS ||--o{ EMPLOYEES : "profiles"
    BRANCHES ||--o{ EMPLOYEES : "posts"
    DEPARTMENTS ||--o{ EMPLOYEES : "assigns"

    EMPLOYEES ||--o{ EMPLOYEE_SHIFTS : "schedules"
    SHIFTS ||--o{ EMPLOYEE_SHIFTS : "applies"

    EMPLOYEES ||--o{ ATTENDANCE : "punches"
    ATTENDANCE ||--o{ ATTENDANCE_LOGS : "telemetry"

    TENANTS ||--o{ LEAVE_TYPES : "governs"
    EMPLOYEES ||--o{ LEAVE_BALANCES : "accrues"
    LEAVE_TYPES ||--o{ LEAVE_BALANCES : "tracks"
    EMPLOYEES ||--o{ LEAVES : "applies_for"
    LEAVE_TYPES ||--o{ LEAVES : "type_of"

    TENANTS ||--o{ EXPENSE_CATEGORIES : "slabs"
    EMPLOYEES ||--o{ EXPENSE_CLAIMS : "submits"
    EXPENSE_CLAIMS ||--o{ EXPENSES : "groups"
    EMPLOYEES ||--o{ EXPENSES : "spends"
    EXPENSE_CATEGORIES ||--o{ EXPENSES : "categorizes"

    TENANTS ||--o{ SALARY_STRUCTURES : "designs"
    SALARY_STRUCTURES ||--o{ SALARY_STRUCTURE_COMPONENTS : "breaks_down"
    EMPLOYEES ||--o{ EMPLOYEE_SALARIES : "contracts"
    SALARY_STRUCTURES ||--o{ EMPLOYEE_SALARIES : "structures"

    TENANTS ||--o{ PAYROLLS : "executes"
    PAYROLLS ||--o{ PAYSLIPS : "generates"
    EMPLOYEES ||--o{ PAYSLIPS : "receives"

    EMPLOYEES {
        uuid id PK
        uuid tenant_id FK
        uuid user_id UK
        text employee_code UK
        text first_name
        text last_name
        text designation
        text bank_account_no
        text pan_no
        text status
    }

    ATTENDANCE {
        uuid id PK
        uuid tenant_id FK
        uuid employee_id FK
        date attendance_date
        timestamptz check_in_time
        timestamptz check_out_time
        double_precision check_in_latitude
        double_precision check_in_longitude
        text status
        numeric work_hours
    }

    EXPENSES {
        uuid id PK
        uuid tenant_id FK
        uuid employee_id FK
        uuid category_id FK
        uuid claim_id FK
        date expense_date
        numeric amount
        text status
    }

    PAYSLIPS {
        uuid id PK
        uuid tenant_id FK
        uuid payroll_id FK
        uuid employee_id FK
        numeric gross_pay
        numeric total_deductions
        numeric net_pay
    }
```

---

## Layer 9: Marketing, Campaigns, Schemes & Offers

Layer 9 governs marketing launches, promotional product territory coverage, trade discount schemes (product bonuses such as buy 10 get 1 free), value turnover slabs, festival coupons, redemptions, and leave-behind promotional collateral.

```mermaid
erDiagram
    TENANTS ||--o{ CAMPAIGNS : "launches"
    CAMPAIGNS ||--o{ CAMPAIGN_TERRITORIES : "targets"
    TERRITORIES ||--o{ CAMPAIGN_TERRITORIES : "involves"
    CAMPAIGNS ||--o{ CAMPAIGN_PRODUCTS : "features"
    PRODUCTS ||--o{ CAMPAIGN_PRODUCTS : "promoted"

    TENANTS ||--o{ SCHEMES : "launches"
    SCHEMES ||--o{ SCHEME_PRODUCTS : "bonuses"
    PRODUCTS ||--o{ SCHEME_PRODUCTS : "buy_sku"
    PRODUCTS ||--o{ SCHEME_PRODUCTS : "free_sku"
    SCHEMES ||--o{ SCHEME_SLABS : "slabs"

    TENANTS ||--o{ OFFERS : "publishes"
    OFFERS ||--o{ COUPONS : "issues"
    COUPONS ||--o{ COUPON_REDEMPTIONS : "redeems"

    CAMPAIGNS ||--o{ PRODUCT_PROMOTIONS : "sponsors"
    PRODUCTS ||--o{ PRODUCT_PROMOTIONS : "discounts"
    CAMPAIGNS ||--o{ PROMOTIONAL_MATERIALS : "produces"
    PROMOTIONAL_MATERIALS ||--o{ PROMOTIONAL_MATERIAL_DISTRIBUTIONS : "hands_over"
    APP_USERS ||--o{ PROMOTIONAL_MATERIAL_DISTRIBUTIONS : "distributes"

    CAMPAIGNS {
        uuid id PK
        uuid tenant_id FK
        text code UK
        text name
        date start_date
        date end_date
        numeric budget
        text status
    }

    SCHEMES {
        uuid id PK
        uuid tenant_id FK
        text code UK
        text name
        text scheme_type
        date start_date
        date end_date
        boolean is_active
    }

    SCHEME_PRODUCTS {
        uuid id PK
        uuid tenant_id FK
        uuid scheme_id FK
        uuid buy_product_id FK
        integer buy_quantity
        uuid free_product_id FK
        integer free_quantity
        numeric discount_percentage
    }

    COUPONS {
        uuid id PK
        uuid tenant_id FK
        uuid offer_id FK
        text coupon_code UK
        integer max_uses
        integer used_count
        boolean is_active
    }
```

---

## Layer 10: Communication, Unified QR Codes, Finance & Integration

Layer 10 unifies omnichannel communications (In-App Notifications, SMS, Email, WhatsApp Cloud API, Mobile Push), Polymorphic QR Codes for anti-counterfeit drug verification, Optional Finance & Accounting Ledgers, Reporting SQL Views, and Third-Party Webhook/API Key integrations.

```mermaid
erDiagram
    APP_USERS ||--o{ NOTIFICATIONS : "alerts"
    TENANTS ||--o{ EMAIL_TEMPLATES : "templates"
    TENANTS ||--o{ EMAILS : "transmits"
    TENANTS ||--o{ SMS_TEMPLATES : "DLT_templates"
    TENANTS ||--o{ SMS : "dispatches"
    TENANTS ||--o{ WHATSAPP_TEMPLATES : "meta_approved"
    WHATSAPP_TEMPLATES ||--o{ WHATSAPP : "dispatches"
    APP_USERS ||--o{ PUSH_NOTIFICATIONS : "fcm_alerts"
    TENANTS ||--o{ COMMUNICATION_LOGS : "logs"

    TENANTS ||--o{ QR_CODES : "generates"
    QR_CODES ||--o{ QR_CODE_SCANS : "telemetry"
    APP_USERS ||--o{ QR_CODE_SCANS : "scanned_by"
    QR_CODES ||--o{ QR_CODE_HISTORIES : "lifecycle"

    TENANTS ||--o{ ACCOUNT_GROUPS : "categorizes"
    ACCOUNT_GROUPS ||--o{ CHART_OF_ACCOUNTS : "organizes"
    CHART_OF_ACCOUNTS ||--o{ CHART_OF_ACCOUNTS : "parent_ledger"
    TENANTS ||--o{ BANK_ACCOUNTS : "banks_at"
    BANK_ACCOUNTS ||--o{ BANK_TRANSACTIONS : "mutates"
    BANK_ACCOUNTS ||--o{ CHEQUE_BOOKS : "issues"
    CHEQUE_BOOKS ||--o{ CHEQUE_LEAVES : "tracks"

    TENANTS ||--o{ JOURNAL_ENTRIES : "posts"
    JOURNAL_ENTRIES ||--o{ JOURNAL_ENTRY_LINES : "balances"
    CHART_OF_ACCOUNTS ||--o{ JOURNAL_ENTRY_LINES : "affects"
    JOURNAL_ENTRIES ||--o{ GENERAL_LEDGERS : "streams"

    STOCKISTS ||--o{ SECONDARY_SALES : "submits_statement"
    CHEMISTS ||--o{ SECONDARY_SALES : "sold_to"
    SECONDARY_SALES ||--o{ SECONDARY_SALES_ITEMS : "details"
    PRODUCTS ||--o{ SECONDARY_SALES_ITEMS : "units"

    TENANTS ||--o{ API_KEYS : "authenticates"
    API_KEYS ||--o{ API_REQUEST_LOGS : "monitors"
    TENANTS ||--o{ WEBHOOK_ENDPOINTS : "subscribes"
    WEBHOOK_ENDPOINTS ||--o{ WEBHOOK_DELIVERIES : "attempts"

    QR_CODES {
        uuid id PK
        uuid tenant_id FK
        text code_value UK
        text entity_type
        uuid entity_id
        text qr_type
        boolean is_active
    }

    JOURNAL_ENTRIES {
        uuid id PK
        uuid tenant_id FK
        text entry_number UK
        date entry_date
        text status
        uuid posted_by_user_id FK
    }

    SECONDARY_SALES {
        uuid id PK
        uuid tenant_id FK
        uuid stockist_id FK
        uuid chemist_id FK
        integer reporting_month
        integer reporting_year
        numeric total_value
    }

    API_KEYS {
        uuid id PK
        uuid tenant_id FK
        text key_name
        text key_prefix UK
        text hashed_key
        text_array scopes
        boolean is_revoked
    }

    WEBHOOK_ENDPOINTS {
        uuid id PK
        uuid tenant_id FK
        text target_url
        text secret
        text_array events
        boolean is_active
    }
```

---

## Reporting Views

As instructed by architecture guidelines, analytical reporting aggregates are maintained as **SQL Views** rather than redundant materialized tables:

1. **`public.view_mr_performance_summary`**  
   Aggregates total visits, doctor visits, chemist visits, stockist visits, and total Pre-Order Booking (POB) values per representative per calendar month.
2. **`public.view_doctor_coverage_metrics`**  
   Compares completed monthly doctor visits against category call frequency norms ($A^+ = 4$, $A = 2$, $B = 1$), calculating whether monthly call coverage targets were met.
3. **`public.view_secondary_sales_aggregates`**  
   Aggregates retail chemist secondary sales statements by brand SKU, reporting month, and stockist territory.
