import 'package:flutter/material.dart';

const kBrandOrange = Color(0xFFFF8C42);

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
    required this.navBarBackground,
    required this.inputFill,
    required this.chipUnselectedLabel,
    required this.cardSurface,
    required this.textMuted,
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
  final Color navBarBackground;
  final Color inputFill;
  final Color chipUnselectedLabel;
  final Color cardSurface;
  final Color textMuted;

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
    Color? navBarBackground,
    Color? inputFill,
    Color? chipUnselectedLabel,
    Color? cardSurface,
    Color? textMuted,
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
      navBarBackground: navBarBackground ?? this.navBarBackground,
      inputFill: inputFill ?? this.inputFill,
      chipUnselectedLabel: chipUnselectedLabel ?? this.chipUnselectedLabel,
      cardSurface: cardSurface ?? this.cardSurface,
      textMuted: textMuted ?? this.textMuted,
    );
  }

  @override
  ThemeExtension<AppColors> lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
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
      navBarBackground: Color.lerp(navBarBackground, other.navBarBackground, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      chipUnselectedLabel: Color.lerp(chipUnselectedLabel, other.chipUnselectedLabel, t)!,
      cardSurface: Color.lerp(cardSurface, other.cardSurface, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
    );
  }
}

const _priorityColors = AppColors(
  priority1: Color(0xFF4CAF50),
  priority2: Color(0xFF8BC34A),
  priority3: Color(0xFFFFC107),
  priority4: Color(0xFFFF9800),
  priority5: Color(0xFFFF3D00),
  statusOpen: Colors.blue,
  statusInProgress: Colors.orange,
  statusCompleted: Colors.green,
  statusCancelled: Colors.red,
  navBarBackground: Colors.white,
  inputFill: Color(0xFFF0F0F0),
  chipUnselectedLabel: Colors.black87,
  cardSurface: Colors.white,
  textMuted: Colors.black54,
);

const AppColors lightAppColors = _priorityColors;

const AppColors darkAppColors = AppColors(
  priority1: Color(0xFF4CAF50),
  priority2: Color(0xFF8BC34A),
  priority3: Color(0xFFFFC107),
  priority4: Color(0xFFFF9800),
  priority5: Color(0xFFFF3D00),
  statusOpen: Colors.blue,
  statusInProgress: Colors.orange,
  statusCompleted: Colors.green,
  statusCancelled: Colors.red,
  navBarBackground: Color(0xFF1A1A1A),
  inputFill: Color(0xFF1A1A1A),
  chipUnselectedLabel: Colors.white,
  cardSurface: Color(0xFF1A1A1A),
  textMuted: Colors.white70,
);

extension AppThemeExtension on ThemeData {
  AppColors get appColors => extension<AppColors>()!;
}
