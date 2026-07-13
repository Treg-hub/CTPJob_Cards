import 'package:flutter/material.dart';

/// Consistent safe-area and chrome clearance for scrollable content and bottom bars.
///
/// Use [scrollBottomFullScreen] on pushed routes (create/detail screens).
/// Use [scrollBottomInHomeShell] for tabs inside [HomeScreen]'s bottom nav shell.
abstract final class ScreenInsets {
  static const double spacing = 16;

  /// System gesture bar / home-indicator inset.
  static double bottomSafe(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom;

  /// Standard FAB height + scaffold margin.
  static double fabClearance({bool extended = false}) =>
      (extended ? 48.0 : 56.0) + spacing * 2;

  /// Bottom padding for a full-screen route (no parent bottom nav).
  static double scrollBottomFullScreen(
    BuildContext context, {
    bool clearFab = false,
    bool extendedFab = false,
    double extra = spacing,
  }) {
    var bottom = bottomSafe(context) + extra;
    if (clearFab) bottom += fabClearance(extended: extendedFab);
    return bottom;
  }

  /// Bottom padding for content inside [HomeScreen]'s shell body (selected tab only).
  /// The outer bottom nav already consumes vertical space; only FAB overlap
  /// within module tabs needs extra clearance.
  static double scrollBottomInHomeShell({
    bool clearFab = false,
    bool extendedFab = false,
    double extra = spacing,
  }) {
    var bottom = extra;
    if (clearFab) bottom += fabClearance(extended: extendedFab);
    return bottom;
  }

  static EdgeInsets listPadding(
    BuildContext context, {
    double horizontal = 8,
    double top = 4,
    bool inHomeShell = false,
    bool clearFab = false,
    bool extendedFab = false,
    double extra = spacing,
  }) {
    final bottom = inHomeShell
        ? scrollBottomInHomeShell(
            clearFab: clearFab,
            extendedFab: extendedFab,
            extra: extra,
          )
        : scrollBottomFullScreen(
            context,
            clearFab: clearFab,
            extendedFab: extendedFab,
            extra: extra,
          );
    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }

  static EdgeInsets symmetricScroll(
    BuildContext context, {
    double horizontal = 20,
    double vertical = 20,
    bool inHomeShell = false,
    bool clearFab = false,
    bool extendedFab = false,
  }) {
    final bottom = inHomeShell
        ? scrollBottomInHomeShell(clearFab: clearFab, extendedFab: extendedFab)
        : scrollBottomFullScreen(
            context,
            clearFab: clearFab,
            extendedFab: extendedFab,
          );
    return EdgeInsets.fromLTRB(horizontal, vertical, horizontal, bottom);
  }
}

/// Wraps bottom action bars and navigation bars so controls stay above the
/// system gesture area.
class SafeBottomBar extends StatelessWidget {
  const SafeBottomBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: ScreenInsets.spacing),
      child: Padding(padding: padding, child: child),
    );
  }
}