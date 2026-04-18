# System Patterns

## System Architecture

### Frontend Architecture (Flutter)
```
lib/
├── main.dart                 # App entry point, Firebase init, theme, routing
├── models/                   # Data models (Employee, JobCard, CopperInventory, etc.)
├── providers/                # Riverpod state management (theme, copper inventory)
├── screens/                  # UI screens (home, detail, create, admin, etc.)
├── services/                 # Business logic (Firestore, Notifications, Sync)
├── theme/                    # App theming (colors, extensions)
├── widgets/                  # Reusable UI components (skeleton, sync indicator)
├── firebase_options.dart     # Firebase configuration
└── stub.dart                 # Development stub file
```

### Backend Architecture (Firebase)
```
Firebase Project
├── Firestore Database        # Document-based storage
│   ├── employees/           # Employee collection
│   ├── jobCards/            # Job card collection
│   ├── copper_inventory/    # Copper inventory single document
│   └── copper_transactions/ # Copper transaction history
├── Cloud Functions          # Server-side logic
│   └── functions/
│       ├── index.js         # Main functions
│       └── lib/             # Helper functions
├── Cloud Messaging          # Push notifications
└── Authentication           # User management (implied)
```

## Key Technical Decisions

### State Management
- **Decision**: Riverpod pattern with Notifier classes and service classes
- **Rationale**: Modern, scalable state management for Firebase integration and better testability
- **Implementation**: Notifier classes for complex state (theme, copper inventory), service classes for data operations, screens consume via Riverpod providers and StreamBuilder

### Firestore Transactions
- **Decision**: Atomic transactions for inventory updates
- **Rationale**: Ensures data consistency for copper inventory operations
- **Implementation**: runTransaction for multi-document updates (inventory + transaction)

### Data Models
- **Employee Model**: Core entity with displayName getter for consistent formatting
- **JobCard Model**: Comprehensive job tracking with status enum, timestamps, and sequential jobCardNumber for easy reference
- **CopperInventory Model**: Single document tracking sort/reuse/sell kg, current R/kg, last updated
- **CopperTransaction Model**: Transaction history with type, amount, buckets, comments, user ID
- **SyncQueueItem Model**: Offline queue item with Hive serialization for offline operations
- **CopyWith Pattern**: Immutable updates with copyWith methods

### UI Patterns
- **Card-based Layout**: Consistent use of Cards for sectioned information
- **Dialog-heavy UX**: Complex operations (assign, comment) use modal dialogs
- **Color-coded Priorities**: P1-P5 with distinct visual indicators
- **Icon + Text Buttons**: Floating action buttons with clear visual cues
- **Notes-style Logs**: Activity and assignment logs display as timestamped lists with left alignment, replicating comment/note format
- **Photo Display**: Horizontal scrolling photo gallery with CachedNetworkImage for job documentation
- **Theme Switching**: Dynamic light/dark mode toggle in settings, persisted via SharedPreferences, with orange primary maintained across themes
- **Copper-themed UI**: Amber/orange colors for copper inventory module
- **Password Authentication**: Modal password dialog for sensitive copper operations

## Design Patterns

### Repository Pattern
- **FirestoreService**: Centralized data access layer
- **Methods**: CRUD operations, streams, and complex queries
- **Benefits**: Clean separation, testable, maintainable

### Factory Pattern
- **Model.fromFirestore()**: Creates model instances from Firestore documents
- **Benefits**: Centralized deserialization, consistent data mapping

### Builder Pattern
- **JobCard Creation**: Step-by-step job card building in create screen
- **Benefits**: Complex object construction, validation at each step

### Observer Pattern
- **StreamBuilder**: Reactive UI updates from Firestore streams
- **Benefits**: Real-time data synchronization, automatic UI refresh

## Component Relationships

### Core Flow: Job Creation → Assignment → Completion → Optional Monitoring
```
Create Job Card
    ↓
Assign to Employees (with filtering)
    ↓
Employee Notification
    ↓
Status Updates & Comments
    ↓
Job Completion (optional monitoring)
    ↓
Monitoring (7 days, auto-close if no adjustments)
    ↓
Closed (final status)
```

### Data Flow
```
Firestore ←→ FirestoreService ←→ Screens ←→ User Interactions
    ↑              ↑                    ↑
Notifications  Push Updates       UI State Updates
```

## Critical Implementation Paths

### Job Assignment Flow
1. **Dialog Opening**: `_showAssignCompleteDialog()` initializes filters and state
2. **Employee Streaming**: `getEmployeesStream()` provides real-time employee list
3. **Filtering Logic**: Sequential filters (search → onsite → department/mech-elec)
4. **Selection Management**: Local state tracks selected employees
5. **Assignment Execution**: Batch update job card + send notifications
6. **Confirmation**: UI feedback and dialog closure

### Notification Flow
1. **Trigger**: Job creation, assignment, or timed escalation
2. **Priority Check**: Read job.priority (1-5) to determine level (normal/medium-high/full-loud)
3. **Recipient Selection**: Techs for creation, assignee for assignment, escalating groups for escalations
4. **Level Application**: CF passes notificationLevel in FCM data
5. **Client Handling**: Dart switches on level for channel/sound/vib/fullscreen
6. **Send Operation**: Async FCM with error handling
7. **Logging**: Debug prints for tracking

### Comment System
1. **Dialog Display**: Bottom sheet with reoccurrence counter
2. **Comment Formatting**: Timestamp + user prefix
3. **Update Operation**: Append to existing comments + update reoccurrence
4. **UI Refresh**: Automatic via StreamBuilder

### Job Creation Flow
1. **Form Submission**: User fills job card details
2. **Counter Transaction**: Atomically read/increment counters/jobCards nextJobCardNumber
3. **Document Creation**: Create job_cards/ doc with jobCardNumber set to incremented value
4. **UI Confirmation**: Show success with new job number

### Photo Upload Flow
1. **Source Selection**: User chooses camera or gallery via dialog
2. **Image Capture/Pick**: Use image_picker to get image file
3. **Maximum Compression**: Apply 1024px min dimension, 70% quality compression for 70-85% size reduction
4. **UUID Path Generation**: Create unique storage path with job_cards/{uuid}/photos/{timestamp}.jpg
5. **Firebase Upload**: Put compressed file to Firebase Storage with jpeg content type
6. **URL Retrieval**: Get download URL from uploaded file
7. **Job Card Update**: Add photo metadata to job card photos array, save via FirestoreService
8. **UI Refresh**: Update job card state and show success message

## Performance Considerations
- **Stream Efficiency**: Firestore streams update entire lists - monitor for large datasets
- **Image Loading**: No images currently, but prepared for asset integration
- **Memory Management**: Stateful widgets disposed properly, no memory leaks
- **Build Optimization**: Debug builds tested, release builds pending

## Error Handling Patterns
- **Network Errors**: ScaffoldMessenger snackbars for user feedback
- **Validation**: Client-side checks before Firestore operations
- **Graceful Degradation**: Null-safe operations with fallback values
- **Logging**: Debug prints for development, structured logging for production