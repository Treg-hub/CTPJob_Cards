# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
├── models/                      # Plain Dart data classes (some are @HiveType)
├── providers/                   # Riverpod Providers and StateNotifiers
├── services/                    # All business logic (Firestore, Sync, Location, Notifications)
├── screens/                     # UI screens (ConsumerStatefulWidget where Riverpod needed)
├── widgets/                     # Reusable UI components
└── theme/app_theme.dart         # Material3 theme + AppColors extension
```

**State management**: Riverpod (`flutter_riverpod ^2.5.3`). Screens extend `ConsumerStatefulWidget` / `ConsumerWidget` to read providers. State lives in `providers/`.

**Backend**: Firestore is the single source of truth. All writes go through `FirestoreService`, which also appends to the `job_card_audit` collection for every change.

**Offline sync**: `SyncService` queues failed writes in a Hive box (`sync_queue`). It listens to `connectivity_plus` and replays the queue when connectivity is restored. `SyncQueueItem` is `@HiveType` annotated — run `build_runner` after modifying it.

**Push notifications**: FCM via `firebase_messaging`. Cloud Functions live in `/functions/index.js`. HTTP/callable functions deploy to `africa-south1`; **scheduled functions (`escalateNotifications`, `autoCloseMonitoringJobs`) must stay in `europe-west1`** — Firebase scheduled functions require a region that supports App Engine, which `africa-south1` does not. Escalation runs as 4 configurable stages stored in `notification_configs/global` (defaults: 5 / 10 / 30 / 60 min; stages 3 and 4 are disabled by default). `FirebaseMessagingService.kt` handles native FCM receipt; `FullScreenJobAlertActivity.kt` renders the full-screen overlay.

**Geofencing**: `LocationService` + `BackgroundGeofenceService` use `geolocator` + `workmanager`. Native Kotlin code in `android/app/src/main/kotlin/com/ctp/jobcards/` handles `GeofenceReceiver`, `GeofenceHelper`, `AlertForegroundService`, and `AlarmReceiver`. The `GeofenceEditorScreen` allows on-device geofence configuration.

## Key Android Details

- **Min/Target SDK**: Driven by `flutter.minSdkVersion` / `flutter.targetSdkVersion` in `android/app/build.gradle.kts`
- **Java/Kotlin target**: Java 11 (desugaring enabled), Kotlin 1.9.22 (Gradle plugin 2.2.20)
- **NDK ABI filter**: `arm64-v8a` only
- **JVM heap**: `-Xmx8G -XX:MaxMetaspaceSize=4G` in `gradle.properties` — don't lower these without testing

## Role-Based Access

Four roles, **inferred from `Employee.position` and `Employee.department`** — the `Employee` model has no explicit `role` field. The canonical inference lives in `lib/utils/role.dart` (`roleFromEmployee()` returning a `UserRole` enum). Admin is gated by a password prompt in `SettingsScreen`, not by position.

| Role | Inference | Key Screens |
|------|-----------|-------------|
| Technician | `position` contains `mechanical`, `electrical`, or `technician` | Home, MyAssignedJobs, JobCardDetail, CreateJobCard |
| Manager | `position` contains `manager` | ManagerDashboard, ViewJobCards, DailyReview (web), NotificationHistory |
| Operator | neither manager nor technician | Home, CreateJobCard (primary), ViewJobCards |
| Admin | hardcoded `clockNo == "22"` (also a password gate in `SettingsScreen` → "Admin") | AdminScreen (Employees / Structures / Escalation Config / Job Cards tabs), GeofenceEditor |

### Capability matrix (job card actions)

| Action | Operator | Technician | Manager | Admin |
|---|---|---|---|---|
| Create job card (any type) | ✅ | ✅ | ✅ | ✅ |
| Start / Complete / Monitor — Maintenance | ✅ | ✅ | ✅ | ✅ |
| Start / Complete / Monitor — Mech/Elec/MechElec | ❌ | ✅ | ✅ | ✅ |
| Join (Start) an in-progress job | ❌ | ✅ (Maintenance + any if technician) | ✅ | ✅ |
| Change job card type | ❌ | ✅ | ✅ | ✅ |
| Assign / unassign others | ❌ | ❌ | ✅ | ✅ |
| Close / reopen / move to monitor via status pill | ❌ | ❌ | ✅ | ✅ |
| Add note | ❌ | ✅ | ✅ | ✅ |
| Add comment | ✅ | ❌ | ✅ | ✅ |
| Add photo | ✅ | ✅ | ✅ | ✅ |
| Remove photo (own) | ✅ | ✅ | ✅ | ✅ |
| Remove photo (any) | ❌ | ❌ | ❌ | ✅ |

**Operator gating** (Maintenance only for Start/Complete/Monitor on mech/elec jobs) is enforced by `_operatorRestrictedFor()` in `job_card_detail_screen.dart`. Operators can still create any type — they need to raise mech/elec faults.

**Technician join-in-progress**: when an open Mechanical/Electrical/Mech-Elec job is already in progress, additional technicians can self-assign by tapping "Join (Start)" on the detail screen. The data model (`assignedClockNos: List<String>`) supports multiple assignees.

**Type changes** route through `FirestoreService.changeJobCardType()` which resets `notifiedAtStageN`, appends a `type_changed` entry to `assignmentHistory`, and triggers the `onJobCardTypeChanged` cloud function to notify the new audience.

Additional flags: `isSuperManager` (`department == "general"`) sees factory-wide manager views; CopperDashboard is whitelisted to specific clock numbers (`22`, `5421`, `20`).

## Job Card Types & Notifications

Four types: **Mechanical**, **Electrical**, **Mech/Elec** (notifies both), **Maintenance**.

- The first three fan out at creation per `notification_configs/global` (`creation_recipients_by_type`) and escalate through stages 1–4.
- **Maintenance is silent** — `excluded_job_types: ["maintenance"]` in `notification_configs/global` means zero creation notifications and zero escalation. Use for planned/routine work; the responsible team must pull these from job lists themselves. `autoCloseMonitoringJobs` is type-agnostic, so a Maintenance job in Monitor will still auto-close after 7 days.
- **Type enum serialization** lives in `lib/models/job_card.dart`. Writes use `type.name` (camelCase, e.g. `"mechanicalElectrical"`); `JobType.fromString` accepts both that form and legacy display names. Don't change the enum names without a migration plan — Firestore docs store the name verbatim.
- Changing a type after creation re-fires the creation notification via the `onJobCardTypeChanged` Firestore trigger (in `africa-south1`), excluding the original creator from any P5 CC.

## Firestore Collections

- `job_cards` — core job card documents
- `job_card_audit` — append-only audit log (written by `FirestoreService`)
- `employees` — user profiles with roles
- `notifications` — notification log (written by Cloud Functions)
- `copper_inventory` / `copper_transactions` — copper stock management

## Local Storage

- **Hive box `sync_queue`**: `SyncQueueItem` objects (offline write queue)
- **SharedPreferences**: `loggedInClockNo` (logged-in employee), `permissionsCompleted` (onboarding flag)

## Initialization Order

`main.dart` bootstraps in this exact sequence — order matters:
1. Hive init
2. Firebase + Crashlytics
3. `NotificationService.init()`
4. Firestore persistence settings
5. `SyncService.init()` + queue listener
6. Auth state check → route to `LoginScreen` or `HomeScreen` (with permissions check)
7. Background location monitoring start

## Cloud Functions

Located in `/functions/index.js` (Node.js v24). Two regions in use:

- **`africa-south1`** (default per `firebase.json`): `createCustomToken`, `onJobCardCreated`, `clearEscalationStamps`, etc.
- **`europe-west1`** (set per-function): `escalateNotifications` (every 2 min) and `autoCloseMonitoringJobs` (scheduled) — scheduled functions require an App-Engine-supported region.

Key responsibilities:
- `createCustomToken` — custom auth token issuance
- `onJobCardCreated` — initial notification dispatch to creation recipients
- `escalateNotifications` — 4-stage escalation driven by `notification_configs/global`
- `autoCloseMonitoringJobs` — auto-close Monitor jobs after threshold
- Recipient routing via rules (`onsite_mechanics`, `onsite_electricians`, `onsite_managers`, `foremen`, `onsite_dept_managers`, `onsite_workshop_manager`, `offsite_*`, `operator`)

See `docs/cloud_functions_deployment.md` for the full inventory and deployment steps.

## Testing

Coverage is minimal — one smoke test in `test/widget_test.dart` that verifies `LoginScreen` renders. There is no mock layer; service calls hit real Firebase in tests.

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
<!-- SPECKIT END -->
