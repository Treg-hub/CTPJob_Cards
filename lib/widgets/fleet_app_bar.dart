import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Fleet Maintenance app bar — orange bar with black foreground from [AppBarTheme].
class FleetAppBar extends StatelessWidget implements PreferredSizeWidget {
  const FleetAppBar({
    super.key,
    required this.title,
    this.actions,
  });

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final appBarTheme = Theme.of(context).appBarTheme;
    return AppBar(
      title: Text(title),
      backgroundColor: appBarTheme.backgroundColor ?? kBrandOrange,
      foregroundColor: appBarTheme.foregroundColor ?? Colors.black,
      iconTheme: appBarTheme.iconTheme,
      actionsIconTheme: appBarTheme.actionsIconTheme,
      titleTextStyle: appBarTheme.titleTextStyle,
      actions: actions,
    );
  }
}