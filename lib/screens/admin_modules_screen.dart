import 'package:flutter/material.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_settings.dart';
import '../models/press_manuals_access_settings.dart';
import '../services/fleet_service.dart';
import '../services/press_manuals_access_service.dart';
import '../services/waste_service.dart';
import '../theme/app_theme.dart';
import '../utils/persona_audit.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';
import 'copper_dashboard_screen.dart';
import 'press_manuals_allowlist_admin_screen.dart';

/// Factory-wide module on/off gates + Copper dashboard shortcut.
class AdminModulesScreen extends StatefulWidget {
  const AdminModulesScreen({super.key});

  @override
  State<AdminModulesScreen> createState() => _AdminModulesScreenState();
}

class _AdminModulesScreenState extends State<AdminModulesScreen> {
  final WasteService _wasteService = WasteService();
  final FleetService _fleetService = FleetService();
  final PressManualsAccessService _pressManualsAccess =
      PressManualsAccessService();

  bool? _wasteEnabled;
  bool? _fleetEnabled;
  FleetSettings? _fleetSettings;
  PressManualsAccessSettings? _pressManualsAccessSettings;
  bool _moduleSaving = false;

  @override
  void initState() {
    super.initState();
    _loadModuleStates();
  }

  Future<void> _loadModuleStates() async {
    final wasteOn = await _wasteService.getWasteMasterEnabled();
    final fleetSettings = await _fleetService.getSettings();
    PressManualsAccessSettings pressManuals;
    try {
      pressManuals = await _pressManualsAccess.getSettings();
    } catch (_) {
      pressManuals = PressManualsAccessSettings.defaults;
    }
    if (mounted) {
      setState(() {
        _wasteEnabled = wasteOn;
        _fleetSettings = fleetSettings;
        _fleetEnabled = fleetSettings.fleetEnabled;
        _pressManualsAccessSettings = pressManuals;
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

  Future<void> _setPressManualsFlag({
    bool? allowPressroom,
    bool? allowTechnicians,
  }) async {
    if (!guardPersonaSubmit(context)) return;
    final current =
        _pressManualsAccessSettings ?? PressManualsAccessSettings.defaults;
    final updated = current.copyWith(
      allowPressroom: allowPressroom,
      allowTechnicians: allowTechnicians,
    );
    setState(() {
      _pressManualsAccessSettings = updated;
      _moduleSaving = true;
    });
    try {
      // Flags only — do not rewrite allowed_clock_nos from possibly stale UI state.
      await _pressManualsAccess.saveGroupFlags(
        allowPressroom: updated.allowPressroom,
        allowTechnicians: updated.allowTechnicians,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _pressManualsAccessSettings = current);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save Press Manuals access: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _moduleSaving = false);
    }
  }

  void _openCopper() {
    // Phase 9: dual isAdmin / copper gate — not hard-coded clock 22.
    final emp = currentEmployee;
    if (role_utils.isAdmin(emp) || role_utils.isCopperAuthorized(emp)) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CopperDashboardScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin or Pre Press manager access required'),
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
            'PRESS MANUALS ACCESS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: muted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'isAdmin always has access. Use these switches for whole groups, '
            'or the allowlist for named managers/employees (any department). '
            'OEM PDFs download only in-app (mobile private cache or web '
            'session) when Storage rules allow the signed-in user.',
            style: TextStyle(fontSize: 12, color: muted, height: 1.35),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 1,
            color: Theme.of(context).appColors.cardSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(
                    Icons.print,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    'Allow Pressroom',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    _pressManualsAccessSettings == null
                        ? 'Loading…'
                        : _pressManualsAccessSettings!.allowPressroom
                            ? 'On — Pressroom department can open Press Manuals'
                            : 'Off — Pressroom only if they are isAdmin or allowlisted',
                    style: TextStyle(
                      color: Theme.of(context).appColors.textMuted,
                    ),
                  ),
                  value: _pressManualsAccessSettings?.allowPressroom ?? false,
                  activeThumbColor: Theme.of(context).colorScheme.primary,
                  onChanged: _moduleSaving || _pressManualsAccessSettings == null
                      ? null
                      : (v) => _setPressManualsFlag(allowPressroom: v),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  secondary: Icon(
                    Icons.build_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    'Allow Technicians',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    _pressManualsAccessSettings == null
                        ? 'Loading…'
                        : _pressManualsAccessSettings!.allowTechnicians
                            ? 'On — mechanics / electrical / technicians can open'
                            : 'Off — technicians only if they are isAdmin or allowlisted',
                    style: TextStyle(
                      color: Theme.of(context).appColors.textMuted,
                    ),
                  ),
                  value: _pressManualsAccessSettings?.allowTechnicians ?? false,
                  activeThumbColor: Theme.of(context).colorScheme.primary,
                  onChanged: _moduleSaving || _pressManualsAccessSettings == null
                      ? null
                      : (v) => _setPressManualsFlag(allowTechnicians: v),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(
                    Icons.playlist_add_check,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    'Individual allowlist',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    _pressManualsAccessSettings == null
                        ? 'Loading…'
                        : _pressManualsAccessSettings!
                                .allowedClockNos.isEmpty
                            ? 'No named people yet — add managers or others'
                            : '${_pressManualsAccessSettings!.allowedClockNos.length} '
                                'clock number(s) granted access',
                    style: TextStyle(
                      color: Theme.of(context).appColors.textMuted,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const PressManualsAllowlistAdminScreen(),
                      ),
                    );
                    if (!mounted) return;
                    await _loadModuleStates();
                  },
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
