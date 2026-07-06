import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/employee.dart';
import 'package:ctp_job_cards/models/job_card.dart';
import 'package:ctp_job_cards/utils/role.dart';

Employee _emp({required String clockNo, required String department, required String position}) {
  return Employee(
    clockNo: clockNo,
    name: 'Test User',
    department: department,
    position: position,
  );
}

JobCard _job({
  JobType type = JobType.mechanical,
  List<String>? assignedClockNos,
}) {
  return JobCard(
    id: 'job-1',
    department: 'Pre Press',
    area: 'Area',
    machine: 'Machine',
    part: 'Part',
    description: 'Test',
    type: type,
    priority: 3,
    operator: 'Operator',
    operatorClockNo: '99',
    status: JobStatus.open,
    assignedClockNos: assignedClockNos,
  );
}

void main() {
  group('roleFromEmployee — Pre Press Specialist', () {
    test('Workshop | Pre Press Specialist resolves to technician', () {
      final emp = _emp(
        clockNo: '1234',
        department: 'Workshop',
        position: 'Pre Press Specialist',
      );
      expect(roleFromEmployee(emp), UserRole.technician);
      expect(isPrepressSpecialist(emp), isTrue);
    });

    test('Pre Press | Specialist resolves to technician', () {
      final emp = _emp(
        clockNo: '1234',
        department: 'Pre Press',
        position: 'Specialist',
      );
      expect(roleFromEmployee(emp), UserRole.technician);
      expect(isPrepressSpecialist(emp), isTrue);
    });
  });

  group('isOperatorRestrictedForJob', () {
    test('operator blocked on unassigned mech job', () {
      final emp = _emp(clockNo: '1', department: 'Pressroom', position: 'Operator');
      expect(isOperatorRestrictedForJob(emp, _job()), isTrue);
    });

    test('operator allowed on assigned mech job', () {
      final emp = _emp(clockNo: '1', department: 'Pressroom', position: 'Operator');
      expect(
        isOperatorRestrictedForJob(emp, _job(assignedClockNos: ['1'])),
        isFalse,
      );
    });

    test('pre press specialist allowed on assigned mech job', () {
      final emp = _emp(
        clockNo: '1',
        department: 'Workshop',
        position: 'Pre Press Specialist',
      );
      expect(
        isOperatorRestrictedForJob(emp, _job(assignedClockNos: ['1'])),
        isFalse,
      );
    });

    test('pre press specialist allowed on unassigned mech job (technician role)', () {
      final emp = _emp(
        clockNo: '1',
        department: 'Workshop',
        position: 'Pre Press Specialist',
      );
      expect(isOperatorRestrictedForJob(emp, _job()), isFalse);
    });
  });
}