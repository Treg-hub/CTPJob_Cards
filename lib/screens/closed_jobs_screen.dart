import 'package:flutter/material.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import '../widgets/job_card_tile.dart';

class ClosedJobsScreen extends StatefulWidget {
  const ClosedJobsScreen({super.key});

  @override
  State<ClosedJobsScreen> createState() => _ClosedJobsScreenState();
}

class _ClosedJobsScreenState extends State<ClosedJobsScreen> {
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
      final depts = await _firestoreService.getDepartmentsForJobCards('closed');
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
      final areaList = await _firestoreService.getAreasForJobCards('closed', dept);
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
      final machineList = await _firestoreService.getMachinesForJobCards('closed', dept, area);
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

  void _showAddCommentDialog(JobCard job) {
    final commentController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Comment'),
        content: TextField(
          controller: commentController,
          decoration: const InputDecoration(labelText: 'Comment'),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (commentController.text.trim().isEmpty) return;
              final now = DateTime.now();
              const user = 'User'; // Since no currentEmployee in this screen
              final newComment = '\n\n[${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2,'0')}] $user: ${commentController.text.trim()}';
              final updatedComments = job.comments + newComment;
              try {
                await _firestoreService.saveJobCardOfflineAware(job.copyWith(comments: updatedComments));
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Comment added!')),
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
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Closed Jobs History'),
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
              stream: _firestoreService.getClosedJobCards(),
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
                  return const Center(child: Text('No closed jobs matching filters', style: TextStyle(fontSize: 20)));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: jobs.length,
                  itemBuilder: (context, index) {
                    final job = jobs[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        JobCardTile(job: job),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12, left: 4, right: 4, top: 2),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              onPressed: () => _showAddCommentDialog(job),
                              icon: const Icon(Icons.comment, size: 16),
                              label: const Text('Add Comment'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                textStyle: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                      ],
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