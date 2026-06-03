import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_issue.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';

/// Reporters, mechanic, and admin can submit a new fleet issue.
/// Steps: pick asset → severity + shift + description → optional photos → submit.
class FleetReportIssueScreen extends ConsumerStatefulWidget {
  /// Pre-select an asset (e.g. launched from a specific asset card).
  final FleetAsset? preSelectedAsset;

  const FleetReportIssueScreen({super.key, this.preSelectedAsset});

  @override
  ConsumerState<FleetReportIssueScreen> createState() =>
      _FleetReportIssueScreenState();
}

class _FleetReportIssueScreenState
    extends ConsumerState<FleetReportIssueScreen> {
  final _service = FleetService();
  final _descCtrl = TextEditingController();

  FleetAsset? _selectedAsset;
  FleetIssueSeverity _severity = FleetIssueSeverity.medium;
  FleetIssueShift _shift = FleetIssueShift.detectFromNow();
  final List<String> _photoUrls = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedAsset = widget.preSelectedAsset ??
        ref.read(selectedFleetAssetProvider);
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    if (_photoUrls.length >= 3) return;
    final source = await _showPhotoSourceDialog();
    if (source == null) return;

    final localPath = await _service.pickAndCompressPhoto(source);
    if (localPath == null) return;

    setState(() => _submitting = true);
    try {
      final url = await _service.uploadFleetPhoto(
        localPath: localPath,
        fleetRef: 'fleet_issues/_temp',
      );
      if (mounted) setState(() => _photoUrls.add(url));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo upload failed. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<ImageSource?> _showPhotoSourceDialog() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final emp = currentEmployee;
    if (emp == null) return;

    if (_selectedAsset == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an asset.')),
      );
      return;
    }
    final desc = _descCtrl.text.trim();
    if (desc.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter a description (at least 10 characters).')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final issue = FleetIssue(
        assetId: _selectedAsset!.id!,
        assetName: _selectedAsset!.name,
        description: desc,
        severity: _severity,
        reportedByClockNo: emp.clockNo,
        reportedByName: emp.name,
        shift: _shift,
        photos: List.from(_photoUrls),
      );
      await _service.createIssue(issue);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Issue reported.'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to submit: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report an Issue'),
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Asset picker ──────────────────────────────────────────────
          _buildSectionLabel('Asset *'),
          _AssetPickerTile(
            selected: _selectedAsset,
            onTap: () async {
              final asset = await Navigator.of(context).push<FleetAsset>(
                MaterialPageRoute(
                    builder: (_) => const FleetAssetPickerScreen()),
              );
              if (asset != null) setState(() => _selectedAsset = asset);
            },
          ),
          const SizedBox(height: 20),

          // ── Severity ──────────────────────────────────────────────────
          _buildSectionLabel('Severity *'),
          Wrap(
            spacing: 8,
            children: FleetIssueSeverity.values.map((s) {
              final isSelected = _severity == s;
              return ChoiceChip(
                label: Text(s.displayLabel),
                selected: isSelected,
                selectedColor: s == FleetIssueSeverity.outOfService
                    ? Colors.red
                    : kBrandOrange,
                labelStyle: TextStyle(
                    color: isSelected ? Colors.white : null,
                    fontWeight: FontWeight.w500),
                onSelected: (_) => setState(() => _severity = s),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // ── Shift ─────────────────────────────────────────────────────
          _buildSectionLabel('Shift'),
          Wrap(
            spacing: 8,
            children: FleetIssueShift.values.map((s) {
              return ChoiceChip(
                label: Text(s.displayLabel),
                selected: _shift == s,
                selectedColor: kBrandOrange,
                labelStyle: TextStyle(
                    color: _shift == s ? Colors.white : null),
                onSelected: (_) => setState(() => _shift = s),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // ── Description ───────────────────────────────────────────────
          _buildSectionLabel('Description *'),
          TextField(
            controller: _descCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Describe the problem clearly. Minimum 10 characters.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),

          // ── Photos ────────────────────────────────────────────────────
          _buildSectionLabel('Photos (optional, max 3)'),
          _buildPhotoRow(),
          const SizedBox(height: 32),

          // ── Submit ────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                  backgroundColor: kBrandOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Submit Issue',
                      style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }

  Widget _buildPhotoRow() {
    return Wrap(
      spacing: 8,
      children: [
        ..._photoUrls.map((url) => Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(url,
                      width: 80, height: 80, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _photoUrls.remove(url)),
                    child: Container(
                      decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle),
                      padding: const EdgeInsets.all(4),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 14),
                    ),
                  ),
                ),
              ],
            )),
        if (_photoUrls.length < 3)
          GestureDetector(
            onTap: _addPhoto,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.add_a_photo, color: Colors.grey),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Asset picker tile
// ---------------------------------------------------------------------------

class _AssetPickerTile extends StatelessWidget {
  const _AssetPickerTile({required this.selected, required this.onTap});
  final FleetAsset? selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.forklift,
                color: selected != null ? kBrandOrange : Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: selected == null
                  ? Text('Tap to select an asset',
                      style: TextStyle(color: Colors.grey[600]))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(selected!.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            if (selected!.hasOpenOosIssue) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(4)),
                                child: const Text('OOS',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
                        ),
                        Text(
                            '${selected!.typeName}  •  ${selected!.assetTag}',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12)),
                      ],
                    ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

/// Exported asset picker screen for use by other fleet screens.
class FleetAssetPickerScreen extends ConsumerStatefulWidget {
  const FleetAssetPickerScreen({super.key});

  @override
  ConsumerState<FleetAssetPickerScreen> createState() =>
      _FleetAssetPickerScreenState();
}

class _FleetAssetPickerScreenState
    extends ConsumerState<FleetAssetPickerScreen> {
  final _service = FleetService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Asset'),
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<FleetAsset>>(
        stream: _service.watchAssets(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final assets = snapshot.data ?? [];
          if (assets.isEmpty) {
            return const Center(
                child: Text('No assets found. Ask admin to add assets.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: assets.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final asset = assets[index];
              return Card(
                child: ListTile(
                  onTap: () => Navigator.of(context).pop(asset),
                  leading: CircleAvatar(
                    backgroundColor:
                        asset.hasOpenOosIssue ? Colors.orange : kBrandOrange,
                    foregroundColor: Colors.white,
                    child: Icon(
                      asset.typeName.toLowerCase().contains('grab')
                          ? Icons.precision_manufacturing
                          : Icons.forklift,
                      size: 20,
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(asset.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (asset.hasOpenOosIssue) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(4)),
                          child: const Text('OOS',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                      '${asset.typeName}  •  ${asset.assetTag}',
                      style: const TextStyle(fontSize: 12)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
