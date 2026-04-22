# CTP Job Cards

**Professional Job Card Tracking System**  
Built with Flutter + Firebase for field technicians and operations teams.

## Overview

CTP Job Cards is a cross-platform mobile application designed for tracking job cards in the field. It supports offline-first operation, geofenced location verification, photo evidence, real-time notifications, and full audit logging — making it ideal for construction, maintenance, mining, utilities, or any operation that needs reliable job tracking with accountability.

## Key Features

- **Job Card Management** — Create, update, assign, and track job cards with status workflow
- **Offline-First Sync** — Full offline support with visual queue, conflict resolution (last-write-wins + manual merge), and one-tap sync
- **Geofencing & Location** — Verify technicians are on-site with accurate geofencing and background tracking
- **Photo Evidence** — Upload, compress, and manage photos with admin deletion controls
- **Real Push Notifications (FCM)** — Instant notifications for new assignments and updates (works even when app is closed)
- **Audit Logging** — Complete history of every change made to any job card (`job_card_audit` collection)
- **Notifications History** — Managers can view every notification the system has sent
- **Cross-Platform** — Android, iOS, Web, Windows, macOS, Linux

## Tech Stack

- **Frontend**: Flutter (Dart)
- **Backend**: Firebase (Firestore, Authentication, Storage, Cloud Functions, Crashlytics)
- **Key Packages**: `firebase_messaging`, `flutter_local_notifications`, `geolocator`, `workmanager` / background services, etc.

## Getting Started

### Prerequisites
- Flutter 3.22+
- Firebase project with Firestore, Auth, Storage, and Cloud Messaging enabled
- Android Studio / Xcode for mobile development

### Setup Instructions

1. **Clone the repository**
   ```bash
   git clone https://github.com/Treg-hub/CTPJob_Cards.git
   cd CTPJob_Cards

Install dependenciesBashflutter pub get
Firebase Setup
Create a new Firebase project (or use existing)
Enable Authentication, Firestore, Storage, and Cloud Messaging
Run flutterfire configure and follow the prompts
Deploy Firestore security rules and indexes (firebase deploy --only firestore)
(Optional but recommended) Deploy Cloud Functions for notification triggers

Run the appBashflutter run

Project Structure
textlib/
├── main.dart
├── models/               # JobCard, User, AuditLog, Notification models
├── services/             # SyncService, AuditService, NotificationService, etc.
├── screens/              # Home, JobCardDetail, NotificationsHistory, etc.
├── widgets/              # Reusable UI components
├── utils/                # Helpers, constants
assets/
functions/                # Firebase Cloud Functions (Node.js)
How It Works (High Level)

Technicians create/update job cards offline.
Changes are queued locally.
On sync: conflicts are detected and resolved intelligently.
Every change is logged to the job_card_audit collection.
Relevant events trigger push notifications via FCM.
Managers can view full audit history and notification logs.

Roadmap (Implemented Features)

 Offline sync with conflict resolution
 Real FCM push notifications + local fallback
 Full audit logging (job_card_audit)
 Manager-only notifications history screen
 Advanced reporting & PDF export
 Interactive map view with geofences
 Time tracking & productivity reports

Contributing
Pull requests are welcome! Please open an issue first to discuss major changes.
License
MIT License – see LICENSE file.

Built with ❤️ by Treg-hub