---
name: pharmasphere-domain
description: Use when designing or changing any PharmaSphere table, API, or screen. Defines pharma SFA/CRM/ERP vocabulary, module ownership, and the MVP build order.
---

# PharmaSphere domain

Multi-tenant pharma Sales Force Automation + CRM + ERP. Tenant = one pharma company. Users: Admin and Manager (React web), MR (Flutter mobile).

## Glossary
- **MR**: Medical Representative; field user who visits doctors and chemists.
- **Territory > Area > Region**: geographic hierarchy that scopes what an MR can see.
- **Beat/Route/BeatPlan**: planned sequence of visits for a day.
- **TourPlan**: monthly plan of visits, approved by a manager.
- **DCR (DailyCallReport)**: end-of-day summary of visits.
- **POB**: Potential/Pre-order Booking taken at a visit; has POBProduct lines.
- **RCPA**: Retail Chemist Prescription Audit; what a chemist sells vs competitors.
- **Primary sales**: company -> distributor. **Secondary sales**: distributor -> chemist.
- **JointWork**: manager accompanies an MR on visits.
- **Activity**: central timeline row. Every visit, check-in, selfie, e-detailing, POB, gift, feedback also writes/links an Activity.

## Module ownership (one owner per entity, no duplicates)
- Core: tenant, company, branch, user, role, permission, audit.
- Product/Inventory: product, batch, warehouse, stock, gift inventory.
- Sales: primary/secondary sales, invoice, payment, collection, returns.
- CRM: doctor, chemist, visit, feedback, POB, RCPA, e-detailing, Activity.
- HR: attendance, leave, expense, payroll, payslip. CRM links to these, never redefines them.
- Marketing: campaign, scheme, offer, coupon. Communication: email/SMS/WhatsApp/push. QR: one generic QRCode table with entity_type/entity_id.

## MVP build order (vertical slices; do not generate all ~190 tables at once)
1. Core + tenancy + auth. 2. Territory/MR/Doctor/Chemist masters. 3. Visit + Activity + feedback + POB (offline-capable).
4. Product + Secondary sales/orders. 5. Tour plan, DCR, attendance, expense. 6. Reports. Everything else later.

## Rules
- Visit check-in/out are columns (or events) on one visit table, not separate parallel entities.
- Before adding a table, grep the schema for an existing owner.
