import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee;
import '../models/security_entry.dart';
import '../services/security_service.dart';
import '../theme/app_theme.dart';
import '../utils/persona_audit.dart';
import '../utils/screen_insets.dart';
import 'security_visitor_sign_out_screen.dart';
import 'security_vehicle_gate_screen.dart';

/// Tabbed on-site screen: Tab 1 vehicles (grouped by entry type), Tab 2
/// on-foot visitors. Rows are tappable for drill-in to scan-out.
class SecurityOnSiteScreen extends StatelessWidget {
  const SecurityOnSiteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = SecurityService();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('On Site'),
          // The AppBar is brand orange in both themes; the dark theme's global
          // TabBar colours are orange, which would be orange-on-orange here.
          // Use black to match the AppBar's black foreground (title/icons).
          bottom: const TabBar(
            labelColor: Colors.black,
            unselectedLabelColor: Colors.black54,
            indicatorColor: Colors.black,
            tabs: [
              Tab(text: 'Vehicles'),
              Tab(text: 'Visitors'),
            ],
          ),
        ),
        body: StreamBuilder<List<SecurityEntry>>(
          // Time-window scoping: 7 days is enough to catch anything
          // genuinely still on site while bounding read volume (was: an
          // unscoped `limit: 300` across ALL entry types, which could miss
          // a long-dwelling vehicle/visitor beyond the 300 most recent
          // gate events).
          stream: service.watchRecentEntriesSince(
            since: DateTime.now().subtract(const Duration(days: 14)), // Harmonized window using createdAt for reliability
          ),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final entries = snap.data ?? [];
            final onSiteVehicles = service.computeOnSite(entries);
            final onSiteVisitors = service.computeOnSiteVisitors(entries);
            return TabBarView(
              children: [
                _VehiclesTab(entries: onSiteVehicles),
                _VisitorsTab(entries: onSiteVisitors),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _VehiclesTab extends StatefulWidget {
  const _VehiclesTab({required this.entries});
  final List<SecurityEntry> entries;

  @override
  State<_VehiclesTab> createState() => _VehiclesTabState();
}

class _VehiclesTabState extends State<_VehiclesTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.entries
        : widget.entries.where((e) {
            return (e.vehicleReg ?? '').toLowerCase().contains(q) ||
                (e.driverName ?? '').toLowerCase().contains(q) ||
                (e.contractorName ?? '').toLowerCase().contains(q);
          }).toList();

    final dateFmt = DateFormat('dd MMM yyyy HH:mm');
    final grouped = <SecurityEntryType, List<SecurityEntry>>{};
    for (final e in filtered) {
      final type = e.entryType ?? SecurityEntryType.visitor;
      grouped.putIfAbsent(type, () => []).add(e);
    }
    const order = [
      SecurityEntryType.companyCar,
      SecurityEntryType.visitor,
      SecurityEntryType.contractor,
      SecurityEntryType.transporter,
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Search reg or name',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: widget.entries.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No vehicles currently on site.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : filtered.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No matches.', textAlign: TextAlign.center),
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        12,
                        12,
                        ScreenInsets.scrollBottomFullScreen(context),
                      ),
                      children: [
                        for (final type in order)
                          if (grouped[type]?.isNotEmpty ?? false) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 4,
                              ),
                              child: Text(
                                '${type.label} (${grouped[type]!.length})',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: kBrandOrange,
                                    ),
                              ),
                            ),
                            for (final e in grouped[type]!) ...[
                              _VehicleOnSiteCard(entry: e, dateFmt: dateFmt),
                              const SizedBox(height: 8),
                            ],
                          ],
                      ],
                    ),
        ),
      ],
    );
  }
}

class _VehicleOnSiteCard extends StatelessWidget {
  const _VehicleOnSiteCard({required this.entry, required this.dateFmt});

  final SecurityEntry entry;
  final DateFormat dateFmt;

  IconData get _icon => switch (entry.entryType) {
        SecurityEntryType.companyCar => Icons.directions_car,
        SecurityEntryType.transporter => Icons.local_shipping,
        SecurityEntryType.contractor => Icons.engineering,
        _ => Icons.time_to_leave,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SecurityVehicleGateScreen()),
        ),
        leading: CircleAvatar(
          backgroundColor: kBrandOrange.withValues(alpha: 0.15),
          child: Icon(_icon, color: kBrandOrange),
        ),
        title: Text(
          entry.vehicleReg ?? '—',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.driverName ?? entry.visitorName ?? '—'),
            if (entry.contractorName != null)
              Text(entry.contractorName!, style: const TextStyle(fontSize: 12)),
            if (entry.gateName != null)
              Text('Gate: ${entry.gateName}', style: const TextStyle(fontSize: 12)),
            if (entry.loggedAt != null)
              Text(
                'Since ${dateFmt.format(entry.loggedAt!.toLocal())}',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
        trailing: _ForceSignOutButton(entry: entry),
        isThreeLine: true,
      ),
    );
  }
}

class _VisitorsTab extends StatefulWidget {
  const _VisitorsTab({required this.entries});
  final List<SecurityEntry> entries;

  @override
  State<_VisitorsTab> createState() => _VisitorsTabState();
}

class _VisitorsTabState extends State<_VisitorsTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.entries
        : widget.entries.where((e) {
            return (e.visitorName ?? '').toLowerCase().contains(q) ||
                (e.driverName ?? '').toLowerCase().contains(q) ||
                (e.hostName ?? '').toLowerCase().contains(q) ||
                (e.companyName ?? '').toLowerCase().contains(q);
          }).toList();

    final dateFmt = DateFormat('dd MMM yyyy HH:mm');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Search name, host or company',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: widget.entries.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No visitors currently on site.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : filtered.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No matches.', textAlign: TextAlign.center),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        12,
                        12,
                        ScreenInsets.scrollBottomFullScreen(context),
                      ),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final e = filtered[i];
                        return Card(
                          child: ListTile(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    SecurityVisitorSignOutScreen(entry: e),
                              ),
                            ),
                            leading: CircleAvatar(
                              backgroundColor: kBrandOrange.withValues(alpha: 0.15),
                              child: const Icon(
                                Icons.directions_walk,
                                color: kBrandOrange,
                              ),
                            ),
                            title: Text(
                              e.visitorName ?? e.driverName ?? '—',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (e.hostName != null)
                                  Text('Host: ${e.hostName}', style: const TextStyle(fontSize: 12)),
                                if (e.companyName != null)
                                  Text(e.companyName!, style: const TextStyle(fontSize: 12)),
                                if (e.gateName != null)
                                  Text('Gate: ${e.gateName}', style: const TextStyle(fontSize: 12)),
                                if (e.loggedAt != null)
                                  Text(
                                    'Since ${dateFmt.format(e.loggedAt!.toLocal())}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                              ],
                            ),
                            trailing: _ForceSignOutButton(entry: e),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

/// Trailing "⋮" menu on an on-site row — offers a manual force sign-out for an
/// entry stuck on site (exit scan never landed). Any security user can use it;
/// the reason + actor are written to the security audit trail.
class _ForceSignOutButton extends StatelessWidget {
  const _ForceSignOutButton({required this.entry});

  final SecurityEntry entry;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'More',
      onSelected: (v) {
        if (v == 'force') _confirmForceSignOut(context, entry);
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'force',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout, color: Colors.redAccent),
            title: Text('Force sign out (no scan)'),
          ),
        ),
      ],
    );
  }
}

Future<void> _confirmForceSignOut(
    BuildContext context, SecurityEntry entry) async {
  if (!guardPersonaSubmit(context)) return;
  final emp = currentEmployee;
  final actor = resolveWriteActor(emp);
  if (actor == null) return;

  final reason = await showDialog<String>(
    context: context,
    builder: (_) => _ForceSignOutDialog(entry: entry),
  );
  if (reason == null || reason.trim().isEmpty) return;

  try {
    await SecurityService().forceSignOut(
      onSiteEntry: entry,
      reason: reason.trim(),
      loggedByClockNo: actor.clockNo,
      loggedByName: actor.name,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${entry.vehicleReg ?? entry.visitorName ?? 'Entry'} signed out (manual)',
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Force sign-out failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _ForceSignOutDialog extends StatefulWidget {
  const _ForceSignOutDialog({required this.entry});

  final SecurityEntry entry;

  @override
  State<_ForceSignOutDialog> createState() => _ForceSignOutDialogState();
}

class _ForceSignOutDialogState extends State<_ForceSignOutDialog> {
  static const _reasons = [
    'Exit scan not captured',
    'Left without signing out',
    'Duplicate / erroneous entry',
    'Other',
  ];
  String? _reason;
  final _detailCtrl = TextEditingController();

  @override
  void dispose() {
    _detailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final who = widget.entry.vehicleReg ??
        widget.entry.visitorName ??
        widget.entry.driverName ??
        'this entry';
    final needsDetail = _reason == 'Other';
    return AlertDialog(
      title: const Text('Force sign out'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Manually sign out $who without a scan. This is recorded for audit — choose a reason.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _reasons
                  .map((r) => ChoiceChip(
                        label: Text(r),
                        selected: _reason == r,
                        onSelected: (s) =>
                            setState(() => _reason = s ? r : null),
                      ))
                  .toList(),
            ),
            if (needsDetail) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _detailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Detail *',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final reason = _reason;
            if (reason == null) return;
            if (reason == 'Other' && _detailCtrl.text.trim().isEmpty) return;
            final composed = reason == 'Other'
                ? 'Other: ${_detailCtrl.text.trim()}'
                : reason;
            Navigator.pop(context, composed);
          },
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}
