import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/persona_audit.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import '../services/job_card_actions_service.dart';
import '../main.dart' show currentEmployee;
import '../theme/app_theme.dart';
import '../widgets/ctp_app_bar.dart';
import '../widgets/job_card_tile.dart';
import '../utils/screen_insets.dart';

class DailyReviewScreen extends StatefulWidget {
  const DailyReviewScreen({super.key});

  @override
  State<DailyReviewScreen> createState() => _DailyReviewScreenState();
}

class _DailyReviewScreenState extends State<DailyReviewScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  final JobCardActionsService _actions = JobCardActionsService();
  StreamSubscription<List<JobCard>>? _subscription;
  late TabController _tabController;

  // Cards seen in this session (frozen snapshot from first load)
  List<JobCard> _pendingCards = [];
  // Cards actually opened (and therefore stamped reviewed) this session.
  final Set<String> _markedThisSession = {};
  // All reviewed cards for this manager (live stream)
  List<JobCard> _reviewedCards = [];
  JobCard? _selectedCard;

  bool _isLoading = true;
  bool _hasMarked = false;

  // Date filter for Reviewed tab
  DateTime? _filterFrom;
  DateTime? _filterTo;

  final TextEditingController _inputController = TextEditingController();
  bool _isSaving = false;

  bool get _isElecManager =>
      (currentEmployee?.position.toLowerCase().contains('electrical') ?? false) &&
      (currentEmployee?.position.toLowerCase().contains('manager') ?? false);

  bool get _isMechManager =>
      (currentEmployee?.position.toLowerCase().contains('mechanical') ?? false) &&
      (currentEmployee?.position.toLowerCase().contains('manager') ?? false);

  // Elec/mech managers add to notes; all others add to comments
  bool get _canAddNotes => _isElecManager || _isMechManager;

  String get _scopeLabel {
    if (_isElecManager) return 'Electrical Jobs — Factory Wide';
    if (_isMechManager) return 'Mechanical Jobs — Factory Wide';
    return '${currentEmployee?.department ?? ''} Department';
  }

  List<JobCard> _scopeCards(List<JobCard> all) {
    if (_isElecManager) {
      return all
          .where((c) =>
              c.type == JobType.electrical ||
              c.type == JobType.mechanicalElectrical)
          .toList();
    } else if (_isMechManager) {
      return all
          .where((c) =>
              c.type == JobType.mechanical ||
              c.type == JobType.mechanicalElectrical)
          .toList();
    }
    return all
        .where((c) => c.department == (currentEmployee?.department ?? ''))
        .toList();
  }

  List<JobCard> get _filteredReviewedCards {
    if (_filterFrom == null && _filterTo == null) return _reviewedCards;
    final clockNo = currentEmployee?.clockNo ?? '';
    return _reviewedCards.where((c) {
      final reviewTime = c.reviewedBy[clockNo];
      if (reviewTime == null) return false;
      if (_filterFrom != null && reviewTime.isBefore(_filterFrom!)) return false;
      if (_filterTo != null &&
          reviewTime.isAfter(_filterTo!.add(const Duration(days: 1)))) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {
        _selectedCard = null;
        _inputController.clear();
      });
    });
    _loadCards();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _tabController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  void _loadCards() {
    // Active jobs + last-14-days closed — review never needs the entire
    // collection history that getAllJobCards() used to stream.
    _subscription =
        _firestoreService.getActiveAndRecentlyClosedJobCards().listen((allCards) {
      final manager = currentEmployee;
      if (manager == null) return;

      final clockNo = manager.clockNo;
      final scoped = _scopeCards(allCards);

      final pending =
          scoped.where((c) => !c.reviewedBy.containsKey(clockNo)).toList();
      final reviewed = scoped
          .where((c) => c.reviewedBy.containsKey(clockNo))
          .toList()
        ..sort((a, b) => (b.reviewedBy[clockNo] ?? DateTime(0))
            .compareTo(a.reviewedBy[clockNo] ?? DateTime(0)));

      if (!mounted) return;

      // Keep selected card in sync with latest Firestore data
      JobCard? updatedSelected;
      if (_selectedCard != null) {
        updatedSelected =
            scoped.where((c) => c.id == _selectedCard!.id).firstOrNull;
      }

      setState(() {
        _isLoading = false;
        _reviewedCards = reviewed;

        if (!_hasMarked) {
          // Frozen session snapshot. Cards are stamped reviewedBy only when
          // the manager actually OPENS them (_selectCard) — the old behaviour
          // stamped everything on screen load, so the reviewedBy timestamps
          // proved nothing.
          _pendingCards = pending;
          _hasMarked = true;
        } else {
          // Update content of pending cards without changing the set, but
          // drop cards this manager has reviewed in this session.
          _pendingCards = _pendingCards
              .where((pc) => !_markedThisSession.contains(pc.id))
              .map((pc) {
            return scoped.where((c) => c.id == pc.id).firstOrNull ?? pc;
          }).toList();
        }

        if (updatedSelected != null) {
          _selectedCard = updatedSelected;
        }
      });
    }, onError: (e) {
      debugPrint('DailyReviewScreen: job cards stream error: $e');
      if (mounted) setState(() => _isLoading = false);
    });
  }

  /// Selecting a card is the review act — stamp reviewedBy NOW, not on
  /// screen load. The stamp is what the audit trail relies on.
  void _selectCard(JobCard card) {
    setState(() {
      _selectedCard = card;
      _inputController.clear();
    });
    final clockNo = currentEmployee?.clockNo;
    if (clockNo == null || card.id == null) return;
    if (_markedThisSession.contains(card.id)) return;
    if (card.reviewedBy.containsKey(clockNo)) return;
    _markedThisSession.add(card.id!);
    _firestoreService.markJobCardsReviewed([card.id!], clockNo);
  }

  Future<void> _saveInput() async {
    if (!guardPersonaSubmit(context)) return;
    final text = _inputController.text.trim();
    if (text.isEmpty || _selectedCard == null || _isSaving) return;
    final current = currentEmployee;
    if (current == null) return;

    setState(() => _isSaving = true);

    try {
      if (_canAddNotes) {
        await _actions.addNote(_selectedCard!, current, text);
      } else {
        await _actions.addComment(_selectedCard!, current, text);
      }
      _inputController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_canAddNotes ? 'Note added.' : 'Comment added.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CtpAppBar(title: 'Daily Review — $_scopeLabel'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                TabBar(
                  controller: _tabController,
                  tabs: [
                    Tab(text: 'Pending Review (${_pendingCards.length})'),
                    Tab(text: 'Reviewed (${_filteredReviewedCards.length})'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTwoPanel(_pendingCards),
                      _buildTwoPanel(_filteredReviewedCards, showDateFilter: true),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTwoPanel(List<JobCard> cards, {bool showDateFilter = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;

        final Widget cardList = cards.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline, size: 64, color: Colors.green[300]),
                    const SizedBox(height: 12),
                    Text(
                      showDateFilter
                          ? 'No reviewed cards in this range'
                          : 'All caught up — nothing to review!',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: ScreenInsets.listPadding(context, horizontal: 12, top: 12),
                itemCount: cards.length,
                itemBuilder: (context, index) {
                  final card = cards[index];
                  final isSelected = _selectedCard?.id == card.id;
                  return JobCardTile(
                    job: card,
                    selected: isSelected,
                    onTap: () => _selectCard(card),
                  );
                },
              );

        // Narrow: show list or detail, not both
        if (isNarrow) {
          if (_selectedCard != null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => setState(() => _selectedCard = null),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.arrow_back, size: 20),
                        SizedBox(width: 8),
                        Text('Back to list'),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: _buildDetailPanel(_selectedCard!)),
              ],
            );
          }
          return Column(
            children: [
              if (showDateFilter) _buildDateFilter(),
              Expanded(child: cardList),
            ],
          );
        }

        // Wide: side-by-side
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 400,
              child: Column(
                children: [
                  if (showDateFilter) _buildDateFilter(),
                  Expanded(child: cardList),
                ],
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: _selectedCard == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.arrow_back, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 8),
                          Text(
                            'Select a job card to review',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    )
                  : _buildDetailPanel(_selectedCard!),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: (_filterFrom != null && _filterTo != null)
          ? DateTimeRange(start: _filterFrom!, end: _filterTo!)
          : null,
    );
    if (range != null && mounted) {
      setState(() {
        _filterFrom = range.start;
        _filterTo = range.end;
      });
    }
  }

  Widget _buildDateFilter() {
    final hasFilter = _filterFrom != null || _filterTo != null;
    String fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          if (hasFilter)
            Expanded(
              child: InputChip(
                avatar: const Icon(Icons.date_range, size: 16),
                label: Text(
                  '${_filterFrom != null ? fmt(_filterFrom!) : '...'} → ${_filterTo != null ? fmt(_filterTo!) : '...'}',
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: _pickDateRange,
                onDeleted: () => setState(() {
                  _filterFrom = null;
                  _filterTo = null;
                }),
              ),
            )
          else
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.date_range, size: 14),
                label: const Text('Filter by date', style: TextStyle(fontSize: 12)),
                onPressed: _pickDateRange,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailPanel(JobCard card) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badges row
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (card.jobCardNumber != null)
                _badge(
                  'JC #${card.jobCardNumber}',
                  Colors.blue,
                ),
              _badge('P${card.priority}', _priorityColor(context, card.priority)),
              _badge(card.type.displayName, Colors.blueGrey),
              _badge(card.status.displayName,
                  _statusColorByStatus(context, card.status)),
            ],
          ),
          const SizedBox(height: 14),

          // Location + meta
          Text(
            '${card.department} › ${card.area} › ${card.machine} › ${card.part}',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            'Operator: ${card.operator}${card.operatorClockNo != null ? ' (${card.operatorClockNo})' : ''}',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13),
          ),
          if (card.createdAt != null)
            Text(
              'Created: ${card.createdAt!.day}/${card.createdAt!.month}/${card.createdAt!.year}'
              ' ${card.createdAt!.hour}:${card.createdAt!.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13),
            ),
          const SizedBox(height: 20),

          // Description
          _sectionLabel(context, 'Description'),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: card.description.isEmpty
                  ? Colors.red.withValues(alpha: 20)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: card.description.isEmpty
                  ? Border.all(color: Colors.red.withValues(alpha: 100))
                  : null,
            ),
            child: Text(
              card.description.isEmpty ? '⚠ No description entered' : card.description,
              style: TextStyle(
                color: card.description.isEmpty
                    ? Colors.red[700]
                    : Theme.of(context).colorScheme.onSurface,
                fontSize: 15,
              ),
            ),
          ),

          // Notes
          if (card.notes.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Divider(),
            _sectionLabel(context, 'Notes'),
            const SizedBox(height: 6),
            Text(card.notes,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14)),
          ],

          // Comments
          if (card.comments.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Divider(),
            _sectionLabel(context, 'Comments'),
            const SizedBox(height: 6),
            Text(card.comments,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14)),
          ],

          // Assigned staff
          if (card.assignedNames?.isNotEmpty == true) ...[
            const SizedBox(height: 20),
            const Divider(),
            _sectionLabel(context, 'Assigned To'),
            const SizedBox(height: 6),
            Text(card.assignedNames!.join(', '),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14)),
          ],

          // Input section
          const SizedBox(height: 28),
          const Divider(),
          _sectionLabel(
              context, _canAddNotes ? 'Add Note' : 'Add Comment'),
          const SizedBox(height: 8),
          TextField(
            controller: _inputController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: _canAddNotes
                  ? 'Add maintenance notes...'
                  : 'Add a comment or additional context...',
              border: const OutlineInputBorder(),
              filled: true,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveInput,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_canAddNotes ? 'Save Note' : 'Save Comment'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kBrandOrange,
                foregroundColor: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: onColor(color),
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  Color _priorityColor(BuildContext context, int priority) {
    final c = Theme.of(context).appColors;
    switch (priority) {
      case 1: return c.priority1;
      case 2: return c.priority2;
      case 3: return c.priority3;
      case 4: return c.priority4;
      case 5: return c.priority5;
      default: return Colors.grey;
    }
  }

  Color _statusColorByStatus(BuildContext context, JobStatus status) {
    final c = Theme.of(context).appColors;
    switch (status) {
      case JobStatus.open: return c.statusOpen;
      case JobStatus.inProgress: return c.statusInProgress;
      case JobStatus.monitor: return Colors.amber[700]!;
      case JobStatus.closed: return c.statusCancelled;
    }
  }
}
