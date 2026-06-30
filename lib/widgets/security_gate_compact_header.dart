import 'package:flutter/material.dart';

import '../models/parsed_document.dart';
import '../models/security_entry.dart';
import '../models/security_vehicle.dart';
import '../theme/app_theme.dart';

/// Compact scan status + direction row for Vehicle at Gate (saves vertical space).
class SecurityGateCompactHeader extends StatelessWidget {
  const SecurityGateCompactHeader({
    super.key,
    required this.direction,
    required this.autoDirection,
    required this.directionOverridden,
    required this.flowLabel,
    required this.onDirectionChanged,
    this.onResetAuto,
    this.disc,
    this.driverLicence,
    this.companyVehicle,
    this.onRescanDisc,
    this.onRescanLicence,
    this.showLicenceRow = false,
    this.scannedReg,
    this.onShowCompanyRegistryInfo,
  });

  final SecurityDirection direction;
  final SecurityDirection? autoDirection;
  final bool directionOverridden;
  final String flowLabel;
  final ValueChanged<SecurityDirection> onDirectionChanged;
  final VoidCallback? onResetAuto;
  final ParsedDocument? disc;
  final ParsedDocument? driverLicence;
  final SecurityVehicle? companyVehicle;
  final VoidCallback? onRescanDisc;
  final VoidCallback? onRescanLicence;
  final bool showLicenceRow;
  final String? scannedReg;
  final VoidCallback? onShowCompanyRegistryInfo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reg = disc != null
        ? SecurityVehicle.normalizeReg(disc!.vehicleReg)
        : (scannedReg ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DirectionRow(
          direction: direction,
          flowLabel: flowLabel,
          directionOverridden: directionOverridden,
          autoDirection: autoDirection,
          onDirectionChanged: onDirectionChanged,
          onResetAuto: onResetAuto,
        ),
        if (companyVehicle != null) ...[
          const SizedBox(height: 8),
          _CompanyCarStrip(vehicle: companyVehicle!),
        ],
        if (disc != null) ...[
          const SizedBox(height: 6),
          _ScanStatusRow(
            icon: Icons.check_circle,
            iconColor: Colors.green.shade600,
            label: 'Disc scanned: $reg',
            onTap: onRescanDisc,
          ),
        ] else if (onRescanDisc != null) ...[
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: onRescanDisc,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan licence disc *'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size.fromHeight(40),
            ),
          ),
        ],
        if (showLicenceRow) ...[
          const SizedBox(height: 4),
          if (driverLicence != null)
            _ScanStatusRow(
              icon: Icons.check_circle,
              iconColor: Colors.green.shade600,
              label: _licenceLabel(driverLicence!),
              onTap: onRescanLicence,
            )
          else if (onRescanLicence != null)
            OutlinedButton.icon(
              onPressed: onRescanLicence,
              icon: const Icon(Icons.badge_outlined, size: 18),
              label: const Text("Scan driver's licence"),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: const Size.fromHeight(36),
              ),
            ),
        ],
        if (onShowCompanyRegistryInfo != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onShowCompanyRegistryInfo,
              icon: Icon(Icons.info_outline, size: 16, color: scheme.primary),
              label: const Text('Not a registered company car'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _licenceLabel(ParsedDocument licence) {
    final name = licence.fullName;
    if (name == null || name.isEmpty) return 'Licence scanned';
    final id = licence.idNumber;
    return id != null && id.isNotEmpty ? 'Licence: $name · $id' : 'Licence: $name';
  }
}

class _DirectionRow extends StatelessWidget {
  const _DirectionRow({
    required this.direction,
    required this.flowLabel,
    required this.directionOverridden,
    required this.autoDirection,
    required this.onDirectionChanged,
    this.onResetAuto,
  });

  final SecurityDirection direction;
  final String flowLabel;
  final bool directionOverridden;
  final SecurityDirection? autoDirection;
  final ValueChanged<SecurityDirection> onDirectionChanged;
  final VoidCallback? onResetAuto;

  @override
  Widget build(BuildContext context) {
    final borderColor = direction == SecurityDirection.in_
        ? Colors.green.shade600
        : Colors.deepOrange.shade600;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 168,
            child: SegmentedButton<SecurityDirection>(
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(
                  value: SecurityDirection.in_,
                  label: Text('IN', style: TextStyle(fontSize: 11)),
                  icon: Icon(Icons.login, size: 14),
                ),
                ButtonSegment(
                  value: SecurityDirection.out,
                  label: Text('OUT', style: TextStyle(fontSize: 11)),
                  icon: Icon(Icons.logout, size: 14),
                ),
              ],
              selected: {direction},
              onSelectionChanged: (s) => onDirectionChanged(s.first),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              flowLabel,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (directionOverridden && onResetAuto != null)
            TextButton(
              onPressed: onResetAuto,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Auto', style: TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

class _CompanyCarStrip extends StatelessWidget {
  const _CompanyCarStrip({required this.vehicle});

  final SecurityVehicle vehicle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: kBrandOrange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kBrandOrange.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.directions_car, color: kBrandOrange, size: 20),
          const SizedBox(width: 8),
          Text(
            vehicle.vehicleReg,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          if (vehicle.description != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                vehicle.description!,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScanStatusRow extends StatelessWidget {
  const _ScanStatusRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.qr_code_scanner,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}