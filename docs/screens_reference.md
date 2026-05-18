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

Three-page swipeable walkthrough shown after first login. Explains the app, asks for critical Android permissions, then routes to Home.

#### Pages

- **Welcome** — app intro
- **How It Works** — explains job alerts, on-site/off-site behaviour, escalation
- **Grant Permissions** — Notifications, System Alert Window (full-screen alerts), Notification Policy (DND bypass), Battery Optimisation, Background Location

> **Note:** Sets `permissionsCompleted: true` in `SharedPreferences` on completion. `main.dart` checks this flag plus `locationAlways` permission — if either is missing, this screen reappears on next launch.

---

## Core Job Card Flow

The screens every technician and most managers use day-to-day.

### Home

`lib/screens/home_screen.dart` — **Roles:** All logged-in users

The main hub after login. Shows the logged-in employee, a live **On-Site / Off-Site** indicator, an employee directory, and a grid of tiles to navigate everywhere else.

#### Standard Tiles

- `Create Job Card`
- `My Assigned Jobs`
- `View Job Cards`
- `Closed Jobs`
- `Copper Dashboard`
- `Settings`

#### Manager-Only Tiles

- `Manager Dashboard` — shown when `position` contains "manager"
- `Monitoring Dashboard`
- `Daily Review` with pulse animation when pending count > 5

#### Admin-Only Tiles

- `Admin` — shown when the logged-in employee is in the admin list (clock no 22)

> **Info:** The On-Site indicator reflects the live value of `employees/{clockNo}.isOnSite`, which is driven by background geofencing in `location_service.dart`.

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

#### What Happens On Save

- Calls `FirestoreService.saveJobCardOfflineAware` → if online, runs a transaction that increments the global `counters/jobCards.nextJobCardNumber` and writes the doc
- If offline, queues the write to Hive via `SyncService`
- The `onJobCardCreated` Cloud Function trigger fires and dispatches initial notifications based on `creation_recipients_by_type`

#### Sidebar Widget

- **Similar Job Cards** — wide-layout sidebar streams matching open cards as the form is filled, helping prevent duplicates

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

- Assigning a job → `sendJobAssignmentNotification` Cloud Function call
- Closing/updating → `sendCreatorNotification` to the original creator
- Both also trigger `onJobCardAssigned` which sets `escalationStopped: true`

### View Job Cards

`lib/screens/view_job_cards_screen.dart` — **Roles:** Manager, Admin

Browse every job card in the system. Four status tabs with live counts; filters for department, area, machine, type, priority, date range.

#### Tabs

- `Open`
- `In Progress`
- `Monitoring`
- `Closed`

#### Capabilities

- Tap any card to open **Job Card Detail**
- Filter and search across all factory structure levels
- Wide-layout view with split master/detail on tablets

### Closed Jobs

`lib/screens/closed_jobs_screen.dart` — **Roles:** All

Lighter-weight read-only browser of completed and auto-closed jobs. Useful for technicians who want to look up past work without the full filter UI of **View Job Cards**.

#### Capabilities

- Date-range filter
- Tap to open the detail view (read-only)

### Daily Review

`lib/screens/daily_review_screen.dart` — **Roles:** Manager

Daily sign-off queue for managers. Each closed/monitored job needs a manager review checkmark — this screen surfaces what's still pending.

#### Tabs

- `Pending Review (N)` — Cards the logged-in manager hasn't marked yet
- `Reviewed` — Already-marked cards

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

KPI rollups for the manager's domain.

#### Tiles

- **Open vs. Closed** count this week / month
- **Average time to close**
- **Per-technician throughput** — completed jobs by clock no
- **Top recurring machines** — highest `reoccurrenceCount` jobs

### Monitoring Dashboard

`lib/screens/monitoring_dashboard_screen.dart` — **Roles:** Manager

Visibility into the "Monitoring" state — jobs that were marked completed but kept open for 7 days to confirm the fix held.

#### Tabs

- `Active Monitoring` — Jobs currently in the 7-day monitoring window
- `Recently Auto-Closed` — Jobs the `autoCloseMonitoringJobs` scheduler closed in the last 7 days

> **Note:** `autoCloseMonitoringJobs` runs daily at 08:00 SAST in `europe-west1`. It closes any monitoring job that hasn't had updates for 7 days since `monitoringStartedAt`, appending an auto-close note to `notes`.

### Admin

`lib/screens/admin_screen.dart` — **Roles:** Admin only

The control panel. Four tabs.

#### Tab: Employees

- Spreadsheet-style editor for the `employees` collection
- Add / edit / bulk-delete employees
- Per-row toggle for `isOnSite`
- FCM token visible and editable (for debugging)
- CSV import / export with template download

#### Tab: Structures

- Manages the factory hierarchy stored under `factoryStructure`
- Add/delete Departments, Areas, and Machine/Parts
- Cascading deletes with confirmation dialogs

#### Tab: Settings

- **Force Location Check Now** — manually runs `LocationService.checkCurrentLocation`
- **Simulate 30-min WorkManager Check** — triggers the background geofence callback for testing
- **Escalation Config** — per-stage cards with Enable toggle, minutes input, recipient checkboxes (including a *Job Creator (Operator)* option that sends a tailored "follow up directly" alert to the person who raised the job). Writes to `notification_configs/global`. See [Escalation Reference](escalation_system.html)
- **Save Escalation Config** — writes the doc; prompts to confirm when re-enabling stages so old jobs aren't bombarded. Writes `enabled_at = now` on any stage transitioning from disabled → enabled
- **Reset Escalation Stamps** — calls the `clearEscalationStamps` Cloud Function. Two uses: (a) clears all stage stamps from open jobs so they re-process, (b) backfills `notifiedAtStage1..4 = null` on legacy docs so they appear in the composite indexes

#### Tab: Job Cards

- Spreadsheet-style export and delete tooling for the `job_cards` collection
- CSV export with full filter applied
- Bulk delete with confirmation

### Geofence Editor

`lib/screens/geofence_editor_screen.dart` — **Roles:** Admin only

Map-based editor for the factory geofence boundary stored in `config/geofence`. The native Android `GeofenceHelper` reads this to decide on-site vs off-site.

#### Capabilities

- Drop a centre point on the map (or enter lat/long)
- Adjust radius via slider
- Save writes `config/geofence` with the new `center.lat`, `center.lng`, `radius_meters`

> **Warning:** Changing the geofence affects every employee's `isOnSite` on their next location check. If you shrink the radius, people currently inside the old boundary may flip to `isOnSite: false` within minutes.

---

## Copper Management

Inventory and transaction tracking for the copper recovery side of operations.

### Copper Dashboard

`lib/screens/copper_dashboard_screen.dart` — **Roles:** All

Current copper stock plus quick-entry forms for inbound/outbound transactions.

#### Transaction Types

- **In** — copper arriving (raw)
- **Sort** — sorted into nuggets / rods
- **Sell (Nuggets)** and **Sell (Rods)** — outbound sales with R/kg rate

#### Notable Behaviour

- When cumulative sell total crosses 400 kg, the `onCopperTransactionWrite` Cloud Function notifies employee clock no 22 ("Copper Sell Ready")
- Stream-based — live updates from `copperTransactions` and `copperInventory` collections

### Copper Transactions

`lib/screens/copper_transactions_screen.dart` — **Roles:** All

Full history table of every copper transaction. Sortable by date, type, amount.

#### Capabilities

- Filter by transaction type
- Date-range filter
- CSV export

### Sort Copper

`lib/screens/sort_copper_screen.dart` — **Roles:** All

Dedicated entry form for sorting raw copper into nuggets or rods. Pulled out into its own screen so it can be a quick one-tap workflow from Home or Copper Dashboard.

#### Inputs

- Amount sorted (kg)
- Output type (Nuggets / Rods)
- Sorter name (auto-filled from `currentEmployee`)
- Optional notes

---

## Configuration & Utilities

Per-user preferences, diagnostics, and developer tools.

### Settings

`lib/screens/settings_screen.dart` — **Roles:** All

Per-user preferences and self-service tooling.

#### Sections

- **Account** — current user info, On-Site indicator, `Log Out`
- **Appearance** — Dark/Light mode toggle (writes to Riverpod theme provider)
- **Permissions Status** — live status for Notifications, System Alert Window, Notification Policy, Battery Optimisation. Tapping any row jumps to the OS settings page
- **Notification Tests**
  - Full Screen Alert (Priority 5, bypasses DND)
  - Persistent Notification with action buttons
  - Medium-priority notification
  - Standard normal notification
- **Diagnostics** — link to [Notification Diagnostics](#notification-diagnostics)

### Notification Diagnostics

`lib/screens/notification_diagnostics_screen.dart` — **Roles:** All (test tool)

Developer/admin tool for verifying the notification + geofence stack works end-to-end on a device.

#### Tests Available

- **Test ENTER** — simulates a geofence enter event. Writes to `geo_fence_logs` and flips `isOnSite: true` on the current employee
- **Test EXIT** — simulates an exit event. Flips `isOnSite: false`
- **Force FCM Token Refresh**
- **Print current employee state** — dumps clock no, position, isOnSite, fcmToken

> **Tip:** Use this when you need to test the escalation system but the device isn't physically inside the geofence. Hit Test ENTER and the next escalation cycle will treat the user as on-site.

---

## Cross-Cutting Concerns

Behaviour that affects multiple screens.

### Role-Based Visibility

*Determined in `home_screen.dart`*

The Home screen is the single source of truth for who sees which tiles. Roles are inferred from the `position` field on `employees/{clockNo}`:

- **Manager** — position contains "manager" (case-insensitive)
- **Admin** — clock number is in the admin allowlist (currently `22`)
- **Technician** — anyone else

### Offline-First Saves

*`SyncService` + Hive `sync_queue`*

Any screen that writes to Firestore (Create Job Card, Job Card Detail, Copper Dashboard, etc.) goes through `FirestoreService.saveJobCardOfflineAware` or the equivalent. If `connectivity_plus` reports offline, the write is queued to the Hive `sync_queue` box. When connectivity returns, `SyncService` replays the queue.

### Audit Log

*`job_card_audit` collection*

Every write to `job_cards` via `FirestoreService` appends a corresponding entry to `job_card_audit`. Future read screens could surface this for forensic / compliance use.

---

*CTP Job Cards · Screens Reference · Engineering documentation*
