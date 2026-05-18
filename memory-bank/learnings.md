# Learnings and Project Insights

Patterns, gotchas, conventions, and accumulated status notes specific to this project.

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
- ✅ **Automatic On-Site Detection**: Implemented native geofencing for automatic employee onsite status updates and notifications - 2km radius around company coordinates, battery efficient, works in background, no manual toggles
- ✅ **Fixed Related Jobs Loading Spinner Bug**: ExpansionTiles in Related Jobs tab were getting stuck on loading spinners when expanding/collapsing. Fixed by adding `key: ValueKey(title)` to ExpansionTile for state preservation and `initialData` to StreamBuilders to prevent loading states on rebuilds.
- ✅ **Moved App Update Check to Startup**: Update checking now happens immediately when the app opens (on mobile) instead of only after login. Uses `WidgetsBinding.instance.addPostFrameCallback` in `CtpJobCardsApp.build()` to get UI context and show update dialogs. Keeps existing daily throttling logic.
- ✅ **Enhanced Related Jobs Display**: Updated Related tab in JobCardDetailScreen with detailed job card format showing Job card number | Created by person | Status, Location, Description, All comments, All notes. Added pagination (max 10 jobs, "Load More" button), removed tap-to-detail, added "View Details" button. Added debug logging to identify why sections show counts but no jobs.
 - ✅ **Fixed Related Tab Expansion Bug**: Resolved ExpansionTile StreamBuilder disposal issue causing "No similar jobs found" on expand despite correct counts. Implemented RelatedSection StatefulWidget with AutomaticKeepAliveClientMixin, Visibility(maintainState: true) for persistent streams, and custom expansion UI with animated chevron.
 - ✅ **Added Related Tab Scrolling and Overflow Fix**: Wrapped Related tab in SingleChildScrollView for vertical scrolling, changed ListView physics to NeverScrollableScrollPhysics to prevent RenderFlex overflow, and added TickerProviderStateMixin for smooth animations.
 - ✅ **Enhanced Related Job Cards with Type Display**: Added job type display in related job cards, positioned on the left side of the "View Details" button for better information hierarchy.
 - ✅ **Full-Screen Critical Job Alerts**: Implemented native Android FullScreenJobAlertActivity for P5 priority jobs - shows on lock screen, turns screen on, loops alarm sound with strong vibration, provides action buttons (Assign Self, View Job, I'm Busy, Dismiss). Includes critical permissions (systemAlertWindow, accessNotificationPolicy, ignoreBatteryOptimizations) and advanced local notification channels (normal, medium-high with loud sound, full-loud with bypassDND, alarm audio, fullScreenIntent).
 - ✅ **Enhanced Notification Details**: Added createdBy field to notifications, ensure escalation notifications are sent to the job creator as well, update banner trigger whilst in app (foreground), add job card number to notification data payload.
 - ✅ **Test Notification Screen**: Added TestNotificationScreen.dart for testing notification levels (persistent banner, fullscreen alarm, normal, medium-high) using NotificationService.
   - 🔄 Ready for next feature development or bug fixes
 - **Recent Commits (HEAD~5 to HEAD)**: 9 files modified with 22 changes, focusing on UI refinements, notification enhancements, and minor fixes (e.g., home_screen.dart updates, improved error handling).

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
