import 'package:flutter/material.dart';

/// Palette taken from the product mockups (dark UI, pink→purple brand gradient).
abstract final class AppColors {
  static const background = Color(0xFF12141C);
  static const surface = Color(0xFF1C1F2A);
  static const surfaceHigh = Color(0xFF262A37);
  static const border = Color(0xFF2E3242);
  static const textPrimary = Color(0xFFF5F6FA);
  static const textSecondary = Color(0xFF9AA0B4);
  static const pink = Color(0xFFEC4899);
  static const purple = Color(0xFFA855F7);
  static const yellow = Color(0xFFFACC15);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const blue = Color(0xFF3B82F6);
  static const orange = Color(0xFFF97316);

  static const brandGradient = LinearGradient(
    colors: [pink, purple],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.pink,
    brightness: Brightness.dark,
    surface: AppColors.surface,
    primary: AppColors.pink,
    secondary: AppColors.purple,
    error: AppColors.red,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: Brightness.dark);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.background,
      indicatorColor: AppColors.surfaceHigh,
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.pink,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
