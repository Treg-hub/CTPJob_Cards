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
  final TextEditingController _commentController = TextEditingController();
  final FirestoreService _firestoreService = FirestoreService();
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _reoccurrenceCount = widget.jobCard.reoccurrenceCount;
  }

  bool get isManager => currentEmployee?.position.toLowerCase().contains('manager') ?? false;

  Future<void> _updateJobCard() async {
    try {
      await _firestoreService.updateJobCard(
        widget.jobCard.id!,
        widget.jobCard.copyWith(reoccurrenceCount: _reoccurrenceCount),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _appendComment() async {
    if (_commentController.text.trim().isEmpty) return;
    final now = DateTime.now();
    final user = currentEmployee?.name ?? 'User';
    final newComment = '\n\n[${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}] $user: ${_commentController.text.trim()}';
    final updatedComments = widget.jobCard.comments + newComment;

    try {
      await _firestoreService.updateJobCard(
        widget.jobCard.id!,
        widget.jobCard.copyWith(
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
                         final filterLower = mechElecFilter!.toLowerCase();
                         employees = employees.where((e) {
                           final pos = (e.position ?? '').toLowerCase();
                           return pos.contains(filterLower);
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

                        int successCount = 0;
                        List<String> failedNames = [];
                         for (var i = 0; i < selectedClockNos.length; i++) {
                           final clockNo = selectedClockNos[i];
                           final emp = await _firestoreService.getEmployee(clockNo);
                           if (emp?.fcmToken?.trim().isNotEmpty == true) {
                             try {
                               await _notificationService.sendJobAssignmentNotification(
                                 recipientToken: emp!.fcmToken!.trim(),
                                 jobCardId: job.id!,
                                 operator: currentEmployee?.name ?? 'Unknown',
                                 department: emp.department,
                                 area: job.area,
                                 machine: job.machine,
                                 part: job.part,
                                 description: notesController.text.trim(),
                               );
                               successCount++;
                             } catch (e) {
                               debugPrint('Notification failed for ${emp?.name ?? 'Unknown'}: $e');
                               failedNames.add(emp?.name ?? 'Unknown');
                             }
                           } else {
                             failedNames.add('${emp?.name ?? 'Unknown'} (no token)');
                           }
                         }

                        if (context.mounted) {
                          Navigator.pop(context);
                          String message = '✅ Job assigned to ${selectedClockNos.length} employee(s)!';
                          if (successCount > 0) message += ' $successCount notified.';
                          if (failedNames.isNotEmpty) message += ' Failed: ${failedNames.join(', ')}';
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(message),
                              backgroundColor: failedNames.isEmpty ? null : Colors.orange,
                            ),
                          );
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
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'assignJob',
            onPressed: () => _showAssignCompleteDialog(context, widget.jobCard),
            icon: const Icon(Icons.assignment, size: 20),
            label: const Text('Assign', style: TextStyle(fontSize: 13)),
            backgroundColor: const Color(0xFF10B981),
          ),
        ],
      ),
      body: SingleChildScrollView(
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
                        Text('Job #${widget.jobCard.id ?? 'N/A'}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: widget.jobCard.status == JobStatus.completed ? Colors.green : Colors.blue,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            widget.jobCard.status.displayName.toUpperCase(),
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
                            border: Border.all(color: _getPriorityColor('P${widget.jobCard.priority}'), width: 2.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'P${widget.jobCard.priority}',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _getPriorityColor('P${widget.jobCard.priority}')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.jobCard.description,
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
              _buildDetailRow('Department', widget.jobCard.department ?? 'N/A'),
              _buildDetailRow('Area', widget.jobCard.area ?? 'N/A'),
              _buildDetailRow('Machine', widget.jobCard.machine ?? 'N/A'),
              _buildDetailRow('Part', widget.jobCard.part ?? 'N/A'),
            ])),
            const SizedBox(height: 6),

            _buildSectionCard(title: 'Personnel', child: Column(children: [
              _buildDetailRow('Created By', widget.jobCard.operator ?? 'Unknown'),
              if (widget.jobCard.assignedNames != null && widget.jobCard.assignedNames!.isNotEmpty)
                _buildDetailRow('Assigned To', widget.jobCard.assignedNames!.join(', ')),
              if (widget.jobCard.completedBy != null)
                _buildDetailRow('Completed By', widget.jobCard.completedBy!),
            ])),
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
                  if (widget.jobCard.comments.isNotEmpty)
                    ..._parseComments(widget.jobCard.comments).map((comment) => Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: Padding(padding: const EdgeInsets.all(8), child: Text(comment, style: const TextStyle(fontSize: 15))),
                        )),
                  if (widget.jobCard.comments.isEmpty) const Text('No comments yet', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            const SizedBox(height: 6),

            _buildSectionCard(
              title: 'Timeline',
              child: Column(
                children: [
                  if (widget.jobCard.createdAt != null) _buildTimelineRow('Created', widget.jobCard.createdAt!),
                  if (widget.jobCard.assignedAt != null) _buildTimelineRow('Assigned', widget.jobCard.assignedAt!),
                  if (widget.jobCard.startedAt != null) _buildTimelineRow('Started', widget.jobCard.startedAt!),
                  if (widget.jobCard.notificationReceivedAt != null) _buildTimelineRow('Notification Received', widget.jobCard.notificationReceivedAt!),
                  if (widget.jobCard.completedAt != null) _buildTimelineRow('Completed', widget.jobCard.completedAt!),
                  if (widget.jobCard.lastUpdatedAt != null) _buildTimelineRow('Last Updated', widget.jobCard.lastUpdatedAt!),
                ],
              ),
            ),
          ],
        ),
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