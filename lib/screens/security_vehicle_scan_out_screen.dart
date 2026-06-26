import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show currentEmployee;
import '../models/parsed_document.dart';
import '../models/security_entry.dart';
import '../models/security_vehicle.dart';
import '../providers/security_provider.dart';
import '../services/security_service.dart';
import '../theme/app_theme.dart';
import 'security_document_scan_screen.dart';
import '../utils/screen_insets.dart';

/// Scan-out: disc scan or manual on-site pick; confirm occupants leaving; flag discrepancies.
class SecurityVehicleScanOutScreen extends ConsumerStatefulWidget {
  const SecurityVehicleScanOutScreen({super.key});

  @override
  ConsumerState<SecurityVehicleScanOutScreen> createState() =>
      _SecurityVehicleScanOutScreenState();
}

class _SecurityVehicleScanOutScreenState
    extends ConsumerState<SecurityVehicleScanOutScreen> {
  final _service = SecurityService();
  final _discrepancyNoteCtrl = TextEditingController();

  SecurityEntry? _matched;
  ParsedDocument? _disc;
  int _occupantsLeaving = 1;
  bool _submitting = false;

  @override
  void dispose() {
    _discrepancyNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanDisc(List<SecurityEntry> onSite) async {
    final result = await Navigator.push<ParsedDocument>(
      context,
      MaterialPageRoute(
        builder: (_) => const SecurityDocumentScanScreen(
          title: 'Scan Licence Disc',
          expectedType: SecurityDocumentType.licenseDisc,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final match = _service.findOnSiteByReg(onSite, result.vehicleReg);
    setState(() {
      _disc = result;
      _matched = match;
      _occupantsLeaving = match?.occupantCount ?? 1;
      _discrepancyNoteCtrl.clear();
    });
  }

  void _selectOnSite(SecurityEntry entry) {
    setState(() {
      _matched = entry;
      _occupantsLeaving = entry.occupantCount ?? 1;
      _discrepancyNoteCtrl.clear();
      if (_disc != null) {
        final discReg = SecurityVehicle.normalizeReg(_disc!.vehicleReg);
        final entryReg = SecurityVehicle.normalizeReg(entry.vehicleReg);
        if (discReg.isNotEmpty &&
            entryReg.isNotEmpty &&
            discReg != entryReg) {
          _disc = null;
        }
      }
    });
  }

  Future<void> _submit() async {
    final emp = currentEmployee;
    final gate = ref.read(selectedSecurityGateProvider);
    if (emp == null || gate == null) return;

    if (_matched == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select or scan to match an on-site vehicle.'),
        ),
      );
      return;
    }

    final reg = SecurityVehicle.normalizeReg(
      _disc?.vehicleReg ?? _matched!.vehicleReg,
    );
    if (reg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle registration is missing.')),
      );
      return;
    }

    if (_disc != null &&
        SecurityVehicle.normalizeReg(_matched!.vehicleReg ?? '') != reg) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Disc reg $reg does not match on-site vehicle '
            '${_matched!.vehicleReg}.',
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final recorded = _matched!.occupantCount ?? 1;
    final discrepancy = _occupantsLeaving != recorded;
    if (discrepancy && _discrepancyNoteCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            recorded > _occupantsLeaving
                ? 'Explain why ${_recordedLabel(recorded)} but only '
                    '$_occupantsLeaving leaving (e.g. staying on site).'
                : 'Explain why more people are leaving than were logged in.',
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final discMissing = _disc == null;

    setState(() => _submitting = true);
    try {
      final result = await _service.scanOut(
        onSiteEntry: _matched!,
        gateId: gate.id,
        gateName: gate.name,
        loggedByClockNo: emp.clockNo,
        loggedByName: emp.name,
        discScan: _disc,
        occupantsLeaving: _occupantsLeaving,
        occupantDiscrepancyNote: discrepancy
            ? _discrepancyNoteCtrl.text.trim()
            : null,
        discScanMissingFlag: discMissing,
      );

      if (!mounted) return;
      final partial = _occupantsLeaving < recorded;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.queuedOffline
                ? 'Scan out queued (${result.entryNumber ?? result.id})'
                : partial
                    ? 'Scan out logged with partial exit flag'
                    : 'Scan out logged: ${result.entryNumber ?? result.id}',
          ),
          backgroundColor: partial ? Colors.orange.shade800 : kBrandOrange,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _recordedLabel(int count) =>
      '$count occupant${count == 1 ? '' : 's'} were recorded on entry';

  @override
  Widget build(BuildContext context) {
    final gate = ref.watch(selectedSecurityGateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle Scan Out')),
      body: StreamBuilder<List<SecurityEntry>>(
        stream: _service.watchRecentEntries(limit: 200),
        builder: (context, snap) {
          final onSite = _service.computeOnSite(snap.data ?? []);
          final recorded = _matched?.occupantCount ?? 1;
          final discrepancy = _matched != null && _occupantsLeaving != recorded;
          final partial = _matched != null && _occupantsLeaving < recorded;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (gate == null)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Select a gate on the Security home screen.'),
                  ),
                ),
              const Text(
                'Scan the disc or pick the on-site vehicle. Enter how many '
                'occupants are leaving; flag any mismatch for manager review.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _scanDisc(onSite),
                icon: Icon(
                  _disc != null ? Icons.check_circle : Icons.qr_code_scanner,
                  color: _disc != null ? Colors.green : null,
                ),
                label: Text(
                  _disc != null
                      ? 'Disc scanned: ${_disc!.vehicleReg ?? "—"}'
                      : 'Scan licence disc (or pick below)',
                ),
              ),
              if (_matched != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: kBrandOrange.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'On-site vehicle',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _matched!.vehicleReg ?? '—',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text(
                          _matched!.driverName ??
                              _matched!.contractorName ??
                              '—',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Recorded on entry: $recorded occupant'
                          '${recorded == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('Leaving now'),
                            const SizedBox(width: 12),
                            IconButton(
                              onPressed: _occupantsLeaving > 1
                                  ? () => setState(() => _occupantsLeaving--)
                                  : null,
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text(
                              '$_occupantsLeaving',
                              style:
                                  Theme.of(context).textTheme.titleMedium,
                            ),
                            IconButton(
                              onPressed: _occupantsLeaving < 20
                                  ? () => setState(() => _occupantsLeaving++)
                                  : null,
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                        if (partial)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '${recorded - _occupantsLeaving} person(s) may '
                              'still be on site — exit will be flagged. '
                              'They can leave later on foot or in another vehicle.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                        if (discrepancy) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _discrepancyNoteCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Discrepancy note *',
                              border: OutlineInputBorder(),
                              helperText:
                                  'Required when leaving count differs from entry',
                            ),
                            maxLines: 2,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ] else if (_disc != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'No on-site record for '
                      '${SecurityVehicle.normalizeReg(_disc!.vehicleReg)}. '
                      'Pick a vehicle from the list below.',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'On-site vehicles (manual fallback)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              if (onSite.isEmpty)
                const Text('No vehicles currently on site.'),
              ...onSite.map((e) {
                final selected = _matched?.id == e.id;
                final occ = e.occupantCount;
                return Card(
                  color: selected
                      ? kBrandOrange.withValues(alpha: 0.12)
                      : null,
                  child: ListTile(
                    title: Text(e.vehicleReg ?? '—'),
                    subtitle: Text(
                      '${e.driverName ?? e.contractorName ?? '—'} · '
                      '${e.entryType?.label ?? ''}'
                      '${occ != null ? ' · $occ occupant${occ == 1 ? '' : 's'}' : ''}',
                    ),
                    trailing: selected
                        ? const Icon(Icons.check_circle, color: kBrandOrange)
                        : null,
                    onTap: () => _selectOnSite(e),
                  ),
                );
              }),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeBottomBar(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: _submitting || gate == null ? null : _submit,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: kBrandOrange,
          ),
          child: _submitting
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Log vehicle out'),
        ),
      ),
    );
  }
}