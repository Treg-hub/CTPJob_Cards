# CTP Job Cards Project Brief

## Project Overview
CTP Job Cards is a Flutter mobile application designed for maintenance department management. The app enables operators to create, assign, track, and manage maintenance job cards efficiently.

## Core Functionality
- **Job Card Creation**: Operators can create detailed job cards with priority levels, descriptions, locations (department/area/machine/part), types (mechanical/electrical), and photo attachments with maximum compression for storage efficiency.
- **Employee Management**: Maintains a database of employees with clock numbers, positions, departments, and onsite status.
- **Automatic On-Site Detection**: Native geofencing (2km radius around company coordinates) automatically updates employee onsite status and sends notifications on entry/exit.
- **Assignment System**: Managers can assign jobs to employees with filtering by department, position, and onsite status.
- **Real-time Tracking**: Track job status (pending, assigned, started, completed) with timestamps and comments.
- **Notifications**: Push notifications to assigned employees via FCM, plus local notifications for onsite status changes.
- **Reporting**: Dashboard views for managers with job statistics and trends.
- **Copper Inventory Management**: Complete copper tracking system for managers with real-time dashboard, transactions, sorting, and password authentication.

## Technical Stack
- **Frontend**: Flutter (Dart)
- **Backend**: Firebase Firestore (data storage), Firebase Cloud Functions (server-side logic)
- **Authentication**: Firebase Auth (implied)
- **Notifications**: Firebase Cloud Messaging (FCM)
- **State Management**: Riverpod pattern with Notifier classes

## Key Features
- Priority-based job management (P1-P5)
- Reoccurrence tracking for recurring issues
- Comment system for work updates
- Onsite/offsite employee filtering
- Mechanical/Electrical specialization filtering
- Real-time employee status updates

## Business Value
Streamlines maintenance workflows, improves response times, tracks recurring issues, and provides visibility into department operations.

## Success Criteria
- Reliable job assignment and tracking
- Intuitive user interface for operators and managers
- Real-time notifications and updates
- Accurate reporting and analytics