import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/fleet_asset.dart';
import '../models/fleet_daily_check.dart';
import '../models/fleet_type.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../utils/screen_insets.dart';
import '../widgets/fleet_app_bar.dart';
import 'fleet_asset_detail_screen.dart';

/// Active fleet machines with hour meters and last pre-use checklist,
/// tabbed by asset type (View Jobs equal-width TabBar pattern).
/// Opened from the mechanic Fleet AppBar (forklift icon).
class FleetAssetsStatusScreen extends StatelessWidget {
  const FleetAssetsStatusScreen({super.key});

  static String typeKey(FleetAsset asset) {
    final name = asset.typeName.trim();
    return name.isEmpty ? 'Other' : name;
  }

  /// Tab order: fleet_types sort_order for labels that have assets, then
  /// any leftover type names A–Z (empty type → Other).
  static List<String> orderedTypeLabels(
    List<FleetAsset> assets,
    List<FleetType> assetTypes,
  ) {
    final present = <String>{};
    for (final a in assets) {
      present.add(typeKey(a));
    }
    if (present.isEmpty) return const [];

    final ordered = <String>[];
    final seen = <String>{};
    final sortedTypes = [...assetTypes]
      ..sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        if (byOrder != 0) return byOrder;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    for (final t in sortedTypes) {
      final label = t.label.trim();
      if (label.isEmpty) continue;
      if (present.contains(label) && seen.add(label)) {
        ordered.add(label);
      }
    }
    final leftovers = present.where((p) => !seen.contains(p)).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    ordered.addAll(leftovers);
    return ordered;
  }

  @override
  Widget build(BuildContext context) {
    final service = FleetService();

    return Scaffold(
      appBar: const FleetAppBar(title: 'Machines'),
      body: StreamBuilder<List<FleetAsset>>(
        stream: service.watchAssets(activeOnly: true),
        builder: (context, assetSnap) {
          if (assetSnap.connectionState == ConnectionState.waiting &&
              !assetSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final assets = assetSnap.data ?? const [];
          if (assets.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No active machines on the register.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return StreamBuilder<List<FleetType>>(
            stream: service.watchTypes(kind: 'asset_type'),
            builder: (context, typeSnap) {
              final typeLabels = orderedTypeLabels(
                assets,
                typeSnap.data ?? const [],
              );
              if (typeLabels.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              return StreamBuilder<List<FleetDailyCheck>>(
                stream: service.watchRecentDailyChecks(limit: 80),
                builder: (context, checkSnap) {
                  final latestByAsset = <String, FleetDailyCheck>{};
                  for (final check
                      in checkSnap.data ?? const <FleetDailyCheck>[]) {
                    if (check.assetId.isEmpty) continue;
                    latestByAsset.putIfAbsent(check.assetId, () => check);
                  }

                  return _MachinesByTypeBody(
                    key: ValueKey(typeLabels.join('|')),
                    typeLabels: typeLabels,
                    assets: assets,
                    latestByAsset: latestByAsset,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _MachinesByTypeBody extends StatefulWidget {
  const _MachinesByTypeBody({
    super.key,
    required this.typeLabels,
    required this.assets,
    required this.latestByAsset,
  });

  final List<String> typeLabels;
  final List<FleetAsset> assets;
  final Map<String, FleetDailyCheck> latestByAsset;

  @override
  State<_MachinesByTypeBody> createState() => _MachinesByTypeBodyState();
}

class _MachinesByTypeBodyState extends State<_MachinesByTypeBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.typeLabels.length,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final byType = <String, List<FleetAsset>>{};
    for (final asset in widget.assets) {
      byType
          .putIfAbsent(FleetAssetsStatusScreen.typeKey(asset), () => [])
          .add(asset);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabController,
          // Match View Jobs / Fleet mechanic: equal-width tabs.
          isScrollable: false,
          labelStyle: TextStyle(
            fontSize: widget.typeLabels.length > 3 ? 12 : 13,
            fontWeight: FontWeight.w600,
          ),
          tabs: [
            for (final label in widget.typeLabels) Tab(text: label),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              for (final label in widget.typeLabels)
                _AssetTypeList(
                  assets: byType[label] ?? const [],
                  latestByAsset: widget.latestByAsset,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AssetTypeList extends StatelessWidget {
  const _AssetTypeList({
    required this.assets,
    required this.latestByAsset,
  });

  final List<FleetAsset> assets;
  final Map<String, FleetDailyCheck> latestByAsset;

  @override
  Widget build(BuildContext context) {
    if (assets.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No machines of this type.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final sorted = [...assets]..sort((a, b) => a.name.compareTo(b.name));

    return ListView.separated(
      padding: ScreenInsets.listPadding(
        context,
        horizontal: 12,
        top: 12,
      ),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final asset = sorted[index];
        return _AssetStatusCard(
          asset: asset,
          lastCheck: asset.id != null ? latestByAsset[asset.id!] : null,
          onTap: asset.id == null
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          FleetAssetDetailScreen(assetId: asset.id!),
                    ),
                  ),
        );
      },
    );
  }
}

class _AssetStatusCard extends StatelessWidget {
  const _AssetStatusCard({
    required this.asset,
    required this.lastCheck,
    this.onTap,
  });

  final FleetAsset asset;
  final FleetDailyCheck? lastCheck;
  final VoidCallback? onTap;

  static String _fmtHours(double h) =>
      h % 1 == 0 ? h.toStringAsFixed(0) : h.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    final dateFmt = DateFormat('d MMM yyyy');
    final hours = asset.currentMachineHours;
    final checkAt = lastCheck?.start?.at;
    final checkDate = lastCheck?.checkDate;
    final driver = lastCheck?.start?.driverName.trim() ?? '';

    String lastCheckLabel;
    if (lastCheck == null) {
      lastCheckLabel = 'No checklist on record';
    } else if (checkAt != null) {
      lastCheckLabel = 'Last checklist ${dateFmt.format(checkAt)}';
    } else if (checkDate != null && checkDate.isNotEmpty) {
      lastCheckLabel = 'Last checklist $checkDate';
    } else {
      lastCheckLabel = 'Checklist on file';
    }

    return Card(
      color: colors.cardSurface,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor:
                    asset.hasOpenOosIssue ? Colors.red : kBrandOrange,
                foregroundColor: Colors.white,
                child: Icon(
                  asset.hasOpenOosIssue
                      ? Icons.warning_amber_rounded
                      : Icons.forklift,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    if (asset.assetTag.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        asset.assetTag,
                        style: TextStyle(
                          color: colors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.timer_outlined,
                            size: 16, color: colors.textMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            hours != null
                                ? '${_fmtHours(hours)} h on meter'
                                : 'No hour reading yet',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.fact_check_outlined,
                            size: 16, color: colors.textMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            driver.isNotEmpty
                                ? '$lastCheckLabel · $driver'
                                : lastCheckLabel,
                            style: TextStyle(
                              color: colors.textMuted,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (asset.serviceDue) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Service due — ${asset.serviceDueReason}',
                        style: TextStyle(
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (asset.hasOpenOosIssue) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Out of service',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
