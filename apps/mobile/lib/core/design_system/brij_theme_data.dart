import 'package:flutter/material.dart';

import 'app_tokens.dart';

ThemeData buildBrijTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: BrijTokens.peacock,
      primary: BrijTokens.peacock,
      secondary: BrijTokens.softGold,
      surface: BrijTokens.sandalwood,
    ),
    scaffoldBackgroundColor: BrijTokens.sandalwood,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: BrijTokens.deepMaroon,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrijTokens.radiusLg),
      ),
      color: Colors.white.withValues(alpha: 0.92),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
  );
  return base;
}
