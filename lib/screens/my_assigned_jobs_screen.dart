import 'package:flutter/material.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../main.dart' show currentEmployee;
import '../theme/app_theme.dart';
import '../widgets/job_card_tile.dart';

class MyAssignedJobsScreen extends StatefulWidget {
  const MyAssignedJobsScreen({super.key});

  @override
  State<MyAssignedJobsScreen> createState() => _MyAssignedJobsScreenState();
}

class _MyAssignedJobsScreenState extends State<MyAssignedJobsScreen> {
  String? selectedDepartment;
  String? selectedArea;
  String? selectedMachine;
  List<String> departments = [];
  List<String> areas = [];
  List<String> machines = [];

  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    if (currentEmployee?.clockNo == null) return;

    try {
      final depts = await _firestoreService.getDepartmentsForJobCards('open');
      setState(() => departments = depts);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading departments: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _updateAreas(String dept) {
    setState(() {
      selectedDepartment = dept;
      selectedArea = null;
      selectedMachine = null;
      areas = [];
      machines = [];
    });
    _loadAreas(dept);
  }

  Future<void> _loadAreas(String dept) async {
    try {
      final areaList = await _firestoreService.getAreasForJobCards('open', dept);
      setState(() => areas = areaList);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading areas: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _updateMachines(String area) {
    setState(() {
      selectedArea = area;
      selectedMachine = null;
      machines = [];
    });
    _loadMachines(selectedDepartment!, area);
  }

  Future<void> _loadMachines(String dept, String area) async {
    try {
      final machineList = await _firestoreService.getMachinesForJobCards('open', dept, area);
      setState(() => machines = machineList);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading machines: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _clearFilters() {
    setState(() {
      selectedDepartment = null;
      selectedArea = null;
      selectedMachine = null;
      areas = [];
      machines = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    if (currentEmployee?.clockNo == null) {
      return const Scaffold(
        body: Center(child: Text('No employee logged in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Assigned Jobs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Clear Filters',
            onPressed: _clearFilters,
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: departments.map((dept) => FilterChip(
                    label: Text(dept, style: const TextStyle(fontSize: 12)),
                    selected: selectedDepartment == dept,
                    onSelected: (_) => _updateAreas(dept),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    labelStyle: selectedDepartment == dept ? const TextStyle(color: Color(0xFFFF8C42)) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
                  )).toList(),
                ),
                if (selectedDepartment != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: areas.map((area) => FilterChip(
                      label: Text(area, style: const TextStyle(fontSize: 12)),
                      selected: selectedArea == area,
                      onSelected: (_) => _updateMachines(area),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      labelStyle: selectedArea == area ? const TextStyle(color: Color(0xFFFF8C42)) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
                    )).toList(),
                  ),
                ],
                if (selectedArea != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: machines.map((machine) => FilterChip(
                      label: Text(machine, style: const TextStyle(fontSize: 12)),
                      selected: selectedMachine == machine,
                      onSelected: (_) => setState(() => selectedMachine = machine),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      labelStyle: selectedMachine == machine ? const TextStyle(color: Color(0xFFFF8C42)) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
                    )).toList(),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<JobCard>>(
              stream: _firestoreService.getAssignedJobCards(currentEmployee!.clockNo),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var jobs = snapshot.data!;
                if (selectedDepartment != null) {
                  jobs = jobs.where((j) => j.department == selectedDepartment).toList();
                }
                if (selectedArea != null) {
                  jobs = jobs.where((j) => j.area == selectedArea).toList();
                }
                if (selectedMachine != null) {
                  jobs = jobs.where((j) => j.machine == selectedMachine).toList();
                }

                if (jobs.isEmpty) {
                  return const Center(child: Text('No jobs assigned to you yet', style: TextStyle(fontSize: 20)));
                }

                return RefreshIndicator(
                  onRefresh: () async => setState(() {}),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    itemCount: jobs.length,
                    itemBuilder: (context, index) {
                      final job = jobs[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          JobCardTile(
                            job: job,
                            onTap: () => _showNotesDialog(context, job),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12, left: 4, right: 4),
                            child: Row(
                              children: [
                                if (job.startedAt == null) ...[
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () => _startWork(job),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                      ),
                                      child: const Text('Start'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => _showCompleteDialog(context, job),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                    ),
                                    child: const Text('Complete'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => _showMonitorDialog(context, job),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                    ),
                                    child: const Text('Monitor'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startWork(JobCard job) async {
    try {
      final startedJob = job.copyWith(
        startedAt: DateTime.now(),
      );

      await _firestoreService.saveJobCardOfflineAware(startedJob);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Work started!'), backgroundColor: Colors.blue),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting work: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }



  void _showNotesDialog(BuildContext context, JobCard job) {
    final notesController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Note'),
        content: TextField(
          controller: notesController,
          decoration: const InputDecoration(labelText: 'Note'),
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (notesController.text.trim().isEmpty) {
                Navigator.pop(context);
                return;
              }

              final now = DateTime.now();
              final user = currentEmployee?.name ?? 'User';
              final newNote = '\n\n[${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}] $user: ${notesController.text.trim()}';
              final updatedNotes = job.notes + newNote;

              try {
                await _firestoreService.saveJobCardOfflineAware(job.copyWith(notes: updatedNotes));

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ Note added!')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error adding note: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showCompleteDialog(BuildContext context, JobCard job) {
    final notesController = TextEditingController();
    bool isCompleting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Complete Job'),
          content: TextField(
            controller: notesController,
            decoration: const InputDecoration(labelText: 'Description/Corrective Action Taken'),
            maxLines: 4,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: isCompleting ? null : () async {
                final note = notesController.text.trim();
                if (note.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a description'), backgroundColor: Colors.red));
                  return;
                }
                setDialogState(() => isCompleting = true);

                try {
                  final now = DateTime.now();
                  final user = currentEmployee?.name ?? 'User';
                   final completedJob = job.copyWith(
                     status: JobStatus.closed,
                    completedBy: user,
                    completedAt: now,
                    notes: job.notes.isNotEmpty
                        ? '${job.notes}\n\n[${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}] Completed by $user: $note'
                        : '[${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}] Completed by $user: $note',
                  );

                  await _firestoreService.saveJobCardOfflineAware(completedJob);

                  // Notify creator
                  if (job.operatorClockNo != null) {
                    try {
                      final creatorEmp = await _firestoreService.getEmployee(job.operatorClockNo!);
                      if (creatorEmp?.fcmToken != null) {
                        await NotificationService().sendCreatorNotification(
                          recipientToken: creatorEmp!.fcmToken!,
                          jobCardId: job.id!,
                          jobCardNumber: job.jobCardNumber ?? 0,
                          operator: currentEmployee?.name ?? 'Unknown',
                          creator: job.operator,
                          department: job.department,
                          area: job.area,
                          machine: job.machine,
                          part: job.part,
                          description: job.description,
                          notificationType: 'closed',
                          assigneeName: currentEmployee?.name ?? 'Unknown',
                        );
                      }
                    } catch (e) {
                      debugPrint('Error sending creator notification: $e');
                    }
                  }

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('✅ Job Completed!')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error completing job: $e'), backgroundColor: Colors.red),
                    );
                  }
                } finally {
                  if (context.mounted) setDialogState(() => isCompleting = false);
                }
              },
              child: isCompleting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Complete'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMonitorDialog(BuildContext context, JobCard job) {
    final notesController = TextEditingController();
    bool isMonitoring = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Start Monitoring'),
          content: TextField(
            controller: notesController,
            decoration: const InputDecoration(labelText: 'Description/Corrective Action Taken'),
            maxLines: 4,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: isMonitoring ? null : () async {
                final note = notesController.text.trim();
                if (note.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a description'), backgroundColor: Colors.red));
                  return;
                }
                setDialogState(() => isMonitoring = true);

                try {
                  final now = DateTime.now();
                  final user = currentEmployee?.name ?? 'User';
                   final monitoredJob = job.copyWith(
                     status: JobStatus.monitor,
                    completedBy: user,
                    completedAt: now,
                    monitoringStartedAt: now,
                    notes: job.notes.isNotEmpty
                        ? '${job.notes}\n\n[${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}] Completed and monitoring started by $user: $note'
                        : '[${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}] Completed and monitoring started by $user: $note',
                  );

                  await _firestoreService.saveJobCardOfflineAware(monitoredJob);

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('✅ Job completed and monitoring started!')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error starting monitoring: $e'), backgroundColor: Colors.red),
                    );
                  }
                } finally {
                  if (context.mounted) setDialogState(() => isMonitoring = false);
                }
              },
              child: isMonitoring
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Start Monitoring'),
            ),
          ],
        ),
      ),
    );
  }

}
