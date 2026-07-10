# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git Workflow

**Always use feature branches — never commit implementation work directly to `master`.**

1. Before starting any implementation, create a feature branch:
   ```bash
   git checkout -b feat/<short-description>   # new features / refactors
   git checkout -b fix/<short-description>    # bug fixes
   git checkout -b docs/<short-description>   # documentation only
   ```
2. Commit work to that branch, then open a PR into `master`:
   ```bash
   gh pr create --base master --title "..." --body "..."
   ```
3. After the PR is merged (or the user approves merging), `master` is updated.
4. Delete the feature branch locally and remotely after merging.

**Never push implementation commits directly to `master`.** Hotfixes to CLAUDE.md or settings files are the only acceptable direct-to-master commits.

### Build number (release only — not every commit)

`pubspec.yaml` `version: X.Y.Z+N` is bumped **only when shipping an APK**, not on ordinary commits (CF, docs, lint).

| Ritual | Skill | Hosting file |
|--------|--------|----------------|
| Factory | `/mobile-app-release` (monorepo skill) | `releases/latest.apk` |
| Pilot | `/mobile-pilot-release` | `releases/pilot.apk` |

```bash
# Explicit bump (skills run this before build unless user already bumped)
node scripts/bump-build-number.js
```

Then prepend `docs/CHANGELOG.md` with the **exact** new build number, build, publish.  
Admin App Update Control version/build must match the binary on Hosting.

`githooks/pre-commit` does **not** auto-bump. Optional: `pwsh scripts/setup-githooks.ps1` only sets hooks path (no version side effects).

## Project Overview

CTP Job Cards is a **Flutter + Firebase** mobile app for field technician job card tracking. It targets Android (primary), with iOS/web secondary. The app is production-grade with offline-first sync, real-time push notifications with escalation logic, background geofencing, role-based access, and audit logging.

## Common Commands

```bash
# Install dependencies
flutter pub get

# Run the app (debug)
flutter run

# Analyze / lint
flutter analyze

# Run all tests
flutter test

# Run a single test
flutter test test/widget_test.dart -v

# Generate Hive type adapters (after modifying @HiveType models)
flutter pub run build_runner build --delete-conflicting-outputs

# Build release APK / AAB
flutter build apk --release
flutter build appbundle --release

# Deploy Cloud Functions
cd functions && npm install && firebase deploy --only functions

# Deploy Firestore rules/indexes
firebase deploy --only firestore
```

## Architecture

**Pattern**: Service-based MVVM with Riverpod state management.

```
lib/
├── main.dart                    # Entry point: Hive → Firebase → Notifications → Sync → Auth routing
├── firebase_options.dart        # Auto-generated, do not edit manually
├── constants/                   # Canonical Firestore collection name constants (collections.dart)
├── models/                      # Plain Dart data classes (some are @HiveType)
├── providers/                   # Riverpod Providers and StateNotifiers
├── services/                    # All business logic (Firestore, Sync, Location, Notifications, Waste)
├── screens/                     # UI screens (ConsumerStatefulWidget where Riverpod needed)
├── widgets/                     # Reusable UI components
├── utils/                       # Pure helpers: role inference (role.dart), docs catalog, formatters, deviation
└── theme/app_theme.dart         # Material3 theme + AppColors extension
```

**State management**: Riverpod (`flutter_riverpod ^2.5.3`). Screens extend `ConsumerStatefulWidget` / `ConsumerWidget` to read providers. State lives in `providers/`:

| Provider | What it manages |
|---|---|
| `currentEmployeeProvider` | Logged-in `Employee` loaded from SharedPreferences + Firestore |
| `themeNotifierProvider` | Dark/light theme toggle, persisted to SharedPreferences |
| `permissionsProvider` | Live status of 4 critical Android permissions; logs grants to Firestore |
| `copperNotifierProvider` | `CopperInventory` async state; wraps all copper transaction operations |
| `wasteNotifierProvider` | Current in-progress `WasteLoad` state; wraps load creation, item additions, and weighbridge sign-off |

**Backend**: Firestore is the single source of truth. All writes go through `FirestoreService`, which also appends to the `job_card_audit` collection for every change.

**Offline sync**: `SyncService` queues failed writes in a Hive box (`sync_queue`). It listens to `connectivity_plus` and replays the queue when connectivity is restored.

**Push notifications**: FCM via `firebase_messaging` + Cloud Functions with 4-stage escalation.

**Geofencing**: Uses `geolocator` + `workmanager` with native Kotlin support.

**Startup resilience (2026-07-03)**: The cold-start / auto-login path is hardened so a claims/token race or dead session can't leave Home blank.
- **`services/resilient_stream.dart`** — `resilientSnapshots<T>()` wraps Firestore snapshot streams so a `permission-denied` (which terminates a listener *permanently*) no longer blanks the screen: it refreshes claims + retries with backoff, and re-arms parked streams via `RetryTriggers` (connectivity / claims-completion / resume / auth). Errors are never forwarded downstream. Retry decisions live in the **pure** `utils/stream_retry_policy.dart` (unit-tested).
- **`utils/list_load_state.dart`** — pure `decideListLoadState()` so a cached-empty snapshot renders "Waiting for connection…" not a false empty state. `FirestoreService` exposes `...WithMeta` variants carrying `metadata.isFromCache`.
- **`widgets/session_health_banner.dart`** — top-of-Home banner for a dead/revoked auth session or a server-confirmed employee-doc deletion; "Sign in" preserves prefs + the Hive `sync_queue`.
- **Home streams are hoisted to `State` fields** — never build a Firestore stream inline in `build()`; that re-subscribes on every rebuild (flicker + wasted reads + resets retry state).
- **Constraint**: nothing new blocks startup — `main.dart` only *caps* existing waits (kill-switch/uid-restore/employee fetch timeouts) and everything resilience-related runs after the first frame.
- **`AuthClaimsService.refreshClaims()`** is deduped + exposes `onRefreshCompleted`; call it **after** `linkMyAccount` (login and registration) so the CF can derive `clockNum`.

**Navigation**: one `PageTransitionsTheme` (Cupertino slide) is set on both themes in `main.dart` — use plain `MaterialPageRoute`; the theme gives the consistent animation. Home Quick Actions grid is width-constrained on desktop (`_maxContentWidth`/`_gridChildAspectRatio`).

---

## Architecture Visualization & Role-Based Access

For a detailed, visual, and up-to-date understanding of screens, roles, and permissions, refer to:

**`docs/architecture/visualization.md`**

This file is the **single source of truth** for role-based access in the app and contains:

- **Permission Matrix** — Clear table showing which roles can access which screens + restrictions
- **Navigation Flow Diagram** — Role-aware navigation with branches
- **Role-to-Screen Access Graph** — Visual mapping of roles to accessible screens
- **High-Level Architecture Overview** — Current state management, navigation style, and authorization approach

### How to Regenerate
After making significant changes to screens, roles, navigation, or permission logic, run this inside **OpenCode**:

```bash
/update-architecture
```

This performs a full recursive analysis of `lib/` and updates the visualization file.

### Current Role System Summary
- Roles are **derived** from `Employee.position` + `department` (see `lib/utils/role.dart`)
- Admin is gated by `Employee.isAdmin` (Firestore field `isAdmin: true`)
- WasteTrack roles are derived from `department == "Security"` + `position` — `isSecurityManager()` and `isSecurityGuard()` are separate helpers in `role.dart`
- Fleet roles: `isFleetMechanic(emp, settings)`, `isFleetReporter(emp, settings)`, and `isFleetCostManager(emp, settings)` all read allow-lists from `fleet_settings/config` (`mechanic_clock_nos`, `reporter_departments`, `cost_manager_clock_nos`). The Fleet tab is gated on `fleet_settings.fleet_enabled` + `isFleetUser()`
- There is **no go_router** and **no centralized route guards**
- Permission checks are scattered across multiple screens
- Copper features are controlled by a hardcoded clock-number whitelist (`_copperAuthorizedClockNos` in `role.dart`)

---

## Key Android Details

- **Min/Target SDK**: Driven by `flutter.minSdkVersion` / `flutter.targetSdkVersion` in `android/app/build.gradle.kts`
- **Java/Kotlin target**: Java 11 (desugaring enabled), Kotlin 1.9.22
- **NDK ABI filter**: `arm64-v8a` only
- **JVM heap**: `-Xmx8G -XX:MaxMetaspaceSize=4G` in `gradle.properties`
- **Kiosk Mode (device lockdown)**: `KioskDeviceAdminReceiver.kt` + `res/xml/kiosk_device_admin.xml` + the `ctp/kiosk` MethodChannel in `MainActivity.kt` let a device be locked to this app via Android Lock Task Mode. Inert unless a specific tablet is enrolled as Device Owner (`adb shell dpm set-device-owner com.ctp.jobcards/.KioskDeviceAdminReceiver`) — see `lib/screens/kiosk_mode_screen.dart` for the in-app setup guide and the monorepo's `Components/kiosk-lockdown.md` for the full design (main-gate Site Security tablet is the first deployment target).

## Role-Based Access

Roles are **inferred from `Employee.position` and `Employee.department`** (see `lib/utils/role.dart`).

| Role | Inference | Key Screens |
|------|-----------|-------------|
| Technician | `position` contains `mechanical`, `electrical`, or `technician` | Home, CreateJobCard, ViewJobCards, JobCardDetail |
| Manager | `position` contains `manager` | ViewJobCards, Recent on Home; KPIs on CTP Pulse `/jobs` (no mobile Dashboard) |
| Operator | neither manager nor technician | Home, CreateJobCard (on-site only), JobCardDetail |
| Admin | `Employee.isAdmin == true` (Firestore field) | Full access to AdminScreen and all admin features |
| Security Manager | `department == "Security"` && `position == "Manager"` | WasteHome, WasteScheduleLoad, WasteReports, WasteAdmin |
| Security Guard | `department == "Security"` && `position == "Guard"` | WasteHome, WasteBeginCollection, WasteLoadDetail, WasteSignature, WastePendingWeighbridge |
| Fleet Mechanic | `clockNo` in `fleet_settings.mechanic_clock_nos` | FleetHome, FleetLogWork, FleetIssuesList, FleetIssueDetail (acknowledge/resolve), FleetWorkRecordDetail (no cost amounts; edits lock after 7 days or once costed) |
| Fleet Reporter | `department` in `fleet_settings.reporter_departments` | FleetHome, FleetReportIssue, FleetIssueDetail (read-only) |
| Fleet Cost Manager | `clockNo` in `fleet_settings.cost_manager_clock_nos` | FleetHome, FleetAddCost, FleetReports (+ CSV export), FleetWorkRecordDetail (with costs) |
| Fleet Admin | `Employee.isAdmin == true` (reuses isAdmin) | FleetAssets (manage register), FleetSettings, plus everything above |

Fleet roles are config-driven (read from `fleet_settings/config`), so all `role.dart` fleet helpers take a `FleetSettings` argument. Mechanics are also operators — they can report plant job cards. The mechanic never sees money — work records show only a "Costs pending / Costs entered" label.

Fleet domain rules: fault reports (`fleet_issues`) are content-immutable after creation (only status transitions). The fix is a separate work record; the fix form shows the fault read-only and the mechanic types their own description. Work records carry `cost_status` (`pending|costed|no_cost`) and lock against mechanic edits 7 days after creation (`FleetWorkRecord.editLockDays`) or as soon as `cost_status != pending`; admins are exempt. One work record can close multiple faults via `linked_issue_ids`.

See `docs/architecture/visualization.md` for the complete and visual permission matrix.

## Job Card Types & Notifications

Four types: **Mechanical**, **Electrical**, **Mech/Elec**, **Maintenance**.

- Maintenance jobs are **silent** (excluded from creation notifications and escalation).
- Type changes re-fire notifications via the `onJobCardTypeChanged` trigger.

## Firestore Collections

All collection names are defined as constants in `lib/constants/collections.dart` — always use the constant, never a string literal. Canonical names are mirrored in `packages/shared-ts/src/collections.ts` (web apps).

**Job Cards (unprefixed — legacy owner):**
- `job_cards`, `job_card_audit`, `counters`, `structures`, `settings`
- `notification_configs`, `notifications`, `alertResponses`
- `copper_inventory`, `copper_transactions`
- `geo_fence_logs`, `feedback` (+ `feedback/{id}/feedback_comments` two-way thread subcollection — submitter + admins only), `employees` (shared)

**Notification Inbox (subcollection):**
- `notification_inbox/{clockNo}/items` — off-site-held notifications per employee; written by Cloud Functions, read by `NotificationInboxScreen`

**WasteTrack (`waste_` prefix):**
- `waste_loads`, `waste_items`, `waste_types`, `waste_contractors`
- `waste_collection_companies`, `waste_rates`, `waste_settings`
- `waste_deleted_loads`, `waste_audit`, `waste_usage_logs`, `waste_counters`

**Fleet Maintenance (`fleet_` prefix):**
- `fleet_assets`, `fleet_issues`, `fleet_work_records` (with `fleet_work_parts` sub-collection)
- `fleet_cost_lines`, `fleet_types`, `fleet_settings`, `fleet_counters`, `fleet_audit`
- Work numbers `FM-NNNN` via global counter (Admin SDK only; legacy records may use `FM-YYYYMMDD-NNN`). Work records carry `cost_status` (`pending|costed|no_cost`), kept in sync by `FleetService.createCostLineResilient` / `deleteCostLine` / `markWorkRecordNoCost`. See `docs/COLLECTIONS.md` for the full schema.

## Local Storage

- **Hive**: `sync_queue`
- **SharedPreferences**: `loggedInClockNo`, `permissionsCompleted`, `lastSeenWhatsNewBuild` (What's-changed sheet — see `lib/services/whats_new_service.dart`; stamped at onboarding for fresh installs, compared against `PackageInfo.buildNumber` on HomeScreen mount)

## Release notes ("What's changed" sheet)

`WhatsNewService` shows a one-time bottom sheet with the newest `docs/CHANGELOG.md` entry the first time a user opens a new build (stamped **after** the sheet is dismissed). **Before building any release APK, prepend a user-facing entry to `docs/CHANGELOG.md`** — the top `## ` section is exactly what every updated user sees.

**In-app APK updates**: `UpdateService` + `ApkInstallService` + FileProvider. Soft = Home banner (**Later** = ~24h snooze only). Force = full-screen; **resume + cold start re-fetch** (not stuck behind 24h). Cohort re-check when employee loads. Kill-switch `minSupportedBuild` factory-wide with channel URL fallback. Guide + **release checklist**: `docs/admin_app_update_guide.md`. Legacy `publishedLatest*` = default channel only.

## Cloud Functions

Located in `/functions/index.js`. Named codebase: **`jobcards`** (set in `firebase.json`) — deploys from this repo only touch Job Cards functions and cannot wipe WasteTrack/Overtime functions in the monorepo.

Two regions:
- `africa-south1` — all callable + Firestore-trigger functions
- `europe-west1` — scheduled functions only (`escalateNotifications`, `autoCloseMonitoringJobs`)

Key functions:
- `onJobCardCreated` — dispatches creation notifications
- `onJobCardAssigned` / `sendJobAssignmentNotification` — assignment alerts; parks to inbox if recipient is off-site
- `sendCreatorNotification` — notifies job creator on status changes; parks if off-site
- `onAlertResponseCreated` — handles Busy responses; parks to inbox if creator is off-site
- `escalateNotifications` *(scheduled, every 2 min, europe-west1)* — 4-stage escalation loop
- `autoCloseMonitoringJobs` *(scheduled, 08:00 SAST, europe-west1)* — closes Monitor jobs after 7 days
- `clearEscalationStamps` — admin-triggered; clears stage stamps on open jobs
- `onCopperTransactionWrite` — copper sell alert; parks to inbox if recipient is off-site
- `onJobCardTypeChanged` — re-fires notifications when job type changes
- `onFeedbackStatusChanged` / `onFeedbackCommentCreated` — feedback loop: status changes + `feedback_comments` thread replies notify the submitter (or admins on submitter replies); push on-site, inbox park off-site with `feedbackId` deep link; maintains `lastCommentAt`/`commentCount`
- `createWasteLoad` *(callable, africa-south1)* — atomic load creation with global sequential number (W-NNNN, never resets)

**Fleet Maintenance functions live in the monorepo codebase, NOT this repo's `/functions`.** They are in `firebase/functions/src/index.ts` (the `wastetrack-overtime` codebase) and deployed from `/firebase`:
- `createFleetWorkRecord` *(callable, africa-south1)* — atomic work-record number (`FM-NNNN`). The mobile app **calls** this via `FleetService.createWorkRecordResilient`.
- `onFleetIssueCreated` *(Firestore trigger)* — out-of-service issues send a medium-high push (or park to inbox) to the mechanic + cost managers and set `fleet_assets.has_open_oos_issue`; high-severity issues park to the notification inbox only.
- `onFleetIssueUpdated` *(Firestore trigger)* — clears `has_open_oos_issue` when the last open OOS issue on an asset is resolved/cancelled.

## Testing

WasteTrack has the most test coverage:
- `test/waste_deviation_test.dart` — deviation threshold logic
- `test/waste_formatters_test.dart` — weight/date formatters
- `test/waste_offline_resilience_test.dart` — offline queue and sync behavior
- `test/waste_widget_smoke_test.dart` — basic widget render smoke tests
- `test/pilot_verification_harness.dart` — end-to-end pilot verification checklist

Job Cards core has minimal test coverage.