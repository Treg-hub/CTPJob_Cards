import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/fleet_work_record.dart';

FleetWorkRecord _record({DateTime? createdAt}) => FleetWorkRecord(
      workNumber: 'FM-0001',
      assetId: 'a1',
      assetName: 'Hyster 01',
      workTypeId: 't1',
      workTypeName: 'Repair',
      title: 'Test',
      description: 'Test',
      labourHours: 1,
      startDate: DateTime(2026, 6, 1),
      endDate: DateTime(2026, 6, 1),
      loggedByClockNo: '77',
      loggedByName: 'Mechanic',
      createdAt: createdAt,
    );

void main() {
  group('FleetWorkRecord edit lock (7 days)', () {
    test('editLockDays is the agreed 7-day window', () {
      expect(FleetWorkRecord.editLockDays, 7);
    });

    test('not locked without createdAt (still syncing offline)', () {
      expect(_record(createdAt: null).isEditLocked, isFalse);
    });

    test('not locked within the window', () {
      final created = DateTime.now().subtract(const Duration(days: 6, hours: 23));
      expect(_record(createdAt: created).isEditLocked, isFalse);
    });

    test('locked once 7 days have passed', () {
      final created = DateTime.now().subtract(const Duration(days: 7, minutes: 1));
      expect(_record(createdAt: created).isEditLocked, isTrue);
    });

    test('locked well past the window', () {
      final created = DateTime.now().subtract(const Duration(days: 90));
      expect(_record(createdAt: created).isEditLocked, isTrue);
    });
  });
}
