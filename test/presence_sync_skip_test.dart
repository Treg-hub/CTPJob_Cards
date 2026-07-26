import 'package:flutter_test/flutter_test.dart';

import 'package:ctp_job_cards/utils/presence_sync_skip.dart';

void main() {
  group('PresenceSyncSkip.fingerprint', () {
    test('is stable across key order', () {
      final a = PresenceSyncSkip.fingerprint({
        'clientPlatform': 'android',
        'fcmToken': 'tok',
      });
      final b = PresenceSyncSkip.fingerprint({
        'fcmToken': 'tok',
        'clientPlatform': 'android',
      });
      expect(a, b);
    });

    test('ignores source', () {
      final a = PresenceSyncSkip.fingerprint({
        'fcmToken': 'tok',
        'source': 'app_open_check',
      });
      final b = PresenceSyncSkip.fingerprint({'fcmToken': 'tok'});
      expect(a, b);
    });

    test('normalizes nested permission maps', () {
      final a = PresenceSyncSkip.fingerprint({
        'permissions': {
          'location': {'granted': true, 'version': 1},
          'notifications': {'granted': false, 'version': 1},
        },
      });
      final b = PresenceSyncSkip.fingerprint({
        'permissions': {
          'notifications': {'version': 1, 'granted': false},
          'location': {'version': 1, 'granted': true},
        },
      });
      expect(a, b);
    });
  });

  group('PresenceSyncSkip.shouldSkip', () {
    final now = DateTime.utc(2026, 7, 26, 4, 0);

    test('never skips when isOnSite is present', () {
      expect(
        PresenceSyncSkip.shouldSkip(
          payload: {'isOnSite': true},
          force: false,
          lastFingerprint: PresenceSyncSkip.fingerprint({'isOnSite': true}),
          lastSuccessAt: now,
          now: now,
        ),
        isFalse,
      );
    });

    test('skips identical non-presence within TTL', () {
      final payload = {'fcmToken': 'abc'};
      final fp = PresenceSyncSkip.fingerprint(payload);
      expect(
        PresenceSyncSkip.shouldSkip(
          payload: payload,
          force: false,
          lastFingerprint: fp,
          lastSuccessAt: now.subtract(const Duration(minutes: 10)),
          now: now,
        ),
        isTrue,
      );
    });

    test('does not skip when force is true', () {
      final payload = {'fcmToken': 'abc'};
      final fp = PresenceSyncSkip.fingerprint(payload);
      expect(
        PresenceSyncSkip.shouldSkip(
          payload: payload,
          force: true,
          lastFingerprint: fp,
          lastSuccessAt: now,
          now: now,
        ),
        isFalse,
      );
    });

    test('does not skip when TTL expired', () {
      final payload = {'fcmToken': 'abc'};
      final fp = PresenceSyncSkip.fingerprint(payload);
      expect(
        PresenceSyncSkip.shouldSkip(
          payload: payload,
          force: false,
          lastFingerprint: fp,
          lastSuccessAt: now.subtract(const Duration(minutes: 46)),
          now: now,
        ),
        isFalse,
      );
    });

    test('does not skip when fingerprint differs', () {
      expect(
        PresenceSyncSkip.shouldSkip(
          payload: {'fcmToken': 'new'},
          force: false,
          lastFingerprint: PresenceSyncSkip.fingerprint({'fcmToken': 'old'}),
          lastSuccessAt: now,
          now: now,
        ),
        isFalse,
      );
    });
  });
}
