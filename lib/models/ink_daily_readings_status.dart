/// Combined ink + toloul daily-readings completion for hub banners.
class InkDailyReadingsStatus {
  const InkDailyReadingsStatus({
    required this.needsInk,
    required this.needsToloul,
    required this.inkDone,
    required this.toloulDone,
  });

  final bool needsInk;
  final bool needsToloul;
  final bool inkDone;
  final bool toloulDone;

  bool get complete =>
      (!needsInk || inkDone) && (!needsToloul || toloulDone);

  /// User-facing banner text with optional ink/toloul split.
  String get bannerMessage {
    if (!inkDone && needsToloul && !toloulDone) {
      return 'Daily readings incomplete — ink and toloul meters still needed.';
    }
    if (inkDone && needsToloul && !toloulDone) {
      return 'Ink done · Toloul pending';
    }
    if (!inkDone && toloulDone && needsInk) {
      return 'Toloul done · Ink pending';
    }
    if (!inkDone) return 'Ink meter readings not captured yet today.';
    if (needsToloul && !toloulDone) {
      return 'Toloul meter readings not captured yet today.';
    }
    return 'Daily readings incomplete.';
  }
}