# Feature Specification: Scheduled Waste Load Handoff

**Feature Branch**: `001-scheduled-waste-handoff`

**Created**: 2026-06-01

**Status**: Draft

**Input**: Manager schedules a waste load before the truck arrives. Guard sees pending/scheduled loads on their home screen, selects the right one when the contractor arrives at the gate, then adds driver name, vehicle registration, waste items with photos, and captures the driver signature. After the guard submits, the load moves to pending_weighbridge status. The manager then enters the actual weighbridge weight and marks the load complete. This replaces the current single-session create flow with a two-phase manager-creates / guard-completes handoff.

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Manager Schedules an Incoming Load (Priority: P1)

The security manager, after arranging a waste collection with a contractor, opens the app and creates a scheduled load. She fills in the contractor name, waste type, expected date, and any notes (e.g. estimated volume, special handling). No driver details or photos are required at this stage. The load appears in the guard's "Incoming" list immediately.

**Why this priority**: This is the starting point of the entire handoff chain. Without it, the guard has nothing to act on. It is the minimum viable first phase.

**Independent Test**: A manager can create a scheduled load with contractor + waste type + date and confirm it appears in the guard's Incoming list — all without any guard involvement.

**Acceptance Scenarios**:

1. **Given** a logged-in Security Manager, **When** they tap "Schedule Load" and complete the form (contractor, waste type, expected date), **Then** a new load with status `scheduled` is saved and immediately visible in the Guard's Incoming list.
2. **Given** a partially filled schedule form, **When** the manager taps Save with the contractor field empty, **Then** the form shows a validation error and does not save.
3. **Given** a saved scheduled load, **When** the manager views their dashboard, **Then** the load appears under "Scheduled — Awaiting Arrival" with the expected date shown.

---

### User Story 2 — Guard Begins Collection When Truck Arrives (Priority: P1)

When the contractor's truck arrives at the gate, the guard opens the app and sees a prominent "Incoming" section listing today's scheduled loads. He taps the correct load, then fills in the driver name, vehicle registration, waste items (subtype, weight, quantity), photographs each item, and collects the driver's signature. Submitting moves the load to `pending_weighbridge` and notifies the manager.

**Why this priority**: This is the core guard-facing workflow — the primary reason for the feature. It replaces the guard creating loads from scratch and enforces the correct two-phase process.

**Independent Test**: With a pre-created scheduled load, a guard can fully complete the "Begin Collection" flow (driver info → items + photos → signature → submit) and confirm the load status changes to `pending_weighbridge`.

**Acceptance Scenarios**:

1. **Given** a scheduled load exists for today, **When** the guard opens the Waste screen, **Then** the load is prominently shown in an "Incoming" section at the top of the list.
2. **Given** the guard taps a scheduled load and taps "Begin Collection", **When** they fill in driver name, reg, at least one waste item with photo, and capture a signature, **Then** submitting changes the load status to `pending_weighbridge`.
3. **Given** the guard is filling in collection details, **When** they attempt to submit without at least one waste item with a photo, **Then** the app shows a validation error and does not submit.
4. **Given** the guard is in "Begin Collection" mode, **When** the device loses connectivity mid-way, **Then** completed photos and partial data are saved locally and synced when connectivity returns.
5. **Given** a guard submits the collection, **When** submission succeeds, **Then** the load disappears from the guard's "Incoming" section and moves to a "Submitted Today" or completed view.

---

### User Story 3 — Manager Enters Weighbridge Weight and Completes Load (Priority: P2)

After the truck has left the gate, the manager opens the Pending Weighbridge list, finds the load just submitted by the guard, enters the actual weighbridge weight, and marks the load complete. The existing Pending Weighbridge screen already handles this flow — it simply needs to now include loads in `pending_weighbridge` status.

**Why this priority**: Completion of the load is important but the existing Pending Weighbridge screen already covers most of this. The change is additive (new status feeds the existing screen).

**Independent Test**: With a load in `pending_weighbridge` status, a manager can open the Pending Weighbridge screen, enter a weight, and confirm the load moves to `completed` status.

**Acceptance Scenarios**:

1. **Given** a load in `pending_weighbridge` status, **When** the manager opens the Pending Weighbridge screen, **Then** the load appears in the list with the guard's submitted details visible.
2. **Given** the manager enters a weighbridge weight and taps "Complete", **Then** the load status changes to `completed` and disappears from the Pending Weighbridge list.
3. **Given** a weighbridge weight is entered that differs from the guard's recorded weight by more than the deviation threshold, **Then** the system flags a deviation alert consistent with existing deviation logic.

---

### User Story 4 — Manager Can Cancel or Edit a Scheduled Load (Priority: P3)

Before a guard begins collection, the manager can cancel a scheduled load (contractor cancelled the pickup) or edit the expected date and notes. Once a guard has started collection (status moves beyond `scheduled`), the load is locked from manager edits.

**Why this priority**: Operational reality — pickups get rescheduled or cancelled. Without this, stale scheduled loads accumulate in the guard's list.

**Independent Test**: A manager can cancel or edit a `scheduled` load and confirm the guard's Incoming list updates accordingly.

**Acceptance Scenarios**:

1. **Given** a load in `scheduled` status, **When** the manager taps "Cancel Load", **Then** the load is removed from the guard's Incoming list and its status changes to `cancelled`.
2. **Given** a load in `scheduled` status, **When** the manager edits the expected date and saves, **Then** the updated date is reflected in the guard's Incoming list.
3. **Given** a load where the guard has already tapped "Begin Collection" (status is transitioning), **When** the manager attempts to cancel it, **Then** the app shows a message that the load is in progress and cannot be cancelled.

---

### Edge Cases

- What happens when two guards attempt to "Begin Collection" on the same scheduled load simultaneously? The first to submit locks the load; the second sees a message that the load is already in progress.
- What happens when the guard submits offline? The submission is queued and synced on reconnect. The load remains in `scheduled` status on the server until the queue processes.
- What happens if a scheduled load has no contractor trucks arriving on the expected date? The manager cancels it (User Story 4). Loads older than 7 days in `scheduled` status are highlighted as overdue in the manager view.
- What happens when the guard's submission fails due to a server error? The guard sees a retry option; the load stays in a local "submitting" state until confirmed.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A Security Manager MUST be able to create a scheduled load containing: contractor, main waste type, expected date, and optional notes — without requiring driver details, items, or photos at creation time.
- **FR-002**: A scheduled load MUST be assigned status `scheduled` upon creation and appear immediately in the Guard's Incoming load list.
- **FR-003**: The Guard's Waste home screen MUST display a dedicated "Incoming" section at the top, showing all loads in `scheduled` status, sorted by expected date ascending.
- **FR-004**: A Security Guard MUST be able to tap a scheduled load and enter "Begin Collection" mode, which adds: driver name, vehicle registration, waste items (subtype, weight, quantity), item photos, and driver signature.
- **FR-005**: Submitting a completed collection MUST transition the load status from `scheduled` to `pending_weighbridge`.
- **FR-006**: The Guard's submission form MUST require at least one waste item with at least one photo before allowing submission — consistent with existing load creation rules.
- **FR-007**: The existing Pending Weighbridge screen MUST display loads in `pending_weighbridge` status (in addition to any existing query logic).
- **FR-008**: A Manager MUST be able to cancel a `scheduled` load, setting its status to `cancelled` and removing it from the guard's Incoming list.
- **FR-009**: A Manager MUST be able to edit the expected date and notes of a `scheduled` load before the guard begins collection.
- **FR-010**: Once a guard begins collection on a load, the load MUST be locked against manager cancellation or editing.
- **FR-011**: The offline queuing system MUST handle guard submissions that occur without connectivity, syncing the full collection data (items, photos, signature) when connectivity is restored.
- **FR-012**: Deviation detection MUST apply when the manager enters the weighbridge weight, comparing against the guard's recorded weight using the existing threshold rules.
- **FR-013**: The existing `draft` + `completed` flow (guard creates load from scratch) MUST remain available as a fallback during transition — both flows coexist.

### Key Entities

- **Scheduled Load**: A `waste_load` document with status `scheduled`, containing contractor, waste type, expected date, optional notes, and the scheduling manager's identity. Driver details, items, and photos are absent at creation.
- **Load Status**: Extended enum — `scheduled` → `pending_weighbridge` are added alongside existing `draft` and `completed`. A `cancelled` status is added for loads cancelled before guard collection.
- **Collection Submission**: The guard's action of adding driver info, items, photos, and signature to a `scheduled` load, atomically transitioning it to `pending_weighbridge`.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A manager can schedule a new incoming load in under 60 seconds from opening the app.
- **SC-002**: A guard can locate an incoming load, complete the full collection (items, photos, signature), and submit in under 5 minutes for a typical single-item load.
- **SC-003**: 100% of guard collection submissions made offline successfully sync to the server when connectivity is restored, with no data loss.
- **SC-004**: Guards no longer need to create loads from scratch for pre-arranged contractor pickups — reducing guard data-entry errors by eliminating duplicate entry of contractor details already known to the manager.
- **SC-005**: The manager's Pending Weighbridge list reflects guard submissions within 30 seconds of a successful online submission.
- **SC-006**: Deviation alerts fire correctly for any weighbridge weight that differs from the guard-recorded weight beyond the existing threshold (5% or 50 kg).

---

## Assumptions

- The existing contractor list, waste type list, and deviation logic are reused without modification.
- The existing offline photo/signature queuing infrastructure in `WasteService` is extended to support the guard's collection submission — no new queuing mechanism is built.
- Both the old (guard creates from scratch) and new (manager schedules, guard completes) flows will coexist during transition; the scheduled flow is opt-in initially.
- The `WasteLoadStatus` enum is the single source of truth for load state; the new statuses (`scheduled`, `pending_weighbridge`, `cancelled`) are additive.
- A load can only be "begun" by one guard at a time; optimistic locking via a Firestore transaction is used to prevent double-collection.
- Manager scheduling is available to Security Managers and Admins; guards cannot create scheduled loads (they can only begin collection on existing ones).
- Notifications to the manager when a guard submits are desirable but deferred to a follow-up; the Pending Weighbridge screen is the primary discovery mechanism.
- The web app (WasteTrack) will reflect the new statuses in its Loads and Reports views without requiring separate web changes beyond status label display.
