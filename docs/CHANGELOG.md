# CTP Job Cards — Documentation Changelog

Append-only log of user-visible changes. Add a new entry at the top each release; do not edit historical entries except to fix factual errors.

The role guides, the onboarding flow, and the reference docs all draw from this log. Whatever you write here is what staff will read next time they open the docs portal.

---

## 2026-06-03 — CTP Pulse web dashboard: theme & contrast fixes

Web-only update to CTP Pulse (factory board at port 3003). No mobile changes.

### What changed

- **Status badge contrast** — Overtime entry status badges (Pending, Workshop Approved, Approved, Cancelled) now use correctly contrasting colours in both light and dark modes. Previously the coloured text was too light to read in light mode.
- **KPI trend colours** — Declining-trend indicators on KPI cards now correctly show in red (destructive colour). Previously they had no colour at all.
- **Fleet severity labels** — Issue severity labels (Out of Service, High, Medium, Low) in the Fleet page open-issues table now render in legible colours in dark mode.
- **Fleet cost chart** — The "Cost by Category per Asset" stacked bar chart now has correctly themed axis labels, gridlines, tooltip, and legend in dark mode. Previously axis text was near-invisible in dark mode.
- **Native date/select inputs** — Date pickers and dropdown filter selects now follow the app's dark theme; previously the browser rendered them with a white background in dark mode.

---

## 2026-06-03 — Fleet Maintenance module (Hyster forklifts & grabs)

A new **Fleet** tab for tracking forklift and grab maintenance — separate from normal job cards. It appears once an admin enables it in Fleet Settings and you have a fleet role.

### User-facing changes

**New: Fleet tab**

- **Report a problem** — operators and shift leads in the configured departments can report an issue on a forklift or grab: pick the asset, choose severity (Low / Medium / High / Out of Service), confirm the shift (auto-detected), describe the fault, and attach up to 3 photos.
- **Out of Service alerts** — when an asset is reported out of service, the Hyster mechanic and the cost manager(s) get an immediate push notification (or it waits in their notification inbox if they're off-site). The asset shows an orange **OOS** badge everywhere it appears. High-severity issues go to the notification inbox without a push.
- **Mechanic queue & work logging** — the mechanic sees open issues sorted by severity, can **Acknowledge** an issue, then resolve it either by logging the work (work type, labour hours, machine-hour reading, parts used, photos) or with a quick resolution note. Each work record gets a number like `FM-20260603-001`.
- **Costs (managers only)** — the overseeing manager records cost lines per asset (parts / labour / invoice / other, with amount, invoice ref and supplier), views month and year-to-date spend per machine, and exports a full CSV. **The mechanic never sees money** — work records only show a "Costs pending / Costs entered" label.
- **Admin** — the asset register (add/edit forklifts and grabs), reporter departments, cost-manager list, asset/work types, and the module on/off switch all live in **Fleet Settings**.

### Who sees what

| Role | How you're recognised | What you can do |
|------|----------------------|-----------------|
| Fleet Mechanic | Workshop department + "Hyster Mechanic" position | Log work, acknowledge/resolve issues |
| Fleet Reporter | Your department is enabled in Fleet Settings | Report issues, track your own |
| Cost Manager | Your clock number is on the cost-manager list | Enter costs, view reports, export CSV |
| Fleet Admin | System admin | Manage assets and all settings |

### Developer / architecture changes

- New `fleet_*` Firestore collections (`fleet_assets`, `fleet_issues`, `fleet_work_records` + `fleet_work_parts`, `fleet_cost_lines`, `fleet_types`, `fleet_settings`, `fleet_counters`, `fleet_audit`). Same signed-in auth model as WasteTrack; role enforcement is client-side.
- Cloud Functions in the monorepo `firebase/functions` codebase: `createFleetWorkRecord` (atomic FM-number), `onFleetIssueCreated` (OOS notifications + asset badge), `onFleetIssueUpdated` (clears badge on resolve).
- CTP Pulse gains a **Fleet Maintenance** board module (open issues, work hours MTD, cost MTD, avg resolution time) plus a `/fleet` detail page with cost-by-asset and cost-by-category charts and a live open-issues table. Access via the `fleet` board module in `/admin/users`.
- See `docs/architecture/visualization.md` for the full role/screen matrix and `docs/COLLECTIONS.md` for the schemas.

---

## 2026-06-03 — Job Card History screen, Firestore read cost fixes

### User-facing changes

**New: Job Card History screen**

- A dedicated **Job History** quick-action tile is now on the Home screen for all roles.
- The screen lets you search the full closed job card archive without streaming the entire collection — only the records matching your filter are downloaded.
- **Server-side filters**: date preset (Last 7 / 30 / 90 days, custom range, or all time), department, area, and machine. Each change triggers a fresh Firestore fetch capped at 50 records per page. Use **Load More** for pagination.
- **Client-side refinement** (no extra reads): Type chips (Mechanical / Electrical / Mech-Elec / Maintenance), Priority chips (P1–P5), and free-text search across description, machine, part, notes, and operator.
- Tap any result to open the full Job Card Detail screen.

**Create Job Card — similar jobs panel**

- The "previous jobs for this machine" sidebar previously downloaded every job card in the system and filtered on-device. It now uses server-filtered indexed queries — only the records that match the current department → area → machine → part selection are fetched.

### Developer / architecture changes

- **`FirestoreService.getInProgressJobCards()`** — new server-filtered stream for `status == inProgress` jobs.
- **`FirestoreService.searchClosedJobCards()`** — new one-shot fetch with server-side equality filters (department, area, machine) and an optional date range on `closedAt`, plus cursor-based pagination. Type and priority filtering applied client-side on the returned page.
- **Home screen count badge** — the two `getAllJobCards()` live listeners used to count the open/in-progress badge and render the recent jobs panel have been replaced with `getOpenJobCards()` + `getInProgressJobCards()` streams. Closed documents are never downloaded to the home screen.
- **`closed_jobs_screen.dart` removed** — superseded by `job_card_history_screen.dart`.
- **3 new Firestore composite indexes** in `firestore.indexes.json`: `status + department + closedAt DESC`, `+ area`, `+ machine`. Required for the server-side history queries. Deploy with `firebase deploy --only firestore:indexes`.

---

## 2026-06-02 — WasteTrack UX overhaul, notification inbox fixes

### User-facing changes

**WasteTrack home screen**

- **Live updates** — The load list now updates automatically in real time. You no longer need to pull down to refresh; new or updated loads appear as soon as they change.
- **Actions moved to overflow menu** — The toolbar buttons (Pending Weighbridge, Reports, Waste Admin, Enable/Disable toggle) are now grouped under a **⋮ More actions** menu at the top right. The cloud sync retry button remains visible at all times when there are queued items.
- **Filter empty states** — When the Today or This Week filter returns no results, the screen now shows a clear "No loads match" message with a tap-to-clear button instead of a blank list.
- **Contractor name on scheduled load cards** — Incoming scheduled load cards now show the contractor's display name instead of the internal contractor ID.

**WasteTrack load detail screen**

- **Waste items now listed** — The load detail screen now shows all waste items in the load (subtype, weight, photo count) directly on the page. Previously you could not see the item breakdown from the detail view.
- **Status progress stepper** — A four-step progress bar (Created → Signature → Weighbridge → Complete, or Scheduled → Collecting → Weighbridge → Complete for two-phase loads) is shown at the top of the detail screen so you can see at a glance where the load is in its lifecycle.
- **Weighbridge action banner** — When a load is in **Pending Weighbridge** status, a highlighted amber banner now appears at the top of the screen prompting the manager to enter the weighbridge weight. Previously this was easy to miss.
- **Collector name shown** — The "Collected by" field now shows the guard's name instead of their clock number.

**WasteTrack create load flow**

- **Opens load detail after saving** — After creating a new load, the app now navigates you directly to the load detail screen. You can immediately capture the driver signature without going back to the home screen to find the load.
- **Waste type icons** — The waste type selection grid now shows category-specific icons (hazardous, recyclables, cardboard, metal, e-waste, organic) instead of a generic trash icon for every type.
- **Add item is a slide-up sheet** — The "Add Waste Item" form is now a slide-up bottom sheet instead of a pop-up dialog. This is more stable when the camera is involved and easier to use on smaller screens.

**WasteTrack begin collection**

- Same camera-stable slide-up sheet for adding waste items during collection (consistent with create load flow above).

**Notification inbox**

- **On-site status indicator in app bar** — The notification inbox screen's app bar now shows the same orange → green (on-site) / orange → red (off-site) gradient as every other screen in the app.

### Developer / architecture changes

- **Firestore rules: notification_inbox added** — The `notification_inbox/{clockNo}/items` subcollection was missing from the Firestore security rules, causing permission denied errors when the Flutter app tried to read or mark inbox items. Rule added to the Job Cards tier. Deployed to production.
- **`WasteLoad` model: `contractorName`, `collectedByName` fields** — Both are now stored on the load document at creation/collection time and read back for display, avoiding secondary lookups.
- **`WasteService.getLoad()`** — New method for fetching a single load by ID, used by the post-creation navigation.

---

## 2026-06-01 — WasteTrack module, offsite notification inbox, admin on-site view, settings redesign

### User-facing changes

**WasteTrack — Waste Management Module**

A full waste management module is now integrated into the app for Security department staff. Accessible via the **Waste** tab in the bottom navigation bar (only visible to Security Manager, Security Guard, and Admin roles).

- **Security Manager** — Schedule waste loads with contractor, waste type, and date. Edit or cancel scheduled loads before collection begins. Review completed loads and deviation reports. Export CSV reports by date range.
- **Security Guard** — Begin collections for scheduled loads. Add waste items with recorded weights and photos. Capture the contractor's on-screen signature. Enter the actual weighbridge weight after the truck returns from the external scale.
- **Deviation alerts** — When the difference between the recorded weight and the actual weighbridge weight exceeds 5% or 50 kg, the load is flagged for manager review.
- **Load numbering** — Each load is assigned an automatic daily sequence number (format: WT-YYYYMMDD-NNN).
- **Admin** — Full WasteTrack configuration panel: manage waste types, sub-types, cost rates, and contractor records.

**Offsite Notification Hold (Notification Inbox)**

- **Notification Inbox** — Notifications are no longer sent as push alerts when you are off site. Instead they are held in a new **Notification Inbox** (bell icon in the top bar). Unread items show a live count badge. When you come back on site and open the app, a banner tells you how many are waiting. Tap any item in the inbox to open the related job card and mark it as read.

- **Notifications affected by offsite hold** — All of the following are now held rather than pushed when the recipient is off-site:
  - Job assignment (assigned directly by a manager while you are off shift)
  - Job completion and update acknowledgements (sent back to the person who raised the job)
  - "I'm Busy" responses from technicians (sent back to the job creator)
  - Copper sell threshold alert (for authorised users only)

**Admin & Settings**

- **Admin — On Site tab** — A new **On Site** tab in Admin Settings shows every employee currently marked on-site, grouped by department, updating in real time. Useful for supervisors to see who is available on the floor.

- **Admin — Employee list** — The `isOnSite` column in the employee table is now a green **"On Site"** / grey **"Off Site"** status chip. Tapping the chip toggles the employee's status directly — no need to open the edit row.

- **Settings screen redesigned** — Reorganised into labelled sections: Your Profile, Preferences, Notifications, App & Connectivity, App Permissions, Admin, Account. Notification test buttons moved to a dedicated sub-screen (Settings → Notifications → Notification Tests) to reduce clutter.

- **Admin settings — Tab icons** — All five admin tabs now display an icon alongside the label for faster navigation.

- **Waste screens — contrast fixes** — Several waste screens had light-grey text or icons that were hard to read on white backgrounds:
  - Weight boxes on the load detail screen now use dark text when no weighbridge data has been entered (was grey-on-grey).
  - Disabled-state block icons across create, home, and reports screens are now a darker grey.
  - The empty items placeholder in the begin-collection screen has a more visible border.

### Developer / architecture changes

- **WasteTrack collections** — 11 new Firestore collections added under the `waste_` prefix (see `lib/constants/collections.dart`).
- **`createWasteLoad` Cloud Function** — Callable function in `africa-south1` handles atomic load creation and daily sequence numbering.
- **`lib/constants/collections.dart`** — New canonical constants file for all Firestore collection names. All services now use constants instead of inline string literals.
- **Functions codebase named `jobcards`** — Deploys from this repo are now scoped to Job Cards functions only; cannot accidentally wipe WasteTrack/Overtime functions in the shared Firebase project.

---

## 2026-05-23 — Dashboard overhaul, screen consistency, and UI improvements

### User-facing changes

- **Manager Dashboard rebuilt** — department and date-range filters are now displayed above the KPI section. Nine KPI cards replace the previous four: Open Jobs, High Priority (P4–P5), Monitoring, Closed Today, Pending Assignment, Avg Resolution Time, Overdue >3 days, Overdue >7 days, and Completion %. Every KPI card that represents a job list is now tappable — tapping it opens a filtered list of exactly those jobs. KPI section is collapsible. Priority breakdown bar chart labels updated to P1 Low / P2 Med / P3 Mid / P4 High / P5 Crit.
- **Manager Dashboard analytics** — technician leaderboard replaced with a **Team Performance table** showing each technician's closed count, average resolution time, and currently assigned count. New **Open Jobs by Day** area chart shows the last 30 days of open job stock, department-filtered. Trendline chart now includes a legend.
- **Daily Review: responsive layout** — on narrow screens (< 700 px) the list and detail panels stack vertically with a back-navigation button. On wider screens both panels display side by side.
- **Daily Review: date range filter** — the two separate date pickers have been replaced with a single date-range picker. The selected range is shown as a deletable chip.
- **Daily Review: Monitor status badge** — the Monitor badge colour changed from green to amber to better reflect "watch" state (not yet resolved).
- **Daily Review: tab switching** — switching between Pending and Reviewed tabs now clears the selected card and any text in the input field.
- **Unified gradient app bar** — every screen now shows a gradient app bar: orange on the left fading to **green** when the current user is on-site, or **red** when off-site. This provides a persistent on-site status cue across the entire app.
- **Tab bars moved into body** — on View Job Cards and Job Card Detail the tab bar is now part of the scrollable body, not pinned to the app bar chrome.
- **Login screen** — left panel background changed to pure black.

---

## 2026-05-21 — Job card detail redesign, onboarding fix, off-site gate, docs accuracy pass

### User-facing changes

- **Job card detail screen redesigned** — unified tile layout, streamlined sections and visual hierarchy across the Details, Assignment, and Timeline tabs.
- **Home screen: Create Job Card tile hidden when off-site** — employees whose `isOnSite` flag is `false` no longer see the Create Job Card tile. This prevents creating jobs while off-site without overriding the on-site check.
- **Registration now routes through onboarding** — first-time registrants are routed through the full 7-page `PermissionsOnboardingScreen` (same as existing users) so location monitoring and permission grants happen immediately after account creation.
- **Unified job card tile** — `JobCardTile` widget refactored for consistent display across Home recent-jobs list, ViewJobCards, MyAssignedJobs, ClosedJobs, and DailyReview.

### Documentation corrections

- **Permissions onboarding**: corrected page count from 3 to 7; listed all pages (Welcome, Your Role, Job Card Flow, Job Status, Priority Levels, Escalation, Grant Permissions).
- **View Job Cards**: role corrected from "Manager, Admin" to "All" — operators and technicians can browse job lists.
- **Role-Based Visibility** section: corrected inference order (Admin → Manager → Technician → Operator catch-all); removed incorrect "Technician = anyone else" statement.
- **CLAUDE.md**: added `utils/` to architecture tree; documented all 4 Riverpod providers; added missing services (`ConnectivityService`, `JobAlertService`, `UpdateService`); expanded Cloud Functions inventory to all 13 functions; fixed Manager role key screens (removed non-existent "NotificationHistory", added MonitoringDashboard and DailyReview).

---

## 2026-05-18 — Documentation portal, role-aware onboarding, accuracy pass

### New for users

- **One docs portal** — `docs/index.html` is the single entry point. Sidebar nav links to every guide (employee, manager, executive, app features, escalation, screens, troubleshooting). Open it in any browser.
- **Role-aware onboarding** — first-login carousel now branches on your role (Technician / Manager / Operator / Admin). The shared pages on P1–P5 priorities, escalation, and permissions stay the same for everyone — that's the part everyone needs to know.
- **P1–P5 explained explicitly** — onboarding now shows all five priority levels with the exact notification behaviour (banner / persistent / full-screen alarm) tied to each.
- **4-stage escalation diagram** — onboarding includes a stage-by-stage walkthrough with the actual defaults (5 / 10 min enabled; 30 / 60 min disabled, configurable by Admin).

### New for admins

- **Three new docs** —
  - [Cloud Functions deployment guide](cloud_functions_deployment.md) — function inventory, two-region layout (`africa-south1` + `europe-west1`), deployment commands, common failure modes.
  - [Troubleshooting & FAQ](troubleshooting.md) — symptom-driven fixes for notifications, geofence, sync, login, and escalation.
  - [Firebase security rules guide](firebase_security_rules.md) — what `storage.rules` enforces, what Firestore rules *should* enforce, action items for tightening.

### Documentation toolchain

- **Markdown is now the single source of truth.** Every doc lives as `.md` first; HTML and PDF are generated by `tools/build-docs.ps1`. To update a guide: edit the `.md`, run the script, commit all three.
- **Backfilled orphans** — `app_features.html`, `escalation_system.html`, `screens_reference.html` now have corresponding `.md` files so future edits go through markdown.
- **CI workflow** — `.github/workflows/docs.yml` regenerates and validates HTML on every PR.

### Accuracy fixes

- `CLAUDE.md` — escalation corrected from 3-stage to 4-stage; the `Employee.role` field reference removed (role is inferred from `position`); region split between `africa-south1` and `europe-west1` documented.
- Role guides — escalation defaults corrected to 5 / 10 / 30 / 60 min with stages 3 and 4 disabled by default (previously documented as 2 / 7 / 30 / 60 with all enabled).
- `manager_guide.md` — Daily Review (web) added; previously undocumented.

### Removed

- `migrate.html` — orphan build artifact at repo root, not linked anywhere.

---

<!-- Add new entries above this line. Keep entries scoped to a single release. -->
