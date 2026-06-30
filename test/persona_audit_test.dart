import 'package:ctp_job_cards/main.dart' as app;
import 'package:ctp_job_cards/models/employee.dart';
import 'package:ctp_job_cards/utils/persona_audit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    app.realEmployee = null;
    app.personaEmployee = null;
    app.personaAllowTestSubmissions = false;
  });

  test('canPersonaSubmit when no persona', () {
    app.realEmployee = Employee(
      clockNo: '22',
      name: 'Admin',
      position: 'Manager',
      department: 'General',
      isAdmin: true,
    );
    expect(canPersonaSubmit, isTrue);
    expect(personaAuditFields(), isEmpty);
  });

  test('blocks writes when persona active without test submissions', () {
    app.realEmployee = Employee(
      clockNo: '22',
      name: 'Admin',
      position: 'Manager',
      department: 'General',
      isAdmin: true,
    );
    app.personaEmployee = Employee(
      clockNo: '100',
      name: 'Operator',
      position: 'Operator',
      department: 'Ink Factory',
    );
    expect(canPersonaSubmit, isFalse);
    expect(() => assertPersonaSubmitAllowed(), throwsA(isA<PersonaWriteBlockedException>()));
  });

  test('audit fields when test submissions enabled', () {
    app.realEmployee = Employee(
      clockNo: '22',
      name: 'Admin',
      position: 'Manager',
      department: 'General',
      isAdmin: true,
    );
    app.personaEmployee = Employee(
      clockNo: '100',
      name: 'Operator',
      position: 'Operator',
      department: 'Ink Factory',
    );
    app.personaAllowTestSubmissions = true;

    expect(canPersonaSubmit, isTrue);
    expect(writeAttributionEmployee?.clockNo, '22');
    expect(personaAuditFields(), {
      'submitted_by_clock_no': '22',
      'submitted_by_name': 'Admin',
      'acting_as_clock_no': '100',
      'acting_as_name': 'Operator',
      'persona_test_submission': true,
    });
  });
}