import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/fleet_work_record.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import 'fleet_work_record_detail_screen.dart';

/// Work records list with asset and work-type filters.
class FleetWorkRecordsListScreen extends ConsumerStatefulWidget {
  const FleetWorkRecordsListScreen({super.key});

  @override
  ConsumerState<FleetWorkRecordsListScreen> createState() =>
      _FleetWorkRecordsListScreenState();
}

class _FleetWorkRecordsListScreenState
    extends ConsumerState<FleetWorkRecordsListScreen> {
  final _service = FleetService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Work Records'),
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<FleetWorkRecord>>(
        stream: _service.watchWorkRecords(limit: 100),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final records = snapshot.data ?? [];
          if (records.isEmpty) {
            return const Center(
              child: Text(
                  'No work records yet.\nTap "Log Work" to add the first one.',
                  textAlign: TextAlign.center),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: records.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) =>
                WorkRecordTile(record: records[index]),
          );
        },
      ),
    );
  }
}

/// Shared work record tile used in list view and Fleet Home.
class WorkRecordTile extends StatelessWidget {
  const WorkRecordTile({super.key, required this.record});
  final FleetWorkRecord record;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final dateFmt = DateFormat('d MMM');

    return Card(
      color: colors?.cardSurface,
      child: ListTile(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              FleetWorkRecordDetailScreen(workRecordId: record.id!),
        )),
        leading: CircleAvatar(
          backgroundColor: kBrandOrange,
          foregroundColor: Colors.white,
          child: const Icon(Icons.build, size: 18),
        ),
        title: Text(record.title,
            style: const TextStyle(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${record.assetName}  •  ${record.workTypeName}',
              style: TextStyle(color: colors?.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(record.workNumber,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        color: colors?.textMuted,
                        fontSize: 11)),
                const Spacer(),
                Text('${record.labourHours} h',
                    style: TextStyle(
                        color: colors?.textMuted, fontSize: 11)),
                const SizedBox(width: 8),
                Text(dateFmt.format(record.startDate),
                    style: TextStyle(
                        color: colors?.textMuted, fontSize: 11)),
                const SizedBox(width: 8),
                if (record.hasCostLines)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(4)),
                    child: const Text('Costed',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
