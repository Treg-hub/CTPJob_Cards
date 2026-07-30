import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/screen_insets.dart';
import '../widgets/ctp_app_bar.dart';
import '../widgets/job_card_badges.dart';
import 'job_card_detail_screen.dart';

/// Historic job card search screen.
///
/// Server-side filters (department, area, machine, date range) narrow the
/// Firestore read to at most [_pageSize] documents per page.
/// Type, priority, and free-text search are applied client-side.
///
/// Layout: compact search + date + Filters sheet (not always-on chip rows).
/// Results use a dense history row (closedAt, no activity block).
///
/// Firestore indexes required:
///   job_cards: status ASC + closedAt DESC
///   job_cards: status ASC + department ASC + closedAt DESC
///   job_cards: status ASC + department ASC + area ASC + closedAt DESC
///   job_cards: status ASC + department ASC + area ASC + machine ASC + closedAt DESC
class JobCardHistoryScreen extends StatefulWidget {
  const JobCardHistoryScreen({super.key});

  @override
  State<JobCardHistoryScreen> createState() => _JobCardHistoryScreenState();
}

class _JobCardHistoryScreenState extends State<JobCardHistoryScreen> {
  static const int _pageSize = 50;
  static const double _loadMoreThreshold = 280;

  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // ── Server-side filter state ──────────────────────────────────────────────
  String? _selectedDepartment;
  String? _selectedArea;
  String? _selectedMachine;
  _DatePreset _datePreset = _DatePreset.last30Days;
  DateTime? _customFrom;
  DateTime? _customTo;
  bool _initialSearchDone = false;

  // ── Client-side filter state ──────────────────────────────────────────────
  JobType? _selectedType;
  int? _selectedPriority;
  String _searchQuery = '';

  // ── Result state ──────────────────────────────────────────────────────────
  List<JobCard> _results = [];
  bool _isLoading = false;
  bool _loadMoreInFlight = false;
  bool _hasMore = false;
  DocumentSnapshot? _lastDoc;
  String? _error;

  // ── Factory structure ─────────────────────────────────────────────────────
  Map<String, dynamic> _factoryStructure = {};
  List<String> _departments = [];
  List<String> _areas = [];
  List<String> _machines = [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFactoryStructure().then((_) {
      if (mounted && !_initialSearchDone) {
        _initialSearchDone = true;
        _search();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoading || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - _loadMoreThreshold) {
      _loadMore();
    }
  }

  Future<void> _loadFactoryStructure() async {
    try {
      final structure = await _firestoreService.getFactoryStructure();
      if (mounted) {
        setState(() {
          _factoryStructure = structure;
          _departments = structure.keys.toList()..sort();
        });
      }
    } catch (_) {}
  }

  (DateTime?, DateTime?) get _effectiveDateRange {
    switch (_datePreset) {
      case _DatePreset.last7Days:
        return (DateTime.now().subtract(const Duration(days: 7)), null);
      case _DatePreset.last30Days:
        return (DateTime.now().subtract(const Duration(days: 30)), null);
      case _DatePreset.last90Days:
        return (DateTime.now().subtract(const Duration(days: 90)), null);
      case _DatePreset.custom:
        return (_customFrom, _customTo);
      case _DatePreset.all:
        return (null, null);
    }
  }

  Future<void> _search({bool loadMore = false}) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
      if (!loadMore) {
        _results = [];
        _lastDoc = null;
        _hasMore = false;
      }
    });

    try {
      final (fromDate, toDate) = _effectiveDateRange;
      final fetched = await _firestoreService.searchClosedJobCards(
        department: _selectedDepartment,
        area: _selectedArea,
        machine: _selectedMachine,
        fromDate: fromDate,
        toDate: toDate,
        limit: _pageSize,
        startAfter: loadMore ? _lastDoc : null,
      );

      if (mounted) {
        setState(() {
          if (loadMore) {
            _results.addAll(fetched);
          } else {
            _results = fetched;
          }
          _hasMore = fetched.length == _pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_results.isEmpty ||
        _isLoading ||
        _loadMoreInFlight ||
        !_hasMore) {
      return;
    }
    final lastId = _results.last.id;
    if (lastId == null) return;
    _loadMoreInFlight = true;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('job_cards')
          .doc(lastId)
          .get();
      _lastDoc = doc;
      await _search(loadMore: true);
    } catch (_) {
      await _search(loadMore: true);
    } finally {
      _loadMoreInFlight = false;
    }
  }

  List<JobCard> get _filtered {
    var list = _results;
    if (_selectedType != null) {
      list = list.where((j) => j.type == _selectedType).toList();
    }
    if (_selectedPriority != null) {
      list = list.where((j) => j.priority == _selectedPriority).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((j) {
        return j.description.toLowerCase().contains(q) ||
            j.machine.toLowerCase().contains(q) ||
            j.part.toLowerCase().contains(q) ||
            j.notes.toLowerCase().contains(q) ||
            j.operator.toLowerCase().contains(q) ||
            j.correctiveAction.toLowerCase().contains(q) ||
            (j.jobCardNumber?.toString().contains(q) ?? false);
      }).toList();
    }
    return list;
  }

  void _onDepartmentSelected(String? dept) {
    final areas = dept != null
        ? ((_factoryStructure[dept] as Map<String, dynamic>?)?.keys.toList() ??
            [])
        : <String>[];
    areas.sort();
    setState(() {
      _selectedDepartment = dept;
      _selectedArea = null;
      _selectedMachine = null;
      _areas = areas;
      _machines = [];
    });
  }

  void _onAreaSelected(String? area) {
    final machines = (area != null && _selectedDepartment != null)
        ? ((_factoryStructure[_selectedDepartment]?[area] as List<dynamic>?)
                ?.cast<String>() ??
            <String>[])
        : <String>[];
    machines.sort();
    setState(() {
      _selectedArea = area;
      _selectedMachine = null;
      _machines = machines;
    });
  }

  int get _activeFilterCount {
    var n = 0;
    if (_selectedType != null) n++;
    if (_selectedPriority != null) n++;
    if (_selectedDepartment != null) n++;
    if (_selectedArea != null) n++;
    if (_selectedMachine != null) n++;
    return n;
  }

  bool get _hasActiveServerLocationFilters =>
      _selectedDepartment != null ||
      _selectedArea != null ||
      _selectedMachine != null;

  bool get _hasActiveClientFilters =>
      _selectedType != null ||
      _selectedPriority != null ||
      _searchQuery.isNotEmpty;

  bool get _hasAnyActiveFilters =>
      _hasActiveClientFilters ||
      _hasActiveServerLocationFilters ||
      _datePreset != _DatePreset.last30Days;

  String get _dateControlLabel {
    switch (_datePreset) {
      case _DatePreset.custom:
        if (_customFrom != null && _customTo != null) {
          return '${_fmtShort(_customFrom!)} – ${_fmtShort(_customTo!)}';
        }
        if (_customFrom != null) return 'From ${_fmtShort(_customFrom!)}';
        return 'Custom range';
      default:
        return _datePreset.shortLabel;
    }
  }

  static String _fmtShort(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  Future<void> _pickDatePreset() async {
    final chosen = await showModalBottomSheet<_DatePreset>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Date range',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              for (final p in _DatePreset.values)
                ListTile(
                  title: Text(p.label),
                  trailing: _datePreset == p
                      ? const Icon(Icons.check, color: kBrandOrange)
                      : null,
                  onTap: () => Navigator.pop(ctx, p),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (chosen == null || !mounted) return;

    if (chosen == _DatePreset.custom) {
      await _pickCustomRange();
      return;
    }

    setState(() {
      _datePreset = chosen;
      _customFrom = null;
      _customTo = null;
    });
    await _search();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initialStart =
        _customFrom ?? now.subtract(const Duration(days: 30));
    final initialEnd = _customTo ?? now;

    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      helpText: 'Closed between',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: kBrandOrange,
                  onPrimary: Colors.black,
                ),
          ),
          child: child!,
        );
      },
    );
    if (range == null || !mounted) return;

    // Inclusive end-of-day for closedAt upper bound.
    final endOfDay = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
      23,
      59,
      59,
    );

    setState(() {
      _datePreset = _DatePreset.custom;
      _customFrom = DateTime(range.start.year, range.start.month, range.start.day);
      _customTo = endOfDay;
    });
    await _search();
  }

  Future<void> _openFiltersSheet() async {
    JobType? draftType = _selectedType;
    int? draftPriority = _selectedPriority;
    String? draftDept = _selectedDepartment;
    String? draftArea = _selectedArea;
    String? draftMachine = _selectedMachine;
    var draftAreas = List<String>.from(_areas);
    var draftMachines = List<String>.from(_machines);

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            void onDept(String? dept) {
              final areas = dept != null
                  ? ((_factoryStructure[dept] as Map<String, dynamic>?)
                          ?.keys
                          .toList() ??
                      [])
                  : <String>[];
              areas.sort();
              setModal(() {
                draftDept = dept;
                draftArea = null;
                draftMachine = null;
                draftAreas = areas;
                draftMachines = [];
              });
            }

            void onArea(String? area) {
              final machines = (area != null && draftDept != null)
                  ? ((_factoryStructure[draftDept]?[area] as List<dynamic>?)
                          ?.cast<String>() ??
                      <String>[])
                  : <String>[];
              machines.sort();
              setModal(() {
                draftArea = area;
                draftMachine = null;
                draftMachines = machines;
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 4,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Filters',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setModal(() {
                              draftType = null;
                              draftPriority = null;
                              draftDept = null;
                              draftArea = null;
                              draftMachine = null;
                              draftAreas = [];
                              draftMachines = [];
                            });
                          },
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const _SectionLabel('Type'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _sheetChoiceChip(
                          label: 'All',
                          selected: draftType == null,
                          onSelected: () => setModal(() => draftType = null),
                        ),
                        ...JobType.values.map(
                          (t) => _sheetChoiceChip(
                            label: t.displayName,
                            selected: draftType == t,
                            onSelected: () => setModal(() => draftType = t),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const _SectionLabel('Priority'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _sheetChoiceChip(
                          label: 'All',
                          selected: draftPriority == null,
                          onSelected: () =>
                              setModal(() => draftPriority = null),
                        ),
                        ...List.generate(5, (i) {
                          final p = i + 1;
                          final color =
                              JobCardColorUtils.priorityColor(context, p);
                          return _sheetChoiceChip(
                            label: 'P$p',
                            selected: draftPriority == p,
                            selectedColor: color.withValues(alpha: 0.45),
                            onSelected: () =>
                                setModal(() => draftPriority = p),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const _SectionLabel('Department'),
                    const SizedBox(height: 6),
                    _buildDropdown<String>(
                      hint: 'All departments',
                      value: draftDept,
                      items: _departments,
                      onChanged: onDept,
                    ),
                    if (draftDept != null && draftAreas.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const _SectionLabel('Area'),
                      const SizedBox(height: 6),
                      _buildDropdown<String>(
                        hint: 'All areas',
                        value: draftArea,
                        items: draftAreas,
                        onChanged: onArea,
                      ),
                    ],
                    if (draftArea != null && draftMachines.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const _SectionLabel('Machine'),
                      const SizedBox(height: 6),
                      _buildDropdown<String>(
                        hint: 'All machines',
                        value: draftMachine,
                        items: draftMachines,
                        onChanged: (v) => setModal(() => draftMachine = v),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () {
                        // Push draft into parent state via closure, then pop.
                        _selectedType = draftType;
                        _selectedPriority = draftPriority;
                        _selectedDepartment = draftDept;
                        _selectedArea = draftArea;
                        _selectedMachine = draftMachine;
                        _areas = draftAreas;
                        _machines = draftMachines;
                        Navigator.pop(ctx, true);
                      },
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Apply filters'),
                      style: FilledButton.styleFrom(
                        backgroundColor: kBrandOrange,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (applied == true && mounted) {
      setState(() {}); // reflect type/priority/location from sheet
      await _search();
    }
  }

  Widget _sheetChoiceChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
    Color? selectedColor,
  }) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => onSelected(),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      selectedColor: selectedColor ?? kBrandOrange.withValues(alpha: 0.22),
      labelStyle: selected
          ? const TextStyle(color: kBrandOrange, fontWeight: FontWeight.w600)
          : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
    );
  }

  void _clearAllFilters() {
    _searchController.clear();
    setState(() {
      _selectedType = null;
      _selectedPriority = null;
      _searchQuery = '';
      _selectedDepartment = null;
      _selectedArea = null;
      _selectedMachine = null;
      _areas = [];
      _machines = [];
      _datePreset = _DatePreset.last30Days;
      _customFrom = null;
      _customTo = null;
    });
    _search();
  }

  void _clearClientFiltersOnly() {
    _searchController.clear();
    setState(() {
      _selectedType = null;
      _selectedPriority = null;
      _searchQuery = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CtpAppBar(title: 'Job Card History'),
      body: Column(
        children: [
          _buildCompactHeader(),
          if (_hasActiveFilterChips) _buildActiveFilterChips(),
          if (_results.isNotEmpty || _isLoading) _buildResultCount(),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              color: kBrandOrange,
              onRefresh: () => _search(),
              child: _buildResults(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Compact header: search + Filters + date ───────────────────────────────

  Widget _buildCompactHeader() {
    final cs = Theme.of(context).colorScheme;
    final filterCount = _activeFilterCount;

    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search description, machine, part, JC#…',
              hintStyle: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            ),
            style: const TextStyle(fontSize: 13),
            onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openFiltersSheet,
                  icon: Badge(
                    isLabelVisible: filterCount > 0,
                    label: Text(
                      '$filterCount',
                      style: const TextStyle(fontSize: 10),
                    ),
                    child: const Icon(Icons.tune, size: 18),
                  ),
                  label: const Text('Filters'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.onSurface,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDatePreset,
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(
                    _dateControlLabel,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _datePreset != _DatePreset.last30Days
                        ? kBrandOrange
                        : cs.onSurface,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool get _hasActiveFilterChips =>
      _selectedType != null ||
      _selectedPriority != null ||
      _hasActiveServerLocationFilters;

  Widget _buildActiveFilterChips() {
    return Container(
      width: double.infinity,
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          if (_selectedType != null)
            _activeFilterChip(_selectedType!.displayName, () {
              setState(() => _selectedType = null);
            }),
          if (_selectedPriority != null)
            _activeFilterChip('P$_selectedPriority', () {
              setState(() => _selectedPriority = null);
            }),
          if (_selectedDepartment != null)
            _activeFilterChip(_selectedDepartment!, () {
              _onDepartmentSelected(null);
              _search();
            }),
          if (_selectedArea != null)
            _activeFilterChip(_selectedArea!, () {
              _onAreaSelected(null);
              _search();
            }),
          if (_selectedMachine != null)
            _activeFilterChip(_selectedMachine!, () {
              setState(() => _selectedMachine = null);
              _search();
            }),
        ],
      ),
    );
  }

  Widget _activeFilterChip(String label, VoidCallback onClear) {
    return InputChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      deleteIcon: const Icon(Icons.close, size: 14),
      onDeleted: onClear,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      backgroundColor: kBrandOrange.withValues(alpha: 0.12),
      side: BorderSide(color: kBrandOrange.withValues(alpha: 0.45)),
    );
  }

  Widget _buildDropdown<T>({
    required String hint,
    required T? value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButton<T>(
        value: value,
        hint: Text(
          hint,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        isExpanded: true,
        underline: const SizedBox(),
        isDense: true,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        items: [
          DropdownMenuItem<T>(
            value: null,
            child: Text(hint, style: const TextStyle(fontSize: 13)),
          ),
          ...items.map(
            (i) => DropdownMenuItem<T>(
              value: i,
              child: Text(i.toString(), style: const TextStyle(fontSize: 13)),
            ),
          ),
        ],
        onChanged: onChanged,
      ),
    );
  }

  // ── Result count bar ──────────────────────────────────────────────────────

  Widget _buildResultCount() {
    final filtered = _filtered;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Text(
            '${filtered.length}'
            '${_results.length != filtered.length ? ' of ${_results.length}' : ''}'
            '${_hasMore ? '+' : ''} '
            'result${filtered.length == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (_hasAnyActiveFilters) ...[
            const Spacer(),
            TextButton(
              onPressed: _clearAllFilters,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Clear all', style: TextStyle(fontSize: 11)),
            ),
          ],
        ],
      ),
    );
  }

  // ── Results list ──────────────────────────────────────────────────────────

  Widget _buildResults() {
    if (_isLoading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _search,
                style: FilledButton.styleFrom(
                  backgroundColor: kBrandOrange,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.45,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.manage_search,
                      size: 72,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.35),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isLoading
                          ? 'Loading closed job cards…'
                          : 'No closed job cards match your filters.\n'
                              'Try a wider date range or clear filters.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (!_isLoading) ...[
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        onPressed: _openFiltersSheet,
                        icon: const Icon(Icons.tune, size: 16),
                        label: const Text('Adjust filters'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final jobs = _filtered;

    if (jobs.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.4,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.filter_list_off,
                      size: 48,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No results match the search / type / priority filters '
                      'on this page.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _clearClientFiltersOnly,
                      child: const Text('Clear search & type filters'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      controller: _scrollController,
      padding: ScreenInsets.listPadding(context, horizontal: 8, top: 4),
      itemCount: jobs.length + (_hasMore || _isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == jobs.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: _isLoading
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const SizedBox(height: 8),
            ),
          );
        }
        final job = jobs[index];
        return _HistoryJobRow(
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
  }
}

// ── Dense history result row ──────────────────────────────────────────────────

class _HistoryJobRow extends StatelessWidget {
  const _HistoryJobRow({required this.job, required this.onTap});

  final JobCard job;
  final VoidCallback onTap;

  static String _relativeClosed(DateTime? dt) {
    if (dt == null) return 'Closed —';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'Closed just now';
    if (diff.inMinutes < 60) return 'Closed ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Closed ${diff.inHours}h ago';
    if (diff.inDays < 7) return 'Closed ${diff.inDays}d ago';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return 'Closed $d/$m/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final priorityColor =
        JobCardColorUtils.priorityColor(context, job.priority);
    final path = [
      job.department,
      job.area,
      job.machine,
      if (job.part.trim().isNotEmpty) job.part,
    ].where((s) => s.trim().isNotEmpty).join(' > ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Theme.of(context).appColors.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: priorityColor.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: priorityColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (job.jobCardNumber != null) ...[
                              JobNumberBadge(number: job.jobCardNumber!),
                              const SizedBox(width: 6),
                            ],
                            PriorityBadge(priority: job.priority),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                job.type.displayName,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: muted,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _relativeClosed(job.closedAt),
                              style: const TextStyle(
                                color: kBrandOrange,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        if (path.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            path,
                            style: TextStyle(
                              color: muted,
                              fontSize: 11,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (job.description.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            job.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

enum _DatePreset {
  last7Days('Last 7 days', 'Last 7d'),
  last30Days('Last 30 days', 'Last 30d'),
  last90Days('Last 90 days', 'Last 90d'),
  custom('Custom range', 'Custom'),
  all('All time', 'All time');

  const _DatePreset(this.label, this.shortLabel);
  final String label;
  final String shortLabel;
}
