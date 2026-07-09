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

  static const int _pageSize = 100;

  final FirestoreService _firestoreService = FirestoreService();

  /// Bumps when filters change so each tab list rebuilds with new filter.
  int _filterEpoch = 0;

  static const _tabStatuses = [
    JobStatus.open,
    JobStatus.inProgress,
    JobStatus.monitor,
    JobStatus.closed,
  ];

  static const _tabLabels = [
    'Open',
    'In Progress',
    'Monitoring',
    'Closed',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

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

  void _bumpFilters() => setState(() => _filterEpoch++);

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
                  alignment: WrapAlignment.center,
                  children: previousParts
                      .map((part) => ActionChip(
                            label: Text(part),
                            onPressed: () {
                              setState(() => selectedPart = part);
                              _bumpFilters();
                            },
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
              alignment: WrapAlignment.center,
              children: machines
                  .map((machine) => ChoiceChip(
                        label: Text(machine),
                        selected: selectedMachine == machine,
                        onSelected: (_) {
                          setState(() {
                            selectedMachine = machine;
                            selectedPart = null;
                          });
                          _bumpFilters();
                        },
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
              alignment: WrapAlignment.center,
              children: areas
                  .map((area) => ChoiceChip(
                        label: Text(area),
                        selected: selectedArea == area,
                        onSelected: (_) {
                          setState(() {
                            selectedArea = area;
                            selectedMachine = null;
                            selectedPart = null;
                          });
                          _bumpFilters();
                        },
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
              alignment: WrapAlignment.center,
              children: data.keys
                  .map((dept) => ChoiceChip(
                        label: Text(dept),
                        selected: selectedDepartment == dept,
                        onSelected: (_) {
                          setState(() {
                            selectedDepartment = dept;
                            selectedArea = null;
                            selectedMachine = null;
                            selectedPart = null;
                          });
                          _bumpFilters();
                        },
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        _bumpFilters();
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
              _bumpFilters();
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
          // Match My Work: full-width centred tabs + swipeable TabBarView.
          TabBar(
            controller: _tabController,
            isScrollable: false,
            tabs: [
              for (final label in _tabLabels) Tab(text: label),
            ],
          ),
          _buildCascadingFilters(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                for (var i = 0; i < _tabStatuses.length; i++)
                  _ViewJobsStatusList(
                    key: ValueKey(
                        '${_tabStatuses[i].name}_$_filterEpoch'),
                    status: _tabStatuses[i],
                    pageSize: _pageSize,
                    staffFilter: selectedStaffFilter,
                    department: selectedDepartment,
                    area: selectedArea,
                    machine: selectedMachine,
                    part: selectedPart,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One status tab — own bounded stream so inactive tabs can stay mounted after
/// first visit without forcing four listeners at open (stream starts on mount).
class _ViewJobsStatusList extends StatefulWidget {
  const _ViewJobsStatusList({
    super.key,
    required this.status,
    required this.pageSize,
    required this.staffFilter,
    this.department,
    this.area,
    this.machine,
    this.part,
  });

  final JobStatus status;
  final int pageSize;
  final String staffFilter;
  final String? department;
  final String? area;
  final String? machine;
  final String? part;

  @override
  State<_ViewJobsStatusList> createState() => _ViewJobsStatusListState();
}

class _ViewJobsStatusListState extends State<_ViewJobsStatusList>
    with AutomaticKeepAliveClientMixin {
  final FirestoreService _firestoreService = FirestoreService();
  late int _limit;
  Stream<JobCardListSnapshot>? _stream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _limit = widget.pageSize;
    _attachStream();
  }

  void _attachStream() {
    if (widget.status == JobStatus.closed) {
      _stream = _firestoreService.getClosedJobCardsWithMeta(limit: _limit);
    } else {
      _stream = _firestoreService.getJobCardsByStatusWithMeta(
        widget.status,
        limit: _limit,
      );
    }
  }

  Future<void> _pullRefresh() async {
    setState(() {
      _limit = widget.pageSize;
      _stream = null;
      _attachStream();
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  void _loadMore() {
    setState(() {
      _limit += widget.pageSize;
      _stream = null;
      _attachStream();
    });
  }

  bool _matchesStaffFilter(JobCard j) {
    switch (widget.staffFilter) {
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

  List<JobCard> _applyFilters(List<JobCard> jobs) {
    var result = jobs;
    if (widget.staffFilter != 'All') {
      result = result.where(_matchesStaffFilter).toList();
    }
    if (widget.department != null) {
      result =
          result.where((j) => j.department == widget.department).toList();
    }
    if (widget.area != null) {
      result = result.where((j) => j.area == widget.area).toList();
    }
    if (widget.machine != null) {
      result = result.where((j) => j.machine == widget.machine).toList();
    }
    if (widget.part != null) {
      result = result.where((j) => j.part == widget.part).toList();
    }
    return result
      ..sort((a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final stream = _stream;
    if (stream == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _pullRefresh,
      child: StreamBuilder<JobCardListSnapshot>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.3,
                  child: Center(
                    child: Text('Error: ${snap.error}',
                        style: const TextStyle(color: Colors.red)),
                  ),
                ),
              ],
            );
          }
          final meta = snap.data;
          switch (decideListLoadState(
            hasSnapshot: meta != null,
            isEmpty: meta?.cards.isEmpty ?? true,
            isFromCache: meta?.isFromCache ?? true,
          )) {
            case ListLoadState.loading:
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator())),
                ],
              );
            case ListLoadState.waitingForServer:
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: 200,
                    child: Center(
                      child: Text(
                        'Waiting for connection…',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            case ListLoadState.empty:
            case ListLoadState.data:
              break;
          }

          final jobs = _applyFilters(meta!.cards);
          final hitCap = jobs.length >= _limit;
          final countLabel = hitCap ? '$_limit+' : '${jobs.length}';

          if (jobs.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.35,
                  child: Center(
                    child: Text(
                      'No jobs available',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: ScreenInsets.listPadding(context, horizontal: 8, top: 8),
            itemCount: jobs.length + 1 + (hitCap ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '$countLabel job${jobs.length == 1 ? '' : 's'} (pull to refresh)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              if (hitCap && index == jobs.length + 1) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: TextButton.icon(
                      onPressed: _loadMore,
                      icon: const Icon(Icons.expand_more),
                      label: Text('Load more (${widget.pageSize} more)'),
                    ),
                  ),
                );
              }
              final job = jobs[index - 1];
              return JobCardTile(
                job: job,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => JobCardDetailScreen(jobCard: job),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
