import 'package:flutter/material.dart';
import '../utils/persona_audit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show currentEmployee;
import '../models/parsed_document.dart';
import '../models/security_deny_entry.dart';
import '../models/security_entry.dart';
import '../models/security_gate.dart';
import '../models/security_settings.dart';
import '../providers/security_provider.dart';
import '../services/security_service.dart';
import '../theme/app_theme.dart';
import '../utils/security_error_messages.dart';
import '../widgets/security_suggestion_field.dart';
import 'security_document_scan_screen.dart';
import '../utils/screen_insets.dart';

/// On-foot visitor entry — optional ID scan, purpose, deny check by name.
class SecurityOnFootVisitorScreen extends ConsumerStatefulWidget {
  const SecurityOnFootVisitorScreen({super.key});

  @override
  ConsumerState<SecurityOnFootVisitorScreen> createState() =>
      _SecurityOnFootVisitorScreenState();
}

class _SecurityOnFootVisitorScreenState
    extends ConsumerState<SecurityOnFootVisitorScreen> {
  final _service = SecurityService();
  final _nameCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController();
  ParsedDocument? _idDoc;
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _companyCtrl.dispose();
    _purposeCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanId() async {
    final result = await Navigator.push<ParsedDocument>(
      context,
      MaterialPageRoute(
        builder: (_) => const SecurityDocumentScanScreen(
          title: 'Scan Visitor ID',
          expectedType: SecurityDocumentType.idDocument,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _idDoc = result;
      if (result.fullName != null) _nameCtrl.text = result.fullName!;
    });
  }

  Future<void> _submit(
    SecuritySettings settings,
    SecurityGate? gate,
    List<SecurityDenyEntry> denyList,
  ) async {
    if (!guardPersonaSubmit(context)) return;
    final emp = currentEmployee;
    if (emp == null || gate == null) return;
    final actor = resolveWriteActor(emp)!;

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showError('Visitor name is required.');
      return;
    }

    if (settings.purposeOfVisitRequired && _purposeCtrl.text.trim().isEmpty) {
      _showError('Purpose of visit is required.');
      return;
    }

    // Visitor ID scan is optional on mobile — no separate settings flag yet.

    final deny = _service.matchDenyList(
      denyList,
      driverName: name,
    );

    setState(() => _submitting = true);
    try {
      if (deny != null) {
        final blocked = await _service.createEntry(
          data: {
            'gate_id': gate.id,
            'gate_name': gate.name,
            'direction': SecurityDirection.in_.value,
            'entry_type': SecurityEntryType.onFootVisitor.value,
            'visitor_name': name,
            'driver_name': name,
            'deny_blocked': true,
            'deny_reason': deny.reason,
            'logged_by_clock_no': actor.clockNo,
            'logged_by_name': actor.name,
            'logged_at': DateTime.now().toIso8601String(),
          },
        );
        await _service.notifyDenyEntry(
          gateId: gate.id,
          gateName: gate.name,
          vehicleReg: deny.vehicleReg.isNotEmpty ? deny.vehicleReg : 'ON-FOOT',
          driverName: name,
          denyReason: deny.reason,
          entryId: blocked.id,
        );
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Deny list — entry blocked'),
            content: Text('Visitor blocked.\n\nReason: ${deny.reason}'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.pop(context);
        return;
      }

      final result = await _service.createEntry(
        data: {
          'gate_id': gate.id,
          'gate_name': gate.name,
          'direction': SecurityDirection.in_.value,
          'entry_type': SecurityEntryType.onFootVisitor.value,
          'visitor_name': name,
          'purpose': _purposeCtrl.text.trim().isEmpty
              ? null
              : _purposeCtrl.text.trim(),
          if (_hostCtrl.text.trim().isNotEmpty)
            'host_name': _hostCtrl.text.trim(),
          if (_companyCtrl.text.trim().isNotEmpty)
            'company_name': _companyCtrl.text.trim(),
          'logged_by_clock_no': actor.clockNo,
          'logged_by_name': actor.name,
          'logged_at': DateTime.now().toIso8601String(),
          'id_scan_captured': _idDoc != null,
          if (_idDoc?.idNumber != null) 'id_number': _idDoc!.idNumber,
          if (_idDoc?.expiryDate != null)
            'id_expiry': _idDoc!.expiryDate!.toIso8601String(),
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.queuedOffline
                ? 'Visitor queued offline'
                : 'Visitor logged: ${result.entryNumber ?? result.id}',
          ),
          backgroundColor: kBrandOrange,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      _showError(friendlySecurityError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(securitySettingsProvider).valueOrNull;
    final gate = ref.watch(selectedSecurityGateProvider);

    final denyList =
        ref.watch(securityDenyListProvider).valueOrNull ?? <SecurityDenyEntry>[];

    return Scaffold(
      appBar: AppBar(title: const Text('On-Foot Visitor')),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<String>>(
              stream: _service.watchLookupSuggestions('host'),
              builder: (context, hostSnap) {
                return StreamBuilder<List<String>>(
                  stream: _service.watchLookupSuggestions('company'),
                  builder: (context, companySnap) {
                    return RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(securityDenyListProvider);
                        await ref.read(securityDenyListProvider.future);
                      },
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (gate == null)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('No gate selected.'),
                                    const SizedBox(height: 8),
                                    OutlinedButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Choose a gate'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          OutlinedButton.icon(
                            onPressed: _scanId,
                            icon: const Icon(Icons.badge_outlined),
                            label: const Text('Scan ID (optional)'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Visitor name *',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SecuritySuggestionField(
                            controller: _hostCtrl,
                            label: 'Host (optional)',
                            suggestions: hostSnap.data ?? [],
                          ),
                          const SizedBox(height: 12),
                          SecuritySuggestionField(
                            controller: _companyCtrl,
                            label: 'Company (optional)',
                            suggestions: companySnap.data ?? [],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _purposeCtrl,
                            decoration: InputDecoration(
                              labelText: settings.purposeOfVisitRequired
                                  ? 'Purpose of visit *'
                                  : 'Purpose of visit',
                              border: const OutlineInputBorder(),
                            ),
                            maxLines: 2,
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
      bottomNavigationBar: settings == null
          ? null
          : SafeBottomBar(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(
                onPressed: _submitting || gate == null
                    ? null
                    : () => _submit(settings, gate, denyList),
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
                    : const Text('Log visitor in'),
              ),
            ),
    );
  }
}