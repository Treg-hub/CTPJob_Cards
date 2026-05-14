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

**Push notifications**: FCM via `firebase_messaging`. Cloud Functions (`/functions/index.js`, deployed to `africa-south1`) drive escalation: 2-min → 7-min → 30-min timers based on job type and priority. `FirebaseMessagingService.kt` handles native FCM receipt; `FullScreenJobAlertActivity.kt` renders the full-screen overlay.

**Geofencing**: `LocationService` + `BackgroundGeofenceService` use `geolocator` + `workmanager`. Native Kotlin code in `android/app/src/main/kotlin/` handles `GeofenceBroadcastReceiver`, `AlertForegroundService`, and `AlarmReceiver`. The `GeofenceEditorScreen` allows on-device geofence configuration.

## Key Android Details

- **Min/Target SDK**: Driven by `flutter.minSdkVersion` / `flutter.targetSdkVersion` in `android/app/build.gradle.kts`
- **Java/Kotlin target**: Java 11 (desugaring enabled), Kotlin 1.9.22 (Gradle plugin 2.2.20)
- **NDK ABI filter**: `arm64-v8a` only
- **TSLocationManager** is pinned to `4.1.6` via a resolution strategy in `android/build.gradle.kts` to avoid a buggy v21 variant
- **JVM heap**: `-Xmx8G -XX:MaxMetaspaceSize=4G` in `gradle.properties` — don't lower these without testing

## Role-Based Access

Three roles, determined by the `role` field on the `Employee` Firestore document:

| Role | Key Screens |
|------|------------|
| Technician | Home, MyAssignedJobs, JobCardDetail, CreateJobCard |
| Manager | ManagerDashboard, ViewJobCards, CopperDashboard, NotificationHistory |
| Admin | AdminScreen, GeofenceEditor, EmployeeManagement |

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

Located in `/functions/index.js` (Node.js v24, region: `africa-south1`). Key responsibilities:
- `createCustomToken` — custom auth token issuance
- Notification dispatch with escalation timers
- Role-based employee routing (mechanic, electrician, manager, foreman)

## Testing

Coverage is minimal — one smoke test in `test/widget_test.dart` that verifies `LoginScreen` renders. There is no mock layer; service calls hit real Firebase in tests.

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
<!-- SPECKIT END -->
