import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/services/whats_new_service.dart';

void main() {
  group('WhatsNewService.extractLatestEntry', () {
    test('returns the first ## section without the trailing divider', () {
      const changelog = '''
# CTP Job Cards — Documentation Changelog

Append-only log of user-visible changes.

---

## 2026-07-03 — Newest release

### Feature A

- Bullet one
- Bullet two

---

## 2026-07-02 — Older release

- Old bullet
''';
      final entry = WhatsNewService.extractLatestEntry(changelog);
      expect(entry, isNotNull);
      expect(entry, startsWith('## 2026-07-03 — Newest release'));
      expect(entry, contains('Bullet two'));
      expect(entry, isNot(contains('Older release')));
      expect(entry!.endsWith('---'), isFalse);
    });

    test('handles a changelog with a single entry and no trailing divider',
        () {
      const changelog = '''
# Title

## 2026-07-03 — Only release

- The only bullet
''';
      final entry = WhatsNewService.extractLatestEntry(changelog);
      expect(entry, startsWith('## 2026-07-03 — Only release'));
      expect(entry, contains('The only bullet'));
    });

    test('returns null when no ## heading exists', () {
      expect(WhatsNewService.extractLatestEntry('# Just a title\n\ntext'),
          isNull);
      expect(WhatsNewService.extractLatestEntry(''), isNull);
    });

    test('does not treat ### subsections as entry boundaries', () {
      const changelog = '''
## 2026-07-03 — Release

### Section one

- a

### Section two

- b
''';
      final entry = WhatsNewService.extractLatestEntry(changelog);
      expect(entry, contains('Section one'));
      expect(entry, contains('Section two'));
    });
  });

  group('WhatsNewService.extractEntriesSince', () {
    const changelog = '''
# Title

## 2026-07-08 — Version 2.3.0 (build 131) — Newest

- New feature

---

## 2026-07-06 — Version 2.3.0 (build 121) — Mid

- Mid feature

---

## 2026-07-01 — Version 2.1.1 (build 38) — Old

- Old feature
''';

    test('null lastSeen returns only the latest entry', () {
      final md = WhatsNewService.extractEntriesSince(changelog, null);
      expect(md, contains('build 131'));
      expect(md, isNot(contains('build 121')));
    });

    test('rolls up numbered builds newer than lastSeen', () {
      final md = WhatsNewService.extractEntriesSince(changelog, 38);
      expect(md, contains('build 131'));
      expect(md, contains('build 121'));
      expect(md, isNot(contains('build 38')));
    });

    test('when already past all numbered builds falls back to latest', () {
      final md = WhatsNewService.extractEntriesSince(changelog, 200);
      expect(md, contains('build 131'));
    });

    test('parseBuildFromHeading supports paren and bare forms', () {
      expect(
        WhatsNewService.parseBuildFromHeading('## x (build 121) — y'),
        121,
      );
      expect(
        WhatsNewService.parseBuildFromHeading('## Version 2.3.0 build 99'),
        99,
      );
      expect(WhatsNewService.parseBuildFromHeading('## No number here'), isNull);
    });
  });
}
