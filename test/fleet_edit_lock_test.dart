import 'package:ctp_job_cards/models/fleet_work_record.dart';
import 'package:flutter_test/flutter_test.dart';

FleetWorkRecord _record({
  DateTime? createdAt,
  bool hasLinkedCosts = false,
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
    hasLinkedCosts: hasLinkedCosts,
  );
}

void main() {
  group('FleetWorkRecord.canEdit', () {
    test('mechanic can edit when no costs linked inside the window', () {
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

    test('mechanic cannot edit once costs are linked, even inside the window', () {
      final r = _record(
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        hasLinkedCosts: true,
      );
      expect(r.canEdit(isMechanic: true, isAdmin: false), isFalse);
    });

    test('missing createdAt stays editable while syncing offline', () {
      final r = _record(createdAt: null);
      expect(r.canEdit(isMechanic: true, isAdmin: false), isTrue);
    });

    test('admin can always edit', () {
      final linkedOld = _record(
        createdAt: DateTime.now().subtract(const Duration(days: 365)),
        hasLinkedCosts: true,
      );
      expect(linkedOld.canEdit(isMechanic: false, isAdmin: true), isTrue);
      final noCreated = _record(createdAt: null);
      expect(noCreated.canEdit(isMechanic: false, isAdmin: true), isTrue);
    });

    test('non-mechanic non-admin can never edit', () {
      final r = _record(createdAt: DateTime.now());
      expect(r.canEdit(isMechanic: false, isAdmin: false), isFalse);
    });
  });

  group('FleetWorkRecord.canAddComment', () {
    test('mechanic can comment inside window even when costs linked', () {
      final r = _record(
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        hasLinkedCosts: true,
      );
      expect(r.canAddComment(isMechanic: true, isAdmin: false), isTrue);
      expect(r.canEdit(isMechanic: true, isAdmin: false), isFalse);
    });

    test('mechanic cannot comment after 7 days', () {
      final r = _record(
        createdAt: DateTime.now().subtract(
          Duration(days: FleetWorkRecord.editLockDays, hours: 1),
        ),
      );
      expect(r.canAddComment(isMechanic: true, isAdmin: false), isFalse);
    });

    test('admin can always comment', () {
      final r = _record(
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
      );
      expect(r.canAddComment(isMechanic: false, isAdmin: true), isTrue);
    });

    test('non-mechanic non-admin cannot comment', () {
      final r = _record(createdAt: DateTime.now());
      expect(r.canAddComment(isMechanic: false, isAdmin: false), isFalse);
    });
  });
}