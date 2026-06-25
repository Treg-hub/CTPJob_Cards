import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/fleet_asset.dart';
import 'package:ctp_job_cards/utils/fleet_asset_filter.dart';

FleetAsset _asset({
  List<String> departments = const [],
  String name = 'Hyster 01',
  String assetTag = 'FL-001',
}) =>
    FleetAsset(
      typeId: 't1',
      typeName: 'Forklift',
      name: name,
      assetTag: assetTag,
      departments: departments,
    );

void main() {
  group('fleetAssetVisibleToReporter', () {
    test('empty departments visible to all reporters', () {
      expect(fleetAssetVisibleToReporter(_asset(), 'Press'), isTrue);
      expect(fleetAssetVisibleToReporter(_asset(), null), isTrue);
    });

    test('scoped asset visible when department matches (case-insensitive)', () {
      final asset = _asset(departments: ['Press', 'Slitting']);
      expect(fleetAssetVisibleToReporter(asset, 'Press'), isTrue);
      expect(fleetAssetVisibleToReporter(asset, 'press'), isTrue);
      expect(fleetAssetVisibleToReporter(asset, 'Slitting'), isTrue);
    });

    test('scoped asset hidden from other departments', () {
      final asset = _asset(departments: ['Press']);
      expect(fleetAssetVisibleToReporter(asset, 'Slitting'), isFalse);
    });

    test('reporter without department sees only unscoped assets', () {
      final scoped = _asset(departments: ['Press']);
      final shared = _asset();
      expect(fleetAssetVisibleToReporter(scoped, null), isFalse);
      expect(fleetAssetVisibleToReporter(scoped, ''), isFalse);
      expect(fleetAssetVisibleToReporter(shared, null), isTrue);
    });
  });

  group('filterAssetsForReporter', () {
    test('filters list for reporter department', () {
      final assets = [
        _asset(departments: ['Press']),
        _asset(name: 'Hyster 02', assetTag: 'FL-02'),
        _asset(name: 'Hyster 03', assetTag: 'FL-03', departments: ['Slitting']),
      ];
      final filtered = filterAssetsForReporter(assets, 'Press');
      expect(filtered, hasLength(2));
      expect(filtered.map((a) => a.assetTag), containsAll(['FL-001', 'FL-02']));
    });
  });
}