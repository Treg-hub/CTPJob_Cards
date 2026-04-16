import 'package:flutter/material.dart';

class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.priority1,
    required this.priority2,
    required this.priority3,
    required this.priority4,
    required this.priority5,
    required this.statusOpen,
    required this.statusInProgress,
    required this.statusCompleted,
    required this.statusCancelled,
  });

  final Color priority1;
  final Color priority2;
  final Color priority3;
  final Color priority4;
  final Color priority5;
  final Color statusOpen;
  final Color statusInProgress;
  final Color statusCompleted;
  final Color statusCancelled;

  @override
  ThemeExtension<AppColors> copyWith({
    Color? priority1,
    Color? priority2,
    Color? priority3,
    Color? priority4,
    Color? priority5,
    Color? statusOpen,
    Color? statusInProgress,
    Color? statusCompleted,
    Color? statusCancelled,
  }) {
    return AppColors(
      priority1: priority1 ?? this.priority1,
      priority2: priority2 ?? this.priority2,
      priority3: priority3 ?? this.priority3,
      priority4: priority4 ?? this.priority4,
      priority5: priority5 ?? this.priority5,
      statusOpen: statusOpen ?? this.statusOpen,
      statusInProgress: statusInProgress ?? this.statusInProgress,
      statusCompleted: statusCompleted ?? this.statusCompleted,
      statusCancelled: statusCancelled ?? this.statusCancelled,
    );
  }

  @override
  ThemeExtension<AppColors> lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) {
      return this;
    }
    return AppColors(
      priority1: Color.lerp(priority1, other.priority1, t)!,
      priority2: Color.lerp(priority2, other.priority2, t)!,
      priority3: Color.lerp(priority3, other.priority3, t)!,
      priority4: Color.lerp(priority4, other.priority4, t)!,
      priority5: Color.lerp(priority5, other.priority5, t)!,
      statusOpen: Color.lerp(statusOpen, other.statusOpen, t)!,
      statusInProgress: Color.lerp(statusInProgress, other.statusInProgress, t)!,
      statusCompleted: Color.lerp(statusCompleted, other.statusCompleted, t)!,
      statusCancelled: Color.lerp(statusCancelled, other.statusCancelled, t)!,
    );
  }
}

extension AppThemeExtension on ThemeData {
  AppColors get appColors => extension<AppColors>()!;
}