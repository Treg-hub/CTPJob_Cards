import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Impression Rollers solid orange app bar — **black** title/icons (same rule as
/// [CtpAppBar] / global AppBarTheme; light and dark).
class ImpressionAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ImpressionAppBar({
    super.key,
    required this.title,
    this.actions,
    this.bottom,
    this.leading,
  });

  final String title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Widget? leading;

  /// Product rule: always black on orange.
  static const Color fg = Colors.black;

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(
        title,
        style: const TextStyle(
          color: fg,
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
      ),
      leading: leading,
      backgroundColor: kBrandOrange,
      foregroundColor: fg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      iconTheme: const IconThemeData(color: fg),
      actionsIconTheme: const IconThemeData(color: fg),
      actions: actions,
      bottom: bottom,
    );
  }
}
