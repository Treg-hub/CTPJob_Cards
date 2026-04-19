# Active Context

## Current Work Focus
- **Job Card ID Simplification**: Implementing sequential numeric Job Card IDs (1,2,3...) instead of long alphanumeric Firestore IDs for easier reference
- **UI Bug Fixes**: Resolving display issues in job assignment dialogs
- **Memory Bank Setup**: Establishing documentation structure for future development
- **Code Quality**: Maintaining clean, efficient Flutter code with proper null safety
- **Job Status Standardization**: Updated job status system to Open, Monitor, Closed with consistent naming, colors, and UI
- **Monitoring Status Feature**: Added optional 7-day monitoring for completed jobs, auto-close if no adjustments, in-app dashboard for visibility
- **Assignment History Tracking**: Implemented detailed assignment history in activity log, showing who assigned whom with timestamps for all assignments and unassignments
- **Copper Inventory Module**: Complete copper tracking system for managers with dashboard, sorting, transactions, password auth, atomic updates

## Recent Changes
- **Hidden Recent Job Cards on Home Screen for Non-Managers**: Recent job cards list now only visible to managers and super-managers (department == 'general'), hiding it completely for operators and technicians.
  - **Before**: Recent job cards visible to all users on home screen
  - **After**: Only managers/super-managers see the list with "Show Dept Only" toggle
  - **Implementation**: Wrapped entire section in `if (isManager || isSuperManager) ...[]` in `_buildHomeTab`
  - **Rationale**: Aligns with role-based access; managers need oversight, others focus on their tasks
- **Enhanced My Assigned Jobs Card Layout**: Completely redesigned job card layout in my_assigned_jobs_screen.dart for better information hierarchy and usability.
  - **New Structure**: Header (Job # | P2 | Type inline) → Location → Description → Comments preview → Notes preview → Action buttons at bottom
  - **Comments/Notes Previews**: Show ALL entries (not just latest) with parsing logic, truncated to 60 chars, with 📝/📋 icons
  - **Button Relocation**: Moved Start/Complete/Monitor buttons from trailing to bottom Row with spaceEvenly distribution
  - **Tapping Behavior**: Entire card tappable opens Notes dialog (not comments) for adding work notes
  - **Priority Display**: Inline RichText style matching home screen (P1-P5 with colors)
  - **Padding**: Reduced to 8px for compact design, smaller text sizes throughout
  - **Job# Styling**: Removed bold, same size as other text (14px)
- **Monitoring Dashboard Available for All Employees**: Added Monitoring Dashboard quick action button to home screen for all employee types (Operators, Technicians, Managers).
  - **Before**: Only managers had access to Monitoring Dashboard
  - **After**: All employees can now access monitoring dashboard from quick actions
  - **Positioning**: Placed strategically in each role's action list (4th for operators, 3rd for technicians, 3rd for managers)
- **Removed Redundant "Closed" Filter**: Eliminated "Closed" status filter from View All Job Cards screen since "Completed" already handles this function.
  - **Before**: Status filters included Open, Monitoring, Completed, Closed
  - **After**: Status filters now include Open, Monitoring, Completed (Closed removed)
  - **Reason**: "Closed" was redundant as completed jobs are already shown under "Completed"
  - **Applied to**: Both mobile and desktop versions of the SegmentedButton
- **Hidden Action Buttons on Completed Jobs**: Made all action buttons invisible on job card detail screen when job status is completed.
  - **Before**: Completed jobs showed a "Monitor" button in the bottom banner
  - **After**: Completed jobs show no buttons at all in the bottom banner
  - **Implementation**: Added early return `if (jobCard.status == JobStatus.completed) return const SizedBox.shrink();` in `_buildBottomBanner`
  - **Rationale**: Once a job is completed, no further actions should be available
- **Added "Add Note" Button for Technical Staff**: Implemented inline "Add Note" button in job card detail screen for electrical, mechanical, and manager roles.
  - **Location**: Notes section header, similar to existing "Add Comment" button
  - **Permissions**: Only visible to employees with "electrical", "mechanical", or "manager" in position
  - **Functionality**: Opens modal bottom sheet with text field for adding work progress notes
  - **Features**: Automatic timestamping, Firestore integration, success feedback
  - **Difference from Comments**: No reoccurrence count adjustment, simpler interface
  - **UI**: Matches existing comment button styling with orange theme
- **Corrected Comments/Notes Order in Home Screen**: Fixed display order in recent job cards to show comments first, then notes.
  - **Before**: Notes displayed before comments in job card previews
  - **After**: Comments now appear first, followed by notes
- **Implemented Priority-Based Smart Notifications**: Added intelligent notification escalation system based on job priority (1-5).
  - **Levels**: Normal (pri1-3), Medium-High (pri4, loud sound+vib), Full-Loud (pri5, max vol+custom sound+repeat vib+fullScreenIntent)
  - **Creation**: Pri1-3 normal, pri4 medium-high, pri5 full-loud to techs+creator
  - **Escalations**: 60s pri5 medium-high, 2min pri1-3 normal pri4-5 medium-high, 7min pri1-3 normal pri4-5 full-loud
  - **Implementation**: CF reads priority, passes level in FCM data; Dart creates 3 channels, switches on level for sound/vib/fullscreen
  - **Android**: Custom sound file, fullScreenIntent permission, MainActivity requests permission
  - **Bonus**: Pri5 first escalation at 60s instead of 2min
  - **Reason**: More logical flow - comments are typically more important than work notes
  - **Applied to**: `_buildJobCardWidget` method in home screen recent jobs section
- **Added Timestamps to Notes**: Implemented timestamp functionality for job card notes similar to comments. Notes now append with timestamps when jobs are completed, and display is updated to parse and show individual notes with timestamps.
  - **Before**: `'${emp.displayName} (${emp.clockNo}) - ${emp.department ?? ''} ${emp.position ?? ''}'`
  - **After**: `'${emp.displayName} - ${emp.department ?? ''}'`
  - **Reason**: `Employee.displayName` already includes name, clockNo, and position
- **Fixed Null Safety Error**: Added null assertion operator for `mechElecFilter!.toLowerCase()` in employee filtering logic
- **Fixed Manager Dashboard Lint Errors**: Resolved compile and lint issues in manager_dashboard_screen.dart.
  - **Const with Runtime Values**: Removed `const` from `SizedBox(height: _sectionSpacing)` where `_sectionSpacing` is runtime getter.
  - **Deprecated APIs**: Updated `Colors.grey.withOpacity(0.3)` to `Colors.grey.withValues(alpha: 0.3)`, `pw.Table.fromTextArray` to `pw.TableHelper.fromTextArray`.
  - **Unnecessary Null Checks**: Simplified `j.machine?.trim().isNotEmpty == true ? j.machine! : 'Unknown Machine'` to `j.machine != null && j.machine.trim().isNotEmpty ? j.machine : 'Unknown Machine'`.
  - **Unnecessary this**: Removed `this.` qualifiers in `_showMonthPicker`.
  - **Result**: Dashboard now compiles cleanly with only minor false positive dead code warnings.
- **Fixed Admin Settings Navigation Error**: Resolved TypeError "String is not subtype of List<dynamic>" when navigating to admin settings.
  - **Root Cause**: Firestore `structures/factory/data` had inconsistent data types (String instead of List for machine arrays).
  - **Fix**: Added `_normalizeStructure()` method in admin_screen.dart to convert legacy String values to List<String>, ensuring all machine fields are Lists.
  - **Implementation**: Applied normalization in `_loadStructure()` to sanitize data before UI rendering.
  - **Result**: AdminScreen Structures tab now loads safely with mixed data types, preventing crashes on navigation.
- **Enhanced Admin Employees Tab to Spreadsheet View**: Transformed Employees tab into a spreadsheet-like interface with bulk operations.
  - **New UI**: Replaced ListView with `PaginatedDataTable` for editable rows, search, and pagination.
  - **Inline Editing**: Click edit icon to toggle row to TextField inputs, save with icon.
  - **Bulk Operations**: Checkbox select rows for bulk delete; CSV import/export for add/edit.
  - **CSV Features**: Export template with headers; import with preview dialog; web-optimized download/upload.
  - **Dependencies**: Added `file_picker: ^8.1.2` and `csv: ^6.0.0` for CSV handling.
  - **Result**: Efficient bulk employee management, especially for web users.
- **Redesigned View Job Cards Screen Filters**: Completely restructured filter system to reduce space usage and improve usability.
  - **New Layout**: Tab-based status selection (Open/Monitoring/Completed) at top, collapsible advanced filters below.
  - **Active Filter Chips**: Removable chips showing only applied filters (Staff Type, Department, Area, Machine, Part).
  - **Collapsible Advanced Filters**: Expandable section containing staff type segmented button and cascading location chips.
  - **Smart Defaults**: Electrical staff default to 'Electrical' filter, Mechanical to 'Mechanical', Super-managers to 'All'.
  - **Space Savings**: Reduced filter height from ~40-50% screen space to ~15% when collapsed, ~25% when expanded.
  - **Mobile/Desktop Responsive**: Collapsed by default on mobile, expanded on desktop (width >= 1200px).
  - **UX Improvements**: Clear visual hierarchy, easy filter removal, logical cascading filter flow.
  - **Result**: Dramatically improved screen space utilization while maintaining full filtering power.
- **Enhanced Job Card Details Screen**: Improved manager assignment button and employee selection with advanced search, department grouping, onsite filtering, and bulk operations.
  - **Search & Filtering**: Real-time search by employee name, onsite status filtering, department-based grouping with expansion tiles.
  - **Bulk Selection**: Multi-select employees with chips display, clear all functionality, offsite employee warnings.
  - **UI Improvements**: Streamlined dialog with grouped employee lists, visual onsite indicators, and efficient selection management.
  - **Result**: Faster, more intuitive job assignments with comprehensive employee visibility.
- **Updated Notification Format**: Enhanced push notifications with creator information and improved message structure.
  - **Title Format**: "Job Assigned by [assigner] Job#[number]" – immediately shows who assigned it.
  - **Body Format**: "Created by [creator]\nLocation: [area]\nDescription: [description]" – key details at a glance.
  - **Implementation**: Updated notification_service.dart and cloud functions to pass creator parameter and format messages.
  - **Result**: More informative notifications with clear assignment context and job details.
- **Hidden Assignment Buttons on Completed Jobs**: Self-assign/unassign buttons now hidden when job status is completed.
  - **Implementation**: Added status check `if (jobCard.status == JobStatus.completed) return const SizedBox.shrink();` in assignment buttons.
  - **Result**: Clean UI that prevents unnecessary actions on completed jobs.
- **Activity and Assignment Logs Redesign**: Logs now display in notes-style format with timestamps and left alignment.
  - **Activity Log**: Status timeline (Created, Started, Completed, etc.) with timestamps.
  - **Assignment Log**: Detailed events (assignments, adjustments, completions) formatted as "[timestamp] details".
  - **UI**: Left-aligned text with consistent styling, crossAxisAlignment for proper layout.
  - **Result**: Chronological, readable history separated by activity type vs detailed actions.
- **Photo Upload Feature**: Added ability to take/upload photos to job cards with compression.
  - **Dependencies**: Added `image_picker: ^1.1.2`, `flutter_image_compress: ^2.3.0`, `firebase_storage: ^13.2.0`.
  - **JobCard Model**: Added `List<String> photos` field with Firestore serialization.
  - **UI**: "📷 Add Photo" button in Notes section, camera/gallery selection dialog.
  - **Upload Flow**: Compress to 800px max, 85% quality, upload to `job_cards/{jobId}/photos/{timestamp}.jpg`.
  - **Display**: GridView of photos in "Photos" section, tap to enlarge.
  - **Result**: Job-specific photo documentation with optimized storage and easy viewing.
- **Copper Inventory Tracking Module**: Implemented complete copper inventory system for managers only.
  - **Features**: Real-time dashboard with charts/cards, password authentication, atomic transactions, sorting screen, transaction history with edit/search/filter.
  - **Models**: CopperInventory (single doc), CopperTransaction (collection) with proper Firestore serialization.
  - **Services**: CopperService with runTransaction for consistency, streams for real-time updates.
  - **Screens**: CopperStorageScreen (main dashboard), SortCopperScreen (validation), CopperTransactionsScreen (list/edit).
  - **UI**: Copper-themed colors (amber/orange), Material 3 design, responsive layout.
  - **Integration**: Added to manager dashboard app bar and home screen (authorized users), separate from job card functionality.
  - **Consolidation**: Removed duplicate copper_dashboard_screen.dart, updated all nav to use CopperStorageScreen as entry point.
- **Result**: Production-ready copper tracking with data integrity and professional UX.
- **Riverpod State Management Refactor**: Migrated from Provider to Riverpod for better scalability, testability, and modern state management patterns.
  - **Before**: Provider pattern with ChangeNotifier
  - **After**: Riverpod providers with Notifier classes
  - **Benefits**: Improved dependency injection, easier testing, better performance
- **Enhanced Firebase Integration**: Added comprehensive Firebase services (Auth, Storage, Crashlytics, Cloud Functions).
  - **Auth**: User authentication framework
  - **Storage**: Photo upload and file management
  - **Crashlytics**: Crash reporting and analytics
  - **Functions**: Server-side notification sending and business logic
- **Offline Support Implementation**: Added Hive local storage with connectivity monitoring for offline functionality.
  - **Dependencies**: hive ^2.2.3, hive_flutter ^1.1.0, connectivity_plus ^6.0.5
  - **Features**: Local data caching, sync on reconnect
- **Dashboard Analytics Enhancement**: Integrated interactive charts and PDF export for manager dashboards.
  - **Charts**: fl_chart ^0.70.0, charts_flutter ^0.12.0 for data visualization
  - **Export**: pdf ^3.11.1, share_plus ^10.0.2 for report generation and sharing
- **Local Notifications**: Added foreground message handling with flutter_local_notifications ^17.2.3.
  - **Platform Support**: Android channels, iOS permissions
  - **Integration**: Works alongside FCM for complete notification experience
- **Advanced Admin Operations**: Enhanced bulk CSV import/export with file_picker ^8.1.2 and csv ^6.0.0.
  - **Features**: Drag-and-drop file selection, preview dialogs, error handling
- **Image Management System**: Improved photo upload with compression and Firebase Storage.
  - **Compression**: flutter_image_compress ^2.3.0 for optimized storage
  - **Storage**: firebase_storage ^12.3.3 for cloud file management
  - **UI**: Enhanced gallery/camera selection with preview
- **Job Status Standardization**: Updated job status system from (Open, Monitoring, Completed, Closed) to (Open, Monitor, Closed).
  - **Enum Changes**: Renamed JobStatus.monitoring to JobStatus.monitor, JobStatus.completed to JobStatus.closed, removed JobStatus.cancelled
  - **UI Updates**: Updated all screens, filters, colors, and buttons to use new status names
  - **Data Migration**: Created migrate_status.js script to update existing Firestore data (completed→closed, monitoring→monitor)
  - **Screen Renames**: Renamed completed_jobs_screen.dart to closed_jobs_screen.dart
  - **Filter Updates**: Updated all status filters and queries to match new status values
  - **Color Coding**: Open(blue), Monitor(orange), Closed(green)
  - **Result**: Consistent, clear status system with proper lifecycle (Open → Monitor → Closed)
- **Home Screen Quick Actions Simplified**: Streamlined quick actions to focus on core functionality.
  - **Removed**: 'Closed Jobs' and 'Monitoring Dashboard' actions from all roles
  - **Renamed**: 'View Open Jobs' → 'View Jobs' for all roles, 'View All Jobs' → 'View Jobs' for managers
  - **Role Actions**:
    - **Operator/Other**: Create → View Jobs → My Assigned
    - **Technician**: My Assigned → View Jobs → Create
    - **Manager**: Create → View Jobs
  - **Result**: Cleaner, more focused home screen with essential actions only
- **Enhanced Manager Dashboard Analytics**: Added comprehensive job card analytics with created vs closed trends and department breakdowns.
  - **Trend Chart**: Line chart showing daily created (blue) vs closed (green) job cards over last 30 days with weekly date labels.
  - **Department Chart**: Line graph displaying outstanding job cards by department (Pre Press green, Pressroom blue, Post Press brown) over last 30 days.
  - **Data Computation**: Added daily outstanding counts by dept, computed from jobs created before each day and not completed by that day.
  - **Metrics**: Added "Created (Month)" and "Closed (Month)" cards for monthly totals.
  - **Layout**: Charts stacked vertically (trend on top, dept below) for all screen sizes, responsive design.
  - **Filters**: Dept/month filters apply to all data, real-time updates from Firestore.
  - **Result**: Professional analytics dashboard providing insights into job creation, completion, and department workload trends.
- **Copper Dashboard App Bar Color Update**: Made the copper dashboard app bar yellow (amber) to match the selected tab text color, with separate black tab bar background.
  - **App Bar**: Changed background from black to amber (yellow), title text from white to black for contrast
  - **Tab Bar**: Moved out of AppBar and placed in separate black Container below app bar for visual separation
  - **Result**: Consistent yellow theme for app bar matching tab selection color, with distinct black tab bar background
- **Fixed Firebase Storage auth & upload issues**: Deployed storage.rules (auth writes to job_cards/**), added anonymous auth check, removed compression to fix freeze, added debug logs in job_card_detail_screen.dart _addPhoto().
  - **Auth**: Anonymous sign-in before upload if no user
  - **Upload**: Original image (no compression hang)
  - **Debug**: Prints for auth/upload/save steps
  - **Result**: Photo uploads work without auth errors or freezes
- **Photo Upload and Display for Web Safety**: Updated photo upload method in create_job_card_screen.dart to use unique UUID for storage paths and improved error handling. Added _buildPhotosSection method in job_card_detail_screen.dart for horizontal scrolling photo display with CachedNetworkImage and CORS fix. Replaced old photo display code with new section call. Published changes to git.
  - **Upload**: Unique UUID paths prevent conflicts, better error handling with snackbars
  - **Display**: Horizontal ListView with CachedNetworkImage, error widget with CORS note
  - **Web Compatibility**: Fixed CORS issues for web photo loading
  - **Result**: Photos now safe and display properly on web platform
- **Photo Upload Maximum Compression in Detail Screen**: Updated _addPhoto method in job_card_detail_screen.dart to use 1024px min dimension and 70% quality compression, UUID paths for web safety, removed web-specific handling, updated all calls to parameterless method. Photos now heavily compressed for storage efficiency.
  - **Compression**: Maximum practical compression (1024px min, 70% quality) for 70-85% smaller files
  - **Upload**: UUID paths prevent conflicts, no web special handling needed
  - **Calls**: Updated all _addPhoto calls to parameterless for consistency
  - **Result**: Photos heavily compressed while maintaining quality, optimized storage usage
- **Custom Token Authentication for Employee Login**: Implemented secure authentication using Firebase Auth custom tokens generated by Cloud Function 'createCustomToken'.
  - **Login Flow**: Employee enters name/clockNo, validates against Firestore, calls CF to generate custom token with uid 'employee_${clockNo}' and claims, signs in with Firebase Auth
  - **Cloud Function**: Validates employee existence, creates token with employee data claims, handles errors gracefully
  - **Security**: Tokens tied to employee clock numbers, secure authentication without passwords
  - **TypeScript Fix**: Added explicit 'any' typing to CF data parameter to resolve TypeScript error
  - **Result**: Employees now authenticated via Firebase Auth, enabling secure access control and user-specific features

## Active Decisions and Considerations
- **Employee Display Format**: Using `displayName` (name + clockNo + position) + department for clean, non-redundant UI
- **Filtering Logic**: Department filter overrides mech/elec filter for precise assignment control
- **Real-time Updates**: StreamBuilder for live employee list updates in assign dialog
- **Super-Manager Pattern**: Users with `department == 'general'` treated as super-managers with full oversight - no dept filters by default, access to all filters like dept managers, view all jobs on login

## Important Patterns and Preferences
- **Error Handling**: Consistent use of `ScaffoldMessenger` for user feedback
- **Dialog State Management**: `StatefulBuilder` for complex dialog state updates
- **Color Scheme**: Orange (#FFFF8C42) for primary actions, green (#FF10B981) for success states
- **Priority Colors**: P1 (green) to P5 (red) with distinct shades for visual hierarchy
- **Null Safety**: Comprehensive null checking with `??` operators and conditional rendering
- **Role-Based UI Visibility**: Comment button hidden for electrical/mechanical staff; Notes button visible for managers + electrical/mechanical; Activity/Assignment logs expandable for all; Manage Assignments button visible only to managers (next to self-assign)

## Learnings and Project Insights
- **UI String Construction**: Always verify display strings don't duplicate model data
- **StreamBuilder Efficiency**: Rebuilds entire lists on stream changes - consider optimization for large employee lists
- **Firebase Streams**: Real-time updates provide excellent UX but require careful state management
- **Dialog Complexity**: Large dialogs benefit from `StatefulBuilder` for local state management

## Current Status
- ✅ Job card detail screen UI issues resolved
- ✅ App builds successfully without errors
- ✅ Memory Bank documentation initialized
- ✅ Notification reliability fixed (migrated employee IDs, added feedback)
- ✅ Individual assignment notifications fixed (logging crash resolved, robust validation, jobCardId extraction added)
- ✅ Notification click navigation implemented (assigned → MyAssignedJobsScreen, broadcast → JobCardDetail)
- ✅ Web version published to Firebase Hosting (https://ctp-job-cards.web.app, service worker disabled)
- ✅ Job Status Standardization: Updated to Open, Monitor, Closed with consistent UI and data migration - deployed to production
- ✅ ARM64 APK built (build\app\outputs\flutter-apk\app-release.apk, 20.1MB)
- ✅ Copper Inventory Module: Complete production-ready system with dashboard, transactions, sorting, password auth, atomic updates
- ✅ Riverpod State Management: Migrated from Provider to Riverpod with Notifier classes for better scalability
- ✅ Offline Support: Implemented Hive local storage with sync queue and connectivity monitoring
- ✅ Photo Upload: Added image picker, compression, Firebase Storage integration
- ✅ Job Status Standardization: Updated to Open, Monitor, Closed with consistent UI and data migration
- ✅ Enhanced Manager Dashboard Analytics: Added comprehensive job card analytics with created vs closed trends and department breakdowns
- ✅ **Lint Errors Fixed**: Resolved all solvable errors in job_card_detail_screen.dart (reduced from 22 to 13 warnings) and create_job_card_screen.dart (0 issues), updated deprecated withOpacity() to withValues(), fixed null checks, use_build_context_synchronously, and curly_braces_in_flow_control_structures
- 🔄 Ready for next feature development or bug fixes

## Next Steps
- Monitor for additional UI inconsistencies
- Consider performance optimizations for large datasets
- Plan dashboard enhancements based on user feedback

## Code Review Summary (2026-04-18 by Cline)
**Strengths**:
- Feature-complete core workflow + extras (copper, photos, analytics).
- Robust backend (priority FCM escalation, schedulers, atomic txns).
- Solid architecture (Riverpod Notifiers, FirestoreService repo, streams).
- Good configs (indexes for queries, persistence, crashlytics).
- Production beta-ready (web/APK deploys).

**Identified Improvements** (prioritized, security skipped):
1. **Perf**: Paginate job/employee lists, optimize StreamBuilder rebuilds (filtered queries/limit).
2. **Quality**: Fix deprecated APIs (withOpacity etc.), lint warnings, update deps (charts_flutter old).
3. **Testing**: Add unit/widget/integration tests (low coverage).
4. **UX**: Consistent skeletons, accessibility, form validation.
5. **Backend**: Abstract CF hardcoded emp IDs (23194/62/22), more env vars.
6. **Security** (later): Granular Firestore rules (operators read all/add comments).
7. **Polish**: i18n, PDF filters, GA4 events.

**Next**: Implement med-pri (quality/perf) in ACT.
