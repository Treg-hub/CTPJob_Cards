<!--
Title: CTP Job Cards — Interactive Feature Guide
Source: Backfilled from app_features.html on 2026-05-18
-->

# CTP Job Cards Platform

## Complete Feature Reference

A real-time digital maintenance management system. Explore every feature — from fault reporting to AI-assisted operations.

| Stat | Value |
|------|-------|
| Priority Levels | 5 |
| Escalation Stages | 4 |
| Job-card roles | 4 (+ module roles: Security, Waste, Fleet, Ink) |
| First Escalation | 5 min |

---

## App Overview

*What CTP Job Cards does and how it fits into daily operations*

CTP Job Cards is a **Flutter + Firebase** mobile application for field technician job card tracking. It targets Android (primary) with iOS and web as secondary platforms. The app operates offline-first — all data syncs automatically when connectivity is restored.

### Core Value Pillars

- **Real-Time Response** — Fault reports reach the right technician in seconds. No dispatcher, no radio, no delay.
- **Full Accountability** — Every action is timestamped and logged. Who created it, who responded, when, what was done.
- **Intelligence Platform** — Structured data today powers predictive maintenance and AI fault-finding tomorrow.

### End-to-End Process

- **Step 1 — Operator creates a job card.** Department, area, machine, component, fault description, priority, and type (Mechanical / Electrical / Mech-Elec) are captured and submitted.
- **Step 2 — System identifies on-site technicians.** Real-time geofencing determines which technicians of the correct trade are currently on site. Notifications are dispatched instantly — no human dispatcher required.
- **Step 3 — Technician accepts or responds.** From the notification: Assign Self (takes ownership, stops escalation), I'm Busy (acknowledges, system keeps looking), or Dismiss (logged — escalation continues).
- **If no response → Auto-Escalation.** Four configurable escalation stages fire. Stage 1 (5 min): Foremen and on-site managers. Stage 2 (10 min): Department managers. Stages 3 and 4 reserved for off-site management — disabled by default. Each stage is independently enable / disable-able by Admin.
- **Step 4 — Job tracked through to closure.** Status moves: Open → In-Progress → Monitor → Closed. Technician records what was done, parts used, root cause, and recommendations. Operator is notified on closure.

### What's Live Today

Live:
- Job card creation & tracking
- Push notifications (P1–P5)
- Full-screen P5 alarms
- 4-stage auto-escalation
- Real-time geofencing
- Offline sync
- Permanent audit trail
- Manager dashboard & Daily Review
- Notification Inbox (offsite hold & delivery)
- Role-based access
- Light & dark theme
- Notification action buttons
- Copper Inventory module (clock-number restricted)
- WasteTrack module (Security department field capture; managers on Pulse for weighbridge)
- Site Security module (gate scan in/out, company cars, on-foot visitors — guards: module hub home, no job-card tiles)
- Fleet Maintenance module (Hyster forklifts & grabs)
- Ink Factory module (production stock inventory)

Planned:
- Predictive maintenance AI
- AI chatbot & manuals

---

## User Roles

*Job-card roles plus module-specific access*

Every employee's role controls what they can see and do. Three roles (Operator, Technician, Manager) are **inferred automatically** from the `position` field in each employee's profile — there is no separate role field to set. The **Admin role** is the exception: it is controlled by the `isAdmin` boolean field on the employee's Firestore document. To grant or revoke Admin, edit that field directly — no code change or app release is needed.

**Site Security guards** (`isSiteSecurityGuardOnly`) use a **module hub** on Home — Waste + Security module cards only; no Create Job Card, My Work, or View Jobs. **Security managers** keep the standard job-card Home plus Security and Waste tabs. See the in-app **Site Security** guides under Documentation.

### Operator

Discovers a fault and creates the job card. Responsible for capturing all details accurately at the point of report. Receives notifications when a technician accepts their job and when it is closed.

**Key Screens:** Create Job Card · Home · Job Card Detail

### Technician

Receives job card notifications (when on site), attends to faults, self-assigns from the notification, and closes the job with a detailed completion note. Can be Mechanical, Electrical, or both.

**Key Screens:** Home · My Assigned Jobs · Job Card Detail · Create Job Card

### Manager

Oversees all job cards in their department. Enforces data quality for operators and technicians. Receives escalation notifications. Has full department visibility on the Manager Dashboard.

**Key Screens:** Manager Dashboard · View Job Cards · Daily Review · Monitoring Dashboard

### Admin

Full system access. Manages employee accounts, configures geofence boundaries, adjusts escalation rules, enables/disables modules (Waste Management, Fleet Maintenance), and has access to all data across all departments.

**Key Screens:** Admin Screen · Geofence Editor · User Feedback · Employee Management · Settings (Modules)

> **Admin access is controlled per user in Firestore.** Set `isAdmin: true` on an employee's Firestore document to grant Admin. No code change required — takes effect on next app launch by that user.

### Authentication

All users sign in with their **Gmail address and password** (Firebase Auth). The system issues a custom token linked to each employee's clock number, which determines their role and department routing. Password resets are handled via email.

> **Operators and Technicians are distinct roles.** A technician can also create job cards when they discover a fault, but operators are typically the frontline personnel who report issues. A technician receiving a job card they created would self-assign it automatically.

---

## Job Cards

*The core record unit — from fault report to closure*

A job card is the formal digital record for every fault, breakdown, or maintenance task on site. It is the system's single source of truth — every subsequent action (notification, escalation, response, closure) is linked to a job card.

### Job Card Fields

| Field | Description | Why It Matters |
|-------|-------------|----------------|
| **Department** | The plant department where the fault occurred | Routes notifications to the correct technicians |
| **Area** | Specific area within the department | Helps technicians locate the fault quickly |
| **Machine** | Named machine or asset ID | Enables asset-specific fault history and pattern analysis |
| **Part / Component** | The specific component affected | Precise identification for ordering parts and recording repairs |
| **Description** | What happened — symptoms, error codes, observations | Gives the technician context before arrival; feeds AI analysis |
| **Priority** | P1–P5 reflecting production impact | Determines notification type and escalation urgency |
| **Type** | Mechanical / Electrical / Mech-Elec / Maintenance / Building / Pre Press Spec | Routes to the correct trade or team; Building and Pre Press Spec bypass escalation |
| **Closure Note** | What was done, parts used, root cause, follow-up | Creates a permanent repair record; feeds future AI insight |

### Priority Levels

| Priority | Production Impact | Expected Response | Notification Type |
|----------|-------------------|-------------------|-------------------|
| P1 | No production effect — routine or planned | Attend when available | Standard banner |
| P2 | Minor — production continuing | Attend soon | Standard banner |
| P3 | Moderate — degraded operation | Within the shift | Standard banner |
| P4 | Significant — output reduced | As soon as possible | Persistent banner |
| P5 | **Production standing — stopped** | **Immediate** | Full-screen alarm + DND override |

> **Priority must be honest.** P5 means production has stopped. Misuse erodes the system's ability to distinguish genuine emergencies. Managers monitor priority accuracy — deliberate misuse must be corrected.

### Job Card Status Flow

`Open` → `In-Progress` → `Monitor` → `Closed`

- **Open** — Created, no technician
- **In-Progress** — Technician self-assigned
- **Monitor** — Fault resolved, watching
- **Closed** — Complete & confirmed

| Status | Meaning | Trigger |
|--------|---------|---------|
| Open | Job is live, awaiting technician acceptance. Escalation is actively firing. | Automatic on creation |
| In-Progress | A technician has self-assigned and is actively working. Escalation stops immediately. | Technician taps "Assign Self" |
| Monitor | Fault resolved but machine is under observation for recurrence. | Technician updates status manually |
| Closed | Job fully complete. Closure note required. Operator notified. Record stored permanently. | Technician closes with note |

### My Assigned Jobs Screen

Technicians see all jobs they have accepted, sorted by priority. Tapping any job opens the full detail view with all fields, the fault description, and controls to update the status or add a closure note.

The priority badge colour-codes urgency at a glance — red for P5, orange for P4, amber for P3, green for P2, blue for P1.

- Pull-to-refresh updates the list in real time
- Jobs automatically reorder as priorities are updated
- Closed jobs are archived, not deleted. **Admin cleanup** (when used) is a **soft-delete** only — the record stays in the system for audit; floor staff never hard-delete job cards.

---

## Notifications

*Three distinct notification types scaled to fault priority*

The notification system uses **Firebase Cloud Messaging (FCM)** with a native Kotlin implementation on Android. Each priority level triggers a different notification type — from a standard banner for routine jobs to a full-screen alarm that bypasses the lock screen for P5 critical faults.

### Priority 1 · 2 · 3 — Normal Banner

Example: *New Job Card · P2 · Pump House — Cooling pump P-02 not priming — Line 3*

Action buttons: **Assign Self** · **I'm Busy** · **Dismiss**

**Standard Android notification banner** — appears at the top of the screen and can be swiped away. Uses the default notification tone. Tapping opens the job card directly.

### Priority 4 — Persistent Banner

Example: *P4 Alert · Significant Impact — Line 2 press machine — reduced output · Workshop*

Action buttons: **Assign Self** · **I'm Busy** · **Dismiss**

**Persistent banner** — cannot be swiped away. Stays in the notification panel until an action button is tapped. Escalation alert tone with strong vibration. Prompt response required.

### Priority 5 — Full-Screen Critical Alarm

Example: *PRODUCTION STOPPED — Conveyor 3 Drive Motor — Line 2 · P5 · Immediate Response Required*

**Full-screen alarm** — takes over the entire phone display, even from the lock screen. Implemented via native Android `FullScreenJobAlertActivity.kt` + `AlarmReceiver`. Powered by scheduled exact alarms so it fires even in deep sleep mode.

- Loud, repeating alarm tone
- Bypasses Do Not Disturb
- Appears over lock screen and other apps
- Cannot be passively ignored — requires a tap to dismiss
- Every response (or non-response) is logged with a timestamp

### Notification Action Buttons

Every notification includes three action buttons that can be tapped without opening the app:

| Action | Effect on Job Card | Effect on Escalation | Who Is Notified |
|--------|--------------------|----------------------|-----------------|
| **Assign Self** | Status → In-Progress. Technician assigned. | **Stops immediately** | Operator receives "Technician on the way" |
| **I'm Busy** | No change to status | Stops for this technician — system continues looking for another | Operator receives "Technician unavailable" |
| **Dismiss** | No change | Escalation continues — next stage fires on schedule | Logged in notification history |

### Notification Inbox — Off-Site Hold

When a user is off-site, the system does **not** send a live push notification. Instead, the notification is held in a **Notification Inbox** until the user is back on site.

Notifications held in the inbox include: job assignments made while off shift, job closure/update acknowledgements sent back to the creator, "I'm Busy" responses from technicians, and Copper sell-threshold alerts (for authorised users).

- The **bell icon** in the Home screen app bar shows a live unread-count badge.
- When the user returns on-site and opens the app, a banner appears: "X notifications waiting" with a one-tap shortcut to the inbox.
- Items in the inbox persist until manually marked as read — they do not expire.
- Tapping any inbox item navigates directly to the relevant job card and marks it as read.

### On-Site Entry & Departure Notifications

The geofencing system also generates automatic notifications when technicians cross the site boundary — no user action required:

- **"Arrived On-Site"** — your on-site status updates and job card notifications begin routing to you
- **"Left Site Area"** — your status updates and notifications pause until you return

---

## Automatic Escalation

*Four configurable stages — no fault can be silently ignored*

If a job card is not accepted by a technician, the escalation system automatically notifies progressively more senior recipients at timed intervals. Escalation is driven by **Cloud Functions** deployed to Google Cloud (`africa-south1`), running independently of any device or person.

> Escalation stops **immediately** the moment any technician taps "Assign Self" or "I'm Busy" on any notification. If a job is escalated but then accepted, all further escalation stages are cancelled.

### Default Escalation Timeline

- **T = 0 minutes — Job created — on-site technicians notified.** All on-site technicians of the correct trade type receive a push notification immediately.
- **Stage 1 · T = 5 minutes (default) — Foremen and on-site managers alerted — operator can also be opted in.** If no technician has responded within 5 minutes, foremen and on-site managers for the relevant department are notified with an escalation alert. The operator who raised the job can optionally be included — they receive a tailored "No response yet — please follow up directly" notification that tells them how many people have been notified so far.
- **Stage 2 · T = 10 minutes (default) — Department managers and workshop manager — urgent alert.** Escalated to management level. Managers receive a high-priority notification indicating the job has been open without response for 10 minutes.
- **Stage 3 · T = 30 minutes (default — currently disabled) — Reserved for senior / off-site management.** Available but disabled by default. Once enabled by Admin, only jobs created from the enable moment onwards will trigger this stage — existing open jobs are protected from a notification flood.
- **Stage 4 · T = 60 minutes (default — currently disabled) — Final escalation tier.** The final configured escalation stage. All timers, recipient lists, and enable / disable toggles are configurable per stage by Admin under Settings → Escalation Config.

> The times above are **defaults**, not fixed rules. An Admin can change the timer and recipient list for any stage at any time without a software update. Each stage can be enabled or disabled independently, and re-enabling a stage applies only to new jobs from that point forward (existing open jobs are not flooded).

### Role-Based Routing by Trade

The Cloud Functions route notifications based on the job type:

- **Mechanical** jobs → Mechanics and mechanical foremen
- **Electrical** jobs → Electricians and electrical foremen
- **Mech-Elec** jobs → Both trades are notified simultaneously

Escalation recipients at Stage 1+ are department-specific — managers only see escalations from their own department, unless they are at senior management level.

---

## Real-Time Geofencing

*On-site status tracking — automatic, continuous, background*

The geofencing system continuously monitors whether each technician is inside or outside the company boundary. Only **on-site technicians** receive job card notifications — off-site staff are excluded automatically. No one ever has to manually mark themselves as present or absent.

Legend:
- On site — receives notifications
- Off site — notifications paused

### How It Works

- **Background Tracking** — The `BackgroundGeofenceService` runs continuously using Android WorkManager, even when the app is closed. It uses `geolocator` to monitor position relative to the configured site boundary polygon.
- **Battery Permission Required** — Android's battery optimiser can kill background services. Users must set the app to **Unrestricted** battery usage to ensure geofencing works overnight and during extended off-screen periods.
- **Entry & Exit Events** — The `GeofenceReceiver` fires on entry and exit. Each event updates the employee's Firestore document, sends an automatic on-site/off-site notification, and adjusts notification routing instantly.
- **Configurable Boundary** — Admins use the **Geofence Editor Screen** to define and adjust the site boundary polygon on a map. Changes take effect immediately for all users without a software update.

> **Location is not used for surveillance.** The system records only whether an employee is inside or outside the configured site boundary — not their precise location or movement within the site.

### Required Permission

Users must grant **"Allow All the Time"** location access (not "Only While Using the App"). Without background location access, geofencing cannot run when the screen is off, and notifications will fail to route correctly.

---


## Offline Mode & Sync

*Works without connectivity — syncs automatically when back online*

CTP Job Cards is **offline-first**. If connectivity is lost, the app continues to function. All writes that cannot reach Firestore are queued locally in a Hive database and replayed automatically when the connection is restored.

### Sync Flow

`App Action (user creates/updates job)` → `Check Connectivity (connectivity_plus)` → `Queue Locally (Hive sync_queue)` → `Sync to Firestore (on reconnect)`

### How It Works

- **SyncService** initialises at app startup and listens to the `connectivity_plus` stream
- Failed writes (Firestore offline) are stored as `SyncQueueItem` objects in a Hive box named `sync_queue`
- When connectivity is restored, `SyncService` replays all queued items in order, correctly restoring Firestore `Timestamp` fields so list screens are not corrupted on reconnect
- The **sync badge** at the top of the Home screen shows a live indicator when items are queued — orange while waiting for connectivity, pulsing while syncing
- Firestore's built-in offline persistence also caches recent reads, so the UI remains usable even when offline

> **Job card creation requires connectivity.** Creating a job card while offline would mean no technicians are notified — the fault would sit silently in the queue. The Create Job Card screen shows a full-width red banner when offline and disables the Save button until connectivity is restored. Use this time to move to a signal area before submitting.

> The sync queue uses **Hive** (a fast key-value store) for local persistence. `SyncQueueItem` is a `@HiveType`-annotated model — if you modify it, run `flutter pub run build_runner build` to regenerate the Hive adapters.

### Local Storage Summary

| Storage | Contents | Purpose |
|---------|----------|---------|
| **Hive — sync_queue** | `SyncQueueItem` objects | Offline write queue — replayed on reconnect |
| **SharedPreferences** | `loggedInClockNo` | Persists the logged-in employee session |
| **SharedPreferences** | `permissionsCompleted` | Tracks whether onboarding permission flow has been completed |
| **Firestore offline cache** | Recent document snapshots | Read cache — UI works without network for cached data |

---

## App Permissions

*Six permissions required for full functionality on Android*

On first launch, the app guides users through a permission setup flow. All six permissions are required — each one enables a specific critical feature. The app will not function correctly if any are denied.

### 1. Location — "Allow All the Time"

Enables background geofencing so the system knows which technicians are on site. Without "All the Time" access, geofencing stops when the screen turns off — technicians miss notifications.

Tip: Must select "Allow All the Time" — not "Only While Using"

### 2. Notifications — "Allow"

All job card alerts reach the user through push notifications. Without this, no notifications are received and the system escalates as if no one is responding.

Tip: Always select "Allow"

### 3. Battery Optimisation — "Unrestricted"

Android's battery saver can kill the background geofencing service after a few minutes. Setting the app to Unrestricted prevents this — especially important overnight.

Tip: Settings → Apps → CTP Job Cards → Battery → Unrestricted

### 4. Display Over Other Apps

P5 full-screen alarms appear over the lock screen and above any other open app. Without this permission, P5 alerts fall back to a standard banner — easily missed.

Tip: Grant this permission for full P5 coverage

### 5. Do Not Disturb Access

Allows P5 critical alarms to bypass DND mode. If a technician has DND enabled overnight, P5 alarms must still sound for production-stopping faults.

Tip: Grant for full P5 alarm coverage

### 6. Schedule Exact Alarms

The P5 alarm uses the Android alarm system to guarantee exact-time firing, even in deep sleep mode. Without this, the alarm may arrive late or not fire at all.

Tip: Settings → Apps → Special App Access → Alarms & Reminders

---

## Manager Dashboard

*Live department visibility — job status, technician presence, escalation history*

The Manager Dashboard gives department managers a real-time view of everything happening in their area. It is the primary tool for oversight, quality control, and escalation response.

### Dashboard Panels

Use the **department** and **date range** filter chips at the top to focus the data on your team and timeframe.

**KPI Cards (9)**

Nine at-a-glance metrics: Open Jobs, High Priority (P4–P5), Monitoring, Closed Today, Pending Assignment, Avg Resolution Time, Overdue >3 Days, Overdue >7 Days, and Completion %. Every countable KPI is tappable — tapping it opens a filtered job list so you can immediately drill into the relevant cards.

**Analytics Charts**

- **Open Jobs by Day** — 30-day area chart of open job stock, department-filtered.
- **Trendline** — opened vs. closed jobs over the selected period, with legend.
- **Department Area Chart** — area breakdown of open jobs by department.
- **Priority Breakdown** — bar chart of open jobs by priority, labelled P1 Low through P5 Crit.
- **Team Performance** — per-technician table showing closed count, average resolution time, and currently assigned count. Assigned count > 3 is flagged in orange as a potential overload indicator.

### Manager Responsibilities in the System

| Responsibility | Why It Matters |
|----------------|----------------|
| Daily review of previous day's job cards | Catches missing records, slow responses, and emerging repeat failures |
| Enforce operator job card quality | Vague entries are worthless for analysis and future AI tools |
| Enforce technician closure note quality | A closure with no note is an incomplete maintenance record |
| Monitor escalation patterns | Repeated Stage 2+ escalations indicate a coverage or staffing problem |
| Identify machines with repeat faults | Same machine twice in 30 days warrants root cause investigation |
| Verify team on-site status accuracy | New phones or permission changes can break geofencing silently |

---

## Audit Trail

*Permanent, append-only log of every action — searchable at any time*

Every action taken on a job card — creation, status change, assignment, notification, escalation, closure — is written to the `job_card_audit` Firestore collection by **FirestoreService**. This is append-only: records are never modified or deleted.

### Example Audit Entries

| Time | Action | Actor |
|------|--------|-------|
| 08:14:23 | Job card created — P5 · Conveyor 3 Drive Motor · Line 2 | J. Pretorius |
| 08:14:25 | Notifications dispatched — 4 on-site technicians (Mechanical) | System |
| 08:15:10 | Notification dismissed — escalation continues | K. Botha |
| 08:16:25 | Stage 1 escalation fired — foremen and on-site managers notified | System |
| 08:17:02 | Job assigned — status changed Open → In-Progress. Escalation cancelled. | D. van Wyk |
| 09:03:47 | Job closed — bearing replaced, motor restarted. Parts: SKF 6208-2RS. Root cause: age/fatigue. | D. van Wyk |

### What Is Captured

| Data Point | Business Value |
|------------|----------------|
| Machine, area, component | Precise asset identification for history tracking |
| Fault description | What happened and what was observed at the time |
| Priority at time of report | Production impact classification — searchable by priority level |
| Who created it, when | Operator accountability and fault timestamp |
| Who responded, when | Technician accountability and response time measurement (MTTR) |
| What was done, parts used | Repair record, parts consumption, cost basis |
| Root cause | Feeds predictive analysis and repeat-failure identification |
| Full notification log | Complete chain of who knew what and when — unalterable |

---

## Admin Tools

*Full system control — accounts, geofences, escalation rules, communications*

Admins have access to all data across all departments plus system configuration tools not available to any other role. Admin Settings has **five tabs** and opens on **Settings** by default: **Settings → Employees → Structures → On Site → Comms**.

- **Settings** — Escalation config (per-stage timer, recipients, enable/disable), location tools, access and module controls, and the User Feedback board link. Includes **App Update Control** (full operator guide: `docs/admin_app_update_guide.md`): shared APK URL; **channels** (Default / Departments / People) with multi-select from employee + department lists; **soft** = Home banner only; **force** = full-screen install for that channel only; **min supported build** = factory-wide launch kill-switch. Network check every 24h.
- **Employees** — Searchable card list with add / edit / bulk-delete. On-site status is a tappable pill on each card. CSV template and import in the toolbar. FCM token is edited in the employee dialog, not on the list.
- **Structures** — Manage the department → area → machine hierarchy with search, count stats, and expandable cards. Cascading deletes with confirmation.
- **On Site** — Real-time panel showing every employee currently marked on-site, grouped by department. Updates live as employees arrive and leave.
- **Comms** — Broadcast an update notification to all employees. A pre-filled message template is provided and can be edited. After sending, a result summary shows sent / parked (off-site users) / no-token counts. Recent broadcasts are listed at the bottom of the tab.

> **Job card export and bulk delete** are not in the mobile Admin screen. Use **CTP Pulse** for job history, KPIs, and read-only oversight.

**Geofence Editor** — Separate screen accessible from Admin → Settings for drawing the site boundary polygon on a live map. Changes take effect immediately for all users without a software update.

**User Feedback** — Admin-only screen accessible from Admin → Settings → Feedback. Lists everything staff have submitted via the **Give Feedback** button on the Home screen, and lets an admin track each item through **New → Planned → Implemented → Declined** and attach private implementation notes. Filter chips with live counts show at a glance what's still outstanding versus done. It's an internal tracking tool — only admins can see it; staff just get a confirmation when they submit.

### Technology Stack

| Component | Provider | Properties |
|-----------|----------|------------|
| Database | Google Firebase Firestore | Real-time, offline-capable, serverless, auto-scaling |
| Push Notifications | Firebase Cloud Messaging (FCM) | Enterprise-grade delivery, high-volume capable |
| Cloud Functions | Google Cloud Functions (africa-south1) | Serverless escalation logic — no server to maintain |
| Authentication | Firebase Auth | Email + password with custom tokens linked to clock numbers |
| Mobile App | Flutter (Dart) | Android primary; iOS and web capable; offline-first |
| Local Storage | Hive + SharedPreferences | Offline queue, session persistence |

> **No on-premises infrastructure required.** No server to maintain, no single point of hardware failure. All data is encrypted at rest and in transit. Backed by Google's 99.99% availability SLA with automatic scaling.

---

## Fleet Maintenance

*Tracking maintenance, issues, and costs for Hyster forklifts and grabs — a separate module from production job cards.*

Fleet Maintenance is a self-contained module behind its own **Fleet** tab. It is only visible once an admin turns it on in Fleet Settings and gives the relevant people a fleet role. It deliberately keeps forklift/grab work **separate** from plant breakdown job cards, with its own asset register and history.

### What it does

- **Issue reporting** — Operators and shift leads (in the departments an admin enables) report a problem on a specific forklift or grab: severity (Low / Medium / High / Out of Service), shift (auto-detected as day / night / weekend), a description, and up to three photos.
- **Out-of-service alerts** — Reporting an asset *out of service* immediately push-notifies the Hyster mechanic and the cost manager(s) — or holds it in their notification inbox if they're off-site — and flags the asset with an orange **OOS** badge until the issue is resolved. High-severity issues go to the inbox without a push.
- **Mechanic work log** — The mechanic works an "open issues" queue sorted by severity, acknowledges an issue, and resolves it by either logging the work or leaving a resolution note (out-of-service issues must be closed with a work record — a note alone is not accepted). Work records capture work type, labour hours, the machine hour-meter reading, parts used, and photos, are numbered `FM-NNNN` (short global sequence; legacy records keep `FM-YYYYMMDD-NNN`), and lock from editing 7 days after creation. The hour-meter reading is propagated to the asset so the next mechanic sees the last recorded hours.
- **Cost tracking (managers only)** — The overseeing manager enters cost lines against an asset (parts / labour / invoice / other, with amount, invoice reference, and supplier), sees month and year-to-date spend per machine, and exports a full CSV. **The mechanic never sees cost amounts** — only a "Costs pending / Costs entered" label.
- **Admin** — The forklift/grab register, the list of reporter departments, the cost-manager clock numbers, the asset and work types, and the module on/off switch are all managed in Fleet Settings.

### Roles

| Role | How you're recognised | What you can do |
|------|----------------------|-----------------|
| **Fleet Mechanic** | Workshop department + "Hyster Mechanic" position | Log work, acknowledge and resolve issues (no money shown) |
| **Fleet Reporter** | Your department is enabled in Fleet Settings | Report issues and track the ones you raised |
| **Cost Manager** | Your clock number is on the cost-manager list | Enter costs, view spend reports, export CSV |
| **Fleet Admin** | System admin | Manage the asset register and all Fleet settings |

### On the management dashboard (CTP Pulse)

Managers with the Fleet module on the web board see a **Fleet Maintenance** section: open issues (live), maintenance hours this month, cost this month, and average issue resolution time — plus a dedicated Fleet page with cost-per-asset and cost-by-category charts and a live list of open issues.

---

## Ink Factory

*Production stock-inventory data entry for the Ink Factory department — a separate module from plant job cards.*

The Ink Factory module is a full stock-inventory system for raw materials, solvents, and manufactured inks. It tracks purchases, production runs, meter consumption, Toloul recovery, and month-end reporting. It is only visible to staff with `department == "Ink Factory"` and to admins.

### What it does

- **Stock on hand** — Live balances and weighted-average costs for all 13 items: raw materials (ASP600, Sylowhite, Spray105, Claytone, Resink, Cellulose), solvent (Toloul), inks (Yellow, Red, Blue, Black — received as IBCs, never manufactured), and manufactured products (CoverWax, Gravure Binder).
- **Receive Local** — List of outstanding local purchase orders (sent from Pulse); operator confirms quantity received per line. Ad-hoc receive without order remains as escape. Cost is entered later by a manager (deferred-cost pattern).
- **Receive ink IBCs** — Operator scans the IBC barcode (GS1-128 / SSCC label), weight and colour are auto-filled from the scan. The audit register records every IBC number received.
- **Consume IBC** — Transfers an IBC from the audit register into the tank. Records Toloul wash consumption and **auto-creates an IBC Bins on-site waste stock item** (by IBC number) for security to collect on a later load.
- **Daily Readings** — Combined screen for ink meters and Toloul meter points. Enter all readings on one page with one submit.
- **Production Run** — Operator picks a recipe (CoverWax or Gravure Binder) and a pot count. The screen previews inputs consumed and output produced; the run is recorded as consumption transactions for each input and a manufacture transaction for the output.
- **Toloul Recovery** — Records solvent recovered from the Lurgi distillation. Previous recovery entries are shown below the form for context.
- **IBC Register** — Searchable register of all ink IBCs with colour tabs (Yellow / Red / Blue / Black), receive date, order number, and CGNA number.

### Daily Readings — ink meters + Toloul meters on one screen

The **Daily Readings** screen (also the Lurgi home tile) shows all ink meter points and all Toloul meter points on a single scrollable page. The Lurgi operator enters both in one sitting at 06:00 each morning.

- **Ink meters** — cumulative reading entry for Yellow, Red, Blue, Black, and Gravure Binder. Each card shows the last few readings as a history strip. The delta (litres consumed since the last reading) is computed automatically and converted to kg using a conversion factor. If the new reading is below the last, a "meter was reset" checkbox appears.
- **Toloul meters** — the same entry pattern for the Toloul Recovery and Toloul Usage meter points. These record how much solvent each press consumed and are used for month-end Toloul reporting. They do not affect stock levels.
- One date at the top (editable by managers), one **Record readings** button at the bottom.

### Roles

| Role | How you're recognised | What you can do |
|------|----------------------|-----------------|
| **Ink operator** | `department == "Ink Factory"` | All data entry: receive stock, meter readings, production, Toloul recovery, consume IBC |
| **Ink manager** | position contains "manager" + Ink Factory, or Admin | All operator capture on mobile + full management on **CTP Pulse** (`/ink`): pending costs, revaluation, month-end count/report, recipes, supplier management, corrections |
| **Lurgi operator** | `department == "Lurgi"` | Daily Readings screen only (ink + Toloul meters) |
| **Admin** | `isAdmin: true` | Full access to all Ink Factory screens |

> **Operators never see money.** Weighted-average costs, stock values, and cost estimates on the Production Run screen are hidden from operators — only managers and admins see financial figures.

### Manager tools (CTP Pulse — not mobile)

Ink managers open **CTP Pulse** from the **Management & costing** card on the Ink Factory hub (`https://ctp-pulse.web.app/ink`). The mobile app no longer shows a manager tile grid.

- **Pending Costs** — after a purchase is received, the manager enters the total cost from the invoice to finalise the weighted-average cost calculation.
- **Recipes** — define input quantities and output per pot for CoverWax and Gravure Binder recipes.
- **Conversion Factors** — set the kg-per-litre factor for each metered ink so meter readings convert to stock consumption correctly.
- **Toloul Meter Points** — manage the list of meter points (Lurgi recovery points and press usage points) shown on the Daily Readings screen.
- **Month-end Count** — enter a physical stock count; the system auto-generates an adjustment transaction per item (count minus ledger balance).
- **Month-end Report** — free date-range report (count-to-count) with opening balance, all movements, and closing balance per item, exportable as CSV and PDF.
- **Stock Adjustment / Value Adjustment / Revaluation** — manager-only corrections.
- **Corrections** — void a transaction and re-enter corrected values (void-and-reenter pattern, preserved for audit).

---

## AI & Predictive Maintenance Roadmap

*The current platform is a data foundation. The long-term value lies in what that data makes possible.*

### Phase 1 — Predictive Maintenance Analytics

Machine learning applied to job card history identifies failure patterns and predicts which assets are likely to fail — triggering proactive maintenance before breakdowns occur. Shifts the operation from reactive to predictive.

### Phase 2 — AI Assistant — Manuals & Fault Finding

A conversational assistant integrated into the app gives technicians instant access to operator manuals, historical repair records, wiring diagrams, and parts specifications — in plain language, on their phone, on the floor.

### Example AI Assistant Queries

- What are the most common causes of overload faults on Conveyor 3?
- What was done the last three times Machine 7 had a bearing failure?
- What is the correct torque spec for the FX400 gearbox drive shaft bearing?
- Which machines on Line 2 are statistically likely to fail in the next 30 days?

### Business Case for AI

| Benefit | Mechanism |
|---------|-----------|
| Reduced unplanned downtime | Predictive alerts trigger maintenance before failure — not after |
| Faster fault resolution | AI-assisted diagnosis reduces time to identify and fix root cause |
| Knowledge retention | Institutional expertise captured in the system — not lost when experienced staff leave |
| Lower parts inventory cost | Predictive maintenance enables targeted stock — not blanket over-stocking |
| Reduced repeat failures | Root cause identified, addressed, and recorded — not just symptoms patched |
| Technician upskilling | Access to manuals and history on-device reduces dependency on senior staff for routine questions |

> **The quality of AI insight is entirely dependent on the quality of data entered today.** Every job card completed with accurate machine identification, clear fault descriptions, and detailed closure notes is a data point that improves predictive accuracy. Enforcing data standards at the management level is a direct investment in the long-term intelligence of the maintenance operation.
