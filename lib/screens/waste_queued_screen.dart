import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import '../utils/persona_audit.dart';

import '../services/sync_service.dart';
import '../services/waste_service.dart';
import '../utils/formatters.dart';
import '../main.dart' show currentEmployee;
import '../theme/app_theme.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/waste_app_bar.dart';

/// Lightweight "Queued Operations" screen for pilots on WasteTrack.
/// 
/// Accessed by tapping the new section on WasteHomeScreen when count > 0.
/// Lists pending items from SyncService with type, load reference (if available), and age.
/// 
/// - Minimal UI: reuses WasteTrack green (#2E7D32) + orange accents.
/// - One primary "Retry All Now" action that exercises the existing processOfflineWasteQueue + SyncService.processNow paths.
/// - Live update of list after retry.
/// - No new heavy widgets, no Riverpod, no additional models.
/// - Safe if queue empty (friendly empty state).
class WasteQueuedScreen extends StatefulWidget {
  const WasteQueuedScreen({super.key});

  @override
  State<WasteQueuedScreen> createState() => _WasteQueuedScreenState();
}

class _WasteQueuedScreenState extends State<WasteQueuedScreen> {
  final WasteService _wasteService = WasteService();
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _lostMedia = [];
  bool _isProcessing = false;
  DateTime? _lastAttempt;

  // Explicit feature flag defense (defense-in-depth)
  bool _effectiveWasteEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadFeatureStatus();
    _loadItems();
    _loadLostMedia();
  }

  Future<void> _loadLostMedia() async {
    final lost = await _wasteService.getRecentLostMediaAudit();
    if (mounted) {
      setState(() => _lostMedia = lost);
    }
  }

  Future<void> _loadFeatureStatus() async {
    final clock = currentEmployee?.clockNo;
    final enabled = await _wasteService.isWasteTrackEnabledForCurrentUser(clock);
    if (mounted) {
      setState(() => _effectiveWasteEnabled = enabled);
    }
  }

  void _loadItems() {
    if (!mounted) return;
    setState(() {
      _items = SyncService().getQueuedWasteDetails();
    });
  }

  Future<void> _retryAll() async {
    setState(() {
      _isProcessing = true;
      _lastAttempt = DateTime.now();
    });

    final before = SyncService().getQueuedWasteOperationCount();

    try {
      await _wasteService.processOfflineWasteQueue();
      await SyncService().processNow();
      _loadItems();
      unawaited(_loadLostMedia());

      if (mounted) {
        final after = SyncService().getQueuedWasteOperationCount();
        final processed = before - after;

        String msg;
        Color bg;
        if (after == 0) {
          msg = processed > 0
              ? 'All $before queued items synced successfully (photos, signatures, loads, etc.).'
              : 'Sync complete. No queued items remaining.';
          bg = Colors.green;
        } else if (processed > 0) {
          msg = '$processed items synced. $after remain queued.';
          bg = Colors.orange;
        } else {
          msg = 'Retry attempted. $after items still queued.';
          bg = Colors.orange;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: bg),
        );
      }
    } catch (e) {
      if (mounted) {
        final after = SyncService().getQueuedWasteOperationCount();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Retry failed: $e. $after items remain queued.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _retryItem(Map<String, dynamic> item) async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _lastAttempt = DateTime.now();
    });

    try {
      final ok = await SyncService().retrySpecificQueuedWasteItem(item);
      _loadItems();

      if (mounted) {
        final typeLabel = (item['type'] as String?) ?? 'item';
        final msg = ok
            ? 'Retried and synced: $typeLabel'
            : 'Retry attempted for $typeLabel. Still queued if transient issue.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: ok ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Per-item retry error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _removeItem(Map<String, dynamic> item) async {
    if (!guardPersonaSubmit(context)) return;
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      await SyncService().removeSpecificQueuedWasteItem(item);
      _loadItems();

      if (mounted) {
        final typeLabel = (item['type'] as String?) ?? 'item';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed from queue: $typeLabel'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Remove error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  IconData _iconForType(String type) {
    final t = type.toLowerCase();
    if (t.contains('photo')) return Icons.photo_camera;
    if (t.contains('signature')) return Icons.draw;
    if (t.contains('load')) return Icons.local_shipping_outlined;
    if (t.contains('item')) return Icons.inventory_2_outlined;
    return Icons.cloud_upload_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final count = _items.length;

    // Explicit feature flag defense (defense-in-depth, matches other Waste screens)
    if (!_effectiveWasteEnabled) {
      final isAdminUser = role_utils.isWasteAdmin(currentEmployee); // reuse existing role helper
      return Scaffold(
        appBar: WasteAppBar(title: 'Queued Operations', isOnSite: currentEmployee?.isOnSite),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                const Text(
                  'WasteTrack is currently disabled',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Contact an administrator to adjust access.',
                  style: TextStyle(color: Theme.of(context).appColors.textMuted),
                  textAlign: TextAlign.center,
                ),
                if (isAdminUser) ...[
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await _wasteService.setWasteMasterEnabled(true);
                      await _loadFeatureStatus();
                    },
                    icon: const Icon(Icons.toggle_on),
                    label: const Text('Re-enable Master Flag (Admin)'),
                    style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).appColors.wasteGreen),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: WasteAppBar(
        title: count > 0 ? 'Queued Operations ($count)' : 'Queued Operations',
        isOnSite: currentEmployee?.isOnSite,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Non-intrusive status banner (matches existing Waste home banners)
          Container(
            width: double.infinity,
            color: Colors.orange.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              count > 0
                  ? 'Pending offline waste operations. Auto-syncs on reconnect. Retry forces upload now.'
                  : 'Queue is empty — all operations have synced or none were queued.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              textAlign: TextAlign.center,
            ),
          ),

          if (_lastAttempt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                'Last retry attempt: ${formatSADateTime(_lastAttempt!)}',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
                textAlign: TextAlign.center,
              ),
            ),

          // Permanently lost media (photo/signature file gone before sync).
          // Sourced from waste_audit media_lost entries — visible to Pulse too.
          if (_lostMedia.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.error_outline, size: 16, color: Colors.red),
                      SizedBox(width: 6),
                      Text(
                        'Media that could not be recovered',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.red),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ..._lostMedia.take(5).map((m) {
                    final mediaType =
                        (m['media_type'] as String?) == 'signature'
                            ? 'Signature'
                            : 'Photo';
                    final loadId = m['load_id'] as String? ?? 'unknown load';
                    final queuedAt = m['queued_at'] as DateTime?;
                    final agePart = queuedAt != null
                        ? ' (queued ${formatSADateTime(queuedAt)})'
                        : '';
                    return Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '$mediaType for load $loadId could not be recovered$agePart',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.red),
                      ),
                    );
                  }),
                  if (_lostMedia.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '+ ${_lostMedia.length - 5} more — see waste audit',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),

          Expanded(
            child: _isProcessing
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                    ),
                  )
                : (count == 0
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline, size: 72, color: Theme.of(context).appColors.wasteGreen),
                              const SizedBox(height: 16),
                              const Text(
                                'All clear',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No queued waste operations.\nReturn to continue using WasteTrack.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Theme.of(context).appColors.textMuted, fontSize: 14),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.arrow_back),
                                label: const Text('Back to WasteTrack Home'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).appColors.wasteGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        itemCount: count,
                        separatorBuilder: (context, index) => const Divider(height: 4),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final loadRef = item['loadRef'] as String?;
                          final age = item['age'] as String;
                          final type = item['type'] as String;
                          final lastError = item['lastError'] as String?;

                          return Card(
                            elevation: 0,
                            color: Colors.orange.shade50,
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                _iconForType(type),
                                color: Colors.orange.shade700,
                                size: 20,
                              ),
                              title: Text(
                                type,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    loadRef != null ? '$loadRef • $age' : age,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if (lastError != null && lastError.isNotEmpty)
                                    Text(
                                      'Last error: $lastError — will retry automatically',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.red),
                                    ),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert, size: 18, color: Colors.orange.shade700),
                                tooltip: 'Actions for this item',
                                onSelected: (value) {
                                  if (value == 'retry') {
                                    _retryItem(item);
                                  } else if (value == 'remove') {
                                    _removeItem(item);
                                  }
                                },
                                itemBuilder: (context) => <PopupMenuEntry<String>>[
                                  PopupMenuItem<String>(
                                    value: 'retry',
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.refresh, size: 16, color: Colors.orange.shade700),
                                        const SizedBox(width: 8),
                                        const Text('Retry this'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'remove',
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                                        const SizedBox(width: 8),
                                        const Text('Remove from queue'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      )),
          ),

          // Bottom action area — easy retry (prominent but contained)
          if (count > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _loadItems,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh List'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange.shade700,
                        side: BorderSide(color: Colors.orange.shade300),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _retryAll,
                      icon: const Icon(Icons.cloud_upload),
                      label: Text(_isProcessing ? 'Syncing…' : 'Retry All Now'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
