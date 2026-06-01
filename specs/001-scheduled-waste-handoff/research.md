# Research: Scheduled Waste Load Handoff

**Feature**: 001-scheduled-waste-handoff
**Phase**: 0 — Research
**Date**: 2026-06-01

---

## Decision 1: New Load Status Values

**Decision**: Add three new values to `WasteLoadStatus` enum in `lib/models/waste_load.dart`:
- `scheduled` — manager-created load awaiting guard collection
- `pendingWeighbridge` — guard submitted, awaiting manager weighbridge entry
- `cancelled` — load cancelled before guard began collection

**Rationale**: The current enum only has `draft` and `completed`. Both `saveCompleteWasteLoad()` and `watchPendingWeighbridge()` use hardcoded string comparisons; adding new enum values keeps the pattern consistent and avoids magic strings.

**Alternatives considered**:
- Reusing `draft` with a flag field — rejected because it breaks the existing `watchPendingWeighbridge` query (which filters on `completed`) and pollutes load semantics.
- Single `pending` status — rejected because we need to distinguish between "scheduled by manager, not yet started" and "collected by guard, needs weighbridge".

**Firestore stored values** (`.value` of enum):
- `scheduled`
- `pending_weighbridge`
- `cancelled`

---

## Decision 2: New WasteLoad Fields

**Decision**: Add the following fields to `WasteLoad` model (both `fromFirestore` and `toFirestore`):

| Dart field | Firestore key | Type | Purpose |
|---|---|---|---|
| `scheduledFor` | `scheduled_for` | `Timestamp?` | Expected collection date/time |
| `scheduledBy` | `scheduled_by` | `String` | clockNo of scheduling manager |
| `scheduledByName` | `scheduled_by_name` | `String` | Display name of scheduling manager |
| `scheduledNotes` | `scheduled_notes` | `String` | Optional manager notes |
| `pendingWeighbridgeAt` | `pending_weighbridge_at` | `Timestamp?` | When guard submitted |
| `collectedBy` | `collected_by` | `String` | clockNo of guard who collected |

**Rationale**: These fields are only populated in certain statuses, so `nullable` (Dart `?`) is appropriate. They never replace existing fields — `created_by`, `completed_by`, `completed_at` etc. remain.

**Alternatives considered**: Separate `scheduled_loads` collection — rejected to avoid data fragmentation; the single `waste_loads` collection with status-gated fields is consistent with the existing pattern.

---

## Decision 3: WasteService Method Strategy

**Decision**: Add four new methods to `WasteService`, leaving existing methods unchanged:

| Method | Purpose |
|---|---|
| `createScheduledLoad(data)` | Manager creates skeleton load with status = `scheduled` |
| `watchScheduledLoads()` | Stream of `scheduled` status loads, ordered by `scheduled_for` asc |
| `submitCollection(loadId, collectionData)` | Guard adds items/photos/signature to a scheduled load, transitions to `pending_weighbridge` |
| `cancelScheduledLoad(loadId)` | Manager cancels, sets status = `cancelled` |

`saveCompleteWasteLoad()` is **not modified** — it remains the path for the legacy "guard creates from scratch" flow (FR-013 coexistence requirement).

**Rationale**: Additive-only changes protect the existing offline queue and photo upload paths. `submitCollection` will reuse the existing photo upload + offline queue patterns from `saveCompleteWasteLoad` for items and photos.

**For `watchPendingWeighbridge`**: Update to query `status == 'pending_weighbridge'` instead of `status == 'completed'` + old weighbridge-number-missing check. The existing screen's `_canAccess` gate is unchanged.

---

## Decision 4: Guard Home Screen — "Incoming" Section

**Decision**: Add a dedicated "Incoming" section above the existing load list in `waste_home_screen.dart`. This section uses `watchScheduledLoads()` as a second stream. The existing `watchLoads(limit: 20)` stream remains for the main list.

**Implementation approach**:
- Two `StreamBuilder` widgets stacked in a `Column` inside the `ListView`
- "Incoming" section hidden when empty (no `scheduled` loads)
- Each Incoming card shows: contractor name, waste type, scheduled date, with a prominent "Begin Collection" tap action

**Rationale**: Existing `watchLoads()` already supports an optional `status` filter — the incoming stream just passes `status: 'scheduled'`. No structural changes to the screen needed.

---

## Decision 5: Guard "Begin Collection" Entry Point

**Decision**: Add a new screen `WasteBeginCollectionScreen` rather than modifying `waste_load_detail_screen.dart`.

**Rationale**: The detail screen is complex (370+ lines, handles admin/manager/read-only divergence). A dedicated screen for the guard collection flow is simpler, testable independently, and avoids breaking the existing role logic. It receives the `WasteLoad` (scheduled) and produces a complete collection submission.

**Screen flow**:
1. Guard taps scheduled load in Incoming list → `WasteBeginCollectionScreen(load: scheduledLoad)`
2. Screen shows read-only load header (contractor, type, date)
3. Guard fills: driver name, vehicle reg
4. Guard adds waste items (reuses existing `WasteItemEntryDialog`)
5. Guard captures driver signature (reuses `WasteSignatureScreen`)
6. Submit → calls `WasteService.submitCollection()`

---

## Decision 6: Manager Schedule Screen

**Decision**: New screen `WasteScheduleLoadScreen` — a simplified form with:
- Contractor (dropdown, existing `watchContractors()` stream)
- Main waste type (dropdown, existing `watchWasteTypes()` stream)
- Expected date (date picker)
- Notes (text field, optional)

**Entry point**: FAB on `waste_home_screen.dart` split into two options for managers: "Schedule Incoming" and "New Load" (legacy). Guards only see "New Load".

**Rationale**: Reuses existing contractor and waste type dropdowns from `WasteLoadFormScreen`. A separate screen keeps the scheduling flow clear and independently testable.

---

## Decision 7: Optimistic Locking for Double-Collection Prevention

**Decision**: Use a Firestore transaction in `submitCollection()` that reads the current load status and writes atomically — if the status is no longer `scheduled`, the transaction aborts and the guard sees an error message.

**Rationale**: Low probability event (two guards unlikely to pick the same load simultaneously) but important for data integrity. A transaction is the correct Firestore primitive for this.

---

## Decision 8: Offline Behaviour for Guard Submission

**Decision**: Guard submission uses the same `SyncService.addToQueue()` pattern as `saveCompleteWasteLoad()`. Photos are individually queued with retry. The load status transition is queued separately and applied when online.

**Rationale**: The existing offline infrastructure already handles this pattern. No new mechanisms needed.

---

## Summary: Files Affected

| File | Change type |
|---|---|
| `lib/models/waste_load.dart` | Add 3 enum values, 6 fields |
| `lib/services/waste_service.dart` | Add 4 methods, update `watchPendingWeighbridge` query |
| `lib/screens/waste_home_screen.dart` | Add Incoming section, split FAB for managers |
| `lib/screens/waste_schedule_load_screen.dart` | **NEW** — manager scheduling form |
| `lib/screens/waste_begin_collection_screen.dart` | **NEW** — guard collection entry |
| Firestore `waste_loads` composite index | Add index on `status` + `scheduled_for` |
