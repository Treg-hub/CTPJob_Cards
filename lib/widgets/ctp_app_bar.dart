import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show realEmployee;
import '../models/employee.dart';
import '../providers/current_employee_provider.dart';
import '../theme/app_theme.dart';

/// Job Cards app bar — brand orange with on-site/off-site gradient (matches home shell).
///
/// Subscribes to the employee doc stream when a clock number is known so pushed
/// screens (History, View Jobs, etc.) stay in sync with presence without relying
/// on Home invalidating [currentEmployeeProvider].
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
  /// Explicit override; when null, reads live presence from the employee stream.
  final bool? isOnSite;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  String? _clockNo(WidgetRef ref) =>
      realEmployee?.clockNo ??
      ref.watch(currentEmployeeProvider).valueOrNull?.clockNo;

  bool _fallbackOnSite(WidgetRef ref) {
    final fromProvider = ref.watch(currentEmployeeProvider).valueOrNull?.isOnSite;
    if (fromProvider != null) return fromProvider;
    return realEmployee?.isOnSite ?? true;
  }

  Widget _buildBar(BuildContext context, bool onSite) {
    final appBarTheme = Theme.of(context).appBarTheme;
    return AppBar(
      title: Text(title),
      leading: leading,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      foregroundColor: appBarTheme.foregroundColor ?? Colors.black,
      iconTheme: appBarTheme.iconTheme,
      actionsIconTheme: appBarTheme.actionsIconTheme,
      titleTextStyle: appBarTheme.titleTextStyle,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isOnSite != null) {
      return _buildBar(context, isOnSite!);
    }

    final clockNo = _clockNo(ref);
    if (clockNo == null) {
      return _buildBar(context, _fallbackOnSite(ref));
    }

    final service = ref.read(firestoreServiceProvider);
    return StreamBuilder<Employee>(
      stream: service.getEmployeeStream(clockNo),
      initialData:
          realEmployee?.clockNo == clockNo ? realEmployee : null,
      builder: (context, snapshot) {
        final onSite = snapshot.data?.isOnSite ?? _fallbackOnSite(ref);
        return _buildBar(context, onSite);
      },
    );
  }
}