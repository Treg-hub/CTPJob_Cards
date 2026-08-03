import 'package:ctp_job_cards/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveOnSiteFromFix', () {
    test('promotes off→on only inside radius with good accuracy', () {
      expect(
        resolveOnSiteFromFix(
          currentlyOnSite: false,
          distM: 100,
          radiusM: 400,
          accuracyM: 40,
        ),
        isTrue,
      );
      expect(
        resolveOnSiteFromFix(
          currentlyOnSite: false,
          distM: 500,
          radiusM: 400,
          accuracyM: 40,
        ),
        isFalse,
      );
    });

    test('refuses promote when accuracy is poor (home-quiet + dead zone)', () {
      expect(
        resolveOnSiteFromFix(
          currentlyOnSite: false,
          distM: 50,
          radiusM: 400,
          accuracyM: 300,
        ),
        isNull,
      );
    });

    test('sticky on-site: bad accuracy does not demote (factory dead zone)', () {
      expect(
        resolveOnSiteFromFix(
          currentlyOnSite: true,
          distM: 100,
          radiusM: 400,
          accuracyM: 500,
        ),
        isNull,
      );
      expect(
        resolveOnSiteFromFix(
          currentlyOnSite: true,
          distM: 200,
          radiusM: 400,
          accuracyM: 300,
        ),
        isNull, // above maxExitAccuracy (250)
      );
    });

    test('sticky on-site: stays on within radius+hysteresis', () {
      expect(
        resolveOnSiteFromFix(
          currentlyOnSite: true,
          distM: 500, // 400+150 = 550
          radiusM: 400,
          accuracyM: 50,
        ),
        isTrue,
      );
    });

    test('demotes only when clearly outside with usable accuracy', () {
      expect(
        resolveOnSiteFromFix(
          currentlyOnSite: true,
          distM: 700,
          radiusM: 400,
          accuracyM: 50,
        ),
        isFalse,
      );
    });
  });
}
