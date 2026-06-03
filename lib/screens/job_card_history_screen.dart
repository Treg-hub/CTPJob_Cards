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
/// Firestore read to at most [_pageSize] documents per page before any client
/// work is done. Type, priority, and free-text search are applied client-side
/// on the already-minimised result set.
///
/// Firestore indexes required (add to firestore.indexes.json and deploy):
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

  // ── Server-side filter state ──────────────────────────────────────────────
  String? _selectedDepartment;
  String? _selectedArea;
  String? _selectedMachine;
  _DatePreset _datePreset = _DatePreset.last30Days;
  DateTime? _customFrom;
  DateTime? _customTo;

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

  // ── Factory structure for cascading dropdowns ─────────────────────────────
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

  // ── Date range helpers ────────────────────────────────────────────────────

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

  // ── Search ────────────────────────────────────────────────────────────────

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

      // Determine the last raw document for cursor-based pagination.
      // We need the raw DocumentSnapshot, so we re-derive it via a secondary
      // query only when the page is full.  For small result sets this is a
      // no-op (hasMore stays false).
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
    // Fetch the raw snapshot for the last result to use as cursor.
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

  // ── Client-side filtering ─────────────────────────────────────────────────

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
            (j.correctiveAction.toLowerCase().contains(q)) ||
            (j.jobCardNumber?.toString().contains(q) ?? false);
      }).toList();
    }
    return list;
  }

  // ── Department / area / machine cascade ───────────────────────────────────

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
        ? ((_factoryStructure[_selectedDepartment]?[area] as List<dynamic>?)?.cast<String>() ?? <String>[])
        : <String>[];
    machines.sort();
    setState(() {
      _selectedArea = area;
      _selectedMachine = null;
      _machines = machines;
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Color _priorityColor(int p) {
    final colors = [Colors.transparent, Colors.green, Colors.lightGreen, Colors.amber, Colors.deepOrange, Colors.red[700]!];
    return p >= 1 && p <= 5 ? colors[p] : Colors.grey;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Card History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => _search(),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          const Divider(height: 1),
          _buildClientFilters(),
          const Divider(height: 1),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return ExpansionTile(
      initiallyExpanded: false,
      dense: true,
      leading: const Icon(Icons.filter_list, size: 20),
      title: const Text('Server Filters', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      subtitle: Text(_filterSummary, style: const TextStyle(fontSize: 11)),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date preset row — no label, chips are self-explanatory
              Wrap(
                spacing: 4,
                runSpacing: 2,
                children: _DatePreset.values.map((p) => ChoiceChip(
                  label: Text(p.label, style: const TextStyle(fontSize: 11)),
                  selected: _datePreset == p,
                  onSelected: (_) {
                    setState(() => _datePreset = p);
                    if (p != _DatePreset.custom) _search();
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  labelStyle: _datePreset == p ? const TextStyle(color: Color(0xFFFF8C42)) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
                )).toList(),
              ),
              if (_datePreset == _DatePreset.custom) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(child: _buildDateButton('From', _customFrom, (d) { setState(() => _customFrom = d); _search(); })),
                    const SizedBox(width: 6),
                    Expanded(child: _buildDateButton('To', _customTo, (d) { setState(() => _customTo = d); _search(); })),
                  ],
                ),
              ],
              const SizedBox(height: 6),

              // Department — inline label prefix
              Wrap(
                spacing: 4,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Dept:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(context).appColors.chipUnselectedLabel)),
                  FilterChip(
                    label: const Text('All', style: TextStyle(fontSize: 11)),
                    selected: _selectedDepartment == null,
                    onSelected: (_) { _onDepartmentSelected(null); _search(); },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    labelStyle: _selectedDepartment == null ? const TextStyle(color: Color(0xFFFF8C42)) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
                  ),
                  ..._departments.map((dept) => FilterChip(
                    label: Text(dept, style: const TextStyle(fontSize: 11)),
                    selected: _selectedDepartment == dept,
                    onSelected: (_) { _onDepartmentSelected(dept); _search(); },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    labelStyle: _selectedDepartment == dept ? const TextStyle(color: Color(0xFFFF8C42)) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
                  )),
                ],
              ),

              // Area (only when dept selected)
              if (_selectedDepartment != null && _areas.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Area:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(context).appColors.chipUnselectedLabel)),
                    FilterChip(
                      label: const Text('All', style: TextStyle(fontSize: 11)),
                      selected: _selectedArea == null,
                      onSelected: (_) { _onAreaSelected(null); _search(); },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      labelStyle: _selectedArea == null ? const TextStyle(color: Color(0xFFFF8C42)) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
                    ),
                    ..._areas.map((area) => FilterChip(
                      label: Text(area, style: const TextStyle(fontSize: 11)),
                      selected: _selectedArea == area,
                      onSelected: (_) { _onAreaSelected(area); _search(); },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      labelStyle: _selectedArea == area ? const TextStyle(color: Color(0xFFFF8C42)) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
                    )),
                  ],
                ),
              ],

              // Machine (only when area selected)
              if (_selectedArea != null && _machines.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Machine:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(context).appColors.chipUnselectedLabel)),
                    FilterChip(
                      label: const Text('All', style: TextStyle(fontSize: 11)),
                      selected: _selectedMachine == null,
                      onSelected: (_) { setState(() => _selectedMachine = null); _search(); },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      labelStyle: _selectedMachine == null ? const TextStyle(color: Color(0xFFFF8C42)) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
                    ),
                    ..._machines.map((m) => FilterChip(
                      label: Text(m, style: const TextStyle(fontSize: 11)),
                      selected: _selectedMachine == m,
                      onSelected: (_) { setState(() => _selectedMachine = m); _search(); },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      labelStyle: _selectedMachine == m ? const TextStyle(color: Color(0xFFFF8C42)) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
                    )),
                  ],
                ),
              ],

              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : () => _search(),
                  icon: const Icon(Icons.search, size: 16),
                  label: Text(_isLoading ? 'Searching…' : 'Search History', style: const TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C42),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    minimumSize: const Size(0, 36),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDateButton(String label, DateTime? value, ValueChanged<DateTime?> onPicked) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_today, size: 16),
      label: Text(value != null ? '${value.day}/${value.month}/${value.year}' : label, style: const TextStyle(fontSize: 12)),
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

  Widget _buildClientFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search field
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search description, machine, part, notes…',
              hintStyle: const TextStyle(fontSize: 12),
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); },
                    )
                  : null,
              isDense: true,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            ),
            style: const TextStyle(fontSize: 12),
            onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
          ),
          const SizedBox(height: 4),
          // Type + Priority in one compact row with inline labels
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Type:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(context).appColors.chipUnselectedLabel)),
                    _typeChip(null, 'All'),
                    ...JobType.values.map((t) => _typeChip(t, t.displayName)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Wrap(
                spacing: 4,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('P:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(context).appColors.chipUnselectedLabel)),
                  _priorityChip(null, 'All'),
                  ...List.generate(5, (i) => _priorityChip(i + 1, '${i + 1}')),
                ],
              ),
            ],
          ),
          if (_results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '${_filtered.length} of ${_results.length}${_hasMore ? '+ more available' : ''}',
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  Widget _typeChip(JobType? type, String label) {
    final selected = _selectedType == type;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      onSelected: (_) => setState(() => _selectedType = type),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      labelStyle: selected ? const TextStyle(color: Color(0xFFFF8C42)) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
    );
  }

  Widget _priorityChip(int? priority, String label) {
    final selected = _selectedPriority == priority;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      backgroundColor: priority != null ? _priorityColor(priority).withValues(alpha: 0.3) : null,
      onSelected: (_) => setState(() => _selectedPriority = priority),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      labelStyle: selected
          ? const TextStyle(color: Color(0xFFFF8C42))
          : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
    );
  }

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
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _search, child: const Text('Retry')),
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
              Icon(Icons.history, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(
                'Set filters above and tap Search to browse closed job card history.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final jobs = _filtered;

    if (jobs.isEmpty) {
      return Center(
        child: Text(
          'No results match the current filters.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: jobs.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == jobs.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton.icon(
                      onPressed: _loadMore,
                      icon: const Icon(Icons.expand_more),
                      label: const Text('Load More'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8C42),
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

  String get _filterSummary {
    final parts = <String>[];
    parts.add(_datePreset.label);
    if (_selectedDepartment != null) parts.add(_selectedDepartment!);
    if (_selectedArea != null) parts.add(_selectedArea!);
    if (_selectedMachine != null) parts.add(_selectedMachine!);
    return parts.join(' · ');
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
