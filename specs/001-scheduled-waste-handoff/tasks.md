# Tasks: Scheduled Waste Load Handoff

**Input**: Design documents from `specs/001-scheduled-waste-handoff/`

**Prerequisites**: plan.md ✅ | spec.md ✅ | research.md ✅ | data-model.md ✅

**Organization**: Tasks grouped by user story — each story is independently implementable and testable.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Firestore index deployment and verify branch is clean before any code changes.

- [x] T001 Verify feature branch `001-scheduled-waste-handoff` is checked out (`git branch`)
- [x] T002 Add two composite Firestore indexes to `firestore.indexes.json` — `(is_deleted, status, scheduled_for ASC)` and `(is_deleted, status, pending_weighbridge_at DESC)` per `data-model.md`
- [ ] T003 Deploy Firestore indexes with `firebase deploy --only firestore` and confirm no index errors

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Model and service changes that ALL user stories depend on. No screen work until this phase is complete.

**⚠️ CRITICAL**: User stories 1–4 cannot be implemented until T004–T011 are done.

- [x] T004 Add `scheduled`, `pendingWeighbridge`, `cancelled` enum values to `WasteLoadStatus` in `lib/models/waste_load.dart` — stored as `'scheduled'`, `'pending_weighbridge'`, `'cancelled'`; update `fromString` factory with fallback to `draft`
- [x] T005 [P] Add 6 nullable fields to `WasteLoad` in `lib/models/waste_load.dart`: `scheduledFor` (Timestamp?), `scheduledBy` (String?), `scheduledByName` (String?), `scheduledNotes` (String?), `pendingWeighbridgeAt` (Timestamp?), `collectedBy` (String?) — update both `fromFirestore` and `toFirestore`
- [x] T006 Add `createScheduledLoad(Map<String, dynamic> data) → Future<String>` to `lib/services/waste_service.dart` — plain `addDoc` (no Cloud Function), sets status `'scheduled'`, `is_deleted: false`, `created_by`, `scheduled_by`, `scheduled_by_name`, `scheduled_notes`, `scheduled_for`; returns doc ID
- [x] T007 Add `watchScheduledLoads() → Stream<List<WasteLoad>>` to `lib/services/waste_service.dart` — queries `is_deleted == false`, `status == 'scheduled'`, ordered by `scheduled_for` ascending, limit 50
- [x] T008 Add `cancelScheduledLoad(String loadId) → Future<void>` to `lib/services/waste_service.dart` — Firestore transaction: read doc → assert status == `scheduled` (throw `StateError` if not) → write `status: 'cancelled'`
- [x] T009 Add `submitCollection(String loadId, Map<String, dynamic> driverData, List<Map<String, dynamic>> itemsData, List<String> itemPhotoPaths, String? signatureLocalPath) → Future<void>` to `lib/services/waste_service.dart` — transaction: assert status == `scheduled`, write status `pending_weighbridge` + driver fields + `pending_weighbridge_at` + `collected_by`; then upload photos + signature reusing existing helpers; batch-write items; queue via `SyncService`
- [x] T010 Update `watchPendingWeighbridge()` in `lib/services/waste_service.dart` — change query from `status == 'completed'` + date threshold to `status == 'pending_weighbridge'`, ordered by `pending_weighbridge_at` descending, limit 100; remove client-side weighbridge-number filter
- [x] T011 Run `flutter analyze` and confirm zero errors from model/service changes

**Checkpoint**: Model + service layer complete. All new Firestore paths are wired. User story screens can now be built.

---

## Phase 3: User Story 1 — Manager Schedules an Incoming Load (Priority: P1) 🎯 MVP

**Goal**: A Security Manager can create a scheduled load (contractor, type, date, notes) that immediately appears in the guard's Incoming list.

**Independent Test**: Sign in as manager → tap "Schedule Incoming" → fill form → save → confirm load appears with status `scheduled` in Firestore and on guard's home screen.

- [x] T012 [US1] Create `WasteScheduleLoadScreen` in `lib/screens/waste_schedule_load_screen.dart` as `ConsumerStatefulWidget` — scaffold with AppBar "Schedule Incoming Load", form body, and Save button in AppBar actions
- [x] T013 [US1] Add contractor dropdown to `WasteScheduleLoadScreen` using `StreamBuilder` on `WasteService.watchContractors()` — required field with validation
- [x] T014 [P] [US1] Add main waste type grid to `WasteScheduleLoadScreen` reusing the type-selection widget pattern from `lib/screens/waste_create_load_screen.dart` — required, tapping a type highlights it
- [x] T015 [US1] Add `DatePicker` for expected date to `WasteScheduleLoadScreen` — required, shows selected date formatted as "Mon 2 Jun 2026"; defaults to today
- [x] T016 [P] [US1] Add optional notes `TextField` to `WasteScheduleLoadScreen` — multiline, max 3 lines, label "Notes (optional)"
- [x] T017 [US1] Wire Save button in `WasteScheduleLoadScreen` — validates required fields, calls `WasteService.createScheduledLoad()`, shows loading state on button, shows success `SnackBar` "Load scheduled", pops screen on success
- [x] T018 [US1] Wire "Schedule Incoming" entry point in `lib/screens/waste_home_screen.dart` — for `isSecurityManager` or `isWasteAdmin`: FAB shows bottom sheet with "Schedule Incoming" and "New Load" options. Guards see single "New Load" FAB (unchanged).

**Checkpoint**: Manager can schedule a load. A Firestore document with `status: 'scheduled'` is created. Guard's home screen will show it after Phase 4.

---

## Phase 4: User Story 2 — Guard Begins Collection When Truck Arrives (Priority: P1)

**Goal**: Guard sees scheduled loads prominently and can complete the full collection (driver, items, photos, signature) → `pending_weighbridge`.

**Independent Test**: With a `scheduled` load in Firestore, sign in as guard → see load in Incoming section → tap "Begin Collection" → fill driver + reg + 1 item + 1 photo + signature → submit → confirm Firestore status = `pending_weighbridge`.

- [x] T019 [US2] Add `watchScheduledLoads()` `StreamBuilder` to `lib/screens/waste_home_screen.dart` — renders "Incoming" header + list of scheduled load cards only when stream is non-empty; placed above the existing loads list
- [x] T020 [US2] Create `_IncomingLoadCard` widget inline in `lib/screens/waste_home_screen.dart` — displays: waste type + icon, contractor ID, formatted expected date, manager notes (if any), cancel option for managers, and a "Begin Collection →" `FilledButton`
- [x] T021 [US2] Create `WasteBeginCollectionScreen` in `lib/screens/waste_begin_collection_screen.dart` as `ConsumerStatefulWidget` — scaffold with AppBar "Begin Collection", read-only header card (contractor, type, scheduled date, notes), and scrollable form body
- [x] T022 [US2] Add driver name and vehicle registration `TextField`s to `WasteBeginCollectionScreen` — both required; shown below the read-only header
- [x] T023 [US2] Add waste items section to `WasteBeginCollectionScreen` — "Add Item" button opens `_AddItemDialog`; items listed with subtype, weight, photo count; at least 1 item required for submit
- [x] T024 [US2] Add signature capture to `WasteBeginCollectionScreen` — "Capture Signature" button navigates to existing `WasteSignatureScreen`; signature preview thumbnail shown once captured; required for submit
- [x] T025 [US2] Wire Submit button in `WasteBeginCollectionScreen` — disabled until driver name + reg + ≥1 item with ≥1 photo + signature are all present; on tap calls `WasteService.submitCollection()`; shows loading indicator; on success pops to home with SnackBar "Collection submitted"; on `StateError` shows dialog "Already started by another guard"
- [x] T026 [US2] Handle offline case in `WasteBeginCollectionScreen` — submission uses `SyncService` queue; error dialog mentions offline resilience

**Checkpoint**: Full guard collection flow works. Load transitions from `scheduled` → `pending_weighbridge` in Firestore.

---

## Phase 5: User Story 3 — Manager Enters Weighbridge Weight (Priority: P2)

**Goal**: Loads in `pending_weighbridge` appear in the existing Pending Weighbridge screen so the manager can enter the weight and complete the load.

**Independent Test**: With a load in `pending_weighbridge` status in Firestore, sign in as manager → open Pending Weighbridge screen → confirm load appears with guard's submitted details → enter weighbridge weight → confirm status = `completed`.

- [x] T027 [US3] Update call site in `waste_pending_weighbridge_screen.dart` to call `watchPendingWeighbridge()` without `daysThreshold` parameter
- [x] T028 [US3] Update load card subtitle in `waste_pending_weighbridge_screen.dart` to display `collectedBy` (guard clockNo) and `pendingWeighbridgeAt` timestamp

**Checkpoint**: Pending Weighbridge screen now surfaces loads submitted by guards. Existing weighbridge entry + complete flow works unchanged.

---

## Phase 6: User Story 4 — Manager Cancels or Edits a Scheduled Load (Priority: P3)

**Goal**: Manager can cancel a `scheduled` load before the guard starts, or edit its expected date and notes.

**Independent Test**: With a `scheduled` load, sign in as manager → long-press Incoming card → cancel → confirm load disappears from guard's Incoming list and Firestore status = `cancelled`.

- [x] T029 [P] [US4] Add `PopupMenuButton` to `_IncomingLoadCard` in `lib/screens/waste_home_screen.dart` — visible only to managers/admins; menu item: "Cancel load"
- [x] T030 [US4] Wire "Cancel load" → `AlertDialog` confirmation → `WasteService.cancelScheduledLoad()` → `onRefresh()`; handles `StateError` "Load already in progress"
- [ ] T031 [US4] Wire "Edit date & notes" menu item — `showModalBottomSheet` with pre-filled `DatePicker` + notes `TextField`; on save calls `WasteService` direct Firestore update

**Checkpoint**: Managers can manage scheduled loads before guards begin. Guards see accurate Incoming list.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [x] T032 Add `displayLabel` getter to `WasteLoadStatus` in `lib/models/waste_load.dart` — returns "Scheduled", "Pending Weighbridge", "Cancelled" for new statuses
- [x] T033 [P] Add status icon/colour helpers `_statusIcon` + `_statusColor` to `waste_home_screen.dart` covering all 5 statuses
- [ ] T034 Confirm `watchLoads()` main list excludes `scheduled` loads for guards — manually verify or add `status != scheduled` filter if needed
- [ ] T035 [P] Update web WasteTrack (`web/job-cards-waste`) — loads page: add `scheduled`/`pending_weighbridge`/`cancelled` badge variants to `app/(dashboard)/loads/page.tsx`
- [x] T036 Run `flutter analyze` — zero errors (1 `info` deprecation on `DropdownButtonFormField.value` — non-blocking)
- [ ] T037 Manual smoke test: full end-to-end as manager (schedule) → guard (begin collection + submit) → manager (weighbridge + complete)
- [ ] T038 [P] Update architecture visualization `docs/architecture/visualization.md` to reflect new screens and status flow

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 — **BLOCKS all user story phases**
- **Phase 3 (US1 — Manager Schedules)**: Requires Phase 2
- **Phase 4 (US2 — Guard Collects)**: Requires Phase 2; independent of Phase 3 (but practically needs a scheduled load to test)
- **Phase 5 (US3 — Weighbridge)**: Requires Phase 2 (T010); independent of Phases 3–4
- **Phase 6 (US4 — Cancel/Edit)**: Requires Phase 3 (Incoming card from T020)
- **Phase 7 (Polish)**: Requires all user story phases complete

### User Story Dependencies

- **US1 (P1)**: Phase 2 complete → can start
- **US2 (P1)**: Phase 2 complete → can start (parallel with US1)
- **US3 (P2)**: Phase 2 complete (specifically T010) → can start
- **US4 (P3)**: T020 (`WasteIncomingLoadCard`) complete → can start

### Within Each Phase

- Phase 2: T004 and T005 can run in parallel (different sections of same file — coordinate on `fromFirestore`/`toFirestore`)
- Phase 2: T006, T007, T008, T009 can run in parallel (all add new methods, no conflicts)
- Phase 2: T010 depends on T004 (needs new status value string)
- Phase 3: T012–T016 can run in parallel once T012 (scaffold) is done
- Phase 4: T021 (scaffold) must precede T022–T026

---

## Parallel Execution Example

```
Phase 2 parallel group A (run together):
  T004 — enum values
  T005 — model fields

Phase 2 parallel group B (after A):
  T006 — createScheduledLoad()
  T007 — watchScheduledLoads()
  T008 — cancelScheduledLoad()
  T009 — submitCollection()
  T010 — update watchPendingWeighbridge()

Phase 3+4 (run in parallel after Phase 2):
  Developer A → T012–T018 (Manager Schedule Screen + FAB)
  Developer B → T019–T026 (Guard Incoming Section + Begin Collection Screen)
```

---

## Implementation Strategy

### MVP (User Stories 1 + 2 only — Phases 1–4)

1. Phase 1: Setup + deploy indexes
2. Phase 2: Model + service layer
3. Phase 3: Manager scheduling screen + FAB
4. Phase 4: Guard Incoming section + Begin Collection screen
5. **Validate end-to-end**: Manager schedules → guard collects → status = `pending_weighbridge` in Firestore
6. Phase 5 is near-zero effort (Pending Weighbridge screen auto-updates via T010)

### Full Delivery

Add Phase 6 (cancel/edit) + Phase 7 (polish) after MVP validates.

---

## Notes

- `[P]` = task touches a different file from adjacent tasks — safe to parallelize
- `[USn]` = maps task to user story for traceability
- Phase 2 is the highest-risk phase — model + service changes affect existing Firestore data paths
- `submitCollection` (T009) reuses existing photo upload + offline queue helpers — do not rewrite them
- Legacy `saveCompleteWasteLoad()` is **not modified** — guard "New Load" flow stays intact (FR-013)
- Deploy Firestore indexes (T003) before testing any `watchScheduledLoads()` query — missing index causes silent empty stream
