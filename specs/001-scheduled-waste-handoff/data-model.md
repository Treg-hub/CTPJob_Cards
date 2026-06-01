# Data Model: Scheduled Waste Load Handoff

**Feature**: 001-scheduled-waste-handoff
**Phase**: 1 — Design
**Date**: 2026-06-01

---

## WasteLoadStatus (enum extension)

File: `lib/models/waste_load.dart`

```
Current:   draft → completed
New:       draft → completed
           scheduled → pending_weighbridge → completed
           scheduled → cancelled
```

| Value (Dart) | Firestore string | Set by | Meaning |
|---|---|---|---|
| `draft` | `draft` | Guard (legacy) | Guard creating from scratch |
| `completed` | `completed` | Manager/Admin | Load fully done |
| `scheduled` | `scheduled` | Manager/Admin | Awaiting contractor arrival |
| `pendingWeighbridge` | `pending_weighbridge` | Guard (submit) | Collection done, weighbridge pending |
| `cancelled` | `cancelled` | Manager/Admin | Cancelled before guard began |

---

## WasteLoad (extended fields)

File: `lib/models/waste_load.dart` — additions only (existing fields unchanged)

| Dart property | Firestore key | Type | Nullable | Set when |
|---|---|---|---|---|
| `scheduledFor` | `scheduled_for` | `Timestamp` | yes | Manager creates scheduled load |
| `scheduledBy` | `scheduled_by` | `String` | yes | Manager creates scheduled load |
| `scheduledByName` | `scheduled_by_name` | `String` | yes | Manager creates scheduled load |
| `scheduledNotes` | `scheduled_notes` | `String` | yes | Manager creates (optional) |
| `pendingWeighbridgeAt` | `pending_weighbridge_at` | `Timestamp` | yes | Guard submits collection |
| `collectedBy` | `collected_by` | `String` | yes | Guard submits collection (clockNo) |

---

## State Transitions

```
                    ┌─────────────┐
                    │  scheduled  │  ← Manager creates
                    └──────┬──────┘
                           │ Guard begins + submits
                           ▼
               ┌───────────────────────┐
               │  pending_weighbridge  │  ← Guard submitted
               └──────────┬────────────┘
                          │ Manager enters weighbridge weight
                          ▼
                    ┌───────────┐
                    │ completed │  ← Manager completes
                    └───────────┘

From scheduled only:
    scheduled → cancelled  (Manager cancels before guard begins)

Legacy path (unchanged):
    draft → completed  (Guard creates from scratch, manager weighbridges)
```

**Guard cannot begin collection** once status ≠ `scheduled` (enforced by Firestore transaction in `submitCollection`).

---

## New WasteService Methods

### `createScheduledLoad(Map<String, dynamic> data) → Future<String>`

Input fields:
- `contractor_id` (required)
- `main_waste_type` (required)
- `scheduled_for` (required, Timestamp)
- `scheduled_notes` (optional)
- `scheduled_by` (set from currentEmployee.clockNo)
- `scheduled_by_name` (set from currentEmployee.name)
- `status` → `'scheduled'`
- `is_deleted` → `false`
- `created_by` → clockNo

Returns: Firestore document ID

---

### `watchScheduledLoads() → Stream<List<WasteLoad>>`

Firestore query:
```
collection: waste_loads
where: is_deleted == false
where: status == 'scheduled'
orderBy: scheduled_for ascending
limit: 50
```

Requires composite index: `status ASC` + `scheduled_for ASC` (or where clause + orderBy).

---

### `submitCollection(String loadId, Map<String, dynamic> collectionData, List<WasteItemData> items, List<String> photoPaths, String? signaturePath) → Future<void>`

Steps (within Firestore transaction + offline queue):
1. Transaction: read load, assert status == `scheduled`, write status = `pending_weighbridge` + driver fields + `pending_weighbridge_at` + `collected_by`
2. Upload item photos (reuse existing photo upload + offline queue)
3. Batch-write waste items to `waste_items` subcollection
4. Upload driver signature (reuse `uploadSignature`)
5. Update load with signature URL

---

### `cancelScheduledLoad(String loadId) → Future<void>`

Transaction: read load, assert status == `scheduled`, write status = `cancelled`.
If status ≠ `scheduled`, throw `WasteLoadAlreadyStartedException`.

---

## Updated `watchPendingWeighbridge`

**Current query** (status = `completed` + missing weighbridge number):
```dart
.where('status', isEqualTo: 'completed')
.where('date_time', isLessThan: cutoff)
// + client-side filter for missing weighbridge number
```

**New query** (status = `pending_weighbridge`):
```dart
.where('is_deleted', isEqualTo: false)
.where('status', isEqualTo: 'pending_weighbridge')
.orderBy('pending_weighbridge_at', descending: true)
.limit(100)
```

The 3-day threshold is removed (pending_weighbridge loads should always be visible until completed). Client-side weighbridge-number filter is also removed (status is now authoritative).

---

## Firestore Index Requirements

New composite indexes needed in `firestore.indexes.json`:

```json
{
  "collectionGroup": "waste_loads",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "is_deleted", "order": "ASCENDING" },
    { "fieldPath": "status", "order": "ASCENDING" },
    { "fieldPath": "scheduled_for", "order": "ASCENDING" }
  ]
},
{
  "collectionGroup": "waste_loads",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "is_deleted", "order": "ASCENDING" },
    { "fieldPath": "status", "order": "ASCENDING" },
    { "fieldPath": "pending_weighbridge_at", "order": "DESCENDING" }
  ]
}
```
