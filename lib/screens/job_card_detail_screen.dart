import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/persona_audit.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/assignment_event.dart';
import '../models/employee.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import '../services/job_card_actions_service.dart';
import '../services/notification_service.dart';
import '../main.dart' show currentEmployee;
import '../utils/role.dart' show isAdmin, isOperatorRestrictedForJob, roleFromEmployee, UserRole;
import '../theme/app_theme.dart';
import '../utils/screen_insets.dart';
import '../widgets/ctp_app_bar.dart';

class JobCardDetailScreen extends StatefulWidget {
  final JobCard jobCard;

  const JobCardDetailScreen({super.key, required this.jobCard});

  @override
  State<JobCardDetailScreen> createState() => _JobCardDetailScreenState();
}

class _JobCardDetailScreenState extends State<JobCardDetailScreen> with TickerProviderStateMixin {
  late int _reoccurrenceCount;
  late JobCard _currentJobCard;
  final TextEditingController _commentController = TextEditingController();
  final FirestoreService _firestoreService = FirestoreService();
  final JobCardActionsService _actions = JobCardActionsService();
  final NotificationService _notificationService = NotificationService();
  late TabController _tabController;

  final Map<String, int> _sectionPageSizes = {};

  @override
  void initState() {
    super.initState();
    _reoccurrenceCount = widget.jobCard.reoccurrenceCount;
    _currentJobCard = widget.jobCard;
    _tabController = TabController(initialIndex: 1, length: 3, vsync: this);
  }

  @override
  void dispose() {
    _commentController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  bool get isManager => currentEmployee?.position.toLowerCase().contains('manager') ?? false;
  bool get isTech => (currentEmployee?.position.toLowerCase().contains('technician') ?? false) || (currentEmployee?.position.toLowerCase().contains('tech') ?? false);
  bool get _canAddNotes => isManager || (currentEmployee?.position.toLowerCase().contains('electrical') ?? false) || (currentEmployee?.position.toLowerCase().contains('mechanical') ?? false);
  bool get _canAddComments => !(currentEmployee?.position.toLowerCase().contains('electrical') ?? false) && !(currentEmployee?.position.toLowerCase().contains('mechanical') ?? false);

  /// Operators are restricted to Maintenance jobs unless explicitly assigned.
  bool _operatorRestrictedFor(JobCard job) =>
      isOperatorRestrictedForJob(currentEmployee, job);

  /// True when the current user can change the job type. Technicians, managers,
  /// and admins can; operators cannot. Closed jobs are immutable.
  bool _canChangeType(JobCard job) {
    if (job.status == JobStatus.closed) return false;
    final role = roleFromEmployee(currentEmployee);
    return role == UserRole.technician || role == UserRole.manager || role == UserRole.admin;
  }

  /// Only the original creator (matched by clockNo) or an admin can correct
  /// the breadcrumb. Terminal statuses are immutable.
  bool get _canEditBreadcrumb =>
      (_currentJobCard.operatorClockNo == currentEmployee?.clockNo ||
       isAdmin(currentEmployee)) &&
      _currentJobCard.status != JobStatus.closed;

  Future<void> _refreshJobCard() async {
    if (_currentJobCard.id != null) {
      final updated = await _firestoreService.getJobCard(_currentJobCard.id!);
      if (updated != null && mounted) {
        setState(() => _currentJobCard = updated);
      }
    }
  }

  // ==================== NEW TABBED ASSIGNMENT SHEET ====================
  void _toggleAssigneeSelection({
    required List<String> selectedClockNos,
    required List<String> selectedNames,
    required Employee emp,
    required bool selected,
    required StateSetter setDialogState,
  }) {
    setDialogState(() {
      if (selected) {
        if (!selectedClockNos.contains(emp.clockNo)) {
          selectedClockNos.add(emp.clockNo);
          selectedNames.add(emp.name);
        }
      } else {
        final idx = selectedClockNos.indexOf(emp.clockNo);
        if (idx >= 0) {
          selectedClockNos.removeAt(idx);
          if (idx < selectedNames.length) {
            selectedNames.removeAt(idx);
          }
        }
      }
    });
  }

  void _showAssignCompleteDialog(BuildContext context, JobCard job) {
    String searchQuery = '';
    List<String> selectedClockNos = [];
    List<String> selectedNames = [];
    bool isSaving = false;

    selectedClockNos.addAll(job.assignedClockNos ?? []);
    selectedNames.addAll(job.assignedNames ?? []);

    final currentDept = currentEmployee?.department ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        final sheetHeight = MediaQuery.sizeOf(context).height * 0.88;
        return SizedBox(
          height: sheetHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: StatefulBuilder(
          builder: (context, setDialogState) => DefaultTabController(
            length: 2,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      const Text('Assign Employees', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text('${selectedClockNos.length} selected'),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: kBrandOrange.withValues(alpha: 0.15),
                        labelStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFF8C42),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setDialogState(() {
                          selectedClockNos.clear();
                          selectedNames.clear();
                        }),
                        child: const Text('Clear All'),
                      ),
                    ],
                  ),
                ),

                const TabBar(
                  tabs: [
                    Tab(text: 'My Department'),
                    Tab(text: 'All Factory'),
                  ],
                  indicatorColor: Color(0xFFFF8C42),
                  labelColor: Color(0xFFFF8C42),
                ),

                Expanded(
                  child: TabBarView(
                    children: [
                      _buildDepartmentEmployeeList(
                        context: context,
                        department: currentDept,
                        selectedClockNos: selectedClockNos,
                        selectedNames: selectedNames,
                        setDialogState: setDialogState,
                      ),
                      Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: TextField(
                              decoration: const InputDecoration(
                                hintText: 'Search by name or clock number...',
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (value) => setDialogState(() => searchQuery = value.toLowerCase()),
                            ),
                          ),
                          Expanded(
                            child: _buildAllFactoryEmployeeList(
                              context: context,
                              searchQuery: searchQuery,
                              selectedClockNos: selectedClockNos,
                              selectedNames: selectedNames,
                              setDialogState: setDialogState,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                SafeBottomBar(
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  setDialogState(() => isSaving = true);
                                  final current = currentEmployee;
                                  if (current == null) {
                                    Navigator.pop(context);
                                    return;
                                  }
                                  try {
                                    // Field-scoped assignment write; the
                                    // onJobCardAssigned CF diffs the array and
                                    // notifies newly added assignees.
                                    await _actions.setAssignees(
                                      _currentJobCard,
                                      current,
                                      List<String>.from(selectedClockNos),
                                      List<String>.from(selectedNames),
                                    );
                                    await _refreshJobCard();
                                    if (_currentJobCard.operatorClockNo != null) {
                                      try {
                                        final creatorEmp = await _firestoreService.getEmployee(_currentJobCard.operatorClockNo!);
                                        if (creatorEmp?.fcmToken != null) {
                                          await _notificationService.sendCreatorNotification(
                                            recipientToken: creatorEmp!.fcmToken!,
                                            jobCardId: _currentJobCard.id!,
                                            jobCardNumber: _currentJobCard.jobCardNumber ?? 0,
                                            operator: current.name,
                                            creator: _currentJobCard.operator,
                                            department: _currentJobCard.department,
                                            area: _currentJobCard.area,
                                            machine: _currentJobCard.machine,
                                            part: _currentJobCard.part,
                                            description: _currentJobCard.description,
                                            notificationType: 'manager_assign',
                                            assigneeName: selectedNames.join(', '),
                                          );
                                        }
                                      } catch (e) {
                                        debugPrint('Error sending creator notification: $e');
                                      }
                                    }
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Employees assigned!')),
                                      );
                                    }
                                  } catch (e) {
                                    setDialogState(() => isSaving = false);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Error assigning: $e'), backgroundColor: Colors.red),
                                      );
                                    }
                                  }
                                },
                          child: isSaving
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(selectedClockNos.isEmpty ? 'Unassign all' : 'Assign'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
            ),
          ),
        );
      },
    );
  }

  // ==================== HELPER METHODS ====================
  /// One-shot assignee lists — no live full-roster listener (presence noise).
  static Future<List<Employee>>? _factoryEmployeesCache;
  static DateTime? _factoryEmployeesCacheAt;
  static final Map<String, Future<List<Employee>>> _deptEmployeesCache = {};
  static DateTime? _deptEmployeesCacheAt;
  static const _assigneeCacheTtl = Duration(minutes: 10);

  Future<List<Employee>> _loadFactoryEmployeesOnce() {
    final now = DateTime.now();
    final cached = _factoryEmployeesCache;
    final at = _factoryEmployeesCacheAt;
    if (cached != null &&
        at != null &&
        now.difference(at) < _assigneeCacheTtl) {
      return cached;
    }
    final future = _firestoreService.getAllEmployees().then((list) {
      list.sort((a, b) {
        if (a.isOnSite != b.isOnSite) return a.isOnSite ? -1 : 1;
        return a.name.compareTo(b.name);
      });
      return list;
    });
    _factoryEmployeesCache = future;
    _factoryEmployeesCacheAt = now;
    return future;
  }

  Future<List<Employee>> _loadDepartmentEmployeesOnce(String department) {
    final now = DateTime.now();
    final at = _deptEmployeesCacheAt;
    if (at == null || now.difference(at) >= _assigneeCacheTtl) {
      _deptEmployeesCache.clear();
      _deptEmployeesCacheAt = now;
    }
    return _deptEmployeesCache.putIfAbsent(
      department,
      () => _firestoreService.getEmployeesByDepartment(department),
    );
  }

  Widget _buildDepartmentEmployeeList({
    required BuildContext context,
    required String department,
    required List<String> selectedClockNos,
    required List<String> selectedNames,
    required StateSetter setDialogState,
  }) {
    return FutureBuilder<List<Employee>>(
      future: _loadDepartmentEmployeesOnce(department),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final employees = snapshot.data!;
        if (employees.isEmpty) {
          return const Center(child: Text('No employees in your department'));
        }

        return ListView.builder(
          itemCount: employees.length,
          itemBuilder: (context, index) {
            final emp = employees[index];
            final isSelected = selectedClockNos.contains(emp.clockNo);

            return CheckboxListTile(
              value: isSelected,
              onChanged: (val) => _toggleAssigneeSelection(
                selectedClockNos: selectedClockNos,
                selectedNames: selectedNames,
                emp: emp,
                selected: val == true,
                setDialogState: setDialogState,
              ),
              title: Text('${emp.name} — ${emp.position}'),
              subtitle: Text('Clock ${emp.clockNo}', style: const TextStyle(fontSize: 12)),
              secondary: Icon(
                emp.isOnSite ? Icons.location_on : Icons.location_off,
                color: emp.isOnSite ? Colors.green : Colors.red[400],
                size: 20,
              ),
              activeColor: kBrandOrange,
            );
          },
        );
      },
    );
  }

  Widget _buildAllFactoryEmployeeList({
    required BuildContext context,
    required String searchQuery,
    required List<String> selectedClockNos,
    required List<String> selectedNames,
    required StateSetter setDialogState,
  }) {
    return FutureBuilder<List<Employee>>(
      future: _loadFactoryEmployeesOnce(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var employees = snapshot.data!;

        if (searchQuery.isNotEmpty) {
          final q = searchQuery.toLowerCase();
          employees = employees
              .where((e) =>
                  e.name.toLowerCase().contains(q) || e.clockNo.contains(searchQuery))
              .toList();
        }

        if (employees.isEmpty) {
          return const Center(child: Text('No employees found'));
        }

        return ListView.builder(
          itemCount: employees.length,
          itemBuilder: (context, index) {
            final emp = employees[index];
            final isSelected = selectedClockNos.contains(emp.clockNo);

            return CheckboxListTile(
              value: isSelected,
              onChanged: (val) => _toggleAssigneeSelection(
                selectedClockNos: selectedClockNos,
                selectedNames: selectedNames,
                emp: emp,
                selected: val == true,
                setDialogState: setDialogState,
              ),
              title: Text('${emp.name} — ${emp.position}'),
              subtitle: Text('${emp.department} · Clock ${emp.clockNo}',
                  style: const TextStyle(fontSize: 12)),
              secondary: Icon(
                emp.isOnSite ? Icons.location_on : Icons.location_off,
                color: emp.isOnSite ? Colors.green : Colors.red[400],
                size: 20,
              ),
              activeColor: kBrandOrange,
            );
          },
        );
      },
    );
  }

  // ==================== ORIGINAL METHODS ====================
  Future<void> _appendComment() async {
    if (!guardPersonaSubmit(context)) return;
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    final current = currentEmployee;
    if (current == null) return;
    final actor = resolveWriteActor(current)!;

    try {
      await _actions.addComment(
        _currentJobCard,
        actor,
        text,
        reoccurrenceCount: _reoccurrenceCount,
      );
      await _refreshJobCard();
      setState(() => _commentController.clear());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Comment added!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding comment: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _selfUnassign(JobCard jobCard) async {
    if (!guardPersonaSubmit(context)) return;
    final current = currentEmployee;
    if (current == null) return;
    final actor = resolveWriteActor(current)!;
    try {
      await _actions.selfUnassign(jobCard, actor);
      await _refreshJobCard();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Removed from job')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error unassigning: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildPhotosSection() {
    if (_currentJobCard.photos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('No photos attached to this job card', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final photo in _currentJobCard.photos) {
      final section = photo['section'] as String? ?? 'General';
      grouped.putIfAbsent(section, () => []).add(photo);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: grouped.entries.map((entry) {
        final section = entry.key;
        final photos = entry.value
          ..sort((a, b) {
            final aTs = DateTime.tryParse(a['timestamp']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bTs = DateTime.tryParse(b['timestamp']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bTs.compareTo(aTs);
          });

        return ExpansionTile(
          title: Text('$section (${photos.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          children: [
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: photos.length,
                itemBuilder: (context, index) {
                  final photo = photos[index];
                  final url = photo['url'] as String?;
                  if (url == null) return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Stack(
                      children: [
                        GestureDetector(
                          onTap: () => _showFullScreenPhotoViewer(photo),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: url,
                              width: 180,
                              height: 180,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                width: 180,
                                height: 180,
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                child: const Center(child: CircularProgressIndicator()),
                              ),
                              errorWidget: (context, url, error) => Container(
                                width: 180,
                                height: 180,
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.broken_image, size: 48, color: Colors.red),
                                    SizedBox(height: 8),
                                    Text('Failed to load', style: TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if ((photo['addedBy'] == FirebaseAuth.instance.currentUser?.uid || isAdmin(currentEmployee)) && _currentJobCard.status != JobStatus.closed && _currentJobCard.status != JobStatus.monitor)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deletePhoto(photo),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  void _showAddCommentDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.72),
          decoration: BoxDecoration(
            color: Theme.of(context).appColors.cardSurface,
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
          ),
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              final bottomInset = MediaQuery.of(context).viewInsets.bottom;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Add Comment & Update Reoccurrence', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 30),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.blue.withValues(alpha: 80)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('What to include in your comment:', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w700, fontSize: 13)),
                                const SizedBox(height: 6),
                                Text('• Clear fault — what happened and what was observed', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
                                Text('• Any error codes or alarms displayed', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
                                Text('• When the fault occurred and how often', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
                                Text('• Any conditions before the fault (production speed, load, etc.)', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(iconSize: 32, icon: const Icon(Icons.remove_circle_outline), color: kBrandOrange, onPressed: () { if (_reoccurrenceCount > 1) setDialogState(() => _reoccurrenceCount--); }),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8), decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(12)), child: Text('$_reoccurrenceCount', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface))),
                              IconButton(iconSize: 32, icon: const Icon(Icons.add_circle_outline), color: kBrandOrange, onPressed: () => setDialogState(() => _reoccurrenceCount++)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _commentController,
                            decoration: InputDecoration(
                              labelText: 'Comment / Work Done',
                              hintText: 'e.g. Machine tripped at 06:30, error E04 on display. Fault occurred 3 times this shift...',
                              hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 128), fontSize: 12.5),
                              border: const OutlineInputBorder(),
                              labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                            maxLines: 5,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset + 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
                        const SizedBox(width: 12),
                        ElevatedButton(onPressed: () { Navigator.pop(context); _appendComment(); }, child: const Text('Save Comment')),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showAddNoteDialog() {
    final noteController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.80),
          decoration: BoxDecoration(
            color: Theme.of(context).appColors.cardSurface,
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Add Technical Note', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 25),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.withValues(alpha: 80)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Every closure note must include:', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w700, fontSize: 13)),
                            const SizedBox(height: 6),
                            Text('• What was done — actions taken to fix the fault', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
                            Text('• Parts used — part numbers and quantities', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
                            Text('• Root cause — why the fault occurred', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
                            Text('• Follow-up recommendations — any further action required', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: noteController,
                        decoration: InputDecoration(
                          labelText: 'Technical Note',
                          hintText: 'e.g. Replaced bearing 6205-2RS (x2). Root cause: lubrication failure due to blocked grease nipple. Recommend weekly greasing schedule.',
                          hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 128), fontSize: 12.5),
                          border: const OutlineInputBorder(),
                          labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 6,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset + 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
                    const SizedBox(width: 12),
                    ElevatedButton(onPressed: () { Navigator.pop(context); _appendNote(noteController.text.trim()); }, child: const Text('Save Note')),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _appendNote(String noteText) async {
    if (!guardPersonaSubmit(context)) return;
    if (noteText.isEmpty) return;
    final current = currentEmployee;
    if (current == null) return;
    final actor = resolveWriteActor(current)!;

    try {
      await _actions.addNote(_currentJobCard, actor, noteText);
      await _refreshJobCard();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note added!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding note: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _addPhoto(String section) async {
    if (!guardPersonaSubmit(context)) return;
    final jobId = widget.jobCard.id;
    if (jobId == null || jobId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot attach photo — job card not yet saved'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final picker = ImagePicker();
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Select Photo Source'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, ImageSource.camera),
              child: const Text('Camera'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
              child: const Text('Gallery'),
            ),
          ],
        ),
      );
      if (source == null) return;
      final pickedFile = await picker.pickImage(source: source);

      if (pickedFile == null) return;

      // Multi-MB uploads on factory Wi-Fi take a while — without feedback the
      // screen looks frozen and users retry, duplicating photos.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(minutes: 2),
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 12),
                Text('Uploading photo…'),
              ],
            ),
          ),
        );
      }

      String downloadUrl;
      final storagePath = 'job_cards/$jobId/photos/${DateTime.now().millisecondsSinceEpoch}.jpg';

      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        final storageRef = FirebaseStorage.instance.ref().child(storagePath);
        final snapshot = await storageRef.putData(bytes);
        downloadUrl = await snapshot.ref.getDownloadURL();
      } else {
        final compressedFile = await FlutterImageCompress.compressAndGetFile(
          pickedFile.path,
          '${pickedFile.path}_compressed.jpg',
          minWidth: 1024,
          minHeight: 1024,
          quality: 70,
        );

        if (compressedFile == null) throw Exception('Failed to compress image');

        final storageRef = FirebaseStorage.instance.ref().child(storagePath);
        final snapshot = await storageRef.putFile(File(compressedFile.path));
        downloadUrl = await snapshot.ref.getDownloadURL();
      }

      final actor = resolveWriteActor(currentEmployee);
      final photoMap = {
        'url': downloadUrl,
        'section': section,
        'addedBy': FirebaseAuth.instance.currentUser?.uid ?? 'legacy',
        'addedByName': actor?.name ?? 'Unknown',
        'timestamp': DateTime.now().toIso8601String(),
        'department': _currentJobCard.department,
        'machine': _currentJobCard.machine,
        'location': _currentJobCard.area,
        'part': _currentJobCard.part,
      };

      await _firestoreService.addPhotoToJobCard(jobId, photoMap);

      setState(() {
        _currentJobCard = _currentJobCard.copyWith(photos: [..._currentJobCard.photos, photoMap]);
      });

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('✅ Photo uploaded successfully'), backgroundColor: Colors.green));
      }
    } catch (e, st) {
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (!kIsWeb) {
        FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'photo_upload_failed',
        information: ['jobId:$jobId', 'section:$section'],
      );
      }
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Photo upload failed'),
            content: Text(
              'The photo file may have reached Firebase Storage, but the job card was not updated.\n\n'
              'Error: $e',
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      }
    }
  }

  Future<void> _deletePhoto(Map<String, dynamic> photo) async {
    if (!guardPersonaSubmit(context)) return;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (photo['addedBy'] != currentUid && !isAdmin(currentEmployee)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You can only delete your own photos'), backgroundColor: Colors.red));
      return;
    }
    if (_currentJobCard.status == JobStatus.closed || _currentJobCard.status == JobStatus.monitor) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot delete photos when job is closed or monitoring'), backgroundColor: Colors.red));
      return;
    }
    final jobId = widget.jobCard.id;
    if (jobId == null || jobId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete photo — job card not yet saved'), backgroundColor: Colors.red),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _firestoreService.removePhotoFromJobCard(jobId, photo);
      setState(() {
        _currentJobCard = _currentJobCard.copyWith(photos: _currentJobCard.photos.where((p) => p != photo).toList());
      });
      messenger.showSnackBar(const SnackBar(content: Text('Photo deleted')));
    } catch (e, st) {
      if (!kIsWeb) FirebaseCrashlytics.instance.recordError(e, st, reason: 'photo_delete_failed', information: ['jobId:$jobId']);
      messenger.showSnackBar(SnackBar(content: Text('Error deleting photo: $e'), backgroundColor: Colors.red));
    }
  }

  void _showFullScreenPhotoViewer(Map<String, dynamic> photo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Photo Viewer')),
          body: Column(
            children: [
              Expanded(
                child: Center(
                  child: InteractiveViewer(
                    child: CachedNetworkImage(
                      imageUrl: photo['url'] as String,
                      fit: BoxFit.contain,
                      placeholder: (context, url) => const CircularProgressIndicator(),
                      errorWidget: (context, url, error) => const Icon(Icons.error),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Section: ${photo['section'] ?? 'N/A'}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                    Text('Department: ${photo['department'] ?? 'N/A'}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                    Text('Machine: ${photo['machine'] ?? 'N/A'}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                    Text('Location: ${photo['location'] ?? 'N/A'}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                    Text('Part: ${photo['part'] ?? 'N/A'}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                    // Prefer the human-readable name; legacy photos only have
                    // the auth UID under addedBy.
                    Text('Added by: ${photo['addedByName'] ?? photo['addedBy'] ?? 'Unknown'}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                    Text('Timestamp: ${_formatPhotoTimestamp(photo['timestamp'])}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const double sectionSpacing = 5.0;

    return Scaffold(
      appBar: const CtpAppBar(title: 'Job Card Details'),
      body: StreamBuilder<JobCard>(
        stream: _firestoreService.getJobCardStream(widget.jobCard.id!),
        builder: (context, snapshot) {
          final jobCard = snapshot.hasData ? snapshot.data! : widget.jobCard;
          // _currentJobCard is the source of truth for handlers that fire
          // outside this build (_addPhoto, _deletePhoto, status changes).
          // Keep it in sync with the latest stream emission. Safe to assign
          // synchronously because non-photo updates now exclude the photos
          // field server-side (see FirestoreService.updateJobCard).
          _currentJobCard = jobCard;
          return Column(
            children: [
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Related'),
                  Tab(text: 'Details'),
                  Tab(text: 'Photos'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
              _buildRelatedTab(),
              RefreshIndicator(
                onRefresh: _refreshJobCard,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeroHeader(jobCard),
                      const SizedBox(height: sectionSpacing),
                      _buildAssignmentButtons(jobCard),
                      const SizedBox(height: sectionSpacing),
                      _buildCombinedCard(jobCard),
                      const SizedBox(height: sectionSpacing),
                      _buildDetailsCard(jobCard),
                      const SizedBox(height: sectionSpacing),
                      _buildActivityLogCard(jobCard),
                    ],
                  ),
                ),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Photos', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                        TextButton.icon(
                          onPressed: () => _addPhoto('Description'),
                          icon: const Icon(Icons.camera_alt, size: 20),
                          label: const Text('Add Photo'),
                          style: TextButton.styleFrom(foregroundColor: kBrandOrange),
                        ),
                      ],
                    ),
                    _buildPhotosSection(),
                  ],
                ),
              ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: _buildBottomBanner(_currentJobCard),
    );
  }

  Widget _buildBottomBanner(JobCard jobCard) {
    if (jobCard.status == JobStatus.closed) return const SizedBox.shrink();

    final isAssigned = jobCard.assignedClockNos?.contains(currentEmployee?.clockNo ?? '') ?? false;
    final role = roleFromEmployee(currentEmployee);
    final operatorBlocked = _operatorRestrictedFor(jobCard);
    // Technicians can JOIN an in-progress job (additional hands on a large job).
    // Operators stay blocked unless the job is Maintenance.
    final canJoinInProgress = jobCard.status == JobStatus.inProgress
        && role == UserRole.technician
        && !isAssigned;

    // Hide the action row entirely when the user has nothing to do:
    //  - Not Open (so no "Start" for fresh viewers)
    //  - Not assigned (so no Complete/Monitor/Adjustment)
    //  - Not a manager (managers can always act)
    //  - Not eligible to join an in-progress job
    if (jobCard.status != JobStatus.open && !isAssigned && !isManager && !canJoinInProgress) {
      return const SizedBox.shrink();
    }

    final buttons = <Widget>[];

    if (jobCard.status == JobStatus.open) {
      buttons.add(
        Expanded(
          child: ElevatedButton.icon(
            onPressed: operatorBlocked ? null : () => _startJob(jobCard),
            icon: const Icon(Icons.play_arrow, size: 20),
            label: Text(
              operatorBlocked ? 'Technicians only' : 'Start',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      );
    } else if (jobCard.status == JobStatus.inProgress) {
      if (canJoinInProgress) {
        buttons.add(
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _startJob(jobCard),
              icon: const Icon(Icons.group_add, size: 20),
              label: const Text('Join (Start)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        );
      }
      if (isAssigned || isManager) {
        buttons.add(
          Expanded(
            child: ElevatedButton.icon(
              onPressed: operatorBlocked ? null : () => _showCompleteDialog(jobCard),
              icon: const Icon(Icons.check_circle, size: 20),
              label: const Text('Complete', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        );
        buttons.add(
          Expanded(
            child: ElevatedButton.icon(
              onPressed: operatorBlocked ? null : () => _showMonitorDialog(jobCard),
              icon: const Icon(Icons.visibility, size: 20),
              label: const Text('Monitor', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        );
      }
    } else if (jobCard.status == JobStatus.monitor) {
      buttons.add(
        Expanded(
          child: ElevatedButton.icon(
            onPressed: operatorBlocked ? null : () => _showAdjustmentDialog(jobCard),
            icon: const Icon(Icons.refresh, size: 20),
            label: const Text('Adjustment Made', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      );
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    return SafeBottomBar(
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).appColors.cardSurface,
          border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outline)),
        ),
        child: Row(
          children: buttons.map((btn) => [btn, const SizedBox(width: 8)]).expand((x) => x).toList()..removeLast(),
        ),
      ),
    );
  }

  Future<void> _startJob(JobCard jobCard) async {
    if (!guardPersonaSubmit(context)) return;
    final current = currentEmployee;
    if (current == null) return;
    final actor = resolveWriteActor(current)!;
    final isAlreadyAssigned =
        jobCard.assignedClockNos?.contains(current.clockNo) ?? false;

    try {
      await _actions.startJob(jobCard, actor);

      // If this user just self-assigned by starting the job (wasn't previously
      // assigned), notify the operator so they know who's now responsible.
      if (!isAlreadyAssigned && jobCard.operatorClockNo != null) {
        try {
          final creatorEmp = await _firestoreService.getEmployee(jobCard.operatorClockNo!);
          if (creatorEmp?.fcmToken != null) {
            await _notificationService.sendCreatorNotification(
              recipientToken: creatorEmp!.fcmToken!,
              jobCardId: jobCard.id ?? '',
              jobCardNumber: jobCard.jobCardNumber,
              operator: jobCard.operator,
              creator: jobCard.operator,
              department: jobCard.department,
              area: jobCard.area,
              machine: jobCard.machine,
              part: jobCard.part,
              description: jobCard.description,
              notificationType: 'self_assign',
              assigneeName: current.name,
              priority: jobCard.priority,
            );
          }
        } catch (e) {
          debugPrint('Failed to notify operator on start: $e');
        }
      }

      await _refreshJobCard();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Job started!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting job: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showCompleteDialog(JobCard jobCard) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Job'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 80)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Closure requires:', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    SizedBox(height: 4),
                    Text('• What was done & parts used', style: TextStyle(fontSize: 12)),
                    Text('• Root cause of the fault', style: TextStyle(fontSize: 12)),
                    Text('• Any follow-up recommendations', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'Corrective Action Taken',
                  hintText: 'e.g. Replaced motor capacitor (35µF). Root cause: aged capacitor. No further action required.',
                  hintStyle: TextStyle(fontSize: 12),
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 5,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final note = noteController.text.trim();
              if (note.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a description'), backgroundColor: Colors.red));
                return;
              }
              Navigator.pop(context);
              await _completeJob(jobCard, false, note);
            },
            child: const Text('Complete'),
          ),
        ],
      ),
    );
  }

  void _showMonitorDialog(JobCard jobCard) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start Monitoring'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 80)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Describe the intervention:', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    SizedBox(height: 4),
                    Text('• What was done & parts used', style: TextStyle(fontSize: 12)),
                    Text('• Root cause (if identified)', style: TextStyle(fontSize: 12)),
                    Text('• Why monitoring is still required', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'Corrective Action Taken',
                  hintText: 'e.g. Tightened belt and realigned pulleys. Monitoring for vibration — root cause unconfirmed.',
                  hintStyle: TextStyle(fontSize: 12),
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 5,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final note = noteController.text.trim();
              if (note.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a description'), backgroundColor: Colors.red));
                return;
              }
              Navigator.pop(context);
              await _completeJob(jobCard, true, note);
            },
            child: const Text('Start Monitoring'),
          ),
        ],
      ),
    );
  }

  void _showAdjustmentDialog(JobCard jobCard) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adjustment Made'),
        content: SingleChildScrollView(
          child: TextField(
            controller: noteController,
            decoration: const InputDecoration(labelText: 'Description of Adjustment'),
            maxLines: 4,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final note = noteController.text.trim();
              if (note.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a description'), backgroundColor: Colors.red));
                return;
              }
              Navigator.pop(context);
              await _adjustmentMade(jobCard, note);
            },
            child: const Text('Save Adjustment'),
          ),
        ],
      ),
    );
  }

  Future<void> _completeJob(JobCard jobCard, bool withMonitoring, String description) async {
    if (!guardPersonaSubmit(context)) return;
    final current = currentEmployee;
    if (current == null) return;
    final actor = resolveWriteActor(current)!;
    try {
      await _actions.completeJob(jobCard, actor, description,
          withMonitoring: withMonitoring);
      await _refreshJobCard();

      if (jobCard.operatorClockNo != null) {
        try {
          final creatorEmp = await _firestoreService.getEmployee(jobCard.operatorClockNo!);
          if (creatorEmp?.fcmToken != null) {
            await _notificationService.sendCreatorNotification(
              recipientToken: creatorEmp!.fcmToken!,
              jobCardId: jobCard.id!,
              jobCardNumber: jobCard.jobCardNumber ?? 0,
              operator: currentEmployee?.name ?? 'Unknown',
              creator: jobCard.operator,
              department: jobCard.department,
              area: jobCard.area,
              machine: jobCard.machine,
              part: jobCard.part,
              description: jobCard.description,
              notificationType: withMonitoring ? 'monitor' : 'completed',
              assigneeName: currentEmployee?.name ?? 'Unknown',
            );
          }
        } catch (e) {
          debugPrint('Error sending creator notification: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(withMonitoring ? 'Job completed and monitoring started!' : 'Job completed!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error completing job: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _adjustmentMade(JobCard jobCard, String description) async {
    if (!guardPersonaSubmit(context)) return;
    final current = currentEmployee;
    if (current == null) return;
    final actor = resolveWriteActor(current)!;
    try {
      await _actions.adjustmentMade(jobCard, actor, description);
      await _refreshJobCard();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Monitoring restarted!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resetting monitoring: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showStatusChangeDialog(JobCard jobCard) {
    JobStatus selectedStatus = jobCard.status;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change Job Status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,   // ← Fixed here
            children: [
              SegmentedButton<JobStatus>(
                segments: const [
                  ButtonSegment(value: JobStatus.open, label: Text('Open')),
                  ButtonSegment(value: JobStatus.monitor, label: Text('Monitor')),
                  ButtonSegment(value: JobStatus.closed, label: Text('Closed')),
                ],
                selected: {selectedStatus},
                onSelectionChanged: (Set<JobStatus> selection) {
                  setDialogState(() => selectedStatus = selection.first);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                if (selectedStatus == jobCard.status) {
                  Navigator.pop(context);
                  return;
                }
                if (!guardPersonaSubmit(context)) return;
                final actor = resolveWriteActor(currentEmployee);
                if (actor == null) return;
                try {
                  // Field-scoped update: stamps closedAt on close, clears
                  // stale completion fields on reopen (copyWith can't null
                  // fields, so the old whole-doc save left them behind).
                  await _firestoreService.changeJobCardStatus(
                    jobCardId: jobCard.id!,
                    current: jobCard,
                    to: selectedStatus,
                    byName: actor.name,
                    byClockNo: actor.clockNo,
                  );
                  await _refreshJobCard();
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Status changed to ${selectedStatus.displayName}!')));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error changing status: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Change Status'),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangeTypeDialog(JobCard jobCard) {
    JobType selectedType = jobCard.type;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change Job Type'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current: ${jobCard.type.displayName}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: JobType.values.map((t) => ChoiceChip(
                  label: Text(t.displayName),
                  selected: selectedType == t,
                  onSelected: (_) => setDialogState(() => selectedType = t),
                )).toList(),
              ),
              const SizedBox(height: 12),
              if (selectedType != jobCard.type)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 30),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withValues(alpha: 120)),
                  ),
                  child: Text(
                    selectedType == JobType.maintenance
                        ? 'Maintenance jobs are silent — no notifications, no escalation.'
                        : 'New ${selectedType.displayName} responders will be notified. Escalation timer will restart from the next tick.',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
              onPressed: selectedType == jobCard.type
                  ? null
                  : () async {
                      final by = currentEmployee;
                      if (by == null || jobCard.id == null) {
                        Navigator.pop(context);
                        return;
                      }
                      final from = jobCard.type;
                      try {
                        await _firestoreService.changeJobCardType(
                          jobCardId: jobCard.id!,
                          from: from,
                          to: selectedType,
                          by: by,
                        );
                        await _refreshJobCard();
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Type changed: ${from.displayName} → ${selectedType.displayName}')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error changing type: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
              child: const Text('Change Type'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBreadcrumbEditDialog() async {
    final structure = await _firestoreService.getFactoryStructure();
    if (!mounted) return;

    String newDept = _currentJobCard.department;
    String newArea = _currentJobCard.area;
    String newMachine = _currentJobCard.machine;
    String newPart = _currentJobCard.part;
    final partCtrl = TextEditingController(text: newPart);
    List<String> previousParts = [];

    if (newDept.isNotEmpty && newArea.isNotEmpty && newMachine.isNotEmpty) {
      previousParts = await _firestoreService.getPreviousParts(newDept, newArea, newMachine);
    }
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Edit Location'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Department', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: structure.keys.map((dept) => ChoiceChip(
                    label: Text(dept),
                    selected: newDept == dept,
                    onSelected: (_) => setS(() {
                      newDept = dept;
                      newArea = newMachine = newPart = '';
                      partCtrl.clear();
                      previousParts = [];
                    }),
                  )).toList(),
                ),
                if (newDept.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Area / Section', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: ((structure[newDept] as Map<String, dynamic>? ?? {}).keys)
                        .map((area) => ChoiceChip(
                              label: Text(area),
                              selected: newArea == area,
                              onSelected: (_) => setS(() {
                                newArea = area;
                                newMachine = newPart = '';
                                partCtrl.clear();
                                previousParts = [];
                              }),
                            ))
                        .toList(),
                  ),
                ],
                if (newArea.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Machine / Location', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: ((structure[newDept]?[newArea] as List<dynamic>? ?? []).cast<String>())
                        .map((machine) => ChoiceChip(
                              label: Text(machine),
                              selected: newMachine == machine,
                              onSelected: (_) async {
                                setS(() {
                                  newMachine = machine;
                                  newPart = '';
                                  partCtrl.clear();
                                });
                                final parts = await _firestoreService.getPreviousParts(newDept, newArea, machine);
                                if (ctx.mounted) setS(() => previousParts = parts);
                              },
                            ))
                        .toList(),
                  ),
                ],
                if (newMachine.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Part / Component', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  if (previousParts.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: previousParts
                          .map((p) => ActionChip(
                                label: Text(p),
                                onPressed: () => setS(() {
                                  newPart = p;
                                  partCtrl.text = p;
                                }),
                              ))
                          .toList(),
                    ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: partCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Part / Component',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setS(() => newPart = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: newDept.isNotEmpty &&
                      newArea.isNotEmpty &&
                      newMachine.isNotEmpty &&
                      newPart.trim().isNotEmpty
                  ? () async {
                      Navigator.pop(ctx);
                      final current = currentEmployee;
                      if (current == null) return;
                      try {
                        await _actions.editLocation(
                          _currentJobCard,
                          current,
                          department: newDept,
                          area: newArea,
                          machine: newMachine,
                          part: newPart.trim(),
                        );
                        if (mounted) {
                          setState(() => _currentJobCard = _currentJobCard.copyWith(
                                department: newDept,
                                area: newArea,
                                machine: newMachine,
                                part: newPart.trim(),
                              ));
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to update location: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  : null,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    partCtrl.dispose();
  }

  Widget _buildAssignmentButtons(JobCard jobCard) {
    if (jobCard.status == JobStatus.closed) return const SizedBox.shrink();

    final isAssigned = jobCard.assignedClockNos?.contains(currentEmployee?.clockNo ?? '') ?? false;

    // Unassigned non-managers see nothing here — Start button handles self-assign
    if (!isAssigned && !isManager) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          if (isAssigned) ...[
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _selfUnassign(jobCard),
                icon: const Icon(Icons.remove_circle, size: 24),
                label: const Text('Unassign', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            if (isManager) const SizedBox(width: 12),
          ],
          if (isManager)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _showAssignCompleteDialog(context, jobCard),
                icon: const Icon(Icons.group_add, size: 24),
                label: const Text('Manage', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBrandOrange,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeroHeader(JobCard jobCard) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Job # + Type pill + Status pill
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Job #${jobCard.jobCardNumber ?? jobCard.id ?? 'N/A'}',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: _canChangeType(jobCard) ? () => _showChangeTypeDialog(jobCard) : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              jobCard.type.displayName,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            if (_canChangeType(jobCard)) const SizedBox(width: 4),
                            if (_canChangeType(jobCard)) const Icon(Icons.edit, color: Colors.white, size: 13),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: isManager ? () => _showStatusChangeDialog(jobCard) : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: jobCard.status == JobStatus.closed
                              ? Colors.green
                              : jobCard.status == JobStatus.monitor
                                  ? Colors.orange
                                  : jobCard.status == JobStatus.inProgress
                                      ? Colors.purple
                                      : Colors.blue,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              jobCard.status.displayName.toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            if (isManager) const SizedBox(width: 4),
                            if (isManager) const Icon(Icons.edit, color: Colors.white, size: 13),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Row 2: Priority + breadcrumb — tappable for creator / admin
            GestureDetector(
              onTap: _canEditBreadcrumb ? _showBreadcrumbEditDialog : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'P${jobCard.priority}',
                            style: TextStyle(
                              color: _getPriorityColor('P${jobCard.priority}'),
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextSpan(
                            text: ' | ${jobCard.department.isEmpty ? 'N/A' : jobCard.department} > ${jobCard.area.isEmpty ? 'N/A' : jobCard.area} > ${jobCard.machine.isEmpty ? 'N/A' : jobCard.machine} > ${jobCard.part.isEmpty ? 'N/A' : jobCard.part}',
                            style: TextStyle(fontSize: 14.5, color: Theme.of(context).colorScheme.onSurface),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_canEditBreadcrumb)
                    const Padding(
                      padding: EdgeInsets.only(left: 4, top: 2),
                      child: Icon(Icons.edit, size: 13, color: Colors.grey),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCombinedCard(JobCard jobCard) {
    final parsedComments = _parseComments(jobCard.comments);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Description', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: onSurface)),
            const SizedBox(height: 4),
            Text(jobCard.description, style: TextStyle(fontSize: 15, color: onSurface)),
            const SizedBox(height: 12),

            // ==================== COMMENTS SECTION ====================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Comments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: onSurface)),
                if (_canAddComments)
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.add_comment, size: 20),
                        color: kBrandOrange,
                        tooltip: 'Add Comment',
                        onPressed: _showAddCommentDialog,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                      IconButton(
                        icon: const Icon(Icons.camera_alt, size: 20),
                        color: kBrandOrange,
                        tooltip: 'Add Photo to Comments',
                        onPressed: () => _addPhoto('Comments'),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (parsedComments.isEmpty)
              Text('No comments yet', style: TextStyle(color: muted)),
            if (parsedComments.isNotEmpty)
              ...parsedComments.map((comment) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(comment, style: TextStyle(fontSize: 14.5, color: onSurface)),
                  )),

            const SizedBox(height: 12),

            // ==================== NOTES SECTION ====================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Notes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: onSurface)),
                if (_canAddNotes)
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.note_add, size: 20),
                        color: kBrandOrange,
                        tooltip: 'Add Note',
                        onPressed: _showAddNoteDialog,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                      IconButton(
                        icon: const Icon(Icons.camera_alt, size: 20),
                        color: kBrandOrange,
                        tooltip: 'Add Photo to Notes',
                        onPressed: () => _addPhoto('Notes'),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (jobCard.notes.isNotEmpty) ..._parseNotes(jobCard.notes).map((note) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(note, style: TextStyle(fontSize: 14.5, color: onSurface)),
                )),
            if (jobCard.notes.isEmpty)
              Text('No notes', style: TextStyle(color: muted)),

            // ==================== CORRECTIVE ACTION SECTION ====================
            if (jobCard.correctiveAction.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Corrective Action', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: onSurface)),
              const SizedBox(height: 4),
              ..._parseNotes(jobCard.correctiveAction).map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(entry, style: TextStyle(fontSize: 14.5, color: onSurface)),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsCard(JobCard jobCard) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: onSurface)),
                Text('Count: ${jobCard.reoccurrenceCount}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: onSurface)),
              ],
            ),
            const SizedBox(height: 6),
            _buildDetailRow('Created By', jobCard.operator, jobCard.createdAt, muted, onSurface),
            if (jobCard.assignedNames != null && jobCard.assignedNames!.isNotEmpty) ...[
              const SizedBox(height: 6),
              _buildCompactDetail('Assigned To', jobCard.assignedNames!.join(', ')),
            ],
            if (jobCard.completedBy != null) ...[
              const SizedBox(height: 6),
              _buildDetailRow('Completed By', jobCard.completedBy!, jobCard.completedAt, muted, onSurface),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, DateTime? timestamp, Color muted, Color onSurface) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: muted)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(fontSize: 13.5, color: onSurface)),
            ],
          ),
        ),
        if (timestamp != null)
          Text(_formatDateTime(timestamp), style: TextStyle(fontSize: 11.5, color: muted)),
      ],
    );
  }

  Widget _buildCompactDetail(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13.5, color: Theme.of(context).colorScheme.onSurface)),
      ],
    );
  }

  Widget _buildActivityLogCard(JobCard jobCard) {
    // Merge lifecycle timestamps + assignmentHistory into one sorted list.
    final entries = <(DateTime, String)>[
      if (jobCard.createdAt != null) (jobCard.createdAt!, 'Created'),
      if (jobCard.startedAt != null) (jobCard.startedAt!, 'Started'),
      if (jobCard.notificationReceivedAt != null) (jobCard.notificationReceivedAt!, 'Notification Received'),
      if (jobCard.completedAt != null) (jobCard.completedAt!, 'Completed'),
      if (jobCard.monitoringStartedAt != null) (jobCard.monitoringStartedAt!, 'Monitoring Started'),
      if (jobCard.lastUpdatedAt != null) (jobCard.lastUpdatedAt!, 'Last Updated'),
      ...jobCard.assignmentHistory.map((e) => (e.timestamp, _eventLabel(e))),
    ]..sort((a, b) => b.$1.compareTo(a.$1));

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        title: Text('Activity Log', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: entries.isEmpty
                  ? [Text('No activity yet', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))]
                  : entries.map((e) => _buildTimelineRow(e.$2, e.$1)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _eventLabel(AssignmentEvent event) {
    if (event.isTypeChange) {
      return 'Type changed: ${event.typeChangedFrom} → ${event.typeChangedTo} by ${event.assignedByName}';
    }
    if (event.assigneeNames.isEmpty) return event.assignedByName;
    return '${event.isUnassign ? 'Unassigned' : 'Assigned to'} ${event.assigneeNames.join(', ')} by ${event.assignedByName}';
  }

  Widget _buildTimelineRow(String label, DateTime dateTime) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurfaceVariant))),
          SizedBox(width: 220, child: Text(_formatDateTime(dateTime), textAlign: TextAlign.right, style: TextStyle(fontSize: 15.5, color: Theme.of(context).colorScheme.onSurface))),
        ],
      ),
    );
  }

  List<String> _parseComments(String comments) => comments.split('\n\n').where((c) => c.trim().isNotEmpty).toList();

  List<String> _parseNotes(String notes) => notes.split('\n\n').where((c) => c.trim().isNotEmpty).toList();


  Color _getPriorityColor(String priority) {
    final num = int.tryParse(priority.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    switch (num) {
      case 1: return Theme.of(context).appColors.priority1;
      case 2: return Theme.of(context).appColors.priority2;
      case 3: return Theme.of(context).appColors.priority3;
      case 4: return Theme.of(context).appColors.priority4;
      case 5: return Theme.of(context).appColors.priority5;
      default: return Colors.grey;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open': return Theme.of(context).appColors.statusOpen;
      case 'in_progress':
      case 'in progress': return Theme.of(context).appColors.statusInProgress;
      case 'completed':
      case 'monitor': return Theme.of(context).appColors.statusCompleted;
      case 'closed':
      case 'cancelled': return Theme.of(context).appColors.statusCancelled;
      default: return Colors.grey;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} - ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// Legacy photos store '' or no timestamp — DateTime.parse used to throw
  /// and crash the full-screen viewer.
  String _formatPhotoTimestamp(dynamic raw) {
    final dt = DateTime.tryParse(raw?.toString() ?? '');
    if (dt == null) return 'Unknown';
    final local = dt.toLocal().toString();
    return local.length >= 16 ? local.substring(0, 16) : local;
  }

  Widget _buildRelatedTab() {
    final current = _currentJobCard;

    final exactMatchStream = _firestoreService
        .getExactRelatedJobCardsStream(
          department: current.department,
          area: current.area,
          machine: current.machine,
          part: current.part,
          type: current.type.name,
        )
        .map((jobs) => jobs.where((j) => j.id != current.id).toList());

    final samePartStream = _firestoreService
        .getExactAllTypesStream(
          department: current.department,
          area: current.area,
          machine: current.machine,
          part: current.part,
        )
        .map((jobs) {
          return jobs
              .where((j) =>
                  j.id != current.id &&
                  j.type != current.type)
              .toList();
        });

    final sameMachineStream = _firestoreService
        .getAllPartsStream(
          department: current.department,
          area: current.area,
          machine: current.machine,
        )
        .map((jobs) {
          return jobs
              .where((j) =>
                  j.id != current.id &&
                  j.part != current.part)
              .toList();
        });

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        children: [
          RelatedSection(
            title: 'Exact Match',
            subtitle: 'Same department, area, machine, part & type (Monitor/Closed only)',
            stream: exactMatchStream,
            initiallyExpanded: true,
            pageSizes: _sectionPageSizes,
            itemBuilder: _buildRelatedJobCardDetailed,
          ),
          RelatedSection(
            title: 'Same Part, Different Type',
            subtitle: 'Same department, area, machine & part — different types (Monitor/Closed only)',
            stream: samePartStream,
            initiallyExpanded: false,
            pageSizes: _sectionPageSizes,
            itemBuilder: _buildRelatedJobCardDetailed,
          ),
          RelatedSection(
            title: 'Same Machine, Different Part',
            subtitle: 'Same department, area & machine — different parts, all types (Monitor/Closed only)',
            stream: sameMachineStream,
            initiallyExpanded: false,
            pageSizes: _sectionPageSizes,
            itemBuilder: _buildRelatedJobCardDetailed,
          ),
        ],
      ),
    );
  }

  Widget _buildRelatedJobCardDetailed(JobCard job) {
    final parsedComments = _parseComments(job.comments);
    final parsedNotes = _parseNotes(job.notes);

    return Card(
      elevation: 6,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (job.jobCardNumber != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 204),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'JC #${job.jobCardNumber}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    'Created by: ${job.operator.isEmpty ? 'Unknown' : job.operator}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(job.status.name),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    job.status.displayName,
                    style: TextStyle(
                      color: onColor(_getStatusColor(job.status.name)),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Text(
              '${job.department.isEmpty ? 'N/A' : job.department} > ${job.area.isEmpty ? 'N/A' : job.area} > ${job.machine.isEmpty ? 'N/A' : job.machine} > ${job.part.isEmpty ? 'N/A' : job.part}',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),

            Text(
              job.description,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),

            if (parsedComments.isNotEmpty) ...[
              Text(
                'Comments:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              ...parsedComments.map((comment) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  comment,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              )),
              const SizedBox(height: 8),
            ],

            if (parsedNotes.isNotEmpty) ...[
              Text(
                'Notes:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              ...parsedNotes.map((note) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  note,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              )),
            ],

            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Type: ${job.type.displayName}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobCardDetailScreen(jobCard: job))),
                  icon: const Icon(Icons.visibility, size: 16),
                  label: const Text('View Details'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBrandOrange,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RelatedSection extends StatefulWidget {
  final String title;
  final String subtitle;
  final Stream<List<JobCard>> stream;
  final bool initiallyExpanded;
  final Map<String, int> pageSizes;
  final Widget Function(JobCard) itemBuilder;

  const RelatedSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.stream,
    required this.initiallyExpanded,
    required this.pageSizes,
    required this.itemBuilder,
  });

  @override
  State<RelatedSection> createState() => _RelatedSectionState();
}

class _RelatedSectionState extends State<RelatedSection> with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  late bool _expanded;
  late AnimationController _controller;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    if (_expanded) _controller.value = 0.5;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        ListTile(
          onTap: _toggleExpanded,
          title: Row(
            children: [
              Expanded(child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium)),
              StreamBuilder<int>(
                stream: widget.stream.map((jobs) => jobs.length),
                initialData: 0,
                builder: (ctx, countSnap) {
                  final count = countSnap.data ?? 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: kBrandOrange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  );
                },
              ),
            ],
          ),
          subtitle: Text(widget.subtitle),
          trailing: RotationTransition(
            turns: Tween(begin: 0.0, end: 0.5).animate(_controller),
            child: const Icon(Icons.expand_more),
          ),
        ),
        Visibility(
          maintainState: true,
          visible: _expanded,
          child: StreamBuilder<List<JobCard>>(
            stream: widget.stream,
            initialData: const [],
            builder: (ctx, snap) {
              if (snap.hasError) {
                final errorMessage = snap.error.toString();
                if (errorMessage.contains('failed-precondition') && errorMessage.contains('index')) {
                  return ListTile(
                    title: const Text('Index Error', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                    subtitle: Text('Database indexes are being updated. Related jobs will be available shortly.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    leading: const Icon(Icons.warning, color: Colors.orange),
                  );
                }
                return ListTile(
                  title: const Text('Error Loading Related Jobs', style: TextStyle(color: Colors.red)),
                  subtitle: Text('Please try again later. ${snap.error}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  leading: const Icon(Icons.error, color: Colors.red),
                );
              }
              if (!snap.hasData) {
                return const ListTile(title: Center(child: CircularProgressIndicator()));
              }
              final jobs = snap.data!;
              if (jobs.isEmpty) {
                return ListTile(title: Text('No similar jobs found for this criteria', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)));
              }

              final pageSize = widget.pageSizes[widget.title] ?? 10;
              final displayedJobs = jobs.take(pageSize).toList();
              final hasMore = jobs.length > pageSize;

              return Column(
                children: [
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: displayedJobs.length,
                    itemBuilder: (ctx, i) => widget.itemBuilder(displayedJobs[i]),
                    separatorBuilder: (_, __) => const Divider(height: 1),
                  ),
                  if (hasMore)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            widget.pageSizes[widget.title] = (widget.pageSizes[widget.title] ?? 10) + 10;
                          });
                        },
                        icon: const Icon(Icons.expand_more),
                        label: const Text('Load More'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kBrandOrange,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}