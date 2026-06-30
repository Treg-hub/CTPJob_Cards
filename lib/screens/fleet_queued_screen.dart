import 'package:flutter/material.dart';
import '../utils/persona_audit.dart';

import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/fleet_app_bar.dart';

/// Lightweight view of fleet items waiting in the offline sync queue.
/// Mirrors WasteQueuedScreen: list with type/reference/age, retry all,
/// per-item error + manual retry, and per-item remove (with confirmation).
class FleetQueuedScreen extends StatefulWidget {
  const FleetQueuedScreen({super.key});

  @override
  State<FleetQueuedScreen> createState() => _FleetQueuedScreenState();
}

class _FleetQueuedScreenState extends State<FleetQueuedScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _retrying = false;
  String? _retryingItemId;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  void _loadItems() {
    setState(() => _items = SyncService().getQueuedFleetDetails());
  }

  Future<void> _retryAll() async {
    setState(() => _retrying = true);
    final before = _items.length;
    try {
      await SyncService().processNow();
    } catch (_) {}
    if (!mounted) return;
    _loadItems();
    setState(() => _retrying = false);
    final synced = before - _items.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          synced > 0
              ? '$synced item(s) synced. ${_items.length} still waiting.'
              : _items.isEmpty
                  ? 'Everything is synced.'
                  : 'Still waiting — items will retry automatically when the connection improves.',
        ),
        backgroundColor: synced > 0 || _items.isEmpty ? Colors.green : null,
      ),
    );
  }

  Future<void> _retryItem(Map<String, dynamic> item) async {
    if (_retrying) return;
    final itemId = item['id'] as String;
    setState(() {
      _retrying = true;
      _retryingItemId = itemId;
    });
    try {
      final ok = await SyncService().retrySpecificQueuedFleetItem(item);
      if (!mounted) return;
      _loadItems();
      final type = item['type'] as String;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Synced: $type'
                : 'Retry failed for $type — see error below.',
          ),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _retrying = false;
          _retryingItemId = null;
        });
      }
    }
  }

  Future<void> _removeItem(Map<String, dynamic> item) async {
    if (!guardPersonaSubmit(context)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from queue?'),
        content: Text(
          'This ${(item['type'] as String).toLowerCase()} has not been synced '
          'to the server yet. Removing it discards it permanently.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await SyncService().removeQueuedItem(
      collection: item['collection'] as String,
      documentId: item['id'] as String,
    );
    _loadItems();
  }

  IconData _iconFor(String type) {
    if (type.startsWith('Photo')) return Icons.photo_outlined;
    if (type.startsWith('Work record')) return Icons.build_outlined;
    if (type.startsWith('Problem')) return Icons.report_problem_outlined;
    if (type.startsWith('Cost')) return Icons.attach_money;
    return Icons.cloud_upload_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).appColors.textMuted;

    return Scaffold(
      appBar: FleetAppBar(
        title: 'Waiting to Sync',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload list',
            onPressed: _loadItems,
          ),
        ],
      ),
      bottomNavigationBar: _items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  onPressed: _retrying ? null : _retryAll,
                  icon: _retrying && _retryingItemId == null
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_sync_outlined),
                  label: Text(_retrying && _retryingItemId == null
                      ? 'Syncing…'
                      : 'Retry sync now'),
                  style: FilledButton.styleFrom(
                    backgroundColor: kBrandOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
      body: _items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_done_outlined,
                        size: 48, color: Colors.green),
                    const SizedBox(height: 12),
                    const Text(
                      'Everything is synced.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Reports and jobs you save offline will appear here '
                      'until they reach the server.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final item = _items[index];
                final type = item['type'] as String;
                final ref = item['ref'] as String?;
                final lastError = item['lastError'] as String?;
                final itemId = item['id'] as String;
                final isRetryingThis =
                    _retrying && _retryingItemId == itemId;

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              backgroundColor:
                                  kBrandOrange.withValues(alpha: 0.15),
                              foregroundColor: kBrandOrange,
                              child: Icon(_iconFor(type), size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    type,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      if (ref != null && ref.isNotEmpty) ref,
                                      'queued ${item['age']}',
                                    ].join('  •  '),
                                    style:
                                        TextStyle(fontSize: 12, color: muted),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              tooltip: 'Remove from queue',
                              onPressed: _retrying ? null : () => _removeItem(item),
                            ),
                          ],
                        ),
                        if (lastError != null && lastError.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.error_outline,
                                    size: 16, color: Colors.red),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    lastError,
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _retrying
                                ? null
                                : () => _retryItem(item),
                            icon: isRetryingThis
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.refresh, size: 16),
                            label: Text(isRetryingThis
                                ? 'Retrying…'
                                : 'Retry this item'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}