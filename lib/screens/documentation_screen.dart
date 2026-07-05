import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart' show currentEmployee;
import '../models/doc_entry.dart';
import '../providers/fleet_provider.dart';
import '../providers/security_provider.dart';
import '../providers/waste_provider.dart';
import '../utils/doc_catalog.dart';
import '../widgets/ctp_app_bar.dart';
import 'doc_viewer_screen.dart';

class DocumentationScreen extends ConsumerWidget {
  const DocumentationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleetSettings = ref.watch(fleetSettingsProvider).asData?.value;
    final wasteSettings = ref.watch(wasteSettingsProvider).asData?.value;
    final securitySettings =
        ref.watch(securitySettingsProvider).asData?.value;
    final docs = docsForUser(
      currentEmployee,
      fleetSettings,
      wasteSettings,
      securitySettings,
    );

    return Scaffold(
      appBar: const CtpAppBar(title: 'Documentation'),
      body: docs.isEmpty ? _buildEmpty(context) : _buildList(context, docs),
    );
  }

  Widget _buildList(BuildContext context, List<DocEntry> docs) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              "Guides, references, and troubleshooting — tailored to your role.",
              style: TextStyle(fontSize: 13, color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          );
        }
        final doc = docs[i - 1];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(doc.icon, color: const Color(0xFFFF8C42)),
            title: Text(doc.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(doc.description),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DocViewerScreen(entry: doc)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              "No docs are available for your role yet.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            SizedBox(height: 6),
            Text(
              "Ask your manager for the docs portal link.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
