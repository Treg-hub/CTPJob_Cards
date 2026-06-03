import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'dart:typed_data';

import '../services/waste_service.dart';
import '../services/sync_service.dart';
import '../main.dart' show currentEmployee;
import '../theme/app_theme.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/waste_app_bar.dart';

/// Signature capture screen for driver sign-off on Waste Loads.
/// Uses the `signature` package (add to pubspec if not already present).
class WasteSignatureScreen extends StatefulWidget {
  final String loadNumber;

  const WasteSignatureScreen({super.key, required this.loadNumber});

  @override
  State<WasteSignatureScreen> createState() => _WasteSignatureScreenState();
}

class _WasteSignatureScreenState extends State<WasteSignatureScreen> {
  final SignatureController _controller = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  final WasteService _wasteService = WasteService();
  bool _effectiveWasteEnabled = true;
  bool _pilotModeActive = false;
  String? _userClock;
  bool get _isAdmin => role_utils.isWasteAdmin(currentEmployee);

  @override
  void initState() {
    super.initState();
    _loadFeatureStatus();
    _wasteService.processOfflineWasteQueue();
  }

  Future<void> _loadFeatureStatus() async {
    final clock = currentEmployee?.clockNo;
    final enabled = await _wasteService.isWasteTrackEnabledForCurrentUser(clock);
    final pilot = await _wasteService.isPilotModeEnabled();
    if (mounted) {
      setState(() {
        _effectiveWasteEnabled = enabled;
        _pilotModeActive = pilot;
        _userClock = clock;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveSignature() async {
    if (_controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a signature')),
      );
      return;
    }

    // Drain any queued waste data before returning (consistent resilience across all Waste screens)
    await _wasteService.processOfflineWasteQueue();

    final Uint8List? data = await _controller.toPngBytes();
    if (data != null && mounted) {
      // In real flow: upload to Storage via WasteService and return URL
      Navigator.pop(context, data); // Return bytes for now
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_effectiveWasteEnabled) {
      return Scaffold(
        appBar: WasteAppBar(title: 'Driver Signature', isOnSite: currentEmployee?.isOnSite),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.block, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  _pilotModeActive ? 'WasteTrack is in pilot mode' : 'WasteTrack is currently disabled',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _pilotModeActive
                      ? 'Your clock number (${_userClock ?? 'unknown'}) is not included in the pilot list.'
                      : 'The feature flag has disabled WasteTrack (safety valve).',
                  style: TextStyle(color: Theme.of(context).appColors.textMuted),
                  textAlign: TextAlign.center,
                ),
                if (_isAdmin) ...[
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
        title: 'Driver Signature - ${widget.loadNumber}',
        isOnSite: currentEmployee?.isOnSite,
        actions: [
          if (SyncService().getQueuedWasteOperationCount() > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: 'Queued offline: waste loads/items, photos, signatures, weighbridge updates, audits etc.',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_upload, size: 16, color: Colors.orange),
                    const SizedBox(width: 2),
                    Text('${SyncService().getQueuedWasteOperationCount()}', style: const TextStyle(fontSize: 11, color: Colors.orange)),
                  ],
                ),
              ),
            ),
          TextButton(
            onPressed: () => _controller.clear(),
            child: const Text('Clear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Signature(
              controller: _controller,
              backgroundColor: Colors.grey[200]!,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveSignature,
                    style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).appColors.wasteGreen),
                    child: const Text('Confirm Signature'),
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
