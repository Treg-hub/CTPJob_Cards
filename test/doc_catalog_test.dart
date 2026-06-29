import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/employee.dart';
import 'package:ctp_job_cards/models/fleet_settings.dart';
import 'package:ctp_job_cards/models/security_settings.dart';
import 'package:ctp_job_cards/models/waste_settings.dart';
import 'package:ctp_job_cards/utils/doc_catalog.dart';

Employee _employee({
  required String position,
  String department = 'Workshop',
  bool isAdmin = false,
}) =>
    Employee(
      clockNo: '100',
      name: 'Test User',
      position: position,
      department: department,
      isAdmin: isAdmin,
    );

Set<String> _docIds(List<dynamic> docs) =>
    docs.map((d) => d.id as String).toSet();

void main() {
  const securityOn = SecuritySettings(securityEnabled: true);
  const wasteOn = WasteSettings(wasteEnabled: true);
  const fleetOn = FleetSettings(fleetEnabled: true);

  group('docsForUser — Site Security guard shell', () {
    final guard = _employee(position: 'Guard', department: 'Security');

    test('sees security guard guide, not job-card-centric docs', () {
      final ids = _docIds(docsForUser(guard, fleetOn, wasteOn, securityOn));

      expect(ids, contains('security_guard_guide'));
      expect(ids, isNot(contains('employee_guide')));
      expect(ids, isNot(contains('app_features')));
      expect(ids, isNot(contains('security_manager_mobile_guide')));
    });

    test('sees waste guide when waste module enabled', () {
      final ids = _docIds(docsForUser(guard, null, wasteOn, securityOn));
      expect(ids, contains('waste_user_guide'));
    });

    test('hides waste guide when not a waste user', () {
      final mechanic = _employee(position: 'Mechanic', department: 'Workshop');
      final ids = _docIds(docsForUser(mechanic, null, wasteOn, securityOn));
      expect(ids, isNot(contains('waste_user_guide')));
    });
  });

  group('docsForUser — Security Manager', () {
    final manager = _employee(position: 'Manager', department: 'Security');

    test('sees manager mobile security guide and standard manager docs', () {
      final ids = _docIds(docsForUser(manager, fleetOn, wasteOn, securityOn));

      expect(ids, contains('security_manager_mobile_guide'));
      expect(ids, contains('manager_guide'));
      expect(ids, contains('employee_guide'));
      expect(ids, isNot(contains('security_guard_guide')));
    });
  });

  group('docsForUser — general operator', () {
    final operator = _employee(position: 'Operator', department: 'Pressroom');

    test('does not see security-specific guides', () {
      final ids = _docIds(docsForUser(operator, fleetOn, wasteOn, securityOn));

      expect(ids, isNot(contains('security_guard_guide')));
      expect(ids, isNot(contains('security_manager_mobile_guide')));
      expect(ids, contains('employee_guide'));
    });
  });
}