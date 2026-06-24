<!--
Title: CTP Job Cards — Screens Reference
Backfilled from screens_reference.html on 2026-05-18.
-->

# CTP Job Cards — Screens Reference

*Engineering Reference*

---

## Onboarding & Authentication

Screens shown when no user is logged in or during first-launch permission setup.

### Login

`lib/screens/login_screen.dart` — **Roles:** All

Email + password authentication via `FirebaseAuth.signInWithEmailAndPassword`. On successful sign-in, looks up the matching `employees` document by Firebase UID, saves `loggedInClockNo` to `SharedPreferences`, refreshes the FCM token, and routes to either **Permissions Onboarding** (first run) or **Home**.

#### Key Actions

- **Login** — Sign in with email + password
- **Forgot password** — Sends a Firebase Auth reset email
- **Register** — Navigates to the Registration screen

> **Info:** Auto-login: `main.dart` bypasses this screen entirely if `SharedPreferences` has a saved `loggedInClockNo`, OR if `FirebaseAuth.currentUser` is still valid after a reinstall.

### Registration

`lib/screens/registration_screen.dart` — **Roles:** All

New employee sign-up. Creates a Firebase Auth account from email + password, then writes a corresponding `employees` document containing the clock number, name, position, and department.

#### Required Fields

- Email, password
- Clock number (must match the employee record in HR)
- Name, position, department

> **Warning:** Admins should pre-populate the `employees` collection. Self-registration only links an Auth account to an existing record; it does not grant any role.

### Permissions Onboarding

`lib/screens/permissions_onboarding_screen.dart` — **Roles:** All (first launch)

Seven-page swipeable walkthrough shown after first login (and after registration). Explains the app, branches on the user's role, then requests critical Android permissions.

#### Pages

1. **Welcome** — app intro
2. **Your Role** — role-specific overview (Technician / Manager / Operator / Admin)
3. **Job Card Flow** — end-to-end creation → resolution walkthrough
4. **Job Status** — explains Open / In-Progress / Monitor / Closed
5. **Priority Levels** — P1–P5 with notification behaviour for each
6. **Escalation** — 4-stage timeline with default timers
7. **Grant Permissions** — Notifications, System Alert Window, DND override, Battery Unrestricted, Background Location, Exact Alarms

> **Note:** Sets `permissionsCompleted: true` in `SharedPreferences` only if `locationAlways` permission was actually granted — if it is denied, the screen reappears on next launch. Also fires `LocationService.startNativeMonitoring()` and `checkCurrentLocation()` on completion.

---

## Core Job Card Flow

The screens every technician and most managers use day-to-day.

### Home

`lib/screens/home_screen.dart` — **Roles:** All logged-in users

The main hub after login. Shows the logged-in employee, a live **On-Site / Off-Site** indicator, an employee directory, and a grid of tiles to navigate everywhere else.

#### Standard Tiles

- `Create Job Card` — **hidden when the employee is off-site** (`isOnSite: false`); off-site employees must be on-site to create new jobs
- `My Assigned Jobs`
- `View Job Cards`
- `Job History` — server-filtered search of closed job cards (see [Job Card History](#job-card-history))
- `Settings`

#### Manager-Only Tiles

- `Manager Dashboard` — shown when `position` contains "manager"
- `Monitoring Dashboard`
- `Daily Review` with pulse animation when pending count > 5

#### Admin-Only Tiles

- `Admin` — shown when the logged-in employee is on the admin whitelist

> **Info:** The On-Site indicator reflects the live value of `employees/{clockNo}.isOnSite`, which is driven by background geofencing in `location_service.dart`.

> **Notification bell** — a bell icon in the AppBar shows a live badge with the count of unread inbox items. Tapping it opens the [Notification Inbox](#notification-inbox). When the employee's `isOnSite` transitions from `false` to `true`, a SnackBar appears with the unread count and an "Open" shortcut if items are waiting.

### Create Job Card

`lib/screens/create_job_card_screen.dart` — **Roles:** All

Form for raising a new job card. The factory structure (department → area → machine → part) is loaded from Firestore, and previously-used parts for the selected machine are suggested.

#### Required Fields

- Department, Area, Machine, Part
- Job Type — `Mechanical`, `Electrical`, `Mech/Elec ?`, `Maintenance`
- Priority (1–5)
- Operator name + clock number
- Description
- Optional photos (per section)

#### Offline Behaviour

The screen checks connectivity on open and before save. If offline, a full-width red banner is shown and the Save button is disabled. Job card creation intentionally blocks offline because the notification pipeline cannot fire without a Firestore write — technicians would not be alerted. The form state is preserved so nothing is lost when moving to signal.

The Home tile also shows a disabled-with-reason state when offline or off-site (rather than hiding).

#### What Happens On Save

- Calls `FirestoreService.saveJobCardOfflineAware` → runs a transaction that increments the global `counters/jobCards.nextJobCardNumber` and writes the doc
- The `onJobCardCreated` Cloud Function trigger fires and dispatches initial notifications based on `creation_recipients_by_type`

#### Sidebar Widget

- **Similar Job Cards** — wide-layout sidebar streams matching closed/monitor cards as the form is filled, server-filtered by department → area → machine → part to prevent duplicate jobs without downloading the full collection

### My Assigned Jobs

`lib/screens/my_assigned_jobs_screen.dart` — **Roles:** Technicians (primary)

The technician's personal queue. Two tabs:

#### Tabs

- `Assigned` — Active cards where the technician's clock number is in `assignedClockNos`
- `History` — Jobs the technician has worked on or completed

#### Per-Card Actions

- Tap to open **Job Card Detail**
- Quick "Self-Assign" if a job is unassigned and the technician's skill matches
- Mark as "Busy" — fires a notification back to the creator via the `alertResponses` collection and sets `escalationStopped: true`

### Job Card Detail

`lib/screens/job_card_detail_screen.dart` — **Roles:** All

Full view of a single job card. The most feature-rich screen in the app.

#### App Bar

Gradient: orange → green (on-site) / red (off-site). The tab bar sits in the body (not pinned to the app bar chrome) — consistent with the View Job Cards pattern.

#### Sections

- **Header** — Job #, status, priority, type, department, area, machine, part
- **Description & notes** — editable inline by assignees
- **Photos** — before/during/after sections, tap to open full-screen viewer
- **Assignment** — assign to one or more technicians; selector orders by `isOnSite` first, then position
- **Status workflow** — Open → In Progress → Monitoring → Closed
- **Assignment history** — timestamped list of who was assigned/unassigned
- **Comments & reviewedBy**
- **Related Jobs** tab pair (`My Department`, `All Factory`) — surfaces same-machine/area history

#### Notifications Triggered Here

- Assigning a job → `sendJobAssignmentNotification` Cloud Function call. If the assignee is **off-site**, the notification is parked in their [Notification Inbox](#notification-inbox) instead of sent as a push.
- Closing/updating → `sendCreatorNotification` to the original creator. If the creator is off-site, parked to inbox.
- Both also trigger `onJobCardAssigned` which sets `escalationStopped: true` regardless of delivery method.

### View Job Cards

`lib/screens/view_job_cards_screen.dart` — **Roles:** All

Browse every job card in the system. Four status tabs with live counts; filters for department, area, machine, type, priority, date range.

#### App Bar

Gradient: orange → green (on-site) / red (off-site). Toggle buttons for filtering have a black border for visibility.

#### Tabs (in body, not pinned to app bar)

- `Open`
- `In Progress`
- `Monitoring`
- `Closed`

#### Capabilities

- Tap any card to open **Job Card Detail**
- Filter and search across all factory structure levels
- Wide-layout view with split master/detail on tablets

### Job Card History

`lib/screens/job_card_history_screen.dart` — **Roles:** All

Searchable archive of all closed job cards with server-side filtering to minimise Firestore read costs. Accessible via the **Job History** quick-action tile on the Home screen.

#### Server-Side Filters (trigger a new Firestore fetch)

| Filter | Options | Notes |
|--------|---------|-------|
| Date Range | Last 7 days / Last 30 days / Last 90 days / Custom / All time | Default: Last 30 days |
| Department | All or specific department chip | Cascading — enables Area when selected |
| Area | All or specific area chip | Cascading — enables Machine when selected |
| Machine | All or specific machine chip | — |

Each filter combination maps to a composite Firestore index. Fetches at most **50 documents per page** ordered by `closedAt` descending. Tap **Load More** for cursor-based pagination.

#### Client-Side Refinement (applied to current page, zero additional reads)

- **Type** — Mechanical / Electrical / Mech-Elec / Maintenance chips
- **Priority** — P1–P5 chips, colour-coded
- **Free-text search** — searches description, machine, part, notes, operator name, and job card number across the fetched result set

#### Navigation

Tap any result to open **Job Card Detail** in full read-only (or write-capable if the user has the right role).

### Daily Review

`lib/screens/daily_review_screen.dart` — **Roles:** Manager

Daily sign-off queue for managers. Each closed/monitored job needs a manager review checkmark — this screen surfaces what's still pending.

#### Tabs

- `Pending Review (N)` — Cards the logged-in manager hasn't marked yet
- `Reviewed` — Already-marked cards

Switching tabs clears the selected card and resets the input field.

#### Layout

Responsive two-panel layout:

- **Narrow (< 700 px)** — list and detail stack vertically. Selecting a card pushes the detail panel with a back button.
- **Wide (≥ 700 px)** — list on the left, detail on the right simultaneously.

#### Date Range Filter (Reviewed tab)

A single **date range picker** produces a deletable chip showing the selected range. Clearing the chip removes the filter. The previous two separate date pickers have been replaced by this single control.

#### App Bar

Gradient: orange (left) → **green** (on-site) or **red** (off-site). Title shows the scope label, e.g. "Daily Review — Mechanical Jobs — Factory Wide".

#### Monitor Status Badge

Cards in Monitor status display an **amber** badge (not green) to distinguish "watching" from "resolved".

#### Mark-on-View

A job card is stamped `reviewedBy.{clockNo}: true` the moment the manager selects it in the list — not when the screen loads. The `Pending Review (N)` count decrements immediately as cards are opened. No explicit "mark as reviewed" button is needed.

#### Filter Logic

- Mechanical Manager: sees cards where job type is Mechanical or Mech/Elec
- Electrical Manager: sees cards where job type is Electrical or Mech/Elec
- Other Managers: sees cards in their own `department`

> **Info:** The Home tile for Daily Review has a pulsing red animation when the pending count is above 5 — a visual nudge to keep the queue clean.

---

## Manager & Admin

Dashboards and tooling for oversight roles.

### Manager Dashboard

`lib/screens/manager_dashboard_screen.dart` — **Roles:** Manager

KPI rollups and analytics for the manager's domain. Filters sit at the top; below them are collapsible KPIs, then an analytics section.

#### Filters (above KPIs)

- **Department filter** — chip-based multi-select. Defaults to the logged-in manager's own department. Selecting "All Departments" removes the department constraint.
- **Date range** — choice chips: 7 Days / 30 Days / All Time (default 30 days).

#### KPI Cards (9 cards, collapsible section)

Each tappable KPI opens a filtered job list for that subset. Non-tappable KPIs display a computed value only.

| KPI | What it counts | Tappable |
|-----|----------------|----------|
| Open Jobs | All open (non-closed) jobs in scope | Yes |
| High Priority | Open P4 + P5 jobs | Yes |
| Monitoring | Jobs at Monitor status | Yes |
| Closed Today | Jobs closed today | Yes |
| Pending Assign | Open jobs with no assigned technician | Yes |
| Avg Resolution | Average hours/days from creation to close | No |
| Overdue >3d | Open jobs older than 3 days | Yes |
| Overdue >7d | Open jobs older than 7 days | Yes |
| Completion % | Closed / total in date range | No |

On phones (< 600 px wide) the KPI grid shows 3 columns; on wider screens it shows 6.

#### Analytics Section

- **Open Jobs by Day** — area chart of open job count over the last 30 days. Respects the department filter; date-range filter is intentionally excluded so the chart shows accurate historical stock levels.
- **Trendline** — line chart of opened vs. closed jobs over the selected period, with a legend.
- **Department Area Chart** — area breakdown of open jobs by department.
- **Priority Breakdown** — bar chart of open jobs per priority level, labelled P1 Low / P2 Med / P3 Mid / P4 High / P5 Crit.
- **Team Performance** — table showing each technician (by name): closed count, average resolution time, and currently assigned count. Sorted by closed count descending. Assigned count > 3 is highlighted in orange.

### Monitoring Dashboard

`lib/screens/monitoring_dashboard_screen.dart` — **Roles:** Manager

Visibility into the "Monitoring" state — jobs that were marked completed but kept open for 7 days to confirm the fix held.

#### Tabs

- `Active Monitoring` — Jobs currently in the 7-day monitoring window
- `Recently Auto-Closed` — Jobs the `autoCloseMonitoringJobs` scheduler closed in the last 7 days

> **Note:** `autoCloseMonitoringJobs` runs daily at 08:00 SAST in `europe-west1`. It closes any monitoring job that hasn't had updates for 7 days since `monitoringStartedAt`, appending an auto-close note to `notes`.

### Admin

`lib/screens/admin_screen.dart` — **Roles:** Admin only

The control panel. Five scrollable tabs with outlined icons. Opens on **Settings** by default (`initialIndex: 0`). Tab order: **Settings → Employees → Structures → On Site → Comms**.

> **Job card export / bulk delete** is not in Admin on mobile. Use **CTP Pulse** (`/jobs`) for read-only job oversight, history, and exports.

#### Tab: Settings

Grouped cards (default tab):

- **App Update Control** — `Minimum Supported Build` (int) and `Update Download URL` (string). Written to `settings/app` in Firestore. On app launch, if `currentBuild < minSupportedBuild`, a blocking update screen is shown with the download URL before Home is reached. Works independently of Remote Config.
- **Location** — Force Location Check Now (manually triggers `LocationService.checkCurrentLocation`); Simulate 30-min WorkManager Check
- **Access** — **Escalation Config** per-stage cards with Enable toggle, minutes input, recipient checkboxes (including a *Job Creator (Operator)* option). Writes to `notification_configs/global`. Prompts to confirm when re-enabling stages so open jobs aren't flooded. Writes `enabled_at = now` on any stage transitioning from disabled → enabled. **Reset Escalation Stamps** calls `clearEscalationStamps` CF.
- **Modules** — enable/disable Waste Management and Fleet Maintenance
- **Feedback** — opens the **User Feedback** admin board (see [User Feedback](#user-feedback)) for reviewing and triaging feedback submitted from the Home screen FAB

#### Tab: Employees

- Searchable **card list** for the `employees` collection (lazy-loaded on first visit to the tab)
- Toolbar card: search field, CSV template download, import, bulk delete when rows are selected
- Each card: clock number badge, name, position · department, on-site / off-site pill (tap to toggle), edit and delete actions
- Add / edit via dialog; FCM token editable in the edit dialog only (not on the list row)
- Checkbox per card for bulk delete selection

#### Tab: Structures

- Manages the factory hierarchy stored under `factoryStructure`
- Search box and stats chips (department / area / machine counts)
- Expandable department cards with nested areas and machines/parts
- Add-new department, area, and machine forms in `_settingsCard` panels; duplicate-name validation
- Delete with cascading confirmation dialogs; structure reloads after deletes

#### Tab: On Site

- Real-time view of every employee currently marked `isOnSite: true`
- Grouped by department with a green header showing the total on-site count
- Each row shows: name, position, clock number
- Updates live as employees clock in and out

#### Tab: Comms

- **Broadcast Update Notice** card — editable title and body fields (pre-filled with the standard update message); **Send Broadcast** button calls the `broadcastUpdateNotice` Cloud Function (`africa-south1`). Admin-gated (`isAdmin: true` on employee doc). After sending, a result card shows: `sent` (push delivered), `parked` (held in inbox for off-site users), `noToken` (no FCM token registered), `total` counts.
- **Recent Broadcasts** — live stream from the `notifications` collection filtered to `triggeredBy == 'update_notice'`, sorted by `createdAt` descending, limited to last 10.

### Geofence Editor

`lib/screens/geofence_editor_screen.dart` — **Roles:** Admin only

Map-based editor for the factory geofence boundary stored in `config/geofence`. The native Android `GeofenceHelper` reads this to decide on-site vs off-site.

#### Capabilities

- Drop a centre point on the map (or enter lat/long)
- Adjust radius via slider
- Save writes `config/geofence` with the new `center.lat`, `center.lng`, `radius_meters`

> **Warning:** Changing the geofence affects every employee's `isOnSite` on their next location check. If you shrink the radius, people currently inside the old boundary may flip to `isOnSite: false` within minutes.

### User Feedback

`lib/screens/feedback_admin_screen.dart` — **Roles:** Admin only

Internal triage board for the feedback employees submit via the **Give Feedback** FAB on the Home screen (written to the `feedback` collection). Reached from **Admin → Settings → Feedback**. Gated on `Employee.isAdmin` — regular staff never see it; they only get the "feedback submitted" confirmation.

#### Capabilities

- **Status workflow** — set each item to `New → Planned → Implemented → Declined`. Legacy items submitted before this screen existed show as `New` until triaged.
- **Implementation notes** — attach private notes to any item (what was done, what's planned, or why it was declined), edited in a dialog.
- **Filter bar** — per-status chips with live counts (`All`, `New`, `Planned`, `Implemented`, `Declined`) to separate outstanding from done.
- **Delete** — remove a submission via the per-card overflow menu.

> **Info:** Triage actions add `status`, `statusUpdatedAt`, `statusUpdatedByClockNo`, `adminNotes`, `adminNotesUpdatedAt`, and `adminNotesByClockNo` to the feedback document — the original `feedback` / `userName` / `clockNo` / `timestamp` fields are never modified. Filtering is client-side, so no Firestore composite index is required.

---

## Configuration & Utilities

Per-user preferences, diagnostics, and developer tools.

### Settings

`lib/screens/settings_screen.dart` — **Roles:** All

Per-user preferences and self-service tooling. Organised into labelled sections:

#### Sections

- **Your Profile** — current user info (name, clock, department), live on-site / off-site indicator, link to Documentation
- **Preferences** — Dark/Light mode toggle (writes to Riverpod theme provider)
- **Notifications** — link to [Notification Inbox](#notification-inbox) with live unread count badge; link to [Notification Tests](#notification-tests)
- **App & Connectivity** — Reset Permissions, Check for Update, Refresh FCM Token
- **App Permissions** — live status for Notifications, System Alert Window, Notification Policy, Battery Optimisation. Tapping any row jumps to the OS settings page
- **Modules** *(Admin only)* — enable/disable **Waste Management** (writes `wasteTrackEnabled` to SharedPreferences) and **Fleet Maintenance** (writes `fleet_enabled` to `fleet_settings/config` in Firestore). Turning a module off hides its tab from all users immediately.
- **Admin** *(Admin only)* — amber-bordered card containing links to Admin Settings and Notification Diagnostics
- **Account** — Log Out

### Notification Inbox

`lib/screens/notification_inbox_screen.dart` — **Roles:** All

Shows notifications that were held because the employee was off-site at the time of delivery. Accessible from the bell icon in the Home screen AppBar (with live unread badge) and from the Notifications section in Settings.

#### Layout

- **Unread** section at the top — highlighted with a coloured border and an orange dot indicator; "Mark all read" action in header
- **Earlier** section — previously-read items in muted style
- Empty state: "You're all caught up" with a green check icon

#### Per-item Actions

- **Tap** — marks item as read and navigates to the relevant job card (if one exists)
- **Mark all read** — batch-marks every unread item via a Firestore batch write

#### Notification Types Displayed

| Type | Icon | Colour |
|------|------|--------|
| `job_assigned` | Person + job card | Blue |
| `job_closed` | Check circle | Green |
| `self_assigned` | Person add | Teal |
| `job_updated` | Edit note | Deep Orange |
| `busy_response` | Do-not-disturb | Red |
| `copper_sell` | Coin | Amber |

#### Data Source

`notification_inbox/{clockNo}/items` — subcollection per employee. Writes are created by Cloud Functions (not the Flutter app). Items persist until manually marked read; they are not auto-deleted.

### Notification Tests

`lib/screens/notification_test_screen.dart` — **Roles:** All

Extracted self-contained screen for triggering the three notification delivery modes on the current device. Accessible from Settings → Notifications → Notification Tests.

- **Full Screen Alert** (P5) — bypasses DND, takes over screen
- **Persistent Notification** — red banner with action buttons
- **General Notification** — standard banner

### Notification Diagnostics

`lib/screens/notification_diagnostics_screen.dart` — **Roles:** Admin

Developer/admin tool for verifying the notification + geofence stack works end-to-end on a device.

#### Tests Available

- **Test ENTER** — simulates a geofence enter event. Writes to `geo_fence_logs` and flips `isOnSite: true` on the current employee
- **Test EXIT** — simulates an exit event. Flips `isOnSite: false`
- **Force FCM Token Refresh**
- **Print current employee state** — dumps clock no, position, isOnSite, fcmToken

> **Tip:** Use this when you need to test the escalation system but the device isn't physically inside the geofence. Hit Test ENTER and the next escalation cycle will treat the user as on-site.

---

## WasteTrack Module

Screens for the waste management feature. Accessible via the **Waste** tab in the bottom navigation bar. Roles: Security Manager (`department == "Security"` && `position == "Manager"`), Security Guard (`department == "Security"` && `position == "Guard"`), and Admin. Other employees do not see the Waste tab.

### Waste Home

`lib/screens/waste_home_screen.dart` — **Roles:** Security Manager, Security Guard, Admin

Entry point for WasteTrack (single **Loads** tab). Shows load cards grouped by status: **Incoming** (scheduled), **Recent** (draft, pending queues, completed). **Security managers and admins** also see a **Copper ready to sell** panel and an **on-site stock** banner (guards do not — they link stock at collection only).

Load list is driven by live streams on `watchLoads()` and `watchScheduledLoads()` — updates reflect in real time without manual refresh. Pending weighbridge and cost-review loads show a **CTP Pulse handoff** banner on detail — those queues are not processed on mobile.

#### Role-based differences

- **Security Manager** — schedule, on-the-spot loads, browse on-site stock inventory, copper ready panel, link stock at collection, finish loading
- **Security Guard** — schedule, begin collection, **From stock** at collection (no inventory browse), items, photos, signature, submit
- **Admin** — same as manager on mobile; weighbridge, cost review, settings on **CTP Pulse**

#### Key Actions

- **+ New / Schedule** *(FAB)* — bottom sheet: "Schedule Incoming Load" or "New Load (on the spot)"
- **Begin Collection** — opens **Waste Begin Collection** for a scheduled load
- **On-site stock** banner *(manager/admin)* — opens stock inventory
- **Copper ready to sell** panel *(manager/admin)* — live copper sell bucket + on-site copper waste stock after 400 kg threshold
- **⋮ More actions** — cloud sync retry when offline queue is non-empty (weighbridge/reports/admin removed 2026-06-22)
- **All / Today / This Week** filter chips — apply to scheduled and recent loads

### Waste Schedule Load

`lib/screens/waste_schedule_load_screen.dart` — **Roles:** Security Manager, Security Guard, Admin

Form for scheduling an incoming load before the truck arrives. Saves to `waste_loads` via `WasteService.createLoad` (Cloud Function `createWasteLoad`) which assigns a global sequential load number (format: `W-NNNN`, never resets).

#### Required Fields

- Contractor (from `waste_contractors`)
- **Waste types** — multi-select chips; stored as `selected_waste_types`
- Expected date (admins may pick past dates for corrections)
- Optional on-site stock pre-link and notes

### Waste Begin Collection

`lib/screens/waste_begin_collection_screen.dart` — **Roles:** Security Guard, Security Manager, Admin

Opens when a user taps **Begin Collection** on a scheduled load. Supports **From stock** for paper, **IBC Bins**, and **Copper Waste** (guards can link here without browsing inventory). On submission: weight-based / no-on-site-weight loads → `pending_weighbridge`; quantity-only loads → `pending_cost_review` (weighbridge skipped). Respects `photos_required` and `signature_required` from Pulse settings.

Add-item uses a `showModalBottomSheet` (not a dialog) for camera stability. Calls `WasteService.submitCollection` which stores `collectedByName` from `currentEmployee.name` on the load document.

### Waste Create Load

`lib/screens/waste_create_load_screen.dart` — **Roles:** Security Guard, Security Manager, Admin

Single-screen flow: contractor, multi-select waste types (`selected_waste_types`), optional stock, driver/vehicle, and items via bottom sheet.

Add-item uses `showModalBottomSheet` (camera-safe). Subtypes are loaded dynamically from the selected `WasteType.subtypes` — not hardcoded.

On successful save, `saveCompleteWasteLoad` returns the new load ID. The screen immediately fetches the full load and `pushReplacement`s to **Waste Load Detail** so the user can capture the signature without navigating back through the home screen.

`contractor_name` is stored on the load document at save time (looked up from the `_contractors` list by the selected `_contractorId`).

#### Key Actions

- **Add Item** — slide-up sheet: select subtype, enter weight, attach photo(s)
- **Remove Item** — tap × on item card
- **Create Load** — validates required fields and items, saves via `saveCompleteWasteLoad`, navigates to detail on success
- Offline: item writes are queued via `SyncService` if connectivity is lost

### Waste Signature

`lib/screens/waste_signature_screen.dart` — **Roles:** Security Guard, Admin

Full-screen signature capture. The contractor driver signs directly on the phone screen. Signature is stored as a PNG byte array, uploaded to Firebase Storage under `waste/{loadId}/signature/`, and the download URL is saved to the load document.

### Waste Load Detail

`lib/screens/waste_load_detail_screen.dart` — **Roles:** All WasteTrack roles

Full detail view of a single waste load.

#### Layout (top to bottom)

1. **Pulse handoff banner** — when `status == pendingWeighbridge` or `pendingCostReview`, directs manager/admin to CTP Pulse (weighbridge + cost review are not on mobile).
2. **Status stepper** — lifecycle position; mobile stops at pending queues.
3. **Status banner** — coloured icon + type name + status label.
4. **Info card** — driver, vehicle, contractor name (`contractorName` field; falls back to `contractorId`), date, and collector name (`collectedByName` field; falls back to clock number).
5. **Items card** — live `StreamBuilder` on `WasteService.watchItemsForLoad()`. Lists each item: subtype, weight, quantity, photo count.
6. **Weight card** — recorded weight vs. actual weighbridge weight with inline variance row (green if within thresholds, red if deviation).
7. **Finish loading** *(draft status)* — optional truck photos + signature per `photos_required` / `signature_required` settings.

#### Status actions available per role

| Current status | Guard action | Manager action |
|----------------|-------------|----------------|
| Scheduled | Begin Collection | Edit / Cancel |
| Draft / In Progress | Capture Signature | View |
| Pending Weighbridge | View (Pulse handoff) | View (Pulse handoff) |
| Pending Cost Review | View (Pulse handoff) | View (Pulse handoff) |
| Completed | View only | View only |

> **Removed 2026-06-22:** `waste_pending_weighbridge_screen`, `waste_review_screen`, `waste_reports_screen`, `waste_admin_screen` — weighbridge, cost review, reports, and settings live on **CTP Pulse** only.

### Waste Stock Inventory

`lib/screens/waste_stock_inventory_screen.dart` — **Roles:** Security Manager, Admin *(not Security Guard)*

Lists on-site `waste_stock` items: manual paper stock, auto **IBC Bins** from ink consume (`stock_ibc_{n}`), and auto **Copper Waste** after the 400 kg threshold (`visibility: manager_only`). Guards are directed to link stock at collection instead.

### Waste Queued

`lib/screens/waste_queued_screen.dart` — **Roles:** Security Guard, Admin

Shows loads that are queued locally (created or updated offline and not yet synced to Firestore). Reflects the Hive `sync_queue` entries for WasteTrack operations. Guard can review pending items and manually trigger a sync flush.

---

## Ink Factory Module

Screens for the Ink Factory stock-inventory module. Accessible via the **Ink Factory** home tile (Ink Factory department staff) and the **Daily Readings** home tile (Lurgi department staff). Roles: Ink operator (`department == "Ink Factory"`), Ink manager (position contains "manager" in the Ink Factory department), Lurgi user (`department == "Lurgi"`), and Admin. Other employees do not see these tiles.

### Ink Home

`lib/screens/ink_home_screen.dart` — **Roles:** Ink operator, Ink manager, Admin, Lurgi (via Daily Readings tile only — not this hub)

Operator **capture hub** on mobile. Management, costing, and month-end workflows live on **CTP Pulse** (`https://ctp-pulse.web.app/ink`), opened via the **Management & costing** card.

#### Layout

- **Stock on hand** summary — item count (not total rand value on mobile)
- **Management & costing** — opens CTP Pulse in the browser (month-end, pending costs, recipes, reports, adjustments)
- **Meter reminder banner** — shown when today's ink meter readings are not yet recorded (links to Daily Readings)
- **Capture** action grid (seven tiles below)
- **Stock on hand** list — each row shows balance and unit; tap opens item ledger detail (recent movements only, bounded query)

#### Capture tiles

| Tile | Screen |
|------|--------|
| Receive Stock | `InkReceiveRawMaterialScreen` |
| Receive Ink (IBC) | `InkReceiveIbcScreen` |
| Meter Readings | `InkDailyReadingsScreen` (combined ink + Toloul) |
| Consume IBC | `InkIbcTransferScreen` |
| Production Run | `InkProductionRunScreen` |
| Toloul Recovery | `InkTolulRecoveryScreen` |
| IBC Register | `InkIbcRegisterScreen` |

> **Money gating:** WAC, stock value, and cost fields are hidden from operators on mobile. Managers enter costs, run month-end, and adjust stock on **CTP Pulse**, not in the Job Cards app.

---

### Daily Readings (combined meter screen)

`lib/screens/ink_daily_readings_screen.dart` — **Roles:** Ink operator, Ink manager, Lurgi user, Admin

Single combined screen for all daily meter readings. Shown via the **Daily Readings** home tile for Lurgi staff and via the **Meter Readings** capture tile in the Ink hub for Ink Factory staff.

#### Layout

- **Reading date** — shared date/time for all entries. Managers and admins can edit it; operators see it as a read-only label.
- **INK METERS section** — one card per metered stock item (Yellow, Red, Blue, Black, Gravure Binder). Each card shows a horizontal history strip of the last four readings, a new-reading text field, a live preview of litres consumed and kg deducted, an over-max warning if the consumption exceeds the configured daily limit, and a "meter was reset" checkbox when the reading drops below the last.
- **TOLOUL METERS section** — same card pattern for each active Toloul meter point (Recovery and Usage points). These record cumulative meter readings; consumption is the delta and is used for month-end Toloul totals only — no stock effect.
- **Record readings** button at the bottom submits all filled entries in one tap. Blank fields are skipped — partial submissions are allowed.

#### Submission

Ink meter entries are written as `consumption_meter` transactions to the ink ledger. Toloul meter entries are written to `ink_meter_point_readings`. Both are submitted in a single handler. Closed-period override check runs once before either batch is written.

---

### Toloul Recovery

`lib/screens/ink_toloul_recovery_screen.dart` — **Roles:** Ink operator, Ink manager, Admin

Captures a Toloul recovery event — solvent recovered from the Lurgi distillation and returned to stock. Written as a `recovery` transaction (additive, at the current WAC — recovery never changes WAC).

#### Fields

- **Solvent** — dropdown of active solvent items (auto-selects Toloul when it's the only one)
- **Volume recovered** — quantity in the item's unit (LTS)
- **Lurgi / source** — free-text note, optional (e.g. "Lurgi 2")
- **Effective date** — date/time picker

#### Recent Recoveries

The last 15 non-voided recovery entries are shown below the form. Each row shows volume, source, date, and actor name. The INK#### sequence number appears when the server has assigned it. This list updates live — entries appear immediately after a successful submit.

The form stays open after submit (fields clear, date resets to now) to allow back-to-back entries without navigation.

---

### Ink Meter Point Entry (standalone)

`lib/screens/ink_meter_point_entry_screen.dart` — **Roles:** Ink operator, Ink manager, Lurgi user, Admin

Standalone Toloul meter point entry screen, available as a fallback but no longer linked from the main navigation. The combined `InkDailyReadingsScreen` is the primary path for Toloul meter entry.

---

### Ink Meter Readings Grid (standalone)

`lib/screens/ink_meter_readings_grid_screen.dart` — **Roles:** Ink operator, Ink manager, Admin

Standalone ink meter readings screen, available as a fallback. The combined `InkDailyReadingsScreen` is the primary path for daily ink meter entry.

---

### Production Run

`lib/screens/ink_production_run_screen.dart` — **Roles:** Ink operator, Ink manager, Admin

Operator picks a recipe (CoverWax or Gravure Binder) and a pot count (1 / 2 / 3). The screen previews the inputs consumed and the output produced with an estimated cost (managers only). Submitting records a `consumption_production` transaction per input and a `manufacture` transaction for the output. The 10 most recent production runs are shown below the form as a history list.

---

### Receive Ink (IBC)

`lib/screens/ink_receive_ibc_screen.dart` — **Roles:** Ink operator, Ink manager, Admin

Scans ink IBCs (GS1-128 barcode labels). The barcode parser reads the SSCC (IBC number), weight, charge number, and colour from the label. Multiple IBCs can be scanned and batched before submitting. On submit, one cost-pending `purchase` transaction is written per colour for the total kg received, and each IBC is registered in the IBC audit register.

---

### IBC Register

`lib/screens/ink_ibc_register_screen.dart` — **Roles:** Ink operator, Ink manager, Admin

Searchable register of all ink IBCs, tabbed by colour (Yellow / Red / Blue / Black). Each tab shows IBC numbers with receive date, charge number, order number, CGNA, and status. A status filter chip (All / Received / Consumed) sits above the tabs. Managers can **void consumption** — this auto-disposes the linked `waste_stock` item if still on site.

### Consume IBC (Waste cross-link)

`lib/screens/ink_ibc_transfer_screen.dart` — **Roles:** Ink operator, Ink manager, Admin

Marks an IBC as consumed (transferred to tank). Atomically creates `waste_stock/stock_ibc_{number}` as an **IBC Bins** on-site item (qty 1, no stock photo). Security links it to a waste load on **collection day** via **Begin Collection → From stock**.

---

### Pending Costs

`lib/screens/ink_pending_costs_screen.dart` — **Roles:** Ink manager, Admin

Lists all `purchase` transactions still in `cost_status: pending` (invoice not yet received). Manager enters the total cost; the server re-runs the WAC replay from that transaction forward to incorporate the finalised cost.

---

### Month-end Report

`lib/screens/ink_month_end_report_screen.dart` — **Roles:** Ink manager, Admin

Free date-range report using count events as period boundaries. Shows opening WAC/balance/value, purchases, manufacturing, consumption, recovery, adjustments, revaluations, and closing balance per item. Exports as Summary CSV, Summary PDF, or full Transaction-list PDF. Toloul Recovery and Toloul Usage totals for the period are shown at the bottom.

---

### Stock Item Detail

`lib/screens/ink_stock_item_detail_screen.dart` — **Roles:** Ink operator (qty only), Ink manager (qty + money), Admin

Full ledger for one item, oldest-effective first. Shows balance and WAC after each transaction. Flagged transactions are highlighted. Accessible by tapping any item in the Ink hub stock list.

---

## Cross-Cutting Concerns

Behaviour that affects multiple screens.

### Gradient App Bar & On-Site Indicator

Every authenticated screen uses a gradient `AppBar` defined in `app_theme.dart`: orange (`kBrandOrange`) on the left fading to **green** when `currentEmployee.isOnSite == true`, or **red** when off-site. This is a persistent visual cue — any screen in the app immediately communicates the user's current on-site status via the app bar colour.

### Role-Based Visibility

*Canonical logic in `lib/utils/role.dart` (`roleFromEmployee()`)*

Roles are inferred from the `position` and `department` fields on `employees/{clockNo}` — there is no explicit role field. Inference order:

- **Admin** — restricted by admin whitelist (also gated in `SettingsScreen`)
- **Manager** — `position` contains `"manager"` (case-insensitive)
- **Technician** — `position` contains `"mechanical"`, `"electrical"`, or `"technician"` (case-insensitive)
- **Operator** — everyone else (default catch-all)

Additional flags: `isSuperManager()` → `department == "general"` (factory-wide manager view).

### Offline-First Saves

*`SyncService` + Hive `sync_queue`*

Any screen that writes to Firestore (Create Job Card, Job Card Detail, etc.) goes through `FirestoreService.saveJobCardOfflineAware` or the equivalent. If `connectivity_plus` reports offline, the write is queued to the Hive `sync_queue` box. When connectivity returns, `SyncService` replays the queue.

### Audit Log

*`job_card_audit` collection*

Every write to `job_cards` via `FirestoreService` appends a corresponding entry to `job_card_audit`. Future read screens could surface this for forensic / compliance use.

---

*CTP Job Cards · Screens Reference · Engineering documentation*
