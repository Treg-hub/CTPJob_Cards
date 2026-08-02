import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../constants/collections.dart';

/// Life review: cycle header, events, mech/elec, linked dailies.
class ImpressionCycleDetailScreen extends StatelessWidget {
  final String cycleId;

  const ImpressionCycleDetailScreen({super.key, required this.cycleId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cycle life review')),
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
            return const Center(child: Text('Cycle not found'));
          }
          final d = snap.data!.data()!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(d['cycleNo']?.toString() ?? cycleId,
                  style: Theme.of(context).textTheme.titleLarge),
              Text('${d['shaftNo']} / ${d['sleeveId']} · ${d['pressId']} · ${d['state']}'),
              if (d['esaSuitability'] != null) Text('ESA: ${d['esaSuitability']}'),
              if (d['rematch'] == true) Text('Rematch: ${d['rematchReason'] ?? "yes"}'),
              const Divider(height: 24),
              const Text('Mechanical', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(_pretty(d['mechanical'])),
              const SizedBox(height: 12),
              const Text('Electrical', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(_pretty(d['electrical'])),
              const SizedBox(height: 12),
              const Text('Install / remove', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Install: ${_pretty(d['install'])}'),
              Text('Remove: ${_pretty(d['remove'])}'),
              if (d['sendOut'] != null) Text('Send-out: ${_pretty(d['sendOut'])}'),
              const Divider(height: 24),
              const Text('Events', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  if (docs.isEmpty) return const Text('No events yet');
                  return Column(
                    children: docs.map((e) {
                      final m = e.data();
                      return ListTile(
                        dense: true,
                        title: Text('${m['type']}'),
                        subtitle: Text('${m['byName'] ?? m['byClock'] ?? ''}'),
                      );
                    }).toList(),
                  );
                },
              ),
              const Divider(height: 24),
              const Text('Daily IR (install life)', style: TextStyle(fontWeight: FontWeight.bold)),
              _DailyHits(cycleId: cycleId, collection: Collections.impressionDailyIr),
              const SizedBox(height: 12),
              const Text('Daily ESA', style: TextStyle(fontWeight: FontWeight.bold)),
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
        final hits = <Widget>[];
        for (final d in snap.data?.docs ?? []) {
          final m = d.data();
          final units = m['units'];
          if (units is! Map) continue;
          var match = false;
          for (final e in units.entries) {
            final line = e.value;
            if (line is Map && line['cycleId'] == cycleId) {
              match = true;
              hits.add(ListTile(
                dense: true,
                title: Text('${m['dateKey']} · unit ${e.key}'),
                subtitle: Text(
                  line['overMax'] == true
                      ? 'OVER MAX ${line['overMaxFields'] ?? ""} · ${line['condition'] ?? ""}'
                      : '${line['condition'] ?? line['conditionCharge'] ?? "ok"}',
                ),
              ));
            }
          }
          if (!match) continue;
        }
        if (hits.isEmpty) return const Text('No linked daily checks yet');
        return Column(children: hits);
      },
    );
  }
}
