import 'package:ctp_job_cards/main.dart' as app;
import 'package:ctp_job_cards/models/employee.dart';
import 'package:ctp_job_cards/models/fleet_settings.dart';
import 'package:ctp_job_cards/models/security_settings.dart';
import 'package:ctp_job_cards/models/waste_settings.dart';
import 'package:ctp_job_cards/providers/persona_provider.dart';
import 'package:ctp_job_cards/services/module_claims.dart';
import 'package:ctp_job_cards/utils/role.dart';
import 'package:flutter_test/flutter_test.dart';

Employee _pressroomOp() => Employee(
      clockNo: '1001',
      name: 'Press Op',
      position: 'Operator',
      department: 'Pressroom',
      isAdmin: false,
    );

void main() {
  setUp(() {
    app.realEmployee = null;
    app.personaEmployee = null;
    app.personaAllowTestSubmissions = false;
    ModuleClaims.instance.clear();
    ModuleClaims.instance.suppressTokenClaimsForUi = false;
  });

  tearDown(() {
    app.personaEmployee = null;
    app.personaAllowTestSubmissions = false;
    ModuleClaims.instance.clear();
    ModuleClaims.instance.suppressTokenClaimsForUi = false;
  });

  test('admin token flags do not leak into persona UI gating', () {
    ModuleClaims.instance.applyFromTokenClaims({
      'isFleetMechanic': true,
      'isFleetReporter': true,
      'isFleetCostManager': true,
      'isSecurityManager': true,
      'isSecurityStaff': true,
      'isWasteStaff': true,
      'isInkStaff': true,
    });

    const fleet = FleetSettings(
      fleetEnabled: true,
      reporterDepartments: ['Despatch'],
      mechanicClockNos: ['9999'],
    );
    const waste = WasteSettings(wasteEnabled: true);
    const security = SecuritySettings(securityEnabled: true);

    // Without suppress: token flags grant everything.
    expect(isInkUser(_pressroomOp()), isTrue);
    expect(isFleetReporter(_pressroomOp(), fleet), isTrue);
    expect(isWasteUser(_pressroomOp(), waste), isTrue);
    expect(canUseSecurityModule(_pressroomOp(), security), isTrue);

    final notifier = PersonaNotifier();
    notifier.start(_pressroomOp(), allowTestSubmissions: false);

    expect(ModuleClaims.instance.suppressTokenClaimsForUi, isTrue);
    expect(ModuleClaims.instance.uiIsInkStaff, isNull);

    // With persona suppress: Pressroom operator matches real department access.
    expect(isInkUser(_pressroomOp()), isFalse);
    expect(isInkMeterUser(_pressroomOp()), isFalse);
    expect(isFleetReporter(_pressroomOp(), fleet), isFalse);
    expect(isFleetMechanic(_pressroomOp(), fleet), isFalse);
    expect(isWasteUser(_pressroomOp(), waste), isFalse);
    expect(canUseSecurityModule(_pressroomOp(), security), isFalse);

    notifier.stop();
    expect(ModuleClaims.instance.suppressTokenClaimsForUi, isFalse);
    expect(isInkUser(_pressroomOp()), isTrue);
  });

  test('persona Ink Factory operator still gets ink tiles from department', () {
    ModuleClaims.instance.applyFromTokenClaims({'isInkStaff': true});
    final notifier = PersonaNotifier();
    final inkOp = Employee(
      clockNo: '2002',
      name: 'Ink Op',
      position: 'Operator',
      department: 'Ink Factory',
      isAdmin: false,
    );
    notifier.start(inkOp, allowTestSubmissions: false);

    expect(isInkUser(inkOp), isTrue);
    expect(isInkMeterUser(inkOp), isTrue);
    notifier.stop();
  });
}
