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
├── utils/                       # Pure helpers: role inference (role.dart), docs catalog (doc_catalog.dart)
└── theme/app_theme.dart         # Material3 theme + AppColors extension
```

**State management**: Riverpod (`flutter_riverpod ^2.5.3`). Screens extend `ConsumerStatefulWidget` / `ConsumerWidget` to read providers. State lives in `providers/`:

| Provider | What it manages |
|---|---|
| `currentEmployeeProvider` | Logged-in `Employee` loaded from SharedPreferences + Firestore |
| `themeNotifierProvider` | Dark/light theme toggle, persisted to SharedPreferences |
| `permissionsProvider` | Live status of 4 critical Android permissions; logs grants to Firestore |
| `copperNotifierProvider` | `CopperInventory` async state; wraps all copper transaction operations |

**Backend**: Firestore is the single source of truth. All writes go through `FirestoreService`, which also appends to the `job_card_audit` collection for every change.

**Offline sync**: `SyncService` queues failed writes in a Hive box (`sync_queue`). It listens to `connectivity_plus` and replays the queue when connectivity is restored.

**Push notifications**: FCM via `firebase_messaging` + Cloud Functions with 4-stage escalation.

**Geofencing**: Uses `geolocator` + `workmanager` with native Kotlin support.

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
- Admin is currently gated by hardcoded `clockNo == "22"`
- There is **no go_router** and **no centralized route guards**
- Permission checks are scattered across multiple screens
- Copper features are controlled by a hardcoded whitelist

---

## Key Android Details

- **Min/Target SDK**: Driven by `flutter.minSdkVersion` / `flutter.targetSdkVersion` in `android/app/build.gradle.kts`
- **Java/Kotlin target**: Java 11 (desugaring enabled), Kotlin 1.9.22
- **NDK ABI filter**: `arm64-v8a` only
- **JVM heap**: `-Xmx8G -XX:MaxMetaspaceSize=4G` in `gradle.properties`

## Role-Based Access

Four roles, **inferred from `Employee.position` and `Employee.department`**.

| Role | Inference | Key Screens |
|------|-----------|-------------|
| Technician | `position` contains `mechanical`, `electrical`, or `technician` | Home, CreateJobCard, ViewJobCards, JobCardDetail |
| Manager | `position` contains `manager` | ManagerDashboard, DailyReview, ViewJobCards |
| Operator | neither manager nor technician | Limited actions on JobCardDetail |
| Admin | `clockNo == "22"` | Full access to AdminScreen and all admin features |

See `docs/architecture/visualization.md` for the complete and visual permission matrix.

## Job Card Types & Notifications

Four types: **Mechanical**, **Electrical**, **Mech/Elec**, **Maintenance**.

- Maintenance jobs are **silent** (excluded from creation notifications and escalation).
- Type changes re-fire notifications via the `onJobCardTypeChanged` trigger.

## Firestore Collections

- `job_cards`
- `job_card_audit`
- `employees`
- `notifications`
- `copper_inventory` / `copper_transactions`

## Local Storage

- **Hive**: `sync_queue`
- **SharedPreferences**: `loggedInClockNo`, `permissionsCompleted`

## Cloud Functions

Located in `/functions/index.js`. Uses two regions:
- `africa-south1` (default)
- `europe-west1` (for scheduled functions)

## Testing

Minimal test coverage currently exists.

<!-- SPECKIT START -->
**Active feature**: Scheduled Waste Load Handoff (`001-scheduled-waste-handoff`)
**Plan**: `specs/001-scheduled-waste-handoff/plan.md`
**Spec**: `specs/001-scheduled-waste-handoff/spec.md`
**Research**: `specs/001-scheduled-waste-handoff/research.md`
**Data model**: `specs/001-scheduled-waste-handoff/data-model.md`
<!-- SPECKIT END -->