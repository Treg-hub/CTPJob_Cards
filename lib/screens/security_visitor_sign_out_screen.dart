import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee;
import '../models/security_entry.dart';
import '../providers/security_provider.dart';
import '../services/security_service.dart';
import '../theme/app_theme.dart';
import '../utils/persona_audit.dart';
import '../utils/screen_insets.dart';
import '../utils/security_error_messages.dart';

/// Confirmation screen to sign out an on-foot visitor from Tab 2 of the
/// on-site screen. No occupant stepper — pedestrians are singular, unlike
/// vehicle exits which can carry passengers.
class SecurityVisitorSignOutScreen extends ConsumerStatefulWidget {
  const SecurityVisitorSignOutScreen({super.key, required this.entry});

  final SecurityEntry entry;

  @override
  ConsumerState<SecurityVisitorSignOutScreen> createState() =>
      _SecurityVisitorSignOutScreenState();
}

class _SecurityVisitorSignOutScreenState
    extends ConsumerState<SecurityVisitorSignOutScreen> {
  final _service = SecurityService();
  bool _submitting = false;

  Future<void> _submit() async {
    if (!guardPersonaSubmit(context)) return;
    final emp = currentEmployee;
    final gate = ref.read(selectedSecurityGateProvider);
    if (emp == null || gate == null) return;
    final actor = resolveWriteActor(emp)!;

    setState(() => _submitting = true);
    try {
      final result = await _service.signOutVisitor(
        onSiteEntry: widget.entry,
        gateId: gate.id,
        gateName: gate.name,
        loggedByClockNo: actor.clockNo,
        loggedByName: emp.name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.queuedOffline
                ? 'Sign-out queued offline'
                : 'Signed out: ${result.entryNumber ?? result.id}',
          ),
          backgroundColor: kBrandOrange,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlySecurityError(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final gate = ref.watch(selectedSecurityGateProvider);
    final dateFmt = DateFormat('dd MMM yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Sign Out Visitor')),
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          ScreenInsets.scrollBottomFullScreen(context),
        ),
        child: Card(
          child: ListTile(
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
              mainAxisSize: MainAxisSize.min,
              children: [
                if (e.hostName != null)
                  Text('Host: ${e.hostName}', style: const TextStyle(fontSize: 12)),
                if (e.companyName != null)
                  Text('Company: ${e.companyName}', style: const TextStyle(fontSize: 12)),
                if (e.purpose != null)
                  Text('Purpose: ${e.purpose}', style: const TextStyle(fontSize: 12)),
                if (e.gateName != null)
                  Text('Gate in: ${e.gateName}', style: const TextStyle(fontSize: 12)),
                if (e.loggedAt != null)
                  Text(
                    'Signed in: ${dateFmt.format(e.loggedAt!.toLocal())}',
                    style: const TextStyle(fontSize: 12),
                  ),
                if (gate == null) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'No gate selected — go back and choose a gate before signing out.',
                    style: TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ],
              ],
            ),
            isThreeLine: true,
          ),
        ),
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
              : const Text('Confirm sign-out'),
        ),
      ),
    );
  }
}
