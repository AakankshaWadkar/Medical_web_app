---
name: offline-sync-contract
description: Use when building MR mobile features that must work offline (visits, POB, check-in, feedback, expenses) or the sync endpoints that serve them.
---

# Offline sync contract

MRs work without connectivity. The Flutter app writes to local SQLite first and syncs later.

## Client rules
- IDs are client-generated UUIDs. Every mutation carries an `idempotency_key` (UUID) and `client_created_at`.
- Local outbox table: (id, entity, op, payload, idempotency_key, status, attempts, last_error). Retry with exponential backoff; never drop silently.
- Photos (selfies) upload separately via signed URL from FastAPI; the visit row stores the storage path. Upload may lag the visit row.
- Capture GPS + device timestamp at check-in; server also stamps `received_at`. Server time is authoritative for ordering/audit.

## Server rules
- `POST /v1/sync/push`: batch of mutations; each processed independently and idempotently (unique `(tenant_id, idempotency_key)`); response lists per-item result.
- `GET /v1/sync/pull?since=<cursor>`: rows changed since cursor (keyset on `updated_at` + `id`), including tombstones (`deleted_at`).
- Conflict policy per entity: visits/POB/feedback = append-only; masters (doctor/chemist/product) = server wins; plans/expenses = last-write-wins on `version` with 409 on stale.
- Rejected items return a machine-readable reason; the app shows them for user action.
