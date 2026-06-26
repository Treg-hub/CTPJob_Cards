import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/security_entry.dart';
import '../services/security_service.dart';
import '../theme/app_theme.dart';
import '../utils/screen_insets.dart';

/// Lists vehicles currently on site (latest direction per reg is in).
class SecurityOnSiteScreen extends StatelessWidget {
  const SecurityOnSiteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = SecurityService();
    final dateFmt = DateFormat('dd MMM yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('On Site')),
      body: StreamBuilder<List<SecurityEntry>>(
        stream: service.watchRecentEntries(limit: 300),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final onSite = service.computeOnSite(snap.data ?? []);
          if (onSite.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No vehicles currently on site.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              12,
              12,
              12,
              ScreenInsets.scrollBottomFullScreen(context),
            ),
            itemCount: onSite.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final e = onSite[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: kBrandOrange.withValues(alpha: 0.15),
                    child: const Icon(Icons.directions_car, color: kBrandOrange),
                  ),
                  title: Text(
                    e.vehicleReg ?? '—',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.driverName ?? e.visitorName ?? '—'),
                      if (e.contractorName != null)
                        Text(e.contractorName!,
                            style: const TextStyle(fontSize: 12)),
                      if (e.gateName != null)
                        Text('Gate: ${e.gateName}',
                            style: const TextStyle(fontSize: 12)),
                      if (e.loggedAt != null)
                        Text(
                          'Since ${dateFmt.format(e.loggedAt!.toLocal())}',
                          style: const TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}