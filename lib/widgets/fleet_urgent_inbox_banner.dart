import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../main.dart' show currentEmployee;
import '../utils/fleet_navigation.dart';

const _urgentFleetInboxTypes = {'fleet_oos_issue', 'fleet_high_issue'};

/// Surfaces unread OOS/high fleet inbox items while CF push remains deferred.
class FleetUrgentInboxBanner extends StatelessWidget {
  const FleetUrgentInboxBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final clockNo = currentEmployee?.clockNo;
    if (clockNo == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notification_inbox')
          .doc(clockNo)
          .collection('items')
          .where('read', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final urgent = docs.where((d) {
          final type = d.data()['type'] as String? ?? '';
          return _urgentFleetInboxTypes.contains(type);
        }).toList();
        if (urgent.isEmpty) return const SizedBox.shrink();

        final firstIssueId = urgent.first.data()['issueId'] as String?;

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
                      urgent.length == 1
                          ? '1 urgent fleet alert in your inbox — tap to open'
                          : '${urgent.length} urgent fleet alerts in your inbox — tap to open first',
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