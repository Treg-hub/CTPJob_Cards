import 'package:flutter/material.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';

class CompletedJobsScreen extends StatefulWidget {
  const CompletedJobsScreen({super.key});

  @override
  State<CompletedJobsScreen> createState() => _CompletedJobsScreenState();
}

class _CompletedJobsScreenState extends State<CompletedJobsScreen> {
  String searchQuery = '';
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
    try {
      final depts = await _firestoreService.getDepartmentsForJobCards('completed');
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
      final areaList = await _firestoreService.getAreasForJobCards('completed', dept);
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
      final machineList = await _firestoreService.getMachinesForJobCards('completed', dept, area);
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
      searchQuery = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Completed Jobs History'),
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
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search description/machine/notes...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (val) => setState(() => searchQuery = val.toLowerCase()),
                ),
                const SizedBox(height: 16),
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
              stream: _firestoreService.getCompletedJobCards(),
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
                if (searchQuery.isNotEmpty) {
                  jobs = jobs.where((doc) {
                    final text = '${doc.description} ${doc.machine} ${doc.notes} ${doc.operator}'.toLowerCase();
                    return text.contains(searchQuery);
                  }).toList();
                }

                if (jobs.isEmpty) {
                  return const Center(child: Text('No completed jobs matching filters', style: TextStyle(fontSize: 20)));
                }

                return ListView.builder(
                  itemCount: jobs.length,
                  itemBuilder: (context, index) {
                    final job = jobs[index];
                    final completedAt = job.completedAt;
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
                              '${job.department} • ${job.area} • ${job.machine}\n${job.type.displayName} | P${job.priority} | Completed by: ${job.completedBy ?? "Unknown"}\nNotes: ${job.notes}',
                              style: const TextStyle(fontSize: 14, color: Colors.grey),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              completedAt != null
                                  ? 'Completed: ${completedAt.day}/${completedAt.month}/${completedAt.year}'
                                  : '',
                              style: const TextStyle(fontSize: 12, color: Colors.white70),
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
}