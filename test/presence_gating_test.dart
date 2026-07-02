import 'package:ctp_job_cards/models/employee.dart';
import 'package:ctp_job_cards/models/fleet_settings.dart';
import 'package:ctp_job_cards/utils/presence_gating.dart';
import 'package:flutter_test/flutter_test.dart';

Employee _emp({
  String clockNo = '100',
  String department = 'Production',
  bool isAdmin = false,
}) =>
    Employee(
      clockNo: clockNo,
      name: 'Test',
      position: 'Operator',
      department: department,
      isAdmin: isAdmin,
    );

const _fleetSettings = FleetSettings(
  fleetEnabled: true,
  reporterDepartments: ['Production'],
  mechanicClockNos: ['200'],
);

void main() {
  group('PresenceGating.canUseOnSiteOnlyModules', () {
    test('on-site floor user allowed', () {
      expect(
        PresenceGating.canUseOnSiteOnlyModules(emp: _emp(), isOnSite: true),
        isTrue,
      );
    });

    test('off-site floor user blocked', () {
      expect(
        PresenceGating.canUseOnSiteOnlyModules(emp: _emp(), isOnSite: false),
        isFalse,
      );
    });

    test('off-site admin allowed', () {
      expect(
        PresenceGating.canUseOnSiteOnlyModules(
          emp: _emp(isAdmin: true),
          isOnSite: false,
        ),
        isTrue,
      );
    });
  });

  group('PresenceGating.showFleetTab', () {
    test('mechanic off-site sees fleet', () {
      final mechanic = _emp(clockNo: '200', department: 'Workshop');
      expect(
        PresenceGating.showFleetTab(
          emp: mechanic,
          settings: _fleetSettings,
          isOnSite: false,
        ),
        isTrue,
      );
    });

    test('reporter off-site hidden', () {
      expect(
        PresenceGating.showFleetTab(
          emp: _emp(department: 'Production'),
          settings: _fleetSettings,
          isOnSite: false,
        ),
        isFalse,
      );
    });

    test('reporter on-site visible', () {
      expect(
        PresenceGating.showFleetTab(
          emp: _emp(department: 'Production'),
          settings: _fleetSettings,
          isOnSite: true,
        ),
        isTrue,
      );
    });

    test('dual-role off-site uses mechanic access', () {
      final dual = _emp(clockNo: '200', department: 'Production');
      expect(
        PresenceGating.showFleetTab(
          emp: dual,
          settings: _fleetSettings,
          isOnSite: false,
        ),
        isTrue,
      );
    });

    test('off-site admin sees fleet when mobile user', () {
      expect(
        PresenceGating.showFleetTab(
          emp: _emp(isAdmin: true, department: 'Production'),
          settings: _fleetSettings,
          isOnSite: false,
        ),
        isTrue,
      );
    });
  });

  group('PresenceGating.canCreateJobCard', () {
    test('on-site floor allowed', () {
      expect(
        PresenceGating.canCreateJobCard(emp: _emp(), isOnSite: true),
        isTrue,
      );
    });

    test('off-site floor blocked', () {
      expect(
        PresenceGating.canCreateJobCard(emp: _emp(), isOnSite: false),
        isFalse,
      );
    });

    test('off-site manager blocked (no bypass)', () {
      final manager = Employee(
        clockNo: '300',
        name: 'Mgr',
        position: 'Mechanical Manager',
        department: 'Mechanical',
      );
      expect(
        PresenceGating.canCreateJobCard(emp: manager, isOnSite: false),
        isFalse,
      );
    });

    test('off-site admin allowed', () {
      expect(
        PresenceGating.canCreateJobCard(
          emp: _emp(isAdmin: true),
          isOnSite: false,
        ),
        isTrue,
      );
    });
  });

  group('PresenceGating.canUseReporterFleetActions', () {
    test('reporter off-site blocked', () {
      expect(
        PresenceGating.canUseReporterFleetActions(
          emp: _emp(department: 'Production'),
          settings: _fleetSettings,
          isOnSite: false,
        ),
        isFalse,
      );
    });

    test('mechanic not a reporter action user', () {
      expect(
        PresenceGating.canUseReporterFleetActions(
          emp: _emp(clockNo: '200', department: 'Workshop'),
          settings: _fleetSettings,
          isOnSite: true,
        ),
        isFalse,
      );
    });
  });

  group('PresenceGating.isReporterOnlyOffSiteBlocked', () {
    test('reporter only off-site blocked', () {
      expect(
        PresenceGating.isReporterOnlyOffSiteBlocked(
          emp: _emp(department: 'Production'),
          settings: _fleetSettings,
          isOnSite: false,
        ),
        isTrue,
      );
    });

    test('mechanic off-site not blocked', () {
      expect(
        PresenceGating.isReporterOnlyOffSiteBlocked(
          emp: _emp(clockNo: '200', department: 'Workshop'),
          settings: _fleetSettings,
          isOnSite: false,
        ),
        isFalse,
      );
    });

    test('dual-role off-site not reporter-only blocked', () {
      expect(
        PresenceGating.isReporterOnlyOffSiteBlocked(
          emp: _emp(clockNo: '200', department: 'Production'),
          settings: _fleetSettings,
          isOnSite: false,
        ),
        isFalse,
      );
    });
  });
}