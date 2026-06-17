import 'package:ctp_job_cards/models/fleet_work_record.dart';
import 'package:flutter_test/flutter_test.dart';

FleetWorkRecord _record({
  DateTime? createdAt,
  FleetCostStatus costStatus = FleetCostStatus.pending,
}) {
  return FleetWorkRecord(
    workNumber: 'FM-0001',
    assetId: 'a1',
    assetName: 'Hyster 01',
    workTypeId: 't1',
    workTypeName: 'Repair',
    title: 'Fix: Hyster 01',
    description: 'Replaced hydraulic hose',
    labourHours: 1.5,
    startDate: DateTime(2026, 6, 1),
    endDate: DateTime(2026, 6, 1),
    loggedByClockNo: '7',
    loggedByName: 'Mechanic',
    createdAt: createdAt,
    costStatus: costStatus,
  );
}

void main() {
  group('FleetWorkRecord.canEdit', () {
    test('mechanic can edit an uncosted record inside the window', () {
      final r = _record(
          createdAt: DateTime.now().subtract(const Duration(days: 1)));
      expect(r.canEdit(isMechanic: true, isAdmin: false), isTrue);
    });

    test('mechanic cannot edit after the edit window', () {
      final r = _record(
          createdAt: DateTime.now().subtract(
              Duration(days: FleetWorkRecord.editLockDays, hours: 1)));
      expect(r.canEdit(isMechanic: true, isAdmin: false), isFalse);
    });

    test('mechanic cannot edit once costed, even inside the window', () {
      final r = _record(
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        costStatus: FleetCostStatus.costed,
      );
      expect(r.canEdit(isMechanic: true, isAdmin: false), isFalse);
    });

    test('mechanic cannot edit a no-cost record, even inside the window', () {
      final r = _record(
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        costStatus: FleetCostStatus.noCost,
      );
      expect(r.canEdit(isMechanic: true, isAdmin: false), isFalse);
    });

    test('missing createdAt stays editable while syncing offline', () {
      final r = _record(createdAt: null);
      expect(r.canEdit(isMechanic: true, isAdmin: false), isTrue);
    });

    test('admin can always edit', () {
      final costedOld = _record(
        createdAt: DateTime.now().subtract(const Duration(days: 365)),
        costStatus: FleetCostStatus.costed,
      );
      expect(costedOld.canEdit(isMechanic: false, isAdmin: true), isTrue);
      final noCreated = _record(createdAt: null);
      expect(noCreated.canEdit(isMechanic: false, isAdmin: true), isTrue);
    });

    test('non-mechanic non-admin can never edit', () {
      final r = _record(createdAt: DateTime.now());
      expect(r.canEdit(isMechanic: false, isAdmin: false), isFalse);
    });
  });

  group('FleetCostStatus.fromValue', () {
    test('parses known values and defaults to pending', () {
      expect(FleetCostStatus.fromValue('pending'), FleetCostStatus.pending);
      expect(FleetCostStatus.fromValue('costed'), FleetCostStatus.costed);
      expect(FleetCostStatus.fromValue('no_cost'), FleetCostStatus.noCost);
      expect(FleetCostStatus.fromValue('garbage'), FleetCostStatus.pending);
      expect(FleetCostStatus.fromValue(null), FleetCostStatus.pending);
    });
  });
}
