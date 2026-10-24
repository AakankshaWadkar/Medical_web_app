# PharmaSphere: Database Architecture Description

**Product:** Multi-tenant SaaS combining Pharmaceutical **Sales Force Automation (SFA) + CRM + ERP**.
**Clients:** Admin web app (React) and Medical Representative (MR) mobile app (Flutter).
**Estimated size:** ~190–200 tables (excluding pharmaceutical compliance, as requested).

The new field-force features are not added as isolated tables. They are integrated into the correct business domains, giving ten layers.

## Revised enterprise architecture

```text
PharmaSphere ERP
│
└── Multi-Tenant SaaS Foundation
    │
    ├── Core ERP            Authentication, Authorization, Company, Branch, Users, Settings
    ├── Product & Stock     Inventory, Purchase, Sales, Warehouse, QR Code, Batch
    ├── Sales CRM           Medical Rep, Doctor CRM, Chemist CRM, Tour Plan, Gift Mgmt, RCPA
    └── HR & Payroll        Attendance, Leave, Payroll, Expense, Payslip, Letters
```

## Contents

1. [Core ERP](#layer-1--core-erp)
2. [Product & Inventory](#layer-2--product--inventory)
3. [Warehouse & Inventory](#layer-3--warehouse--inventory)
4. [Purchase](#layer-4--purchase)
5. [Sales](#layer-5--sales)
6. [CRM](#layer-6--crm-completely-redesigned)
7. [HR](#layer-7--hr)
8. [Marketing](#layer-8--marketing)
9. [Communication](#layer-9--communication)
10. [QR Code](#layer-10--qr-code)
11. [Estimated database size](#estimated-database-size)
12. [Design recommendation: Activity table](#design-recommendation-central-activity-table)
13. [Conversion notes](#conversion-notes-not-part-of-the-original-document)

---

## Layer 1 – Core ERP

No major changes.

- Company
- Branch
- Department
- User
- Role
- Permission
- UserRole
- RolePermission
- CompanySettings
- SubscriptionPlan
- CompanySubscription
- AuditLog
- LoginHistory
- RefreshToken

---

## Layer 2 – Product & Inventory

**New entities added**

- ProductQRCode
- ProductBarcode
- ProductPromotion
- GiftItem
- GiftInventory
- Scheme
- SchemeProduct

**Updated ER**

```text
Category
└── Product
    ├── ProductBatch
    ├── ProductQRCode
    ├── ProductBarcode
    ├── ProductPromotion
    └── SchemeProduct
        └── Scheme
```

---

## Layer 3 – Warehouse & Inventory

**New tables**

- GiftInventory
- GiftStockTransaction

```text
Warehouse
├── Inventory
├── ProductBatch
└── GiftInventory
    └── GiftStockTransaction
```

---

## Layer 4 – Purchase

No major change.

---

## Layer 5 – Sales

Instead of only Sales Orders, sales is split into primary and secondary sales.

- PrimarySales
- PrimarySalesItem
- SecondarySales
- SecondarySalesItem
- SalesReturn
- Invoice
- Payment
- Collection

**ER**

```text
Distributor
└── PrimarySales
    └── PrimarySalesItem

Chemist
└── SecondarySales
    └── SecondarySalesItem

Invoice
├── Payment
└── Collection
```

---

## Layer 6 – CRM (Completely Redesigned)

This becomes one of the biggest modules.

### Doctor

- Doctor
- DoctorSpeciality
- DoctorCategory
- DoctorAddress
- DoctorPrescription
- DoctorFeedback
- DoctorVisit
- DoctorTourPlan
- DoctorCheckIn
- DoctorCheckOut
- JointWork
- VisitSelfie
- EDetailing
- POB
- POBProduct
- DoctorGiftDistribution

### Chemist

- Chemist
- ChemistCategory
- ChemistContact
- ChemistRCPA
- ChemistPOB
- ChemistFeedback
- ChemistVisit
- ChemistPayment
- ChemistQRCode

### Medical Representative

- MedicalRepresentative
- Territory
- Area
- Region
- DailyCallReport
- TourPlan
- JointWork
- Expense
- Leave
- Attendance
- Target
- Achievement
- FileUpload
- MRDocument
- Route
- BeatPlan

### New CRM ER

```text
MedicalRepresentative
├── TourPlan
├── DailyCallReport
├── Expense
├── Leave
├── Attendance
├── JointWork
└── DoctorVisit
    ├── CheckIn
    ├── CheckOut
    ├── VisitSelfie
    ├── DoctorFeedback
    ├── EDetailing
    ├── POB
    │   └── POBProduct
    ├── DoctorPrescription
    └── GiftDistribution
```

### Chemist CRM

```text
MedicalRepresentative
└── ChemistVisit
    ├── Chemist
    ├── ChemistRCPA
    ├── ChemistPayment
    ├── ChemistFeedback
    ├── ChemistPOB
    └── ChemistAddition
```

---

## Layer 7 – HR

New module.

- Employee
- Attendance
- AttendanceLog
- Leave
- LeaveType
- Expense
- ExpenseClaim
- Payslip
- Salary
- Payroll
- Letter
- Holiday
- Shift
- Policy
- FileUpload

**ER**

```text
Employee
├── Attendance
├── Leave
├── Expense
├── Payslip
├── Salary
├── Letter
└── FileUpload
```

---

## Layer 8 – Marketing

- Campaign
- Gift
- GiftInventory
- GiftDistribution
- ProductPromotion
- Scheme
- SchemeProduct
- Offer
- Coupon

```text
Campaign
├── ProductPromotion
├── GiftDistribution
└── Scheme
    └── SchemeProduct
```

---

## Layer 9 – Communication

- Notification
- Email
- EmailTemplate
- SMS
- WhatsApp
- WhatsAppTemplate
- POBEmail
- PushNotification

```text
POB
├── Email
├── WhatsApp
└── SMS
```

This supports sending POBs and schemes by email or WhatsApp.

---

## Layer 10 – QR Code

- QRCode
- QRCodeScan
- QRCodeHistory
- ProductQRCode
- ChemistQRCode
- DoctorQRCode

```text
Product
└── ProductQRCode

Doctor
└── DoctorQRCode

Chemist
└── ChemistQRCode
```

---

## Estimated database size

**Estimated total: ~190–200 tables** (excluding pharmaceutical compliance, as requested).

| Module | Tables |
|---|---:|
| Core ERP | 14 |
| Product | 18 |
| Inventory | 15 |
| Purchase | 12 |
| Sales | 16 |
| CRM | 32 |
| HR & Payroll | 18 |
| Marketing | 12 |
| Finance | 20 |
| Communication | 10 |
| Dashboard & Reports | 10 |
| API & Integration | 12 |
| **Total** | **189** |

---

## Design recommendation: central Activity table

Introduce a central **Activity** table that links together doctor visits, chemist visits, tour plans, check-ins, selfies, e-detailing, POBs, gift distribution, and feedback. This gives a single timeline of field-force activity, simplifies reporting and analytics, and reduces duplicated data across modules. This pattern is common in enterprise CRM/SFA platforms.

---

## Conversion notes (not part of the original document)

Added while converting from `.docx`; remove this section if you prefer a pure copy.

**Typo fixed:** "API & Inrtegration" → "API & Integration".

**Entities that appear in more than one layer** (each needs a single owning table before any SQL is written):

| Entity | Appears in |
|---|---|
| JointWork | Doctor list, Medical Representative list |
| Attendance, Leave, Expense | Medical Representative list (Layer 6) and HR (Layer 7) |
| FileUpload | Medical Representative list and HR |
| GiftInventory | Layer 2, Layer 3, Layer 8 |
| Scheme, SchemeProduct, ProductPromotion | Layer 2 and Layer 8 |
| GiftDistribution / DoctorGiftDistribution | Layer 6 and Layer 8 |
| ProductQRCode, ChemistQRCode | Layer 2 / Chemist list and Layer 10 |
| POB | Layer 6 and Layer 9 diagram |

**Naming inconsistencies to resolve:**

- `DoctorCheckIn` / `DoctorCheckOut` (entity list) vs `CheckIn` / `CheckOut` (ER diagram) vs `DoctorVisit`.
- `ChemistAddition` appears in the Chemist CRM diagram but not in the Chemist entity list.
- `GiftDistribution` (ER diagram) vs `DoctorGiftDistribution` (entity list).

**Modules in the size table with no entity list in this document:** Finance (20), Dashboard & Reports (10), API & Integration (12), and a separate Purchase list (12). Their tables still need to be defined; the layers above name only about 100 distinct entities, so roughly half of the estimated ~190 tables are not yet described.
