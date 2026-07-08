import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/employee.dart';
import 'package:ctp_job_cards/models/fleet_settings.dart';
import 'package:ctp_job_cards/models/waste_settings.dart';
import 'package:ctp_job_cards/utils/onboarding_persona.dart';

void main() {
  group('resolveOnboardingPersona', () {
    test('defaults to job cards', () {
      expect(resolveOnboardingPersona(null), OnboardingPersona.jobCards);
      expect(
        resolveOnboardingPersona(
          Employee(
            clockNo: '1',
            name: 'A',
            position: 'Operator',
            department: 'Printing',
          ),
        ),
        OnboardingPersona.jobCards,
      );
    });

    test('security guard from waste allow-list', () {
      final emp = Employee(
        clockNo: '50',
        name: 'Guard',
        position: 'Guard',
        department: 'Security',
      );
      final waste = WasteSettings(
        wasteEnabled: true,
        guardClockNos: const ['50'],
      );
      expect(
        resolveOnboardingPersona(emp, wasteSettings: waste),
        OnboardingPersona.securityGuard,
      );
    });

    test('fleet mechanic from allow-list', () {
      final emp = Employee(
        clockNo: '99',
        name: 'Mech',
        position: 'Mechanic',
        department: 'Workshop',
      );
      final fleet = FleetSettings(
        fleetEnabled: true,
        mechanicClockNos: const ['99'],
      );
      expect(
        resolveOnboardingPersona(emp, fleetSettings: fleet),
        OnboardingPersona.fleetMechanic,
      );
    });

    test('ink floor non-admin', () {
      final emp = Employee(
        clockNo: '10',
        name: 'Ink',
        position: 'Operator',
        department: 'Ink Factory',
      );
      expect(resolveOnboardingPersona(emp), OnboardingPersona.inkFloor);
    });

    test('ink admin stays job-cards track', () {
      final emp = Employee(
        clockNo: '22',
        name: 'Admin',
        position: 'Admin',
        department: 'Ink Factory',
        isAdmin: true,
      );
      expect(resolveOnboardingPersona(emp), OnboardingPersona.jobCards);
    });
  });

  group('onboardingHomeExpectations', () {
    test('guard list is non-empty', () {
      expect(
        onboardingHomeExpectations(OnboardingPersona.securityGuard),
        isNotEmpty,
      );
    });
  });
}
