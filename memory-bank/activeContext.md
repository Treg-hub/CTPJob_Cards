# Active Context

## Current Work Focus
- **Job Card ID Simplification**: Implementing sequential numeric Job Card IDs (1,2,3...) instead of long alphanumeric Firestore IDs for easier reference
- **UI Bug Fixes**: Resolving display issues in job assignment dialogs
- **Memory Bank Setup**: Establishing documentation structure for future development
- **Code Quality**: Maintaining clean, efficient Flutter code with proper null safety
- **Monitoring Status Feature**: Added optional 7-day monitoring for completed jobs, auto-close if no adjustments, in-app dashboard for visibility

## Recent Changes
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

## Active Decisions and Considerations
- **Employee Display Format**: Using `displayName` (name + clockNo + position) + department for clean, non-redundant UI
- **Filtering Logic**: Department filter overrides mech/elec filter for precise assignment control
- **Real-time Updates**: StreamBuilder for live employee list updates in assign dialog

## Important Patterns and Preferences
- **Error Handling**: Consistent use of `ScaffoldMessenger` for user feedback
- **Dialog State Management**: `StatefulBuilder` for complex dialog state updates
- **Color Scheme**: Orange (#FFFF8C42) for primary actions, green (#FF10B981) for success states
- **Priority Colors**: P1 (green) to P5 (red) with distinct shades for visual hierarchy
- **Null Safety**: Comprehensive null checking with `??` operators and conditional rendering

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
- ✅ ARM64 APK built (build\app\outputs\flutter-apk\app-release.apk, 20.1MB)
- 🔄 Ready for next feature development or bug fixes

## Next Steps
- Monitor for additional UI inconsistencies
- Consider performance optimizations for large datasets
- Plan dashboard enhancements based on user feedback