import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../main.dart' show currentEmployee;
import 'job_card_detail_screen.dart';

class ViewJobCardsScreen extends StatefulWidget {
  const ViewJobCardsScreen({
    super.key,
    this.filterDepartment,
    this.filterArea,
    this.filterMachine,
    this.filterPart,
  });

  final String? filterDepartment;
  final String? filterArea;
  final String? filterMachine;
  final String? filterPart;

  @override
  State<ViewJobCardsScreen> createState() => _ViewJobCardsScreenState();
}

class _ViewJobCardsScreenState extends State<ViewJobCardsScreen> {
  String? selectedDepartment;
  String? selectedArea;
  String? selectedMachine;
  String? selectedPart;
  List<String> departments = [];
  List<String> areas = [];
  List<String> machines = [];
  List<String> parts = [];
  bool viewOpenJobs = true;
  int openCount = 0;
  int closedCount = 0;
  bool _updatingCounts = false;

  final FirestoreService _firestoreService = FirestoreService();
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    selectedDepartment = widget.filterDepartment;
    selectedArea = widget.filterArea;
    selectedMachine = widget.filterMachine;
    selectedPart = widget.filterPart;
    _loadDepartments();
    if (selectedDepartment != null) {
      _updateAreas(selectedDepartment!);
    }
  }

  Future<void> _loadDepartments() async {
    try {
      final snapshot = await _firestoreService.getAllJobCards().first;
      final depts = snapshot.map((j) => j.department).toSet().toList()..sort();
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
      selectedPart = null;
      areas = [];
      machines = [];
      parts = [];
    });
    _loadAreas(dept);
  }

  Future<void> _loadAreas(String dept) async {
    try {
      final snapshot = await _firestoreService.getAllJobCards().first;
      final areaList = snapshot.where((j) => j.department == dept).map((j) => j.area).toSet().toList()..sort();
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
      selectedPart = null;
      machines = [];
      parts = [];
    });
    _loadMachines(selectedDepartment!, area);
  }

  Future<void> _loadMachines(String dept, String area) async {
    try {
      final snapshot = await _firestoreService.getAllJobCards().first;
      final machineList = snapshot.where((j) => j.department == dept && j.area == area).map((j) => j.machine).toSet().toList()..sort();
      setState(() => machines = machineList);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading machines: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadParts(String dept, String area, String machine) async {
    try {
      final snapshot = await _firestoreService.getAllJobCards().first;
      final partList = snapshot.where((j) => j.department == dept && j.area == area && j.machine == machine).map((j) => j.part).toSet().toList()..sort();
      setState(() => parts = partList);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading parts: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _clearFilters() {
    setState(() {
      selectedDepartment = null;
      selectedArea = null;
      selectedMachine = null;
      selectedPart = null;
      areas = [];
      machines = [];
      parts = [];
    });
  }

  bool get _isDesktop => MediaQuery.of(context).size.width >= 1200;

  Color _getPriorityColor(String priority) {
    final num = int.tryParse(priority.substring(1)) ?? 0;
    switch (num) {
      case 1:
        return Colors.green[500]!;
      case 2:
        return Colors.lightGreen[500]!;
      case 3:
        return Colors.amber[500]!;
      case 4:
        return Colors.deepOrange[500]!;
      case 5:
        return Colors.red[700]!;
      default:
        return Colors.grey;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return Colors.blue;
      case 'in progress':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildJobList(List<JobCard> jobs, String title) {
    return Column(
      children: [
        if (title.isNotEmpty) Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: jobs.isEmpty
            ? Center(child: Text('No ${title.toLowerCase()} available', style: const TextStyle(color: Colors.white70)))
            : ListView.builder(
                itemCount: jobs.length,
                itemBuilder: (context, index) => _buildJobCard(jobs[index]),
              ),
        ),
      ],
    );
  }

  Widget _buildJobCard(JobCard job) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => JobCardDetailScreen(jobCard: job)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // First line: department, machine, area, created by
              Row(
                children: [
                  Text(
                    '${job.department} • ${job.machine} • ${job.area}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Created by: ${job.operator}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Second line: Priority, description
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getPriorityColor('P${job.priority}'),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'P${job.priority}',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      job.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Third line: Status, Type, Assigned to, Last updated
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getStatusColor(job.status.name).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      job.status.displayName,
                      style: TextStyle(color: _getStatusColor(job.status.name), fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      job.type.displayName,
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      job.assignedToName ?? job.assignedTo ?? 'Unassigned',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                Text(
                  job.lastUpdatedAt != null ? _formatDateTime(job.lastUpdatedAt!) : 'Unknown',
                  style: const TextStyle(color: Color(0xFFFF8C42), fontSize: 11),
                ),
                  IconButton(
                    icon: const Icon(Icons.assignment, size: 20),
                    onPressed: () => _showAssignCompleteDialog(context, job),
                    tooltip: 'Assign / Complete',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Job Cards'),
        actions: [
                if (selectedDepartment != null || selectedArea != null || selectedMachine != null || selectedPart != null)
                  TextButton.icon(
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear'),
                    onPressed: _clearFilters,
                  ),
        ],
      ),
      body: Column(
        children: [
          if (!_isDesktop) Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: true, label: Text('Open ($openCount)')),
                    ButtonSegment(value: false, label: Text('Closed ($closedCount)')),
                  ],
                  selected: {viewOpenJobs},
                  onSelectionChanged: (Set<bool> selected) {
                    if (selected.isNotEmpty) {
                      setState(() => viewOpenJobs = selected.first);
                    }
                  },
                ),
                if (selectedDepartment != null || selectedArea != null || selectedMachine != null || selectedPart != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear Filters',
                    onPressed: _clearFilters,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: departments.map((dept) => ChoiceChip(
                        label: Text(dept),
                        selected: selectedDepartment == dept,
                        onSelected: (_) => _updateAreas(dept),
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                      )).toList(),
                    ),
                  ),
                ),
                if (selectedDepartment != null)
                  Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: areas.map((area) => ChoiceChip(
                          label: Text(area),
                          selected: selectedArea == area,
                          onSelected: (_) => _updateMachines(area),
                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                        )).toList(),
                      ),
                    ),
                  ),
                if (selectedArea != null)
                  Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: machines.map((machine) => ChoiceChip(
                          label: Text(machine),
                          selected: selectedMachine == machine,
                          onSelected: (_) {
                            setState(() => selectedMachine = machine);
                            _loadParts(selectedDepartment!, selectedArea!, machine);
                          },
                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                        )).toList(),
                      ),
                    ),
                  ),
                if (selectedMachine != null && parts.isNotEmpty)
                  Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: parts.map((part) => ChoiceChip(
                          label: Text(part),
                          selected: selectedPart == part,
                          onSelected: (_) => setState(() => selectedPart = part),
                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                        )).toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<JobCard>>(
              stream: _firestoreService.getAllJobCards(),
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
                if (selectedPart != null) {
                  jobs = jobs.where((j) => j.part == selectedPart).toList();
                }

                List<JobCard> openJobs = jobs.where((j) => !j.isCompleted).toList();
                List<JobCard> closedJobs = jobs.where((j) => j.isCompleted).toList();

                // Update counts for selector
                if ((openCount != openJobs.length || closedCount != closedJobs.length) && !_updatingCounts) {
                  _updatingCounts = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        openCount = openJobs.length;
                        closedCount = closedJobs.length;
                      });
                    }
                    _updatingCounts = false;
                  });
                }

                if (_isDesktop) {
                  return Row(
                    children: [
                      Expanded(child: _buildJobList(openJobs, 'Open Jobs')),
                      Expanded(child: _buildJobList(closedJobs, 'Closed Jobs')),
                    ],
                  );
                } else {
                  return _buildJobList(viewOpenJobs ? openJobs : closedJobs, '');
                }
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
                    assignedAt: DateTime.now(),
                    notes: notesController.text.trim(),
                  );

                  await _firestoreService.updateJobCard(job.id!, updatedJob);

                  // Send notification
                  if (assignedEmp.fcmToken != null) {
                    try {
                      await _notificationService.sendJobAssignmentNotification(
                        recipientToken: assignedEmp.fcmToken!,
                        jobCardId: job.id!,
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