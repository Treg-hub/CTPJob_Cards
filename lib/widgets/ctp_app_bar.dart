import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show realEmployee;
import '../providers/current_employee_provider.dart';
import '../theme/app_theme.dart';

/// Job Cards app bar — brand orange with on-site/off-site gradient (matches home shell).
///
/// Presence is read from [isOnSite] when provided, otherwise from the shared
/// [realEmployee] / [currentEmployeeProvider] state that Home already keeps live
/// via a single employee doc stream. This widget intentionally does **not** open
/// a second Firestore listener (Phase A read discipline).
class CtpAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const CtpAppBar({
    super.key,
    required this.title,
    this.isOnSite,
    this.actions,
    this.leading,
    this.bottom,
  });

  final String title;
  /// Explicit override when the caller already has presence (preferred).
  final bool? isOnSite;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  bool _resolveOnSite(WidgetRef ref) {
    if (isOnSite != null) return isOnSite!;
    final fromProvider =
        ref.watch(currentEmployeeProvider).valueOrNull?.isOnSite;
    if (fromProvider != null) return fromProvider;
    return realEmployee?.isOnSite ?? true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSite = _resolveOnSite(ref);
    // Solid product rule: title + icons always black on orange (and on the
    // orange→green/red presence gradient). Same in light and dark theme.
    const fg = Colors.black;
    return AppBar(
      title: Text(title, style: const TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w500)),
      leading: leading,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      foregroundColor: fg,
      iconTheme: const IconThemeData(color: fg),
      actionsIconTheme: const IconThemeData(color: fg),
      titleTextStyle: const TextStyle(
        color: fg,
        fontSize: 20,
        fontWeight: FontWeight.w500,
      ),
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [kBrandOrange, onSite ? Colors.green : Colors.red],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      actions: actions,
      bottom: bottom,
    );
  }
}
