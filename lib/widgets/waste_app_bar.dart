import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class WasteAppBar extends StatelessWidget implements PreferredSizeWidget {
  const WasteAppBar({
    super.key,
    required this.title,
    this.isOnSite,
    this.actions,
  });

  final String title;
  // null = solid waste-green (admin/neutral); true/false = gradient reflecting onsite status
  final bool? isOnSite;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final wasteGreen = Theme.of(context).appColors.wasteGreen;
    return AppBar(
      title: Text(title),
      // Waste green is dark (~8.75:1 contrast with white); override the global black foreground.
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w500,
      ),
      backgroundColor: isOnSite == null ? wasteGreen : null,
      flexibleSpace: isOnSite == null
          ? null
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [wasteGreen, isOnSite! ? Colors.green : Colors.red],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
      actions: actions,
    );
  }
}
