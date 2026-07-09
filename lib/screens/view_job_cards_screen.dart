import 'package:flutter/material.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import '../main.dart' show currentEmployee, realEmployee;
import 'job_card_detail_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/ctp_app_bar.dart';
import '../widgets/job_card_tile.dart';
import '../utils/screen_insets.dart';
import '../utils/list_load_state.dart';

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

class _ViewJobCardsScreenState extends State<ViewJobCardsScreen>
    with SingleTickerProviderStateMixin {
  String? selectedDepartment;
  String? selectedArea;
  String? selectedMachine;
  String? selectedPart;

  String selectedStaffFilter = 'All';

  late TabController _tabController;

  bool get isSuperManager =>
      currentEmployee?.department.toLowerCase() == 'general';
  bool get _isWide => MediaQuery.of(context).size.width >= 1000;

  static const int _statusLimit = 300;
  static const int _closedLimit = 200;

  final FirestoreService _firestoreService = FirestoreService();

  /// Only the selected tab is live — other tabs are not subscribed until visited.
  late JobStatus _activeStatus;
  Stream<JobCardListSnapshot>? _activeTabStream;
  JobStatus? _streamedStatus;

  static const _tabStatuses = [
    JobStatus.open,
    JobStatus.inProgress,
    JobStatus.monitor,
    JobStatus.closed,
  ];

  @override
  void initState() {
    super.initState();
    _activeStatus = JobStatus.open;
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      final next = _tabStatuses[_tabController.index];
      if (next == _activeStatus) return;
      setState(() {
        _activeStatus = next;
        _ensureStreamForActiveTab();
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

    _ensureStreamForActiveTab();
  }

  void _ensureStreamForActiveTab() {
    if (_streamedStatus == _activeStatus && _activeTabStream != null) return;
    _streamedStatus = _activeStatus;
    if (_activeStatus == JobStatus.closed) {
      _activeTabStream =
          _firestoreService.getClosedJobCardsWithMeta(limit: _closedLimit);
    } else {
      _activeTabStream = _firestoreService.getJobCardsByStatusWithMeta(
        _activeStatus,
        limit: _statusLimit,
      );
    }
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

  Widget _buildCascadingFilters() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _firestoreService.getFactoryStructure(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Error loading filters: ${snapshot.error}',
                style: const TextStyle(color: Colors.red)),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          );
        }

        final data = snapshot.data!;
        final areas = selectedDepartment != null
            ? (data[selectedDepartment] as Map<String, dynamic>? ?? {})
                .keys
                .toList()
            : <String>[];
        final machines = selectedArea != null && selectedDepartment != null
            ? (data[selectedDepartment]?[selectedArea] as List<dynamic>? ?? [])
                .cast<String>()
            : <String>[];

        Widget currentStep;

        if (selectedPart != null) {
          currentStep = const SizedBox.shrink();
        } else if (selectedMachine != null) {
          currentStep = FutureBuilder<List<String>>(
            future: _firestoreService.getPreviousParts(
                selectedDepartment!, selectedArea!, selectedMachine!),
            builder: (context, snapshot) {
              final previousParts = snapshot.data ?? [];
              if (previousParts.isEmpty) {
                return Text('No previous parts found',
                    style: TextStyle(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant));
              }
              return Center(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: previousParts
                      .map((part) => ActionChip(
                            label: Text(part),
                            onPressed: () =>
                                setState(() => selectedPart = part),
                            backgroundColor: selectedPart == part
                                ? kBrandOrange.withValues(alpha: 51)
                                : null,
                            labelStyle: TextStyle(
                                color: selectedPart == part
                                    ? kBrandOrange
                                    : Theme.of(context)
                                        .appColors
                                        .chipUnselectedLabel),
                          ))
                      .toList(),
                ),
              );
            },
          );
        } else if (selectedArea != null) {
          currentStep = Center(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: machines
                  .map((machine) => ChoiceChip(
                        label: Text(machine),
                        selected: selectedMachine == machine,
                        onSelected: (_) => setState(() {
                          selectedMachine = machine;
                          selectedPart = null;
                        }),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        labelStyle: selectedMachine == machine
                            ? const TextStyle(color: Color(0xFFFF8C42))
                            : TextStyle(
                                color: Theme.of(context)
                                    .appColors
                                    .chipUnselectedLabel),
                      ))
                  .toList(),
            ),
          );
        } else if (selectedDepartment != null) {
          currentStep = Center(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: areas
                  .map((area) => ChoiceChip(
                        label: Text(area),
                        selected: selectedArea == area,
                        onSelected: (_) => setState(() {
                          selectedArea = area;
                          selectedMachine = null;
                          selectedPart = null;
                        }),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        labelStyle: selectedArea == area
                            ? const TextStyle(color: Color(0xFFFF8C42))
                            : TextStyle(
                                color: Theme.of(context)
                                    .appColors
                                    .chipUnselectedLabel),
                      ))
                  .toList(),
            ),
          );
        } else {
          currentStep = Center(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: data.keys
                  .map((dept) => ChoiceChip(
                        label: Text(dept),
                        selected: selectedDepartment == dept,
                        onSelected: (_) => setState(() {
                          selectedDepartment = dept;
                          selectedArea = null;
                          selectedMachine = null;
                          selectedPart = null;
                        }),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        labelStyle: selectedDepartment == dept
                            ? const TextStyle(color: Color(0xFFFF8C42))
                            : TextStyle(
                                color: Theme.of(context)
                                    .appColors
                                    .chipUnselectedLabel),
                      ))
                  .toList(),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectedDepartment != null ||
                  selectedArea != null ||
                  selectedMachine != null ||
                  selectedPart != null)
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
                      style: TextButton.styleFrom(foregroundColor: kBrandOrange),
                    ),
                  ),
                ),
              currentStep,
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final stream = _activeTabStream;
    return Scaffold(
      appBar: CtpAppBar(
        title: 'All Job Cards',
        isOnSite: realEmployee?.isOnSite ?? currentEmployee?.isOnSite,
        actions: [
          ToggleButtons(
            isSelected: [
              selectedStaffFilter == 'Mechanical',
              selectedStaffFilter == 'Electrical',
              selectedStaffFilter == 'All',
            ],
            onPressed: (index) {
              setState(() {
                selectedStaffFilter =
                    ['Mechanical', 'Electrical', 'All'][index];
              });
            },
            borderRadius: BorderRadius.circular(8),
            borderColor: Colors.black87,
            selectedBorderColor: Colors.black,
            selectedColor: kBrandOrange,
            fillColor: kBrandOrange.withValues(alpha: 0.35),
            constraints: const BoxConstraints(minHeight: 36, minWidth: 40),
            children: const [
              Icon(Icons.build, size: 22),
              Icon(Icons.bolt, size: 22),
              Icon(Icons.all_inclusive, size: 22),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: !_isWide,
            tabAlignment: _isWide ? null : TabAlignment.start,
            tabs: const [
              Tab(text: 'Open'),
              Tab(text: 'In Progress'),
              Tab(text: 'Monitoring'),
              Tab(text: 'Closed'),
            ],
          ),
          _buildCascadingFilters(),
          Expanded(
            child: stream == null
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<JobCardListSnapshot>(
                    key: ValueKey(_activeStatus),
                    stream: stream,
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Center(
                          child: Text('Error: ${snap.error}',
                              style: const TextStyle(color: Colors.red)),
                        );
                      }
                      final meta = snap.data;
                      switch (decideListLoadState(
                        hasSnapshot: meta != null,
                        isEmpty: meta?.cards.isEmpty ?? true,
                        isFromCache: meta?.isFromCache ?? true,
                      )) {
                        case ListLoadState.loading:
                          return const Center(
                              child: CircularProgressIndicator());
                        case ListLoadState.waitingForServer:
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 12),
                                Text(
                                  'Waiting for connection…',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          );
                        case ListLoadState.empty:
                        case ListLoadState.data:
                          break;
                      }

                      final jobs = _applyFilters(meta!.cards);
                      final countLabel = _activeStatus == JobStatus.closed &&
                              jobs.length >= _closedLimit
                          ? '$_closedLimit+'
                          : '${jobs.length}';
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '$countLabel job${jobs.length == 1 ? '' : 's'}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                          Expanded(child: _buildJobList(jobs)),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<JobCard> _applyFilters(List<JobCard> jobs) {
    var result = jobs;
    if (selectedStaffFilter != 'All') {
      result = result.where(_matchesStaffFilter).toList();
    }
    if (selectedDepartment != null) {
      result =
          result.where((j) => j.department == selectedDepartment).toList();
    }
    if (selectedArea != null) {
      result = result.where((j) => j.area == selectedArea).toList();
    }
    if (selectedMachine != null) {
      result = result.where((j) => j.machine == selectedMachine).toList();
    }
    if (selectedPart != null) {
      result = result.where((j) => j.part == selectedPart).toList();
    }
    return result
      ..sort((a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
  }

  Widget _buildJobList(List<JobCard> jobs) {
    return jobs.isEmpty
        ? Center(
            child: Text('No jobs available',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)))
        : ListView.builder(
            padding:
                ScreenInsets.listPadding(context, horizontal: 8, top: 8),
            itemCount: jobs.length,
            itemBuilder: (context, index) => JobCardTile(
              job: jobs[index],
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          JobCardDetailScreen(jobCard: jobs[index]))),
            ),
          );
  }
}
