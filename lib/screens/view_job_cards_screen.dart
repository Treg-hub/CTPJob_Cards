import 'package:flutter/material.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import '../main.dart' show currentEmployee;
import 'job_card_detail_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/job_card_tile.dart';

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
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {
        selectedStatus = ['open', 'inProgress', 'monitor', 'closed'][_tabController.index];
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

  /// Mech/Elec combined jobs must appear under BOTH trade filters — the old
  /// exact-name match hid them from the default view of exactly the
  /// technicians who have to respond to them.
  bool _matchesStaffFilter(JobCard j) {
    switch (selectedStaffFilter) {
      case 'Mechanical':
        return j.type == JobType.mechanical ||
            j.type == JobType.mechanicalElectrical;
      case 'Electrical':
        return j.type == JobType.electrical ||
            j.type == JobType.mechanicalElectrical;
      default:
        return true;
    }
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
                return Text('No previous parts found', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));
              }
              return Center(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: previousParts.map((part) => ActionChip(
                    label: Text(part),
                    onPressed: () => setState(() => selectedPart = part),
                    backgroundColor: selectedPart == part ? const Color(0xFFFF8C42).withValues(alpha: 51) : null,
                    labelStyle: TextStyle(color: selectedPart == part ? const Color(0xFFFF8C42) : Theme.of(context).appColors.chipUnselectedLabel),
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
                labelStyle: selectedMachine == machine ? const TextStyle(color: Color(0xFFFF8C42)) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
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
                labelStyle: selectedArea == area ? const TextStyle(color: Color(0xFFFF8C42)) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
              )).toList(),
            ),
          );
        } else {
          // Show dept chips (no "All Departments" chip — use Clear All Filters to deselect)
          currentStep = Center(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: data.keys.map((dept) => ChoiceChip(
                label: Text(dept),
                selected: selectedDepartment == dept,
                onSelected: (_) => setState(() {
                  selectedDepartment = dept;
                  selectedArea = null;
                  selectedMachine = null;
                  selectedPart = null;
                }),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                labelStyle: selectedDepartment == dept ? const TextStyle(color: Color(0xFFFF8C42)) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
              )).toList(),
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
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Job Cards'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFFFF8C42),
                (currentEmployee?.isOnSite ?? true) ? Colors.green : Colors.red,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
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
            borderColor: Colors.black,
            selectedBorderColor: Colors.black,
            selectedColor: const Color(0xFFFF8C42),
            fillColor: const Color(0xFFFF8C42).withValues(alpha: 51),
            children: const [
              Icon(Icons.build, size: 24, color: Colors.black),
              Icon(Icons.bolt, size: 24, color: Colors.black),
              Icon(Icons.circle_outlined, size: 24, color: Colors.black),
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
            jobs = jobs.where(_matchesStaffFilter).toList();
          }

          // Apply location filters for counts
          if (selectedDepartment != null) jobs = jobs.where((j) => j.department == selectedDepartment).toList();
          if (selectedArea != null) jobs = jobs.where((j) => j.area == selectedArea).toList();
          if (selectedMachine != null) jobs = jobs.where((j) => j.machine == selectedMachine).toList();
          if (selectedPart != null) jobs = jobs.where((j) => j.part == selectedPart).toList();

          // Compute counts
          final openCount = jobs.where((j) => j.status.name == 'open').length;
          final inProgressCount = jobs.where((j) => j.status.name == 'inProgress').length;
          final monitorCount = jobs.where((j) => j.status.name == 'monitor').length;
          final closedCount = jobs.where((j) => j.status.name == 'closed' || j.status.name == 'cancelled').length;

          return _isWide
              ? _buildWideLayout(openCount, inProgressCount, monitorCount, closedCount)
              : _buildNarrowLayout(openCount, inProgressCount, monitorCount, closedCount);
        },
      ),
    );
  }

  Widget _buildNarrowLayout(int openCount, int inProgressCount, int monitorCount, int closedCount) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'Open ($openCount)'),
            Tab(text: 'In Progress ($inProgressCount)'),
            Tab(text: 'Monitoring ($monitorCount)'),
            Tab(text: 'Closed ($closedCount)'),
          ],
        ),

        // Cascading Filters
        _buildCascadingFilters(),

        // Main Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildJobListForStatus('open'),
              _buildJobListForStatus('inProgress'),
              _buildJobListForStatus('monitor'),
              _buildJobListForStatus('closed'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWideLayout(int openCount, int inProgressCount, int monitorCount, int closedCount) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Open ($openCount)'),
            Tab(text: 'In Progress ($inProgressCount)'),
            Tab(text: 'Monitoring ($monitorCount)'),
            Tab(text: 'Closed ($closedCount)'),
          ],
        ),

        // Cascading Filters
        _buildCascadingFilters(),

        // Job List
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildJobListForStatus('open'),
              _buildJobListForStatus('inProgress'),
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
          jobs = jobs.where(_matchesStaffFilter).toList();
        }

        // Apply location filters
        if (selectedDepartment != null) jobs = jobs.where((j) => j.department == selectedDepartment).toList();
        if (selectedArea != null) jobs = jobs.where((j) => j.area == selectedArea).toList();
        if (selectedMachine != null) jobs = jobs.where((j) => j.machine == selectedMachine).toList();
        if (selectedPart != null) jobs = jobs.where((j) => j.part == selectedPart).toList();

        // Filter by status
        final filteredJobs = status == 'closed'
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
            child: Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
          ),
        Expanded(
          child: jobs.isEmpty
              ? Center(child: Text('No jobs available', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: jobs.length,
                  itemBuilder: (context, index) => JobCardTile(
                    job: jobs[index],
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobCardDetailScreen(jobCard: jobs[index]))),
                  ),
                ),
        ),
      ],
    );
  }
}
