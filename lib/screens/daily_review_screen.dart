import 'dart:async';
import 'package:flutter/material.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import '../main.dart' show currentEmployee;
import '../theme/app_theme.dart';
import '../widgets/job_card_tile.dart';

class DailyReviewScreen extends StatefulWidget {
  const DailyReviewScreen({super.key});

  @override
  State<DailyReviewScreen> createState() => _DailyReviewScreenState();
}

class _DailyReviewScreenState extends State<DailyReviewScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  StreamSubscription<List<JobCard>>? _subscription;
  late TabController _tabController;

  // Cards seen in this session (frozen snapshot from first load)
  List<JobCard> _pendingCards = [];
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
    _subscription = _firestoreService.getAllJobCards().listen((allCards) {
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
          _pendingCards = pending;
          _hasMarked = true;

          final ids = pending
              .where((c) => c.id != null && c.id!.isNotEmpty)
              .map((c) => c.id!)
              .toList();
          if (ids.isNotEmpty) {
            _firestoreService.markJobCardsReviewed(ids, clockNo);
          }
        } else {
          // Update content of pending cards without changing the set
          _pendingCards = _pendingCards.map((pc) {
            return scoped.where((c) => c.id == pc.id).firstOrNull ?? pc;
          }).toList();
        }

        if (updatedSelected != null) {
          _selectedCard = updatedSelected;
        }
      });
    });
  }

  Future<void> _saveInput() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _selectedCard == null || _isSaving) return;

    setState(() => _isSaving = true);

    final now = DateTime.now();
    final user = currentEmployee?.name ?? 'Manager';
    final entry =
        '\n\n[${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}] $user: $text';

    try {
      final updated = _canAddNotes
          ? _selectedCard!.copyWith(notes: _selectedCard!.notes + entry)
          : _selectedCard!.copyWith(comments: _selectedCard!.comments + entry);

      await _firestoreService.saveJobCardOfflineAware(updated);
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
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Daily Review',
                style: TextStyle(fontSize: 18, color: Colors.black)),
            Text(
              _scopeLabel,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [kBrandOrange, Color.fromARGB(255, 124, 124, 124)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.black,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black54,
          tabs: [
            Tab(text: 'Pending Review (${_pendingCards.length})'),
            Tab(
                text:
                    'Reviewed (${_filteredReviewedCards.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTwoPanel(_pendingCards),
                _buildTwoPanel(_filteredReviewedCards, showDateFilter: true),
              ],
            ),
    );
  }

  Widget _buildTwoPanel(List<JobCard> cards, {bool showDateFilter = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left panel — card list
        SizedBox(
          width: 400,
          child: Column(
            children: [
              if (showDateFilter) _buildDateFilter(),
              Expanded(
                child: cards.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 64, color: Colors.green[300]),
                            const SizedBox(height: 12),
                            Text(
                              showDateFilter
                                  ? 'No reviewed cards in this range'
                                  : 'All caught up — nothing to review!',
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: cards.length,
                        itemBuilder: (context, index) {
                          final card = cards[index];
                          final isSelected = _selectedCard?.id == card.id;
                          return Container(
                            decoration: isSelected
                                ? BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: kBrandOrange, width: 2),
                                  )
                                : null,
                            child: JobCardTile(
                              job: card,
                              onTap: () => setState(() {
                                _selectedCard = card;
                                _inputController.clear();
                              }),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),

        const VerticalDivider(width: 1, thickness: 1),

        // Right panel — detail + edit
        Expanded(
          child: _selectedCard == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.arrow_back,
                          size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text(
                        'Select a job card to review',
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : _buildDetailPanel(_selectedCard!),
        ),
      ],
    );
  }

  Widget _buildDateFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 14),
              label: Text(
                _filterFrom != null
                    ? '${_filterFrom!.day}/${_filterFrom!.month}/${_filterFrom!.year}'
                    : 'From date',
                style: const TextStyle(fontSize: 12),
              ),
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _filterFrom ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null && mounted) {
                  setState(() => _filterFrom = date);
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 14),
              label: Text(
                _filterTo != null
                    ? '${_filterTo!.day}/${_filterTo!.month}/${_filterTo!.year}'
                    : 'To date',
                style: const TextStyle(fontSize: 12),
              ),
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _filterTo ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null && mounted) {
                  setState(() => _filterTo = date);
                }
              },
            ),
          ),
          if (_filterFrom != null || _filterTo != null)
            IconButton(
              icon: const Icon(Icons.clear, size: 16),
              tooltip: 'Clear filter',
              onPressed: () => setState(() {
                _filterFrom = null;
                _filterTo = null;
              }),
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
      case JobStatus.monitor: return c.statusCompleted;
      case JobStatus.closed: return c.statusCancelled;
    }
  }
}
