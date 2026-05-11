import 'package:flutter/material.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
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

class _ViewJobCardsScreenState extends State<ViewJobCardsScreen> with SingleTickerProviderStateMixin {
  String? selectedDepartment;
  String? selectedArea;
  String? selectedMachine;
  String? selectedPart;

  String selectedStatus = 'open';
  int openCount = 0;
  int closedCount = 0;

  String selectedStaffFilter = 'All';

  late TabController _tabController;

  bool get isManager => (currentEmployee?.position ?? '').toLowerCase().contains('manager');
  bool get isSuperManager => currentEmployee?.department.toLowerCase() == 'general';
  bool get _isWide => MediaQuery.of(context).size.width >= 1000;

  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {
        selectedStatus = ['open', 'monitor', 'closed'][_tabController.index];
      });
    });

    selectedStaffFilter = _employeeStaffDefault ?? 'All';
    if (_employeeStaffDefault == null) {
      selectedDepartment = currentEmployee?.department;
    } else {
      selectedDepartment = null;
    }
    if (isSuperManager) {
      selectedDepartment = null;
    }
    selectedArea = widget.filterArea;
    selectedMachine = widget.filterMachine;
    selectedPart = widget.filterPart;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String? get _employeeStaffDefault {
    final empPosition = currentEmployee?.position.toLowerCase();
    if (empPosition?.contains('electrical') ?? false) return 'Electrical';
    if (empPosition?.contains('mechanical') ?? false) return 'Mechanical';
    return null;
  }

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

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open': return Colors.blue;
      case 'monitor': return Colors.orange;
      case 'closed': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _getLastCommentPreview(String comments) {
    final parts = comments.split('\n\n').where((c) => c.trim().isNotEmpty).toList();
    if (parts.isEmpty) return '';
    final lastComment = parts.last;
    final lines = lastComment.split('\n');
    return lines.length > 1 ? lines[1].trim() : lastComment.trim();
  }



  // ==================== CASCADING FILTERS ====================
  Widget _buildCascadingFilters() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _firestoreService.getFactoryStructure(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Error loading filters: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          );
        }

        final data = snapshot.data!;
        final areas = selectedDepartment != null ? (data[selectedDepartment] as Map<String, dynamic>? ?? {}).keys.toList() : <String>[];
        final machines = selectedArea != null && selectedDepartment != null
            ? (data[selectedDepartment]?[selectedArea] as List<dynamic>? ?? []).cast<String>()
            : <String>[];

        Widget currentStep;

        if (selectedPart != null) {
          // All selected, show nothing
          currentStep = const SizedBox.shrink();
        } else if (selectedMachine != null) {
          // Show part chips only
          currentStep = FutureBuilder<List<String>>(
            future: _firestoreService.getPreviousParts(selectedDepartment!, selectedArea!, selectedMachine!),
            builder: (context, snapshot) {
              final previousParts = snapshot.data ?? [];
              if (previousParts.isEmpty) {
                return const Text('No previous parts found', style: TextStyle(color: Colors.white70));
              }
              return Center(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: previousParts.map((part) => ActionChip(
                    label: Text(part),
                    onPressed: () => setState(() => selectedPart = part),
                    backgroundColor: selectedPart == part ? const Color(0xFFFF8C42).withValues(alpha: 51) : null,
                    labelStyle: TextStyle(color: selectedPart == part ? const Color(0xFFFF8C42) : Colors.white),
                  )).toList(),
                ),
              );
            },
          );
        } else if (selectedArea != null) {
          // Show machine chips
          currentStep = Center(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: machines.map((machine) => ChoiceChip(
                label: Text(machine),
                selected: selectedMachine == machine,
                onSelected: (_) => setState(() {
                  selectedMachine = machine;
                  selectedPart = null;
                }),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                labelStyle: selectedMachine == machine ? const TextStyle(color: Color(0xFFFF8C42)) : const TextStyle(color: Colors.white),
              )).toList(),
            ),
          );
        } else if (selectedDepartment != null) {
          // Show area chips
          currentStep = Center(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: areas.map((area) => ChoiceChip(
                label: Text(area),
                selected: selectedArea == area,
                onSelected: (_) => setState(() {
                  selectedArea = area;
                  selectedMachine = null;
                  selectedPart = null;
                }),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                labelStyle: selectedArea == area ? const TextStyle(color: Color(0xFFFF8C42)) : const TextStyle(color: Colors.white),
              )).toList(),
            ),
          );
        } else {
          // Show dept chips
          currentStep = Center(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('All Departments'),
                  selected: selectedDepartment == null,
                  onSelected: (_) => setState(() {
                    selectedDepartment = null;
                    selectedArea = null;
                    selectedMachine = null;
                    selectedPart = null;
                  }),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  labelStyle: selectedDepartment == null ? const TextStyle(color: Color(0xFFFF8C42)) : const TextStyle(color: Colors.white),
                ),
                ...data.keys.map((dept) => ChoiceChip(
                  label: Text(dept),
                  selected: selectedDepartment == dept,
                  onSelected: (_) => setState(() {
                    selectedDepartment = dept;
                    selectedArea = null;
                    selectedMachine = null;
                    selectedPart = null;
                  }),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  labelStyle: selectedDepartment == dept ? const TextStyle(color: Color(0xFFFF8C42)) : const TextStyle(color: Colors.white),
                )),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Clear All Button
              if (selectedDepartment != null || selectedArea != null || selectedMachine != null || selectedPart != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Center(
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          selectedStaffFilter = 'All';
                          selectedDepartment = null;
                          selectedArea = null;
                          selectedMachine = null;
                          selectedPart = null;
                        });
                      },
                      icon: const Icon(Icons.clear),
                      label: const Text('Clear All Filters'),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF8C42)),
                    ),
                  ),
                ),

              // Current Step
              currentStep,
            ],
          ),
        );
      },
    );
  }

  // ==================== IMPROVED JOB CARD (same as HomeScreen) ====================
  Widget _buildJobCardWidget(JobCard job) {
    return Card(
      elevation: 6,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => JobCardDetailScreen(jobCard: job)),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'P${job.priority}',
                      style: TextStyle(
                        color: _getPriorityColor('P${job.priority}'),
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                    TextSpan(
                      text: ' | ${job.department ?? 'N/A'} > ${job.area ?? 'N/A'} > ${job.machine ?? 'N/A'} > ${job.part ?? 'N/A'} | ${job.operator ?? 'Unknown'}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
               Row(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Container(
                     padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                     decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 204),
                       borderRadius: BorderRadius.circular(6),
                     ),
                   child: Text(
                     'JC #${job.jobCardNumber ?? 'N/A'}',
                     style: const TextStyle(
                       color: Colors.white,
                       fontSize: 12,
                       fontWeight: FontWeight.w600,
                     ),
                   ),
                   ),
                   const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      job.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              if (job.comments.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _getLastCommentPreview(job.comments),
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade300, fontStyle: FontStyle.italic),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (job.notes.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  job.notes.split('\n').first.trim(),
                  style: const TextStyle(fontSize: 13, color: Colors.white70, fontStyle: FontStyle.italic),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _getStatusColor(job.status.name).withValues(alpha: 128),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      job.status.displayName,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                             color: Colors.blueGrey.withValues(alpha: 64),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      job.type.displayName,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  const Spacer(),

                  // FIXED: Prevents horizontal overflow when many people are assigned
                  Expanded(
                    child: Text(
                      job.assignedNames?.join(', ') ?? 'Unassigned',
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      textAlign: TextAlign.end,
                    ),
                  ),

                  const SizedBox(width: 12),
                  Text(
                    job.lastUpdatedAt != null ? _formatDateTime(job.lastUpdatedAt!) : '—',
                    style: const TextStyle(color: Color(0xFFFF8C42), fontSize: 12),
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
        backgroundColor: const Color(0xFFFF8C42),
        actions: [
          // Staff Filter Icons
          ToggleButtons(
            isSelected: [
              selectedStaffFilter == 'Mechanical',
              selectedStaffFilter == 'Electrical',
              selectedStaffFilter == 'All',
            ],
            onPressed: (index) {
              setState(() {
                selectedStaffFilter = ['Mechanical', 'Electrical', 'All'][index];
              });
            },
            borderRadius: BorderRadius.circular(8),
            selectedColor: const Color(0xFFFF8C42),
            fillColor: const Color(0xFFFF8C42).withValues(alpha: 51),
            children: const [
              Icon(Icons.build, size: 24, color: Colors.black), // Mechanical
              Icon(Icons.bolt, size: 24, color: Colors.black), // Electrical
              Icon(Icons.circle_outlined, size: 24, color: Colors.black), // All
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<JobCard>>(
        stream: _firestoreService.getAllJobCards(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allJobs = snapshot.data!;

          // Apply staff filter for counts
          var jobs = allJobs;
          if (selectedStaffFilter != 'All') {
            jobs = jobs.where((j) => j.type.name == selectedStaffFilter.toLowerCase()).toList();
          }

          // Apply location filters for counts
          if (selectedDepartment != null) jobs = jobs.where((j) => j.department == selectedDepartment).toList();
          if (selectedArea != null) jobs = jobs.where((j) => j.area == selectedArea).toList();
          if (selectedMachine != null) jobs = jobs.where((j) => j.machine == selectedMachine).toList();
          if (selectedPart != null) jobs = jobs.where((j) => j.part == selectedPart).toList();

          // Compute counts
          final openCount = jobs.where((j) => j.status.name == 'open').length;
          final monitorCount = jobs.where((j) => j.status.name == 'monitor').length;
          final closedCount = jobs.where((j) => j.status.name == 'closed' || j.status.name == 'cancelled').length;

          return _isWide ? _buildWideLayout(openCount, monitorCount, closedCount) : _buildNarrowLayout(openCount, monitorCount, closedCount);
        },
      ),
    );
  }

  Widget _buildNarrowLayout(int openCount, int monitorCount, int closedCount) {
    return Column(
      children: [
        // Status Tabs
        Container(
          color: Colors.black,
          child: TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: 'Open ($openCount)'),
              Tab(text: 'Monitor ($monitorCount)'),
              Tab(text: 'Closed ($closedCount)'),
            ],
            labelColor: const Color(0xFFFF8C42),
            unselectedLabelColor: Colors.white70,
            indicatorColor: const Color(0xFFFF8C42),
          ),
        ),

        // Cascading Filters
        _buildCascadingFilters(),

        // Main Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildJobListForStatus('open'),
              _buildJobListForStatus('monitor'),
              _buildJobListForStatus('closed'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWideLayout(int openCount, int monitorCount, int closedCount) {
    return Column(
      children: [
        // Status Tabs
        Container(
          color: Colors.black,
          child: TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: 'Open ($openCount)'),
              Tab(text: 'Monitor ($monitorCount)'),
              Tab(text: 'Closed ($closedCount)'),
            ],
            labelColor: const Color(0xFFFF8C42),
            unselectedLabelColor: Colors.white70,
            indicatorColor: const Color(0xFFFF8C42),
          ),
        ),

        // Cascading Filters
        _buildCascadingFilters(),

        // Job List
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildJobListForStatus('open'),
              _buildJobListForStatus('monitor'),
              _buildJobListForStatus('closed'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildJobListForStatus(String status) {
    return StreamBuilder<List<JobCard>>(
      stream: _firestoreService.getAllJobCards(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var jobs = snapshot.data!;

        // Apply staff filter
        if (selectedStaffFilter != 'All') {
          jobs = jobs.where((j) => j.type.name == selectedStaffFilter.toLowerCase()).toList();
        }

        // Apply location filters
        if (selectedDepartment != null) jobs = jobs.where((j) => j.department == selectedDepartment).toList();
        if (selectedArea != null) jobs = jobs.where((j) => j.area == selectedArea).toList();
        if (selectedMachine != null) jobs = jobs.where((j) => j.machine == selectedMachine).toList();
        if (selectedPart != null) jobs = jobs.where((j) => j.part == selectedPart).toList();

        // Filter by status
        final filteredJobs = status == 'open'
            ? jobs.where((j) => j.status.name == 'open').toList()
            : status == 'monitor'
                ? jobs.where((j) => j.status.name == 'monitor').toList()
                : status == 'closed'
                    ? jobs.where((j) => j.status.name == 'closed' || j.status.name == 'cancelled').toList()
                    : jobs.where((j) => j.status.name == status).toList();

        return _buildJobList(filteredJobs, '');
      },
    );
  }

  Widget _buildJobList(List<JobCard> jobs, String title) {
    return Column(
      children: [
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        Expanded(
          child: jobs.isEmpty
              ? const Center(child: Text('No jobs available', style: TextStyle(color: Colors.white70)))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: jobs.length,
                  itemBuilder: (context, index) => _buildJobCardWidget(jobs[index]),
                ),
        ),
      ],
    );
  }
}
