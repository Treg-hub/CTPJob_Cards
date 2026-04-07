import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../main.dart' show currentEmployee;

class ViewJobCardsScreen extends StatefulWidget {
  const ViewJobCardsScreen({super.key});

  @override
  State<ViewJobCardsScreen> createState() => _ViewJobCardsScreenState();
}

class _ViewJobCardsScreenState extends State<ViewJobCardsScreen> {
  String? selectedDepartment;
  String? selectedArea;
  String? selectedMachine;
  List<String> departments = [];
  List<String> areas = [];
  List<String> machines = [];

  final FirestoreService _firestoreService = FirestoreService();
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Open Job Cards'),
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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Filter by Department:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: departments.map((dept) => FilterChip(
                    label: Text(dept, style: const TextStyle(fontSize: 12)),
                    selected: selectedDepartment == dept,
                    onSelected: (_) => _updateAreas(dept),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                    )).toList(),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<JobCard>>(
              stream: _firestoreService.getOpenJobCards(),
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
                  return const Center(child: Text('No open job cards matching filters', style: TextStyle(fontSize: 20)));
                }

                return ListView.builder(
                  itemCount: jobs.length,
                  itemBuilder: (context, index) {
                    final job = jobs[index];
                    return Card(
                      margin: const EdgeInsets.all(8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              job.description,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${job.department} • ${job.area} • ${job.machine}\n${job.type.displayName} | P${job.priority} | Operator: ${job.operator}\nAssigned: ${job.assignedToName ?? "Unassigned"}',
                              style: const TextStyle(fontSize: 14, color: Colors.grey),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => _showAssignCompleteDialog(context, job),
                                child: const Text('Assign / Complete'),
                              ),
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

  void _showAssignCompleteDialog(BuildContext context, JobCard job) {
    final notesController = TextEditingController();
    String searchQuery = '';
    String? selectedClockNo;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Assign or Complete'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search employee...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setDialogState(() => searchQuery = value.toLowerCase()),
                ),
                const SizedBox(height: 10),
                StreamBuilder<List<Employee>>(
                  stream: _firestoreService.getEmployeesStream(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const CircularProgressIndicator();
                    var employees = snapshot.data!;

                    // Filter by job type
                    if (job.type == JobType.mechanical) {
                      employees = employees.where((e) => e.position.toLowerCase().contains('mech')).toList();
                    } else if (job.type == JobType.electrical) {
                      employees = employees.where((e) => e.position.toLowerCase().contains('elec')).toList();
                    }

                    if (searchQuery.isNotEmpty) {
                      employees = employees.where((e) => e.displayName.toLowerCase().contains(searchQuery)).toList();
                    }

                    return SizedBox(
                      height: 300,
                      child: ListView.builder(
                        itemCount: employees.length,
                        itemBuilder: (context, index) {
                          final emp = employees[index];
                          return RadioListTile<String>(
                            title: Text(emp.displayName),
                            value: emp.clockNo,
                            groupValue: selectedClockNo,
                            onChanged: (val) => setDialogState(() => selectedClockNo = val),
                          );
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'Notes / Work Done'),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: isSaving ? null : () async {
                if (selectedClockNo == null) return;
                setDialogState(() => isSaving = true);

                try {
                  final assignedEmp = await _firestoreService.getEmployee(selectedClockNo!);
                  if (assignedEmp == null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Employee not found'), backgroundColor: Colors.red),
                      );
                    }
                    return;
                  }

                  final isOnSite = assignedEmp.isOnSite;

                  // Off site confirmation
                  if (!isOnSite && context.mounted) {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Employee is OFF SITE'),
                        content: const Text('This employee is currently OFF SITE.\n\nDo you still want to assign the job?'),
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

                  // Update job card
                  final updatedJob = job.copyWith(
                    assignedTo: selectedClockNo,
                    assignedToName: assignedEmp.name,
                    notes: notesController.text.trim(),
                  );

                  await _firestoreService.updateJobCard(job.id!, updatedJob);

                  // Send notification
                  if (assignedEmp.fcmToken != null) {
                    try {
                      await _notificationService.sendJobAssignmentNotification(
                        recipientToken: assignedEmp.fcmToken!,
                        operator: currentEmployee?.name ?? 'Unknown',
                        department: assignedEmp.department,
                        area: job.area,
                        machine: job.machine,
                        part: job.part,
                        description: notesController.text.trim(),
                      );
                    } catch (e) {
                      debugPrint('Notification failed: $e');
                    }
                  }

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('✅ Job assigned!')),
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
}