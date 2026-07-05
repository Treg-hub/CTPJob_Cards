import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Fleet Maintenance app bar — brand orange with optional on-site/off-site gradient.
class FleetAppBar extends StatelessWidget implements PreferredSizeWidget {
  const FleetAppBar({
    super.key,
    required this.title,
    this.isOnSite,
    this.actions,
  });

  final String title;
  /// null = solid brand orange; true/false = orange → green/red gradient.
  final bool? isOnSite;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final appBarTheme = Theme.of(context).appBarTheme;
    return AppBar(
      title: Text(title),
      backgroundColor: isOnSite == null ? kBrandOrange : null,
      foregroundColor: appBarTheme.foregroundColor ?? Colors.black,
      iconTheme: appBarTheme.iconTheme,
      actionsIconTheme: appBarTheme.actionsIconTheme,
      titleTextStyle: appBarTheme.titleTextStyle,
      flexibleSpace: isOnSite == null
          ? null
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [kBrandOrange, isOnSite! ? Colors.green : Colors.red],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
      actions: actions,
    );
  }
}