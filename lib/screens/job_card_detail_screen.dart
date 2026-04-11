import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../main.dart' show currentEmployee;

class JobCardDetailScreen extends StatefulWidget {
  final JobCard jobCard;

  const JobCardDetailScreen({super.key, required this.jobCard});

  @override
  State<JobCardDetailScreen> createState() => _JobCardDetailScreenState();
}

class _JobCardDetailScreenState extends State<JobCardDetailScreen> {
  late int _reoccurrenceCount;
  late JobCard _currentJobCard;
  final TextEditingController _commentController = TextEditingController();
  final FirestoreService _firestoreService = FirestoreService();
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _reoccurrenceCount = widget.jobCard.reoccurrenceCount;
    _currentJobCard = widget.jobCard;
  }

  bool get isManager => (currentEmployee?.position ?? '').toLowerCase().contains('manager');

  Future<void> _appendComment() async {
    if (_commentController.text.trim().isEmpty) return;
    final now = DateTime.now();
    final user = currentEmployee?.name ?? 'User';
    final newComment = '\n\n[${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}] $user: ${_commentController.text.trim()}';
    final updatedComments = _currentJobCard.comments + newComment;

    try {
      await _firestoreService.updateJobCard(
        _currentJobCard.id!,
        _currentJobCard.copyWith(
          comments: updatedComments,
          reoccurrenceCount: _reoccurrenceCount,
        ),
      );
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

  Future<void> _selfAssign(JobCard jobCard) async {
    final current = currentEmployee;
    if (current == null) return;
    final updated = jobCard.copyWith(
      assignedClockNos: [...?jobCard.assignedClockNos, current.clockNo],
      assignedNames: [...?jobCard.assignedNames, current.name],
      assignedAt: DateTime.now(),
      notes: jobCard.notes,
    );
    try {
      await _firestoreService.updateJobCard(jobCard.id!, updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Assigned to job!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error assigning: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _selfUnassign(JobCard jobCard) async {
    final current = currentEmployee;
    if (current == null) return;
    final updated = jobCard.copyWith(
      assignedClockNos: jobCard.assignedClockNos?.where((c) => c != current.clockNo).toList(),
      assignedNames: jobCard.assignedNames?.where((n) => n != current.name).toList(),
    );
    try {
      await _firestoreService.updateJobCard(jobCard.id!, updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unassigned from job!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error unassigning: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ==================== ASSIGN DIALOG WITH MECH/ELEC TOGGLE ====================
  void _showAssignCompleteDialog(BuildContext context, JobCard job) {
    final notesController = TextEditingController();
    String searchQuery = '';
    String? selectedDepartmentFilter;
    String? mechElecFilter; // null = Both, "Mechanical", "Electrical"
    List<String> selectedClockNos = [];
    List<String> selectedNames = [];
    bool isSaving = false;
    bool showOnsiteOnly = true;

    // Pre-select currently assigned employees
    selectedClockNos.addAll(job.assignedClockNos ?? []);
    selectedNames.addAll(job.assignedNames ?? []);

    // Auto-select Mech/Elec based on job type
    if (job.type.displayName.toLowerCase().contains('mechanical')) {
      mechElecFilter = 'Mechanical';
    } else if (job.type.displayName.toLowerCase().contains('electrical')) {
      mechElecFilter = 'Electrical';
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Assign to Employees'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search employee...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setDialogState(() => searchQuery = value.toLowerCase()),
                ),
                const SizedBox(height: 12),

                Column(
                  children: [
                    SegmentedButton<bool>(
                      selected: {showOnsiteOnly},
                      onSelectionChanged: (Set<bool> selection) {
                        setDialogState(() => showOnsiteOnly = selection.first);
                      },
                      segments: const [
                        ButtonSegment(value: true, label: Text('Onsite Only')),
                        ButtonSegment(value: false, label: Text('All')),
                      ],
                    ),
                    const SizedBox(height: 8),

                    SegmentedButton<String?>(
                      selected: {mechElecFilter},
                      onSelectionChanged: (Set<String?> selection) {
                        setDialogState(() => mechElecFilter = selection.first);
                      },
                      segments: const [
                        ButtonSegment(value: 'Mechanical', label: Text('Mech')),
                        ButtonSegment(value: 'Electrical', label: Text('Elec')),
                        ButtonSegment(value: null, label: Text('Both')),
                      ],
                    ),
                    const SizedBox(height: 8),

                    StreamBuilder<List<Employee>>(
                      stream: _firestoreService.getEmployeesStream(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const CircularProgressIndicator();
                        final depts = snapshot.data!
                            .map((e) => e.department)
                            .where((d) => d != null && d.isNotEmpty)
                            .cast<String>()
                            .toSet()
                            .toList()
                          ..sort();

                        return DropdownButtonFormField<String>(
                          isDense: true,
                          decoration: const InputDecoration(
                            labelText: 'Department',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          value: selectedDepartmentFilter,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('All Departments')),
                            ...depts.map((d) => DropdownMenuItem(value: d, child: Text(d))),
                          ],
                          onChanged: (val) => setDialogState(() => selectedDepartmentFilter = val),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                SizedBox(
                  height: 280,
                  child: StreamBuilder<List<Employee>>(
                    stream: _firestoreService.getEmployeesStream(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      var employees = snapshot.data!;

                      if (searchQuery.isNotEmpty) {
                        employees = employees.where((e) => e.displayName.toLowerCase().contains(searchQuery)).toList();
                      }
                      if (showOnsiteOnly) {
                        employees = employees.where((e) => e.isOnSite).toList();
                      }

                      // DEPARTMENT OVERRIDES MECH/ELEC
                      if (selectedDepartmentFilter != null) {
                        employees = employees.where((e) => e.department == selectedDepartmentFilter).toList();
                      } else if (mechElecFilter != null) {
                        employees = employees.where((e) {
                          final pos = (e.position ?? '').toLowerCase();
                          return pos.contains(mechElecFilter!.toLowerCase());
                        }).toList();
                      }

                      employees.sort((a, b) => (a.isOnSite ? 0 : 1).compareTo(b.isOnSite ? 0 : 1));

                      if (employees.isEmpty) {
                        return const Center(child: Text('No employees match filters', style: TextStyle(color: Colors.white70)));
                      }

                      return ListView.separated(
                        itemCount: employees.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
                        itemBuilder: (context, index) {
                          final emp = employees[index];
                          final isSelected = selectedClockNos.contains(emp.clockNo);

                          return CheckboxListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            title: Text(
                              '${emp.displayName} - ${emp.department ?? ''}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                            secondary: Icon(
                              emp.isOnSite ? Icons.location_on : Icons.location_off,
                              color: emp.isOnSite ? Colors.green : Colors.red[400]!,
                              size: 20,
                            ),
                            tileColor: emp.isOnSite ? Colors.green.withOpacity(0.08) : Colors.red.withOpacity(0.08),
                            value: isSelected,
                            onChanged: (val) {
                              setDialogState(() {
                                if (val == true) {
                                  selectedClockNos.add(emp.clockNo);
                                  selectedNames.add(emp.name);
                                } else {
                                  selectedClockNos.remove(emp.clockNo);
                                  selectedNames.remove(emp.name);
                                }
                              });
                            },
                          );
                        },
                      );
                    },
                  ),
                ),

                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'Notes / Work Done', border: OutlineInputBorder()),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
              onPressed: isSaving || selectedClockNos.isEmpty
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      try {
                        for (var clockNo in selectedClockNos) {
                          final emp = await _firestoreService.getEmployee(clockNo);
                          if (emp != null && !emp.isOnSite && context.mounted) {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Employee is OFF SITE'),
                                content: Text('${emp.name} is currently OFF SITE.\n\nDo you still want to assign the job?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, Assign Anyway')),
                                ],
                              ),
                            );
                            if (confirm != true) {
                              setDialogState(() => isSaving = false);
                              return;
                            }
                          }
                        }

                        final updatedJob = job.copyWith(
                          assignedClockNos: selectedClockNos,
                          assignedNames: selectedNames,
                          assignedAt: DateTime.now(),
                          notes: notesController.text.trim(),
                        );

                        await _firestoreService.updateJobCard(job.id!, updatedJob);

                        for (var i = 0; i < selectedClockNos.length; i++) {
                          final clockNo = selectedClockNos[i];
                          final emp = await _firestoreService.getEmployee(clockNo);
                          if (emp?.fcmToken != null) {
                            try {
                              await _notificationService.sendJobAssignmentNotification(
                                recipientToken: emp!.fcmToken!,
                                jobCardId: job.id!,
                                operator: currentEmployee?.name ?? 'Unknown',
                                department: emp.department,
                                area: job.area,
                                machine: job.machine,
                                part: job.part,
                                description: notesController.text.trim(),
                              );
                            } catch (e) {
                              debugPrint('Notification failed for ${emp?.name ?? 'Unknown'}: $e');
                            }
                          }
                        }

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Job assigned!')));
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                          );
                        }
                      } finally {
                        if (context.mounted) setDialogState(() => isSaving = false);
                      }
                    },
              child: isSaving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Assign'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Card Details'),
        backgroundColor: const Color(0xFFFF8C42),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'addComment',
            onPressed: _showAddCommentDialog,
            icon: const Icon(Icons.comment, size: 20),
            label: const Text('Comment', style: TextStyle(fontSize: 13)),
            backgroundColor: const Color(0xFFFF8C42),
          ),
          if (isManager) const SizedBox(height: 8),
          if (isManager) FloatingActionButton.extended(
            heroTag: 'assignJob',
            onPressed: () => _showAssignCompleteDialog(context, _currentJobCard),
            icon: const Icon(Icons.assignment, size: 20),
            label: const Text('Assign', style: TextStyle(fontSize: 13)),
            backgroundColor: const Color(0xFF10B981),
          ),
        ],
      ),
      body: StreamBuilder<JobCard>(
        stream: _firestoreService.getJobCardStream(widget.jobCard.id!),
        builder: (context, snapshot) {
          final jobCard = snapshot.hasData ? snapshot.data! : widget.jobCard;
          _currentJobCard = jobCard;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  elevation: 6,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Job #${jobCard.id ?? 'N/A'}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: jobCard.status == JobStatus.completed ? Colors.green : Colors.blue,
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: Text(
                                jobCard.status.displayName.toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                border: Border.all(color: _getPriorityColor('P${jobCard.priority}'), width: 2.5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'P${jobCard.priority}',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _getPriorityColor('P${jobCard.priority}')),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                jobCard.description,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                _buildSectionCard(title: 'Location', child: Column(children: [
                  _buildDetailRow('Department', jobCard.department ?? 'N/A'),
                  _buildDetailRow('Area', jobCard.area ?? 'N/A'),
                  _buildDetailRow('Machine', jobCard.machine ?? 'N/A'),
                  _buildDetailRow('Part', jobCard.part ?? 'N/A'),
                ])),
                const SizedBox(height: 6),

                _buildSectionCard(title: 'Personnel', child: Column(children: [
                  _buildDetailRow('Created By', jobCard.operator ?? 'Unknown'),
                  if (jobCard.assignedNames != null && jobCard.assignedNames!.isNotEmpty)
                    _buildDetailRow('Assigned To', jobCard.assignedNames!.join(', ')),
                  if (jobCard.completedBy != null)
                    _buildDetailRow('Completed By', jobCard.completedBy!),
                  if ((currentEmployee?.position ?? '').toLowerCase().contains('mechanical') || (currentEmployee?.position ?? '').toLowerCase().contains('electrical')) Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ElevatedButton(
                      onPressed: jobCard.assignedClockNos?.contains(currentEmployee?.clockNo ?? '') ?? false ? () => _selfUnassign(jobCard) : () => _selfAssign(jobCard),
                      style: jobCard.assignedClockNos?.contains(currentEmployee?.clockNo ?? '') ?? false ? ElevatedButton.styleFrom(backgroundColor: Colors.red) : null,
                      child: Text(jobCard.assignedClockNos?.contains(currentEmployee?.clockNo ?? '') ?? false ? 'Unassign Self' : 'Assign Self'),
                    ),
                  ),
                ])),
                const SizedBox(height: 6),

                _buildSectionCard(
                  title: 'Notes',
                  child: jobCard.notes.isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(jobCard.notes, style: const TextStyle(fontSize: 15)),
                      )
                    : const Text('No notes', style: TextStyle(color: Colors.white70)),
                ),
                const SizedBox(height: 6),

                _buildSectionCard(
                  title: 'Reoccurrence Count',
                  child: Center(child: Text('$_reoccurrenceCount', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold))),
                ),
                const SizedBox(height: 6),

                _buildSectionCard(
                  title: 'Comments',
                  child: Column(
                    children: [
                      if (jobCard.comments.isNotEmpty)
                        ..._parseComments(jobCard.comments).map((comment) => Card(
                              margin: const EdgeInsets.only(bottom: 6),
                              child: Padding(padding: const EdgeInsets.all(8), child: Text(comment, style: const TextStyle(fontSize: 15))),
                            )),
                      if (jobCard.comments.isEmpty) const Text('No comments yet', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                _buildSectionCard(
                  title: 'Timeline',
                  child: Column(
                    children: [
                      if (jobCard.createdAt != null) _buildTimelineRow('Created', jobCard.createdAt!),
                      if (jobCard.assignedAt != null) _buildTimelineRow('Assigned', jobCard.assignedAt!),
                      if (jobCard.startedAt != null) _buildTimelineRow('Started', jobCard.startedAt!),
                      if (jobCard.notificationReceivedAt != null) _buildTimelineRow('Notification Received', jobCard.notificationReceivedAt!),
                      if (jobCard.completedAt != null) _buildTimelineRow('Completed', jobCard.completedAt!),
                      if (jobCard.lastUpdatedAt != null) _buildTimelineRow('Last Updated', jobCard.lastUpdatedAt!),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAddCommentDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
          decoration: const BoxDecoration(
            color: Color(0xFF1F1F1F),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
          ),
          child: StatefulBuilder(
            builder: (context, setDialogState) => Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Add Comment & Update Reoccurrence', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(iconSize: 32, icon: const Icon(Icons.remove_circle_outline), color: const Color(0xFFFF8C42), onPressed: () { if (_reoccurrenceCount > 1) setDialogState(() => _reoccurrenceCount--); }),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8), decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(12)), child: Text('$_reoccurrenceCount', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold))),
                      IconButton(iconSize: 32, icon: const Icon(Icons.add_circle_outline), color: const Color(0xFFFF8C42), onPressed: () => setDialogState(() => _reoccurrenceCount++)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(controller: _commentController, decoration: const InputDecoration(labelText: 'Comment / Work Done', border: OutlineInputBorder()), maxLines: 4),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                      const SizedBox(width: 12),
                      ElevatedButton(onPressed: () { Navigator.pop(context); _appendComment(); }, child: const Text('Save Comment')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)), const SizedBox(height: 6), child]),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 120, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.grey))), Expanded(child: Text(value, style: const TextStyle(fontSize: 15.5)))]),
    );
  }

  Widget _buildTimelineRow(String label, DateTime dateTime) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [SizedBox(width: 130, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.grey))), Expanded(child: Text(_formatDateTime(dateTime), style: const TextStyle(fontSize: 15.5)))]),
    );
  }

  List<String> _parseComments(String comments) => comments.split('\n\n').where((c) => c.trim().isNotEmpty).toList();

  Color _getPriorityColor(String priority) {
    final num = int.tryParse(priority.substring(1)) ?? 0;
    switch (num) {
      case 1: return Colors.green[600]!;
      case 2: return Colors.lightGreen[500]!;
      case 3: return Colors.amber[600]!;
      case 4: return Colors.deepOrange[600]!;
      case 5: return const Color(0xFFFF3D00);
      default: return Colors.grey;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}