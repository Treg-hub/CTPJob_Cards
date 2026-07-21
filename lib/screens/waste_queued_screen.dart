import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/sync_queue_item.dart';
import '../services/sync_service.dart';
import '../services/waste_service.dart';
import '../utils/formatters.dart';
import '../main.dart' show currentEmployee;
import '../theme/app_theme.dart';
import '../utils/persona_audit.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/waste_app_bar.dart';
import '../utils/screen_insets.dart';

/// Lightweight "Queued Operations" screen for pilots on WasteTrack.
///
/// Accessed by tapping the banner on WasteHomeScreen when count > 0.
/// Lists pending Hive queue items with type, load reference, and age.
///
/// - Theme-aware tiles (no light-on-light in dark mode).
/// - Live list via Hive [SyncService.queueListenable] so auto-sync drain updates UI.
/// - Snackbars cleared/refreshed when the queue drains so stale "still queued"
///   messages do not linger after a successful upload.
class WasteQueuedScreen extends StatefulWidget {
  const WasteQueuedScreen({super.key});

  @override
  State<WasteQueuedScreen> createState() => _WasteQueuedScreenState();
}

class _WasteQueuedScreenState extends State<WasteQueuedScreen> {
  final WasteService _wasteService = WasteService();
  List<Map<String, dynamic>> _lostMedia = [];
  bool _isProcessing = false;
  DateTime? _lastAttempt;
  int _lastWasteCount = -1;

  bool _effectiveWasteEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadFeatureStatus();
    _loadLostMedia();
    _lastWasteCount = SyncService().getQueuedWasteOperationCount();
  }

  Future<void> _loadLostMedia() async {
    final lost = await _wasteService.getRecentLostMediaAudit();
    if (mounted) setState(() => _lostMedia = lost);
  }

  Future<void> _loadFeatureStatus() async {
    final clock = currentEmployee?.clockNo;
    final enabled =
        await _wasteService.isWasteTrackEnabledForCurrentUser(clock);
    if (mounted) setState(() => _effectiveWasteEnabled = enabled);
  }

  /// Refresh snackbars when Hive queue shrinks (auto-sync or background drain).
  void _onQueueCountChanged(int wasteCount) {
    if (_lastWasteCount < 0) {
      _lastWasteCount = wasteCount;
      return;
    }
    if (wasteCount == _lastWasteCount) return;

    final prev = _lastWasteCount;
    _lastWasteCount = wasteCount;
    if (!mounted || _isProcessing) return;

    final messenger = ScaffoldMessenger.of(context);
    if (wasteCount >= prev) return;

    messenger.hideCurrentSnackBar();
    if (wasteCount == 0 && prev > 0) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            prev == 1
                ? 'Queued item uploaded successfully'
                : 'All $prev queued items uploaded successfully',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
      unawaited(_loadLostMedia());
    } else if (wasteCount > 0) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${prev - wasteCount} item(s) synced. $wasteCount remain queued.',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _retryAll() async {
    setState(() {
      _isProcessing = true;
      _lastAttempt = DateTime.now();
    });

    final before = SyncService().getQueuedWasteOperationCount();
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    try {
      await _wasteService.processOfflineWasteQueue();
      await SyncService().processNow();
      unawaited(_loadLostMedia());

      if (!mounted) return;
      final after = SyncService().getQueuedWasteOperationCount();
      _lastWasteCount = after;
      final processed = before - after;

      final String msg;
      final Color bg;
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

      messenger.showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: bg,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final after = SyncService().getQueuedWasteOperationCount();
      _lastWasteCount = after;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Retry failed: $e. $after items remain queued.'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _retryItem(Map<String, dynamic> item) async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _lastAttempt = DateTime.now();
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    try {
      final ok = await SyncService().retrySpecificQueuedWasteItem(item);
      if (!mounted) return;
      _lastWasteCount = SyncService().getQueuedWasteOperationCount();
      final typeLabel = (item['type'] as String?) ?? 'item';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Retried and synced: $typeLabel'
                : 'Retry attempted for $typeLabel. Still queued if transient issue.',
          ),
          backgroundColor: ok ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Per-item retry error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _removeItem(Map<String, dynamic> item) async {
    if (!guardPersonaSubmit(context)) return;
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    try {
      await SyncService().removeSpecificQueuedWasteItem(item);
      if (!mounted) return;
      _lastWasteCount = SyncService().getQueuedWasteOperationCount();
      final typeLabel = (item['type'] as String?) ?? 'item';
      messenger.showSnackBar(
        SnackBar(
          content: Text('Removed from queue: $typeLabel'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Remove error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
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

  /// Soft orange surface that stays dark enough in dark theme for readable text.
  Color _queueSurface(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const Color(0xFF3E2A14) : Colors.orange.shade50;
  }

  Color _queueAccent(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? Colors.orange.shade300 : Colors.orange.shade800;
  }

  Color _queueBannerBg(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const Color(0xFF3E2A14) : Colors.orange.shade50;
  }

  ValueListenable<Box<SyncQueueItem>>? _tryQueueListenable() {
    try {
      return SyncService().queueListenable;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_effectiveWasteEnabled) {
      final isAdminUser = role_utils.isWasteAdmin(currentEmployee);
      return Scaffold(
        appBar: WasteAppBar(
          title: 'Queued Operations',
          isOnSite: currentEmployee?.isOnSite,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                const Text(
                  'WasteTrack is currently disabled',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Contact an administrator to adjust access.',
                  style:
                      TextStyle(color: Theme.of(context).appColors.textMuted),
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).appColors.wasteGreen,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final listenable = _tryQueueListenable();
    if (listenable == null) {
      final items = SyncService().getQueuedWasteDetails();
      return _buildScaffold(context, items);
    }

    return ValueListenableBuilder<Box<SyncQueueItem>>(
      valueListenable: listenable,
      builder: (context, box, _) {
        final items = SyncService().getQueuedWasteDetails();
        final count = items.length;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _onQueueCountChanged(count);
        });
        return _buildScaffold(context, items);
      },
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    List<Map<String, dynamic>> items,
  ) {
    final count = items.length;
    return Scaffold(
      appBar: WasteAppBar(
        title: count > 0 ? 'Queued Operations ($count)' : 'Queued Operations',
        isOnSite: currentEmployee?.isOnSite,
      ),
      body: _buildQueueBody(context, items, count),
    );
  }

  Widget _buildQueueBody(
    BuildContext context,
    List<Map<String, dynamic>> items,
    int count,
  ) {
    final surface = _queueSurface(context);
    final accent = _queueAccent(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).appColors.textMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          color: _queueBannerBg(context),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            count > 0
                ? 'Pending offline waste operations. Auto-syncs on reconnect. Retry forces upload now.'
                : 'Queue is empty — all operations have synced or none were queued.',
            style: TextStyle(fontSize: 12, color: accent),
            textAlign: TextAlign.center,
          ),
        ),
        if (_lastAttempt != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(
              'Last retry attempt: ${formatSADateTime(_lastAttempt!)}',
              style: TextStyle(fontSize: 11, color: accent),
              textAlign: TextAlign.center,
            ),
          ),
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
                const Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: Colors.red),
                    SizedBox(width: 6),
                    Text(
                      'Media that could not be recovered',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.red,
                      ),
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
                      style: const TextStyle(fontSize: 11, color: Colors.red),
                    ),
                  );
                }),
                if (_lostMedia.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '+ ${_lostMedia.length - 5} more — see waste audit',
                      style: const TextStyle(fontSize: 11, color: Colors.red),
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
                            Icon(
                              Icons.check_circle_outline,
                              size: 72,
                              color: Theme.of(context).appColors.wasteGreen,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'All clear',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No queued waste operations.\nReturn to continue using WasteTrack.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: muted, fontSize: 14),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('Back to WasteTrack Home'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Theme.of(context).appColors.wasteGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: ScreenInsets.listPadding(
                        context,
                        horizontal: 8,
                        top: 4,
                      ),
                      itemCount: count,
                      separatorBuilder: (_, __) => const Divider(height: 4),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final loadRef = item['loadRef'] as String?;
                        final age = item['age'] as String;
                        final type = item['type'] as String;
                        final lastError = item['lastError'] as String?;

                        return Card(
                          elevation: 0,
                          color: surface,
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              _iconForType(type),
                              color: accent,
                              size: 20,
                            ),
                            title: Text(
                              type,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                                color: onSurface,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  loadRef != null ? '$loadRef • $age' : age,
                                  style: TextStyle(fontSize: 12, color: muted),
                                ),
                                if (lastError != null && lastError.isNotEmpty)
                                  Text(
                                    'Last error: $lastError — will retry automatically',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.red,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert,
                                  size: 18, color: accent),
                              tooltip: 'Actions for this item',
                              onSelected: (value) {
                                if (value == 'retry') {
                                  _retryItem(item);
                                } else if (value == 'remove') {
                                  _removeItem(item);
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem<String>(
                                  value: 'retry',
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.refresh,
                                          size: 16, color: accent),
                                      const SizedBox(width: 8),
                                      const Text('Retry this'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem<String>(
                                  value: 'remove',
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.delete_outline,
                                          size: 16, color: Colors.redAccent),
                                      SizedBox(width: 8),
                                      Text('Remove from queue'),
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
        if (count > 0)
          SafeBottomBar(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing
                        ? null
                        : () {
                            setState(() {});
                            unawaited(_loadLostMedia());
                          },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh List'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: BorderSide(color: accent.withValues(alpha: 0.5)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _retryAll,
                    icon: const Icon(Icons.cloud_upload),
                    label:
                        Text(_isProcessing ? 'Syncing…' : 'Retry All Now'),
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
    );
  }
}
