import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../constants/collections.dart';
import '../widgets/impression_app_bar.dart';
import '../widgets/impression_tip_banner.dart';

/// Life review: cycle header, events, mech/elec, linked dailies.
class ImpressionCycleDetailScreen extends StatelessWidget {
  final String cycleId;

  const ImpressionCycleDetailScreen({super.key, required this.cycleId});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: const ImpressionAppBar(title: 'Cycle life review'),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(Collections.impressionCycles)
            .doc(cycleId)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.data!.exists) {
            return Center(child: Text('Cycle not found', style: TextStyle(color: onSurface)));
          }
          final d = snap.data!.data()!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ImpressionTipBanner(
                tipId: 'cycle_detail',
                text: ImpressionTipBanner.tips['cycle_detail']!,
              ),
              Text(
                d['cycleNo']?.toString() ?? cycleId,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: onSurface),
              ),
              Text(
                '${d['shaftNo']} / ${d['sleeveId']} · ${d['pressId']} · ${d['state']}',
                style: TextStyle(color: onSurface),
              ),
              if (d['esaSuitability'] != null)
                Text('ESA: ${d['esaSuitability']}', style: TextStyle(color: onSurface)),
              if (d['rematch'] == true)
                Text(
                  'Rematch: ${d['rematchReason'] ?? "yes"}',
                  style: TextStyle(color: onSurface),
                ),
              const Divider(height: 24),
              Text('Mechanical', style: TextStyle(fontWeight: FontWeight.bold, color: onSurface)),
              Text(_pretty(d['mechanical']), style: TextStyle(color: onSurface)),
              const SizedBox(height: 12),
              Text('Electrical', style: TextStyle(fontWeight: FontWeight.bold, color: onSurface)),
              Text(_pretty(d['electrical']), style: TextStyle(color: onSurface)),
              const SizedBox(height: 12),
              Text('Install / remove', style: TextStyle(fontWeight: FontWeight.bold, color: onSurface)),
              Text('Install: ${_pretty(d['install'])}', style: TextStyle(color: onSurface)),
              Text('Remove: ${_pretty(d['remove'])}', style: TextStyle(color: onSurface)),
              if (d['sendOut'] != null)
                Text('Send-out: ${_pretty(d['sendOut'])}', style: TextStyle(color: onSurface)),
              const Divider(height: 24),
              Text('Events', style: TextStyle(fontWeight: FontWeight.bold, color: onSurface)),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection(Collections.impressionCycles)
                    .doc(cycleId)
                    .collection('events')
                    .orderBy('at', descending: true)
                    .limit(50)
                    .snapshots(),
                builder: (context, es) {
                  final docs = es.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Text('No events yet', style: TextStyle(color: onSurface));
                  }
                  return Column(
                    children: docs.map((e) {
                      final m = e.data();
                      return ListTile(
                        dense: true,
                        title: Text('${m['type']}', style: TextStyle(color: onSurface)),
                        subtitle: Text(
                          '${m['byName'] ?? m['byClock'] ?? ''}',
                          style: TextStyle(color: onSurface.withValues(alpha: 0.75)),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const Divider(height: 24),
              Text(
                'Daily IR (install life)',
                style: TextStyle(fontWeight: FontWeight.bold, color: onSurface),
              ),
              _DailyHits(cycleId: cycleId, collection: Collections.impressionDailyIr),
              const SizedBox(height: 12),
              Text('Daily ESA', style: TextStyle(fontWeight: FontWeight.bold, color: onSurface)),
              _DailyHits(cycleId: cycleId, collection: Collections.impressionDailyEsa),
            ],
          );
        },
      ),
    );
  }

  static String _pretty(dynamic v) {
    if (v == null) return '—';
    if (v is Map) {
      return v.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    }
    return v.toString();
  }
}

class _DailyHits extends StatelessWidget {
  final String cycleId;
  final String collection;

  const _DailyHits({required this.cycleId, required this.collection});

  @override
  Widget build(BuildContext context) {
    // Cost-conscious: recent dailies limit; filter client-side for cycleId in units
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(collection)
          .orderBy('at', descending: true)
          .limit(40)
          .snapshots(),
      builder: (context, snap) {
        final onSurface = Theme.of(context).colorScheme.onSurface;
        final hits = <Widget>[];
        for (final d in snap.data?.docs ?? []) {
          final m = d.data();
          final units = m['units'];
          if (units is! Map) continue;
          for (final e in units.entries) {
            final line = e.value;
            if (line is Map && line['cycleId'] == cycleId) {
              hits.add(ListTile(
                dense: true,
                title: Text(
                  '${m['dateKey']} · unit ${e.key}',
                  style: TextStyle(color: onSurface),
                ),
                subtitle: Text(
                  line['overMax'] == true
                      ? 'OVER MAX ${line['overMaxFields'] ?? ""} · ${line['condition'] ?? ""}'
                      : '${line['condition'] ?? line['conditionCharge'] ?? "ok"}',
                  style: TextStyle(color: onSurface.withValues(alpha: 0.75)),
                ),
              ));
            }
          }
        }
        if (hits.isEmpty) {
          return Text('No linked daily checks yet', style: TextStyle(color: onSurface));
        }
        return Column(children: hits);
      },
    );
  }
}
