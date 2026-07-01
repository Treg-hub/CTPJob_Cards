import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/ink_daily_readings_status.dart';

void main() {
  group('InkDailyReadingsStatus.bannerMessage', () {
    test('all toloul pending when none captured', () {
      const status = InkDailyReadingsStatus(
        needsInk: true,
        needsToloul: true,
        inkDone: true,
        toloulDone: false,
        toloulCapturedCount: 0,
        toloulRequiredCount: 5,
        missingToloulPointNames: ['Press 1', 'Press 2'],
      );
      expect(status.bannerMessage, 'Ink done · toloul pending');
    });

    test('partial toloul shows progress and missing names', () {
      const status = InkDailyReadingsStatus(
        needsInk: true,
        needsToloul: true,
        inkDone: true,
        toloulDone: false,
        toloulCapturedCount: 3,
        toloulRequiredCount: 7,
        missingToloulPointNames: ['Press 4', 'Lurgi recovery'],
      );
      expect(
        status.bannerMessage,
        'Ink done · toloul 3/7 done — still need: Press 4, Lurgi recovery',
      );
    });

    test('partial toloul with many missing summarizes count', () {
      const status = InkDailyReadingsStatus(
        needsInk: true,
        needsToloul: true,
        inkDone: true,
        toloulDone: false,
        toloulCapturedCount: 2,
        toloulRequiredCount: 8,
        missingToloulPointNames: ['A', 'B', 'C', 'D', 'E', 'F'],
      );
      expect(
        status.bannerMessage,
        'Ink done · toloul 2/8 done — 6 meters still needed',
      );
    });

    test('complete clears banner via complete getter', () {
      const status = InkDailyReadingsStatus(
        needsInk: true,
        needsToloul: true,
        inkDone: true,
        toloulDone: true,
        toloulCapturedCount: 4,
        toloulRequiredCount: 4,
      );
      expect(status.complete, isTrue);
    });
  });
}