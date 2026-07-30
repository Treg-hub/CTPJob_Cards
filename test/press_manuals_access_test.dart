import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/employee.dart';
import 'package:ctp_job_cards/models/press_manual_entry.dart';
import 'package:ctp_job_cards/models/press_manuals_access_settings.dart';
import 'package:ctp_job_cards/utils/role.dart';

Employee _emp({
  required String department,
  String position = 'Operator',
  bool isAdmin = false,
}) =>
    Employee(
      clockNo: '200',
      name: 'Test',
      position: position,
      department: department,
      isAdmin: isAdmin,
    );

void main() {
  group('canAccessPressManuals', () {
    test('isAdmin always allowed even when flags off', () {
      expect(
        canAccessPressManuals(
          _emp(department: 'Workshop', isAdmin: true),
          PressManualsAccessSettings.defaults,
        ),
        isTrue,
      );
    });

    test('Pressroom denied when flag off', () {
      expect(
        canAccessPressManuals(
          _emp(department: 'Pressroom'),
          PressManualsAccessSettings.defaults,
        ),
        isFalse,
      );
    });

    test('Pressroom allowed when flag on', () {
      expect(
        canAccessPressManuals(
          _emp(department: 'Pressroom'),
          const PressManualsAccessSettings(allowPressroom: true),
        ),
        isTrue,
      );
    });

    test('technician denied when flag off', () {
      expect(
        canAccessPressManuals(
          _emp(department: 'Workshop', position: 'Mechanical Technician'),
          PressManualsAccessSettings.defaults,
        ),
        isFalse,
      );
    });

    test('technician allowed when flag on', () {
      expect(
        canAccessPressManuals(
          _emp(department: 'Workshop', position: 'Mechanical Technician'),
          const PressManualsAccessSettings(allowTechnicians: true),
        ),
        isTrue,
      );
    });

    test('operator non-pressroom still denied when only tech flag on', () {
      expect(
        canAccessPressManuals(
          _emp(department: 'Ink Factory', position: 'Operator'),
          const PressManualsAccessSettings(allowTechnicians: true),
        ),
        isFalse,
      );
    });
  });

  group('PressManualsAccessSettings', () {
    test('fromMap defaults', () {
      final s = PressManualsAccessSettings.fromMap(null);
      expect(s.allowPressroom, isFalse);
      expect(s.allowTechnicians, isFalse);
    });

    test('fromMap reads snake_case', () {
      final s = PressManualsAccessSettings.fromMap({
        'allow_pressroom': true,
        'allow_technicians': true,
      });
      expect(s.allowPressroom, isTrue);
      expect(s.allowTechnicians, isTrue);
    });
  });

  group('pressManualCatalog', () {
    test('has short packs', () {
      expect(pressManualCatalog.where((e) => e.isBundledMarkdown).length, 6);
    });
  });
}
