import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/fleet_asset.dart';

FleetAsset _asset({
  bool active = true,
  double? currentHours,
  double? intervalHours,
  int? intervalDays,
  double? lastServiceHours,
  DateTime? lastServiceDate,
}) =>
    FleetAsset(
      typeId: 't1',
      typeName: 'Forklift',
      name: 'Hyster 01',
      assetTag: 'FL-001',
      active: active,
      currentMachineHours: currentHours,
      serviceIntervalHours: intervalHours,
      serviceIntervalDays: intervalDays,
      lastServiceMachineHours: lastServiceHours,
      lastServiceDate: lastServiceDate,
    );

void main() {
  group('FleetAsset service-due (hours)', () {
    test('due when meter advanced past the interval since last service', () {
      final a = _asset(
          currentHours: 5100, intervalHours: 1000, lastServiceHours: 4000);
      expect(a.serviceDueByHours, isTrue);
      expect(a.serviceDue, isTrue);
      expect(a.serviceDueReason, contains('1100 h since service'));
    });

    test('not due within the interval', () {
      final a = _asset(
          currentHours: 4900, intervalHours: 1000, lastServiceHours: 4000);
      expect(a.serviceDueByHours, isFalse);
    });

    test('not computable without a last-service baseline', () {
      final a = _asset(currentHours: 5100, intervalHours: 1000);
      expect(a.serviceDueByHours, isFalse);
    });

    test('not computable without a current reading', () {
      final a = _asset(intervalHours: 1000, lastServiceHours: 4000);
      expect(a.serviceDueByHours, isFalse);
    });
  });

  group('FleetAsset service-due (calendar)', () {
    test('due once the interval in days has passed', () {
      final a = _asset(
        intervalDays: 90,
        lastServiceDate: DateTime.now().subtract(const Duration(days: 95)),
      );
      expect(a.serviceDueByDays, isTrue);
      expect(a.serviceDue, isTrue);
      expect(a.serviceDueReason, contains('95 days since service'));
    });

    test('not due within the window', () {
      final a = _asset(
        intervalDays: 90,
        lastServiceDate: DateTime.now().subtract(const Duration(days: 30)),
      );
      expect(a.serviceDueByDays, isFalse);
      expect(a.serviceDue, isFalse);
    });
  });

  test('inactive assets are never flagged as due', () {
    final a = _asset(
      active: false,
      currentHours: 9000,
      intervalHours: 1000,
      lastServiceHours: 4000,
    );
    expect(a.serviceDue, isFalse);
  });

  test('either interval type alone can trigger due', () {
    final hoursOnly = _asset(
        currentHours: 5100, intervalHours: 1000, lastServiceHours: 4000);
    final daysOnly = _asset(
      intervalDays: 30,
      lastServiceDate: DateTime.now().subtract(const Duration(days: 31)),
    );
    expect(hoursOnly.serviceDue, isTrue);
    expect(daysOnly.serviceDue, isTrue);
  });
}
