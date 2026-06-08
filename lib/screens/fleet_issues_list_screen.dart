import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fleet_issue.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../widgets/fleet_app_bar.dart';
import '../widgets/fleet_issue_widgets.dart';
import '../widgets/fleet_mechanic_widgets.dart';
import 'fleet_issue_detail_screen.dart';

/// Full list of fleet issues with status filter chips.
/// Visible to reporters (transparency), mechanics, cost managers, and admins.
class FleetIssuesListScreen extends ConsumerStatefulWidget {
  final bool embedded;
  final bool mechanicMode;
  const FleetIssuesListScreen({
    super.key,
    this.embedded = false,
    this.mechanicMode = false,
  });

  @override
  ConsumerState<FleetIssuesListScreen> createState() =>
      _FleetIssuesListScreenState();
}

class _FleetIssuesListScreenState
    extends ConsumerState<FleetIssuesListScreen> {
  final _service = FleetService();
  String? _statusFilter; // null = all open statuses

  @override
  Widget build(BuildContext context) {
    final body = Column(
        children: [
          if (widget.mechanicMode) const FleetMechanicGuideBanner(),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: widget.mechanicMode
                  ? [
                      _FilterChip(
                        label: 'To fix',
                        selected: _statusFilter == null,
                        onTap: () => setState(() => _statusFilter = null),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'In progress',
                        selected: _statusFilter == 'acknowledged',
                        onTap: () =>
                            setState(() => _statusFilter = 'acknowledged'),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Fixed',
                        selected: _statusFilter == 'resolved',
                        onTap: () =>
                            setState(() => _statusFilter = 'resolved'),
                      ),
                    ]
                  : [
                      _FilterChip(
                        label: 'Open',
                        selected: _statusFilter == null,
                        onTap: () => setState(() => _statusFilter = null),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Acknowledged',
                        selected: _statusFilter == 'acknowledged',
                        onTap: () =>
                            setState(() => _statusFilter = 'acknowledged'),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Resolved',
                        selected: _statusFilter == 'resolved',
                        onTap: () =>
                            setState(() => _statusFilter = 'resolved'),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Cancelled',
                        selected: _statusFilter == 'cancelled',
                        onTap: () =>
                            setState(() => _statusFilter = 'cancelled'),
                      ),
                    ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<FleetIssue>>(
              stream: _statusFilter == null
                  ? _service.watchOpenIssues(limit: 100)
                  : _service.watchIssues(
                      status: _statusFilter, limit: 100),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final issues = snapshot.data ?? [];
                if (issues.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.mechanicMode
                            ? (_statusFilter == null
                                ? 'Nothing to fix right now.\nGood job!'
                                : _statusFilter == 'resolved'
                                    ? 'No fixed jobs in this list yet.'
                                    : 'Nothing in progress.')
                            : (_statusFilter == null
                                ? 'No open issues. All clear!'
                                : 'No issues with this status.'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: issues.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) => FleetIssueTile(
                    issue: issues[index],
                    mechanicMode: widget.mechanicMode,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => FleetIssueDetailScreen(
                        issueId: issues[index].id!,
                        mechanicMode: widget.mechanicMode,
                      ),
                    )),
                  ),
                );
              },
            ),
          ),
        ],
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: const FleetAppBar(title: 'Fleet Issues'),
      body: body,
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label,
      required this.selected,
      required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: kBrandOrange,
      labelStyle: TextStyle(color: selected ? Colors.white : null),
      onSelected: (_) => onTap(),
    );
  }
}

// FleetIssueTile, FleetStatusBadge, FleetSeverityBadge, FleetSeverityDot
// are defined in lib/widgets/fleet_issue_widgets.dart
