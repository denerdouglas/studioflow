import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

abstract final class AppTheme {
  static ThemeData light({Color? seedColor}) {
    return buildTheme(
      ColorScheme.fromSeed(
        seedColor: seedColor ?? AppColors.temaSeed,
        brightness: Brightness.light,
      ),
    );
  }

  static ThemeData dark({Color? seedColor}) {
    return buildTheme(
      ColorScheme.fromSeed(
        seedColor: seedColor ?? AppColors.temaSeed,
        brightness: Brightness.dark,
      ),
    );
  }

  static ThemeData buildTheme(ColorScheme colorScheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  const AppTheme._();
}
