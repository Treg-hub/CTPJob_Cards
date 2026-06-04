import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/job_card_tile.dart';
import 'job_card_detail_screen.dart';

/// Historic job card search screen.
///
/// Server-side filters (department, area, machine, date range) narrow the
/// Firestore read to at most [_pageSize] documents per page.
/// Type, priority, and free-text search are applied client-side.
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
  bool _filtersExpanded = false;

  // ── Client-side filter state ──────────────────────────────────────────────
  JobType? _selectedType;
  int? _selectedPriority;
  String _searchQuery = '';

  // ── Result state ──────────────────────────────────────────────────────────
  List<JobCard> _results = [];
  bool _isLoading = false;
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
    _loadFactoryStructure();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
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
            if (_results.isNotEmpty) _filtersExpanded = false;
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
    if (_results.isEmpty) return;
    final lastId = _results.last.id;
    if (lastId == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('job_cards')
          .doc(lastId)
          .get();
      _lastDoc = doc;
      await _search(loadMore: true);
    } catch (_) {
      await _search(loadMore: true);
    }
  }

  List<JobCard> get _filtered {
    var list = _results;
    if (_selectedType != null) list = list.where((j) => j.type == _selectedType).toList();
    if (_selectedPriority != null) list = list.where((j) => j.priority == _selectedPriority).toList();
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
        ? ((_factoryStructure[dept] as Map<String, dynamic>?)?.keys.toList() ?? [])
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

  Color _priorityColor(int p) {
    const colors = [
      Colors.transparent,
      Colors.green,
      Colors.lightGreen,
      Colors.amber,
      Colors.deepOrange,
    ];
    if (p == 5) return Colors.red;
    return p >= 1 && p <= 4 ? colors[p] : Colors.grey;
  }

  String get _filterSummary {
    final parts = <String>[_datePreset.label];
    if (_selectedDepartment != null) parts.add(_selectedDepartment!);
    if (_selectedArea != null) parts.add(_selectedArea!);
    if (_selectedMachine != null) parts.add(_selectedMachine!);
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Card History'),
      ),
      body: Column(
        children: [
          _buildSearchAndQuickFilters(),
          _buildFilterPanel(),
          if (_results.isNotEmpty || _isLoading) _buildResultCount(),
          const Divider(height: 1),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  // ── Search bar + always-visible type/priority chips ───────────────────────

  Widget _buildSearchAndQuickFilters() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search text field
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search description, machine, part, notes…',
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
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            ),
            style: const TextStyle(fontSize: 13),
            onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
          ),
          const SizedBox(height: 8),

          // Type filter — full labels, horizontally scrollable
          _FilterRow(
            label: 'Type',
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _typeChip(null, 'All'),
                  ...JobType.values.map((t) => _typeChip(t, t.displayName)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),

          // Priority filter — coloured chips, scrollable
          _FilterRow(
            label: 'Priority',
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _priorityChip(null, 'All'),
                  ...List.generate(5, (i) => _priorityChip(i + 1, 'P${i + 1}')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeChip(JobType? type, String label) {
    final selected = _selectedType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => setState(() => _selectedType = type),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
        labelStyle: selected
            ? const TextStyle(color: kBrandOrange, fontWeight: FontWeight.w600)
            : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
      ),
    );
  }

  Widget _priorityChip(int? priority, String label) {
    final selected = _selectedPriority == priority;
    final bg = priority != null ? _priorityColor(priority) : null;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        backgroundColor: bg?.withValues(alpha: 0.25),
        selectedColor: bg != null ? bg.withValues(alpha: 0.55) : kBrandOrange.withValues(alpha: 0.2),
        onSelected: (_) => setState(() => _selectedPriority = priority),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
        labelStyle: selected
            ? TextStyle(
                color: priority != null ? _priorityColor(priority) : kBrandOrange,
                fontWeight: FontWeight.w600,
              )
            : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
      ),
    );
  }

  // ── Collapsible server-filter panel ──────────────────────────────────────

  Widget _buildFilterPanel() {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: _filtersExpanded,
        onExpansionChanged: (v) => setState(() => _filtersExpanded = v),
        dense: true,
        leading: Icon(
          Icons.tune,
          size: 18,
          color: _hasActiveServerFilters
              ? kBrandOrange
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        title: Text(
          'Server Filters',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _hasActiveServerFilters
                ? kBrandOrange
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          _filterSummary,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 1),
                const SizedBox(height: 10),

                // Date presets
                _SectionLabel('Date range'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _DatePreset.values.map((p) {
                    final sel = _datePreset == p;
                    return ChoiceChip(
                      label: Text(p.label, style: const TextStyle(fontSize: 12)),
                      selected: sel,
                      onSelected: (_) {
                        setState(() => _datePreset = p);
                        if (p != _DatePreset.custom) _search();
                      },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                      labelStyle: sel
                          ? const TextStyle(color: kBrandOrange, fontWeight: FontWeight.w600)
                          : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
                    );
                  }).toList(),
                ),
                if (_datePreset == _DatePreset.custom) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDateButton('From', _customFrom,
                            (d) { setState(() => _customFrom = d); _search(); }),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildDateButton('To', _customTo,
                            (d) { setState(() => _customTo = d); _search(); }),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 12),

                // Department
                _SectionLabel('Department'),
                const SizedBox(height: 6),
                _buildDropdown<String>(
                  hint: 'All departments',
                  value: _selectedDepartment,
                  items: _departments,
                  onChanged: (v) { _onDepartmentSelected(v); },
                ),

                // Area (shown when dept selected)
                if (_selectedDepartment != null && _areas.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _SectionLabel('Area'),
                  const SizedBox(height: 6),
                  _buildDropdown<String>(
                    hint: 'All areas',
                    value: _selectedArea,
                    items: _areas,
                    onChanged: (v) { _onAreaSelected(v); },
                  ),
                ],

                // Machine (shown when area selected)
                if (_selectedArea != null && _machines.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _SectionLabel('Machine'),
                  const SizedBox(height: 6),
                  _buildDropdown<String>(
                    hint: 'All machines',
                    value: _selectedMachine,
                    items: _machines,
                    onChanged: (v) => setState(() => _selectedMachine = v),
                  ),
                ],

                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : () => _search(),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.search, size: 18),
                    label: Text(
                      _isLoading ? 'Searching…' : 'Search History',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: kBrandOrange,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasActiveServerFilters =>
      _datePreset != _DatePreset.last30Days ||
      _selectedDepartment != null ||
      _selectedArea != null ||
      _selectedMachine != null;

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
        hint: Text(hint, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        isExpanded: true,
        underline: const SizedBox(),
        isDense: true,
        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
        items: [
          DropdownMenuItem<T>(value: null, child: Text(hint, style: const TextStyle(fontSize: 13))),
          ...items.map((i) => DropdownMenuItem<T>(
                value: i,
                child: Text(i.toString(), style: const TextStyle(fontSize: 13)),
              )),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildDateButton(
      String label, DateTime? value, ValueChanged<DateTime?> onPicked) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_today, size: 15),
      label: Text(
        value != null
            ? '${value.day}/${value.month}/${value.year}'
            : label,
        style: const TextStyle(fontSize: 12),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        onPicked(picked);
      },
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
            '${filtered.length}${_results.length != filtered.length ? ' of ${_results.length}' : ''}'
            '${_hasMore ? '+' : ''} result${filtered.length == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (_selectedType != null || _selectedPriority != null || _searchQuery.isNotEmpty) ...[
            const Spacer(),
            TextButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _selectedType = null;
                  _selectedPriority = null;
                  _searchQuery = '';
                });
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Clear filters', style: TextStyle(fontSize: 11)),
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
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _search,
                style: FilledButton.styleFrom(backgroundColor: kBrandOrange, foregroundColor: Colors.black),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.manage_search,
                size: 72,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 16),
              Text(
                'Set your filters and tap\nSearch History to get started.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => setState(() => _filtersExpanded = true),
                icon: const Icon(Icons.tune, size: 16),
                label: const Text('Open Filters'),
              ),
            ],
          ),
        ),
      );
    }

    final jobs = _filtered;

    if (jobs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_list_off, size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                'No results match the current filters.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _selectedType = null;
                    _selectedPriority = null;
                    _searchQuery = '';
                  });
                },
                child: const Text('Clear quick filters'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: jobs.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == jobs.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : FilledButton.icon(
                      onPressed: _loadMore,
                      icon: const Icon(Icons.expand_more, size: 18),
                      label: const Text('Load More'),
                      style: FilledButton.styleFrom(
                        backgroundColor: kBrandOrange,
                        foregroundColor: Colors.black,
                      ),
                    ),
            ),
          );
        }
        final job = jobs[index];
        return JobCardTile(
          job: job,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => JobCardDetailScreen(jobCard: job)),
          ),
        );
      },
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

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

enum _DatePreset {
  last7Days('Last 7 days'),
  last30Days('Last 30 days'),
  last90Days('Last 90 days'),
  custom('Custom range'),
  all('All time');

  const _DatePreset(this.label);
  final String label;
}
