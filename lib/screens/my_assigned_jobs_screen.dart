import 'package:flutter/material.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import '../main.dart' show currentEmployee;

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
  final TextEditingController _commentController = TextEditingController();

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
                    labelStyle: selectedDepartment == dept ? const TextStyle(color: Color(0xFFFF8C42)) : const TextStyle(color: Colors.white),
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
                      labelStyle: selectedArea == area ? const TextStyle(color: Color(0xFFFF8C42)) : const TextStyle(color: Colors.white),
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
                      labelStyle: selectedMachine == machine ? const TextStyle(color: Color(0xFFFF8C42)) : const TextStyle(color: Colors.white),
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

                return ListView.builder(
                  itemCount: jobs.length,
                  itemBuilder: (context, index) {
                    final job = jobs[index];
                    return Card(
                      margin: const EdgeInsets.all(8),
                      child: ListTile(
                        title: Text(job.description),
                        subtitle: Text('${job.department} > ${job.machine} > ${job.area}'),
                        onTap: () => _showCommentDialog(context, job),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (job.startedAt == null)
                              ElevatedButton(
                                onPressed: () => _startWork(job),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                ),
                                child: const Text('Start', style: TextStyle(fontSize: 12)),
                              ),
                            const SizedBox(width: 4),
                            ElevatedButton(
                              onPressed: () => _showCompleteDialog(context, job),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              ),
                              child: const Text('Complete', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
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

      await _firestoreService.updateJobCard(job.id!, startedJob);

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

  void _showCommentDialog(BuildContext context, JobCard job) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Comment'),
        content: TextField(
          controller: _commentController,
          decoration: const InputDecoration(labelText: 'Comment'),
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (_commentController.text.trim().isEmpty) {
                Navigator.pop(context);
                return;
              }

              final now = DateTime.now();
              final user = currentEmployee?.name ?? 'User';
              final newComment = '\n\n[${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}] $user: ${_commentController.text.trim()}';
              final updatedComments = job.comments + newComment;

              try {
                await _firestoreService.updateJobCard(
                  job.id!,
                  job.copyWith(comments: updatedComments),
                );

                if (context.mounted) {
                  Navigator.pop(context);
                  setState(() => _commentController.clear());
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ Comment added!')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error adding comment: $e'), backgroundColor: Colors.red),
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
            decoration: const InputDecoration(labelText: 'Notes / Work Done'),
            maxLines: 4,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: isCompleting ? null : () async {
                setDialogState(() => isCompleting = true);

                try {
                  final completedJob = job.copyWith(
                    status: JobStatus.completed,
                    completedBy: currentEmployee?.name,
                    completedAt: DateTime.now(),
                    notes: notesController.text.trim(),
                  );

                  await _firestoreService.updateJobCard(job.id!, completedJob);

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
}
