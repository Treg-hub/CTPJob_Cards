import 'dart:async';

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

  /// When false, location chips are hidden and only the path strip shows.
  bool _filtersExpanded = true;

  late TabController _tabController;

  bool get isSuperManager =>
      currentEmployee?.department.toLowerCase() == 'general';

  static const int _pageSize = 100;

  final FirestoreService _firestoreService = FirestoreService();

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

  /// Per-status page size (Load more / pull-to-refresh).
  final Map<JobStatus, int> _limits = {
    for (final s in _tabStatuses) s: _pageSize,
  };

  final Map<JobStatus, List<JobCard>> _cardsByStatus = {
    for (final s in _tabStatuses) s: const <JobCard>[],
  };
  final Map<JobStatus, bool> _hasSnapshot = {
    for (final s in _tabStatuses) s: false,
  };
  final Map<JobStatus, bool> _fromCache = {
    for (final s in _tabStatuses) s: true,
  };
  final Map<JobStatus, Object?> _errors = {
    for (final s in _tabStatuses) s: null,
  };
  final Map<JobStatus, StreamSubscription<JobCardListSnapshot>?> _subs = {
    for (final s in _tabStatuses) s: null,
  };

  bool get _hasLocationFilter =>
      selectedDepartment != null ||
      selectedArea != null ||
      selectedMachine != null ||
      selectedPart != null;

  /// Breadcrumb path for the location strip (dept › area › machine › part).
  String get _locationPath {
    final parts = <String>[
      if (selectedDepartment != null) selectedDepartment!,
      if (selectedArea != null) selectedArea!,
      if (selectedMachine != null) selectedMachine!,
      if (selectedPart != null) selectedPart!,
    ];
    return parts.join(' › ');
  }

  /// All loaded jobs across status tabs (for chip relevance).
  Iterable<JobCard> get _allLoadedCards =>
      _tabStatuses.expand((s) => _cardsByStatus[s]!);

  /// Staff-scoped jobs used to build location chips (not location-filtered).
  List<JobCard> get _chipSourceCards {
    if (selectedStaffFilter == 'All') {
      return _allLoadedCards.toList();
    }
    return _allLoadedCards.where(_matchesStaffFilter).toList();
  }

  bool get _anySnapshot => _hasSnapshot.values.any((v) => v);

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
    // Deep-link from Create "View similar" (or any caller) wins over defaults.
    if (widget.filterDepartment != null) {
      selectedDepartment = widget.filterDepartment;
    }
    selectedArea = widget.filterArea;
    selectedMachine = widget.filterMachine;
    selectedPart = widget.filterPart;

    // Start collapsed when opened already at machine/part — list space first.
    if (selectedMachine != null || selectedPart != null) {
      _filtersExpanded = false;
    }

    // Own all four status streams so chips reflect every tab, not only the
    // currently mounted page (and without a second set of listeners).
    for (final status in _tabStatuses) {
      _subscribe(status);
    }
  }

  @override
  void dispose() {
    for (final sub in _subs.values) {
      sub?.cancel();
    }
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

  void _subscribe(JobStatus status) {
    _subs[status]?.cancel();
    final limit = _limits[status]!;
    final stream = status == JobStatus.closed
        ? _firestoreService.getClosedJobCardsWithMeta(limit: limit)
        : _firestoreService.getJobCardsByStatusWithMeta(status, limit: limit);

    _subs[status] = stream.listen(
      (snap) {
        if (!mounted) return;
        setState(() {
          _cardsByStatus[status] = snap.cards;
          _fromCache[status] = snap.isFromCache;
          _hasSnapshot[status] = true;
          _errors[status] = null;
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _errors[status] = e;
          _hasSnapshot[status] = true;
        });
      },
    );
  }

  void _loadMore(JobStatus status) {
    setState(() {
      _limits[status] = _limits[status]! + _pageSize;
    });
    _subscribe(status);
  }

  Future<void> _pullRefresh(JobStatus status) async {
    setState(() {
      _limits[status] = _pageSize;
      _hasSnapshot[status] = false;
      _errors[status] = null;
    });
    _subscribe(status);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  /// Clears dept/area/machine/part only — staff toggle stays in the app bar.
  void _clearLocationFilters() {
    setState(() {
      selectedDepartment = null;
      selectedArea = null;
      selectedMachine = null;
      selectedPart = null;
      _filtersExpanded = true;
    });
  }

  void _toggleFiltersExpanded() {
    setState(() => _filtersExpanded = !_filtersExpanded);
  }

  List<String> _departmentsFromJobs(List<JobCard> jobs) {
    final set = <String>{};
    for (final j in jobs) {
      final d = j.department.trim();
      if (d.isNotEmpty) set.add(d);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> _areasFromJobs(List<JobCard> jobs, String department) {
    final set = <String>{};
    for (final j in jobs) {
      if (j.department != department) continue;
      final a = j.area.trim();
      if (a.isNotEmpty) set.add(a);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> _machinesFromJobs(
    List<JobCard> jobs,
    String department,
    String area,
  ) {
    final set = <String>{};
    for (final j in jobs) {
      if (j.department != department || j.area != area) continue;
      final m = j.machine.trim();
      if (m.isNotEmpty) set.add(m);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> _partsFromJobs(
    List<JobCard> jobs,
    String department,
    String area,
    String machine,
  ) {
    final set = <String>{};
    for (final j in jobs) {
      if (j.department != department ||
          j.area != area ||
          j.machine != machine) {
        continue;
      }
      final p = j.part.trim();
      if (p.isNotEmpty) set.add(p);
    }
    final list = set.toList()..sort();
    return list;
  }

  Widget _buildLocationPathStrip() {
    final colors = Theme.of(context).colorScheme;
    final path = _locationPath;
    final expandHint =
        _filtersExpanded ? 'Collapse filter chips' : 'Expand filter chips';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _toggleFiltersExpanded,
                borderRadius: BorderRadius.circular(8),
                child: Semantics(
                  button: true,
                  label: 'Filters: $path. $expandHint',
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        Icon(
                          _filtersExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 22,
                          color: colors.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Clear location filters',
            visualDensity: VisualDensity.compact,
            onPressed: _clearLocationFilters,
          ),
        ],
      ),
    );
  }

  Widget _chipWrap(List<Widget> children) {
    if (children.isEmpty) {
      return Text(
        _anySnapshot
            ? 'No matching locations in loaded job cards'
            : 'Loading filters…',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Center(
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: children,
      ),
    );
  }

  Widget _buildCascadingFilters() {
    final source = _chipSourceCards;
    final departments = _departmentsFromJobs(source);
    final areas = selectedDepartment != null
        ? _areasFromJobs(source, selectedDepartment!)
        : <String>[];
    final machines =
        selectedDepartment != null && selectedArea != null
            ? _machinesFromJobs(source, selectedDepartment!, selectedArea!)
            : <String>[];
    final parts = selectedDepartment != null &&
            selectedArea != null &&
            selectedMachine != null
        ? _partsFromJobs(
            source,
            selectedDepartment!,
            selectedArea!,
            selectedMachine!,
          )
        : <String>[];

    final Widget currentStep;
    if (selectedMachine != null) {
      if (parts.isEmpty && _anySnapshot) {
        currentStep = Text(
          'No parts on loaded jobs for this machine',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
      } else {
        currentStep = _chipWrap(
          parts
              .map(
                (part) => ActionChip(
                  label: Text(part),
                  onPressed: () {
                    setState(() {
                      selectedPart = part;
                      _filtersExpanded = false;
                    });
                  },
                  backgroundColor: selectedPart == part
                      ? kBrandOrange.withValues(alpha: 51)
                      : null,
                  labelStyle: TextStyle(
                    color: selectedPart == part
                        ? kBrandOrange
                        : Theme.of(context).appColors.chipUnselectedLabel,
                  ),
                ),
              )
              .toList(),
        );
      }
    } else if (selectedArea != null) {
      currentStep = _chipWrap(
        machines
            .map(
              (machine) => ChoiceChip(
                label: Text(machine),
                selected: selectedMachine == machine,
                onSelected: (_) {
                  setState(() {
                    selectedMachine = machine;
                    selectedPart = null;
                    _filtersExpanded = false;
                  });
                },
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                labelStyle: selectedMachine == machine
                    ? const TextStyle(color: Color(0xFFFF8C42))
                    : TextStyle(
                        color: Theme.of(context).appColors.chipUnselectedLabel,
                      ),
              ),
            )
            .toList(),
      );
    } else if (selectedDepartment != null) {
      currentStep = _chipWrap(
        areas
            .map(
              (area) => ChoiceChip(
                label: Text(area),
                selected: selectedArea == area,
                onSelected: (_) {
                  setState(() {
                    selectedArea = area;
                    selectedMachine = null;
                    selectedPart = null;
                  });
                },
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                labelStyle: selectedArea == area
                    ? const TextStyle(color: Color(0xFFFF8C42))
                    : TextStyle(
                        color: Theme.of(context).appColors.chipUnselectedLabel,
                      ),
              ),
            )
            .toList(),
      );
    } else {
      currentStep = _chipWrap(
        departments
            .map(
              (dept) => ChoiceChip(
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                labelStyle: selectedDepartment == dept
                    ? const TextStyle(color: Color(0xFFFF8C42))
                    : TextStyle(
                        color: Theme.of(context).appColors.chipUnselectedLabel,
                      ),
              ),
            )
            .toList(),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hasLocationFilter) _buildLocationPathStrip(),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _filtersExpanded
                ? Padding(
                    padding: EdgeInsets.only(
                      top: _hasLocationFilter ? 2 : 4,
                      bottom: 4,
                    ),
                    child: currentStep,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
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
                for (final status in _tabStatuses)
                  _ViewJobsStatusList(
                    status: status,
                    pageSize: _pageSize,
                    limit: _limits[status]!,
                    cards: _cardsByStatus[status]!,
                    hasSnapshot: _hasSnapshot[status]!,
                    isFromCache: _fromCache[status]!,
                    error: _errors[status],
                    staffFilter: selectedStaffFilter,
                    department: selectedDepartment,
                    area: selectedArea,
                    machine: selectedMachine,
                    part: selectedPart,
                    onLoadMore: () => _loadMore(status),
                    onRefresh: () => _pullRefresh(status),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One status tab — presents parent-owned data (no extra Firestore listener).
class _ViewJobsStatusList extends StatefulWidget {
  const _ViewJobsStatusList({
    required this.status,
    required this.pageSize,
    required this.limit,
    required this.cards,
    required this.hasSnapshot,
    required this.isFromCache,
    required this.error,
    required this.staffFilter,
    this.department,
    this.area,
    this.machine,
    this.part,
    required this.onLoadMore,
    required this.onRefresh,
  });

  final JobStatus status;
  final int pageSize;
  final int limit;
  final List<JobCard> cards;
  final bool hasSnapshot;
  final bool isFromCache;
  final Object? error;
  final String staffFilter;
  final String? department;
  final String? area;
  final String? machine;
  final String? part;
  final VoidCallback onLoadMore;
  final Future<void> Function() onRefresh;

  @override
  State<_ViewJobsStatusList> createState() => _ViewJobsStatusListState();
}

class _ViewJobsStatusListState extends State<_ViewJobsStatusList>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

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

    if (widget.error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.3,
            child: Center(
              child: Text(
                'Error: ${widget.error}',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        ],
      );
    }

    switch (decideListLoadState(
      hasSnapshot: widget.hasSnapshot,
      isEmpty: widget.cards.isEmpty,
      isFromCache: widget.isFromCache,
    )) {
      case ListLoadState.loading:
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            ),
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

    final jobs = _applyFilters(widget.cards);
    final hitCap = widget.cards.length >= widget.limit;
    final countLabel = hitCap ? '${widget.limit}+' : '${jobs.length}';

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: jobs.isEmpty
          ? ListView(
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
                // Unfiltered page may still be capped — more matching jobs can appear.
                if (hitCap)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: TextButton.icon(
                        onPressed: widget.onLoadMore,
                        icon: const Icon(Icons.expand_more),
                        label: Text('Load more (${widget.pageSize} more)'),
                      ),
                    ),
                  ),
              ],
            )
          : ListView.builder(
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
                        onPressed: widget.onLoadMore,
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
            ),
    );
  }
}
