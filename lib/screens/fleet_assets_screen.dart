import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_type.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/fleet_app_bar.dart';
import '../widgets/fleet_form_fields.dart';
import '../widgets/fleet_type_selector.dart';

/// Admin-only screen: manage the fleet asset register (forklifts, grabs, etc.).
class FleetAssetsScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const FleetAssetsScreen({super.key, this.embedded = false});

  @override
  ConsumerState<FleetAssetsScreen> createState() => _FleetAssetsScreenState();
}

class _FleetAssetsScreenState extends ConsumerState<FleetAssetsScreen> {
  final _service = FleetService();

  @override
  Widget build(BuildContext context) {
    if (!role_utils.isFleetAdmin(currentEmployee)) {
      if (widget.embedded) return const Center(child: Text('Admin access required.'));
      return const Scaffold(body: Center(child: Text('Admin access required.')));
    }

    final body = StreamBuilder<List<FleetAsset>>(
        stream: _service.watchAssets(activeOnly: false),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final assets = snapshot.data ?? [];
          if (assets.isEmpty) {
            return const Center(
              child: Text(
                'No assets yet.\nTap + to add a Hyster (forks or grab).',
                textAlign: TextAlign.center,
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: assets.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final asset = assets[index];
              return _AssetTile(
                asset: asset,
                onTap: () => _openAssetForm(context, asset),
              );
            },
          );
        },
    );
    // When embedded in a TabBarView the parent scaffold owns the FAB.
    // Just return the body filling the full available space.
    if (widget.embedded) return body;
    return Scaffold(
      appBar: const FleetAppBar(title: 'Fleet Assets'),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
        onPressed: () => _openAssetForm(context, null),
        child: const Icon(Icons.add),
      ),
      body: body,
    );
  }

  void _openAssetForm(BuildContext context, FleetAsset? existing) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FleetAssetFormScreen(service: _service, asset: existing),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Asset tile
// ---------------------------------------------------------------------------

class _AssetTile extends StatelessWidget {
  const _AssetTile({required this.asset, required this.onTap});
  final FleetAsset asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    return Card(
      color: colors?.cardSurface,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: asset.active ? kBrandOrange : Colors.grey,
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
            Text(asset.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (asset.hasOpenOosIssue) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'OOS',
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${asset.typeName}  •  Tag: ${asset.assetTag}'
          '${asset.serial != null ? '  •  S/N: ${asset.serial}' : ''}',
          style: TextStyle(color: colors?.textMuted, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!asset.active)
              Chip(
                label: const Text('Inactive', style: TextStyle(fontSize: 11)),
                backgroundColor: Colors.grey.withAlpha(50),
                padding: EdgeInsets.zero,
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Asset add/edit form screen
// ---------------------------------------------------------------------------

class FleetAssetFormScreen extends ConsumerStatefulWidget {
  const FleetAssetFormScreen({super.key, required this.service, this.asset});
  final FleetService service;
  final FleetAsset? asset;

  @override
  ConsumerState<FleetAssetFormScreen> createState() => FleetAssetFormScreenState();
}

class FleetAssetFormScreenState extends ConsumerState<FleetAssetFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final _serialCtrl = TextEditingController();

  FleetType? _selectedType;
  bool _active = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.asset;
    if (a != null) {
      _nameCtrl.text = a.name;
      _tagCtrl.text = a.assetTag;
      _serialCtrl.text = a.serial ?? '';
      _active = a.active;
    }
    _loadTypes();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _tagCtrl.dispose();
    _serialCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    final snap = await widget.service
        .watchTypes(kind: 'asset_type')
        .first;
    if (mounted) {
      setState(() {
        if (widget.asset != null) {
          _selectedType = snap
              .where((t) => t.id == widget.asset!.typeId)
              .firstOrNull;
        }
        _selectedType ??= snap.firstOrNull;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an asset type.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final asset = FleetAsset(
        id: widget.asset?.id,
        typeId: _selectedType!.id!,
        typeName: _selectedType!.label,
        name: _nameCtrl.text.trim(),
        assetTag: _tagCtrl.text.trim(),
        serial: _serialCtrl.text.trim().isEmpty ? null : _serialCtrl.text.trim(),
        active: _active,
        hasOpenOosIssue: widget.asset?.hasOpenOosIssue ?? false,
      );
      await widget.service.saveAsset(asset);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.asset != null;
    return Scaffold(
      appBar: FleetAppBar(
        title: isEdit ? 'Edit Asset' : 'Add Asset',
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FleetTypeSelector(
              kind: 'asset_type',
              value: _selectedType,
              hintText: 'Select asset type',
              decoration: fleetDropdownDecoration(labelText: 'Asset Type *'),
              onChanged: (type) => setState(() => _selectedType = type),
              validator: (v) => v == null ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: fleetDropdownDecoration(
                labelText: 'Name *',
                hintText: 'e.g. Hyster 01',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tagCtrl,
              decoration: fleetDropdownDecoration(
                labelText: 'Asset Tag *',
                hintText: 'e.g. FL-001',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _serialCtrl,
              decoration: fleetDropdownDecoration(
                labelText: 'Serial Number (optional)',
              ),
            ),
            const SizedBox(height: 24),
            SwitchListTile(
              title: const Text('Active'),
              subtitle: const Text('Inactive assets are hidden in pickers'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ],
        ),
      ),
    );
  }
}
