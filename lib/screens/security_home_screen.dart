import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show currentEmployee;
import '../providers/security_provider.dart';
import '../theme/app_theme.dart';
import '../utils/screen_insets.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/security_widgets.dart';
import 'security_add_cost_screen.dart';
import 'security_company_car_screen.dart';
import 'security_on_foot_visitor_screen.dart';
import 'security_on_site_screen.dart';
import 'security_vehicle_scan_in_screen.dart';
import 'security_vehicle_scan_out_screen.dart';

/// Site Security hub — gate selector and action cards.
class SecurityHomeScreen extends ConsumerStatefulWidget {
  const SecurityHomeScreen({super.key});

  @override
  ConsumerState<SecurityHomeScreen> createState() =>
      _SecurityHomeScreenState();
}

class _SecurityHomeScreenState extends ConsumerState<SecurityHomeScreen> {
  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(securitySettingsProvider);
    final settings = settingsAsync.valueOrNull;

    if (!settingsAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    if (settings == null || !settings.securityEnabled) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Site Security is not enabled.\nAsk an admin to turn it on in CTP Pulse Settings.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final emp = currentEmployee;
    final canManageCosts = role_utils.isSecurityCostManager(emp, settings);
    final gate = ref.watch(selectedSecurityGateProvider);
    final gatesAsync = ref.watch(securityGatesProvider);
    gatesAsync.whenData((gates) {
      if (gate == null && gates.length == 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(selectedSecurityGateProvider.notifier).state =
                gates.first;
          }
        });
      }
    });

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          ScreenInsets.scrollBottomInHomeShell(),
        ),
        children: [
          Text(
            'Site Security',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: kBrandOrange,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Select your gate, then choose an action below.',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).appColors.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          SecurityGateSelector(onChanged: (_) {}),
          const SizedBox(height: 20),
          SecurityActionCard(
            title: 'Vehicle Scan In',
            subtitle: 'Disc + driver licence + occupant count',
            icon: Icons.login,
            enabled: gate != null,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SecurityVehicleScanInScreen(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SecurityActionCard(
            title: 'Vehicle Scan Out',
            subtitle: 'Scan licence disc on vehicle leaving',
            icon: Icons.logout,
            enabled: gate != null,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SecurityVehicleScanOutScreen(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SecurityActionCard(
            title: 'Company Car',
            subtitle: 'Exit: licence + clock no · Return: disc + mileage',
            icon: Icons.directions_car,
            enabled: gate != null,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SecurityCompanyCarScreen(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SecurityActionCard(
            title: 'On-Foot Visitor',
            subtitle: 'Pedestrian entry without a vehicle',
            icon: Icons.directions_walk,
            enabled: gate != null,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SecurityOnFootVisitorScreen(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SecurityActionCard(
            title: 'On Site List',
            subtitle: 'Vehicles currently on site',
            icon: Icons.list_alt,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SecurityOnSiteScreen(),
              ),
            ),
          ),
          if (canManageCosts) ...[
            const SizedBox(height: 10),
            SecurityActionCard(
              title: 'Add Company Car Cost',
              subtitle: 'Fuel, parking, tolls — registered company cars only',
              icon: Icons.payments_outlined,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SecurityAddCostScreen(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}