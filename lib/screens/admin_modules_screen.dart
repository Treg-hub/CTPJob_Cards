import 'package:flutter/material.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_settings.dart';
import '../services/fleet_service.dart';
import '../services/waste_service.dart';
import '../theme/app_theme.dart';
import '../utils/persona_audit.dart';
import '../utils/screen_insets.dart';
import 'copper_dashboard_screen.dart';

/// Factory-wide module on/off gates + Copper dashboard shortcut.
class AdminModulesScreen extends StatefulWidget {
  const AdminModulesScreen({super.key});

  @override
  State<AdminModulesScreen> createState() => _AdminModulesScreenState();
}

class _AdminModulesScreenState extends State<AdminModulesScreen> {
  final WasteService _wasteService = WasteService();
  final FleetService _fleetService = FleetService();

  bool? _wasteEnabled;
  bool? _fleetEnabled;
  FleetSettings? _fleetSettings;
  bool _moduleSaving = false;

  @override
  void initState() {
    super.initState();
    _loadModuleStates();
  }

  Future<void> _loadModuleStates() async {
    final wasteOn = await _wasteService.getWasteMasterEnabled();
    final fleetSettings = await _fleetService.getSettings();
    if (mounted) {
      setState(() {
        _wasteEnabled = wasteOn;
        _fleetSettings = fleetSettings;
        _fleetEnabled = fleetSettings.fleetEnabled;
      });
    }
  }

  Future<void> _setWasteEnabled(bool value) async {
    if (!guardPersonaSubmit(context)) return;
    setState(() {
      _wasteEnabled = value;
      _moduleSaving = true;
    });
    try {
      await _wasteService.setWasteMasterEnabled(value);
    } catch (_) {
      if (mounted) setState(() => _wasteEnabled = !value);
    } finally {
      if (mounted) setState(() => _moduleSaving = false);
    }
  }

  Future<void> _setFleetEnabled(bool value) async {
    if (!guardPersonaSubmit(context)) return;
    if (_fleetSettings == null) return;
    setState(() {
      _fleetEnabled = value;
      _moduleSaving = true;
    });
    try {
      final updated = _fleetSettings!.copyWith(fleetEnabled: value);
      await _fleetService.saveSettings(updated);
      if (mounted) setState(() => _fleetSettings = updated);
    } catch (_) {
      if (mounted) setState(() => _fleetEnabled = !value);
    } finally {
      if (mounted) setState(() => _moduleSaving = false);
    }
  }

  void _openCopper() {
    final clock = currentEmployee?.clockNo;
    if (clock == '22') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CopperDashboardScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin access required'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).appColors.textMuted;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modules'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: ScreenInsets.symmetricScroll(context),
        children: [
          Text(
            'MODULE GATES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: muted,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 1,
            color: Theme.of(context).appColors.cardSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.delete_outline, color: Color(0xFF22863A)),
                  title: const Text('Waste Management'),
                  subtitle: Text(
                    _wasteEnabled == null
                        ? 'Loading…'
                        : _wasteEnabled!
                            ? 'Enabled — guards can submit loads'
                            : 'Disabled — Waste tab hidden for all users',
                  ),
                  value: _wasteEnabled ?? true,
                  activeThumbColor: const Color(0xFF22863A),
                  onChanged: _moduleSaving || _wasteEnabled == null
                      ? null
                      : _setWasteEnabled,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  secondary:
                      const Icon(Icons.directions_car_outlined, color: kBrandOrange),
                  title: const Text('Fleet Maintenance'),
                  subtitle: Text(
                    _fleetEnabled == null
                        ? 'Loading…'
                        : _fleetEnabled!
                            ? 'Enabled — Fleet tab visible to eligible users'
                            : 'Disabled — Fleet tab hidden for all users',
                  ),
                  value: _fleetEnabled ?? false,
                  activeThumbColor: kBrandOrange,
                  onChanged: _moduleSaving || _fleetEnabled == null
                      ? null
                      : _setFleetEnabled,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'MODULE DASHBOARDS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: muted,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 1,
            color: Theme.of(context).appColors.cardSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined, color: kBrandOrange),
              title: const Text('Copper Storage'),
              subtitle: const Text('View and manage copper inventory'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openCopper,
            ),
          ),
        ],
      ),
    );
  }
}
