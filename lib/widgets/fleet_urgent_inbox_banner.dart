import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../constants/collections.dart';
import '../main.dart' show currentEmployee;
import '../utils/fleet_navigation.dart';

const _urgentFleetInboxTypes = {'fleet_oos_issue', 'fleet_high_issue'};

/// Surfaces unread OOS/high fleet inbox items while CF push remains deferred.
/// Hides (and auto-clears) inbox rows whose linked issue is already resolved.
class FleetUrgentInboxBanner extends StatefulWidget {
  const FleetUrgentInboxBanner({super.key});

  @override
  State<FleetUrgentInboxBanner> createState() => _FleetUrgentInboxBannerState();
}

class _FleetUrgentInboxBannerState extends State<FleetUrgentInboxBanner> {
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _activeUrgent = [];
  bool _resolving = false;
  Object? _lastRawKey;

  Future<void> _resolveUrgent(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> raw,
  ) async {
    if (_resolving) return;
    _resolving = true;
    try {
      final active = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in raw) {
        final issueId = doc.data()['issueId'] as String?;
        if (issueId == null || issueId.isEmpty) {
          active.add(doc);
          continue;
        }
        final issueSnap = await FirebaseFirestore.instance
            .collection(Collections.fleetIssues)
            .doc(issueId)
            .get();
        final status = issueSnap.data()?['status'] as String? ?? 'open';
        if (status == 'open' || status == 'acknowledged') {
          active.add(doc);
        } else {
          // Stale alert — issue fixed but inbox row still unread.
          await doc.reference.update({
            'read': true,
            'readAt': FieldValue.serverTimestamp(),
          });
        }
      }
      if (mounted) setState(() => _activeUrgent = active);
    } finally {
      _resolving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final clockNo = currentEmployee?.clockNo;
    if (clockNo == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(Collections.notificationInbox)
          .doc(clockNo)
          .collection(Collections.notificationInboxItems)
          .where('read', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final urgent = docs.where((d) {
          final type = d.data()['type'] as String? ?? '';
          return _urgentFleetInboxTypes.contains(type);
        }).toList();

        final rawKey = urgent.map((d) => d.id).join(',');
        if (rawKey != _lastRawKey) {
          _lastRawKey = rawKey;
          if (urgent.isEmpty) {
            if (_activeUrgent.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _activeUrgent = []);
              });
            }
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _resolveUrgent(urgent);
            });
          }
        }

        if (_activeUrgent.isEmpty) return const SizedBox.shrink();

        final firstIssueId = _activeUrgent.first.data()['issueId'] as String?;

        return Material(
          color: Colors.red.shade50,
          child: InkWell(
            onTap: firstIssueId != null && firstIssueId.isNotEmpty
                ? () => navigateToFleetIssue(firstIssueId)
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.red.shade800, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _activeUrgent.length == 1
                          ? '1 urgent fleet alert in your inbox — tap to open'
                          : '${_activeUrgent.length} urgent fleet alerts in your inbox — tap to open first',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade900,
                      ),
                    ),
                  ),
                  if (firstIssueId != null)
                    Icon(Icons.chevron_right,
                        color: Colors.red.shade800, size: 18),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}