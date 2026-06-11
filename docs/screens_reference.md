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

The control panel. Six scrollable tabs with outlined icons.

#### Tab: Employees

- Spreadsheet-style editor for the `employees` collection
- Add / edit / bulk-delete employees
- `isOnSite` column shows a tappable green **"On Site"** / grey **"Off Site"** chip — tap to toggle the employee's status directly
- FCM token visible and editable (for debugging)
- CSV import / export with template download

#### Tab: Structures

- Manages the factory hierarchy stored under `factoryStructure`
- Add/delete Departments, Areas, and Machine/Parts
- Cascading deletes with confirmation dialogs

#### Tab: Settings

Four grouped cards:

- **App Update Control** — `Minimum Supported Build` (int) and `Update Download URL` (string). Written to `settings/app` in Firestore. On app launch, if `currentBuild < minSupportedBuild`, a blocking update screen is shown with the download URL before Home is reached. Works independently of Remote Config.
- **Location** — Force Location Check Now (manually triggers `LocationService.checkCurrentLocation`); Simulate 30-min WorkManager Check
- **Access** — **Escalation Config** per-stage cards with Enable toggle, minutes input, recipient checkboxes (including a *Job Creator (Operator)* option). Writes to `notification_configs/global`. Prompts to confirm when re-enabling stages so open jobs aren't flooded. Writes `enabled_at = now` on any stage transitioning from disabled → enabled. **Reset Escalation Stamps** calls `clearEscalationStamps` CF.
- **Modules** — enable/disable Waste Management and Fleet Maintenance

#### Tab: Job Cards

- Spreadsheet-style export and delete tooling for the `job_cards` collection
- CSV export with full filter applied
- Bulk delete with confirmation

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

Entry point for WasteTrack. Shows load cards grouped by status: **Incoming** (scheduled, awaiting collection), **In Progress** (collection started), **Pending Weighbridge** (waiting for actual weight), and a summary count of Completed loads.

Load list is driven by two live `StreamSubscription`s on `watchLoads()` and `watchScheduledLoads()` — updates are reflected in real time without any manual refresh.

#### Role-based differences

- **Security Manager** — sees all loads; can tap **Schedule Load** to create a new scheduled load; can edit or cancel any scheduled load via bottom sheet
- **Security Guard** — sees only loads ready for collection (scheduled, incoming); tapping a card opens **Begin Collection**
- **Admin** — full visibility; Admin button navigates to **Waste Admin**

#### Key Actions

- **+ New / Schedule** *(FAB)* — bottom sheet with "Schedule Incoming Load" or "New Load (on the spot)"
- **Begin Collection** *(Guard/Admin)* — opens **Waste Begin Collection** for that load
- **⋮ More actions** *(top-right overflow menu)* — Pending Weighbridge, Reports, Waste Admin, Enable/Disable toggle (shown per role). Cloud sync retry button appears alongside when queue is non-empty.
- **All / Today / This Week** filter chips — apply to both scheduled and recent loads; shows "No loads match" empty state with a clear-filter button when active filter returns zero results

### Waste Schedule Load

`lib/screens/waste_schedule_load_screen.dart` — **Roles:** Security Manager, Admin

Form for creating a new scheduled waste load. Saves to `waste_loads` via `WasteService.createLoad` (Cloud Function `createWasteLoad`) which assigns an auto-incremented load number (format: `WT-YYYYMMDD-NNN`).

#### Required Fields

- Contractor (from `waste_contractors`)
- Main waste type (from `waste_types`)
- Scheduled date/time
- Optional notes

### Waste Begin Collection

`lib/screens/waste_begin_collection_screen.dart` — **Roles:** Security Guard, Admin

Opens for a specific scheduled load when a guard taps **Begin Collection**. Transitions the load status from `scheduled` → `pending_weighbridge` on submission. Guard fills in driver name, vehicle reg, adds waste items with photos, and captures the contractor signature.

Add-item uses a `showModalBottomSheet` (not a dialog) for camera stability. Calls `WasteService.submitCollection` which stores `collectedByName` from `currentEmployee.name` on the load document.

### Waste Create Load

`lib/screens/waste_create_load_screen.dart` — **Roles:** Security Guard, Security Manager, Admin

Two-screen flow: **Step 1** selects the main waste type (grid with category-aware icons); **Step 2** fills load details and adds items. A step progress bar is shown at the top of each screen.

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

1. **Amber action banner** — shown only when `status == pendingWeighbridge` and the user is Admin or Manager. Prompts immediate weighbridge entry.
2. **Status stepper** — 4-step horizontal progress bar showing current lifecycle position. Steps vary by flow: `scheduled` loads show (Scheduled → Collecting → Weighbridge → Complete); direct loads show (Created → Signature → Weighbridge → Complete).
3. **Status banner** — coloured icon + type name + status label.
4. **Info card** — driver, vehicle, contractor name (`contractorName` field; falls back to `contractorId`), date, and collector name (`collectedByName` field; falls back to clock number).
5. **Items card** — live `StreamBuilder` on `WasteService.watchItemsForLoad()`. Lists each item: subtype, weight, quantity, photo count.
6. **Weight card** — recorded weight vs. actual weighbridge weight with inline variance row (green if within thresholds, red if deviation).
7. **Weighbridge entry** *(Admin/Manager only, non-terminal status)* — text field + save button.
8. **Mark Complete & Signature button** *(draft status only)* — navigates to **Waste Signature**, then marks load complete.

#### Status actions available per role

| Current status | Guard action | Manager action |
|----------------|-------------|----------------|
| Scheduled | Begin Collection | Edit / Cancel |
| Draft / In Progress | Capture Signature | View |
| Pending Weighbridge | View | Enter Weighbridge Weight (amber banner) |
| Completed | View only | View only |

### Waste Pending Weighbridge

`lib/screens/waste_pending_weighbridge_screen.dart` — **Roles:** Security Guard, Security Manager, Admin

List screen showing all loads in `pending_weighbridge` status. Guard or manager enters the actual weighbridge weight. On save, `WasteService.saveWeighbridgeWeight` computes the deviation, writes the result to `waste_loads`, and triggers a deviation flag if thresholds are exceeded (> 5% or > 50 kg).

### Waste Queued

`lib/screens/waste_queued_screen.dart` — **Roles:** Security Guard, Admin

Shows loads that are queued locally (created or updated offline and not yet synced to Firestore). Reflects the Hive `sync_queue` entries for WasteTrack operations. Guard can review pending items and manually trigger a sync flush.

### Waste Reports

`lib/screens/waste_reports_screen.dart` — **Roles:** Security Manager, Admin

Date-range report of completed loads. Filterable by contractor and waste type.

#### Capabilities

- **Run Report** — queries `waste_loads` with server-side date and status filters
- **Export CSV** — pure-Dart CSV generation, written to device storage
- Deviation-flagged loads are highlighted in the results table

### Waste Admin

`lib/screens/waste_admin_screen.dart` — **Roles:** Admin only

Configuration panel for the WasteTrack module. Three tabs:

| Tab | What it manages |
|-----|-----------------|
| **Manage Types** | Create waste type categories; add sub-types; set active/inactive |
| **Manage Rates** | Set cost rate per kg per waste type; view current rate list |
| **Contractors** | Add/edit contractor records used when scheduling loads |

Writes to `waste_types`, `waste_rates`, and `waste_contractors` collections.

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
