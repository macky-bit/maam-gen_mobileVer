import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF0D0817);
  static const inkSoft = Color(0xFF171025);
  static const card = Color(0xFF241638);
  static const violet = Color(0xFF7C3AED);
  static const violetLight = Color(0xFF9B6DF3);
  static const violetDeep = Color(0xFF4C1D95);
  static const gold = Color(0xFFF5A800);
  static const orange = Color(0xFFFF6B00);
  static const muted = Color(0xFFAAA3B4);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.violet,
    brightness: Brightness.dark,
    surface: AppColors.inkSoft,
  );
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.ink,
    useMaterial3: true,
    fontFamily: 'Arial',
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -1.5),
      headlineLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.8),
      headlineMedium: TextStyle(
        fontWeight: FontWeight.w800,
        letterSpacing: -.5,
      ),
      titleLarge: TextStyle(fontWeight: FontWeight.w800),
      titleMedium: TextStyle(fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(height: 1.45),
      bodyMedium: TextStyle(height: 1.4),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: const Color(0xFF1A1000),
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: .07),
      hintStyle: const TextStyle(color: AppColors.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.violetLight, width: 1.5),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF130C20),
      indicatorColor: AppColors.violet.withValues(alpha: .22),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.muted,
        ),
      ),
    ),
  );
}
