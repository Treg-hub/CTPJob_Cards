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

  bool _filtersExpanded = false;

  late TabController _tabController;

  bool get isManager => (currentEmployee?.position ?? '').toLowerCase().contains('manager');
  bool get isSuperManager => currentEmployee?.department.toLowerCase() == 'general';

  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {
        selectedStatus = ['open', 'completed'][_tabController.index];
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
      case 'monitoring': return Colors.orange;
      case 'completed': return Colors.green;
      case 'closed': return Colors.grey;
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

  // ==================== ACTIVE FILTER CHIPS ====================
  Widget _buildActiveFilterChips() {
    final activeFilters = <Widget>[];

    if (selectedStaffFilter != (_employeeStaffDefault ?? 'All')) {
      activeFilters.add(
        Chip(
          label: Text(selectedStaffFilter),
          deleteIcon: const Icon(Icons.close, size: 16),
          onDeleted: () => setState(() => selectedStaffFilter = _employeeStaffDefault ?? 'All'),
          backgroundColor: Colors.orange.withValues(alpha: 51),
          labelStyle: const TextStyle(color: Colors.orange),
        ),
      );
    }

    if (selectedDepartment != null) {
      activeFilters.add(
        Chip(
          label: Text(selectedDepartment!),
          deleteIcon: const Icon(Icons.close, size: 16),
          onDeleted: () => setState(() {
            selectedDepartment = null;
            selectedArea = null;
            selectedMachine = null;
            selectedPart = null;
          }),
          backgroundColor: Colors.blue.withValues(alpha: 51),
          labelStyle: const TextStyle(color: Colors.blue),
        ),
      );
    }

    if (selectedArea != null) {
      activeFilters.add(
        Chip(
          label: Text(selectedArea!),
          deleteIcon: const Icon(Icons.close, size: 16),
          onDeleted: () => setState(() {
            selectedArea = null;
            selectedMachine = null;
            selectedPart = null;
          }),
          backgroundColor: Colors.green.withValues(alpha: 51),
          labelStyle: const TextStyle(color: Colors.green),
        ),
      );
    }

    if (selectedMachine != null) {
      activeFilters.add(
        Chip(
          label: Text(selectedMachine!),
          deleteIcon: const Icon(Icons.close, size: 16),
          onDeleted: () => setState(() {
            selectedMachine = null;
            selectedPart = null;
          }),
          backgroundColor: Colors.purple.withValues(alpha: 51),
          labelStyle: const TextStyle(color: Colors.purple),
        ),
      );
    }

    if (selectedPart != null) {
      activeFilters.add(
        Chip(
          label: Text(selectedPart!),
          deleteIcon: const Icon(Icons.close, size: 16),
          onDeleted: () => setState(() => selectedPart = null),
          backgroundColor: Colors.teal.withValues(alpha: 51),
          labelStyle: const TextStyle(color: Colors.teal),
        ),
      );
    }

    if (activeFilters.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Text('Active Filters:', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(width: 8),
            ...activeFilters.map((chip) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: chip,
            )),
          ],
        ),
      ),
    );
  }

  // ==================== ADVANCED FILTERS ====================
  Widget _buildAdvancedFilters() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _filtersExpanded ? null : 0,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Staff Type Filter
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'Electrical', label: Text('Electrical')),
                    ButtonSegment(value: 'Mechanical', label: Text('Mechanical')),
                    ButtonSegment(value: 'All', label: Text('All')),
                  ],
                  selected: {selectedStaffFilter},
                  onSelectionChanged: (Set<String> selected) {
                    if (selected.isNotEmpty) {
                      setState(() => selectedStaffFilter = selected.first);
                    }
                  },
                ),
              ),

              // Department Chips
              StreamBuilder<List<JobCard>>(
                stream: _firestoreService.getAllJobCards(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox();
                  final jobs = snapshot.data!;

                  final depts = jobs
                      .map((j) => j.department)
                      .where((d) => d.isNotEmpty)
                      .toSet()
                      .toList()
                    ..sort();

                  return Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('All Departments'),
                        selected: selectedDepartment == null,
                        onSelected: (_) {
                          setState(() {
                            selectedDepartment = null;
                            selectedArea = null;
                            selectedMachine = null;
                            selectedPart = null;
                          });
                        },
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                      ...depts.map((dept) => ChoiceChip(
                        label: Text(dept),
                        selected: selectedDepartment == dept,
                        onSelected: (_) {
                          setState(() {
                            selectedDepartment = dept;
                            selectedArea = null;
                            selectedMachine = null;
                            selectedPart = null;
                          });
                        },
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      )),
                    ],
                  );
                },
              ),

              // Area Chips (conditional)
              if (selectedDepartment != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: StreamBuilder<List<JobCard>>(
                    stream: _firestoreService.getAllJobCards(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox();
                      final jobs = snapshot.data!.where((j) => j.department == selectedDepartment).toList();
                      final areaList = jobs
                          .map((j) => j.area)
                          .where((a) => a.isNotEmpty)
                          .toSet()
                          .toList()
                        ..sort();

                      return Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: areaList.map((area) => ChoiceChip(
                          label: Text(area),
                          selected: selectedArea == area,
                          onSelected: (_) {
                            setState(() {
                              selectedArea = area;
                              selectedMachine = null;
                              selectedPart = null;
                            });
                          },
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        )).toList(),
                      );
                    },
                  ),
                ),

              // Machine Chips (conditional)
              if (selectedArea != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: StreamBuilder<List<JobCard>>(
                    stream: _firestoreService.getAllJobCards(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox();
                      final jobs = snapshot.data!
                          .where((j) => j.department == selectedDepartment && j.area == selectedArea)
                          .toList();
                      final machineList = jobs
                          .map((j) => j.machine)
                          .where((m) => m.isNotEmpty)
                          .toSet()
                          .toList()
                        ..sort();

                      return Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: machineList.map((machine) => ChoiceChip(
                          label: Text(machine),
                          selected: selectedMachine == machine,
                          onSelected: (_) {
                            setState(() {
                              selectedMachine = machine;
                              selectedPart = null;
                            });
                          },
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        )).toList(),
                      );
                    },
                  ),
                ),

              // Part Chips (conditional)
              if (selectedMachine != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: StreamBuilder<List<JobCard>>(
                    stream: _firestoreService.getAllJobCards(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox();
                      final jobs = snapshot.data!
                          .where((j) => j.department == selectedDepartment &&
                                       j.area == selectedArea &&
                                       j.machine == selectedMachine)
                          .toList();
                      final partList = jobs
                          .map((j) => j.part)
                          .where((p) => p.isNotEmpty)
                          .toSet()
                          .toList()
                        ..sort();

                      return Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: partList.map((part) => ChoiceChip(
                          label: Text(part),
                          selected: selectedPart == part,
                          onSelected: (_) => setState(() => selectedPart = part),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        )).toList(),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
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
                  if (job.jobCardNumber != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                               color: Colors.blue.withValues(alpha: 204),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'JC #${job.jobCardNumber}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
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
                      style: TextStyle(
                        color: _getStatusColor(job.status.name),
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
                  Text(
                    job.assignedNames?.join(', ') ?? 'Unassigned',
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5),
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
        actions: [
          if (selectedDepartment != null || selectedArea != null || selectedMachine != null || selectedPart != null || selectedStaffFilter != (_employeeStaffDefault ?? 'All'))
            TextButton.icon(
              icon: const Icon(Icons.clear),
              label: const Text('Clear Filters'),
              onPressed: () {
                setState(() {
                  selectedStaffFilter = _employeeStaffDefault ?? 'All';
                  if (_employeeStaffDefault == null) {
                    selectedDepartment = currentEmployee?.department;
                  } else {
                    selectedDepartment = null;
                  }
                  if (isSuperManager) {
                    selectedDepartment = null;
                  }
                  selectedArea = null;
                  selectedMachine = null;
                  selectedPart = null;
                });
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Status Tabs
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Open'),
              Tab(text: 'Completed'),
            ],
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: const Color(0xFFFF8C42),
          ),

          // Active Filter Chips
          _buildActiveFilterChips(),

          // Advanced Filters Toggle
          InkWell(
            onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Advanced Filters',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  Icon(
                    _filtersExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white70,
                  ),
                ],
              ),
            ),
          ),

          // Advanced Filters (Collapsible)
          _buildAdvancedFilters(),

          // Main Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildJobListForStatus('open'),
                _buildJobListForStatus('completed'),
              ],
            ),
          ),
        ],
      ),
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
            ? jobs.where((j) => j.status.name == 'open' || j.status.name == 'monitoring').toList()
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
