/// Combined ink + toloul daily-readings completion for hub banners.
class InkDailyReadingsStatus {
  const InkDailyReadingsStatus({
    required this.needsInk,
    required this.needsToloul,
    required this.inkDone,
    required this.toloulDone,
    this.inkCapturedCount = 0,
    this.inkRequiredCount = 0,
    this.toloulCapturedCount = 0,
    this.toloulRequiredCount = 0,
    this.missingToloulPointNames = const [],
  });

  final bool needsInk;
  final bool needsToloul;
  final bool inkDone;
  final bool toloulDone;
  final int inkCapturedCount;
  final int inkRequiredCount;
  final int toloulCapturedCount;
  final int toloulRequiredCount;
  final List<String> missingToloulPointNames;

  bool get complete =>
      (!needsInk || inkDone) && (!needsToloul || toloulDone);

  bool get toloulPartiallyDone =>
      needsToloul && toloulCapturedCount > 0 && !toloulDone;

  /// User-facing banner text with optional ink/toloul split.
  String get bannerMessage {
    if (!inkDone && needsToloul && !toloulDone) {
      if (toloulPartiallyDone) {
        return _toloulProgressPrefix('Daily readings incomplete — ink still needed · ');
      }
      return 'Daily readings incomplete — ink and toloul meters still needed.';
    }
    if (inkDone && needsToloul && !toloulDone) {
      return _toloulProgressPrefix('Ink done · ');
    }
    if (!inkDone && toloulDone && needsInk) {
      return 'Toloul done · Ink pending';
    }
    if (!inkDone) return 'Ink meter readings not captured yet today.';
    if (needsToloul && !toloulDone) {
      if (toloulPartiallyDone) {
        return _toloulProgressPrefix('');
      }
      return 'Toloul meter readings not captured yet today.';
    }
    return 'Daily readings incomplete.';
  }

  String _toloulProgressPrefix(String prefix) {
    if (toloulRequiredCount <= 0) {
      return '${prefix}toloul pending';
    }
    if (toloulCapturedCount <= 0) {
      return '${prefix}toloul pending';
    }
    final progress =
        'toloul $toloulCapturedCount/$toloulRequiredCount done';
    if (missingToloulPointNames.isEmpty) {
      return '$prefix$progress';
    }
    if (missingToloulPointNames.length <= 2) {
      return '$prefix$progress — still need: ${missingToloulPointNames.join(', ')}';
    }
    return '$prefix$progress — ${missingToloulPointNames.length} meters still needed';
  }
}