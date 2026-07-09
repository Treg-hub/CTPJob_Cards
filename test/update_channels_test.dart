import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/utils/update_channels.dart';

void main() {
  group('resolveUpdateChannel', () {
    final defaultCh = UpdateChannel(
      id: 'default',
      latestVersion: '2.3.0',
      latestBuild: '100',
      downloadUrl: 'https://example.com/app.apk',
    );
    final ink = UpdateChannel(
      id: 'ink',
      match: const UpdateChannelMatch(departments: ['Ink Factory']),
      latestVersion: '2.3.0',
      latestBuild: '110',
      forceUpdate: true,
      downloadUrl: 'https://example.com/ink.apk',
    );
    final testers = UpdateChannel(
      id: 'testers',
      match: const UpdateChannelMatch(clockNos: ['22', '50']),
      latestVersion: '2.4.0',
      latestBuild: '200',
      forceUpdate: true,
      downloadUrl: 'https://example.com/dev.apk',
    );

    test('prefers testers clock list over ink and default', () {
      final c = resolveUpdateChannel(
        [defaultCh, ink, testers],
        clockNo: '22',
        department: 'Ink Factory',
      );
      expect(c?.id, 'testers');
      expect(c?.forceUpdate, isTrue);
    });

    test('matches ink by department', () {
      final c = resolveUpdateChannel(
        [defaultCh, ink, testers],
        clockNo: '99',
        department: 'Ink Factory',
      );
      expect(c?.id, 'ink');
      expect(c?.latestBuild, '110');
    });

    test('falls back to default for other staff', () {
      final c = resolveUpdateChannel(
        [defaultCh, ink, testers],
        clockNo: '99',
        department: 'Workshop',
      );
      expect(c?.id, 'default');
      expect(c?.latestBuild, '100');
    });

    test('ignores disabled channels', () {
      final disabledInk = ink.copyWith(enabled: false);
      final c = resolveUpdateChannel(
        [defaultCh, disabledInk],
        clockNo: '1',
        department: 'Ink Factory',
      );
      expect(c?.id, 'default');
    });
  });

  group('resolveKillSwitchDownloadUrl', () {
    test('prefers shared updateDownloadUrl', () {
      expect(
        resolveKillSwitchDownloadUrl({
          'updateDownloadUrl': 'https://shared/app.apk',
          'updateChannels': {
            'default': {
              'enabled': true,
              'downloadUrl': 'https://channel/default.apk',
              'latestVersion': '2.3.0',
            },
          },
        }),
        'https://shared/app.apk',
      );
    });

    test('falls back to default channel when shared empty', () {
      expect(
        resolveKillSwitchDownloadUrl({
          'updateDownloadUrl': '',
          'updateChannels': {
            'default': {
              'enabled': true,
              'downloadUrl': 'https://channel/default.apk',
              'latestVersion': '2.3.0',
              'latestBuild': '140',
            },
            'ink': {
              'enabled': true,
              'downloadUrl': 'https://channel/ink.apk',
              'latestVersion': '2.3.0',
            },
          },
        }),
        'https://channel/default.apk',
      );
    });

    test('falls back to ink channel when default has no url', () {
      expect(
        resolveKillSwitchDownloadUrl({
          'updateChannels': {
            'default': {
              'enabled': true,
              'latestVersion': '2.3.0',
              'latestBuild': '100',
            },
            'ink': {
              'enabled': true,
              'downloadUrl': 'https://channel/ink.apk',
              'latestVersion': '2.3.0',
            },
          },
        }),
        'https://channel/ink.apk',
      );
    });

    test('returns empty when nothing configured', () {
      expect(resolveKillSwitchDownloadUrl(null), '');
      expect(resolveKillSwitchDownloadUrl({}), '');
    });
  });

  group('channelsFromSettingsApp', () {
    test('legacy-only doc becomes default channel', () {
      final list = channelsFromSettingsApp({
        'publishedLatestVersion': '2.1.0',
        'publishedLatestBuild': '90',
        'updateDownloadUrl': 'https://x/a.apk',
        'publishedForceUpdate': false,
      });
      expect(list, hasLength(1));
      expect(list.first.id, 'default');
      expect(list.first.latestBuild, '90');
      expect(list.first.downloadUrl, 'https://x/a.apk');
    });

    test('fills empty channel url from shared download url', () {
      final list = channelsFromSettingsApp({
        'updateDownloadUrl': 'https://shared/app.apk',
        'updateChannels': {
          'ink': {
            'enabled': true,
            'match': {
              'departments': ['Ink Factory']
            },
            'latestVersion': '2.3.0',
            'latestBuild': '136',
            'downloadUrl': '',
            'forceUpdate': true,
          },
        },
        'publishedLatestVersion': '2.3.0',
        'publishedLatestBuild': '135',
      });
      final ink = list.firstWhere((c) => c.id == 'ink');
      expect(ink.downloadUrl, 'https://shared/app.apk');
      expect(list.any((c) => c.id == 'default'), isTrue);
    });
  });

  group('legacyPublishFieldsFromDefault', () {
    test('mirrors default for old clients', () {
      final m = legacyPublishFieldsFromDefault(
        const UpdateChannel(
          id: 'default',
          latestVersion: '2.3.0',
          latestBuild: '135',
          downloadUrl: 'https://x/a.apk',
          forceUpdate: false,
          releaseNotes: 'notes',
        ),
      );
      expect(m['publishedLatestBuild'], '135');
      expect(m['publishedForceUpdate'], false);
      expect(m['updateDownloadUrl'], 'https://x/a.apk');
    });
  });
}
