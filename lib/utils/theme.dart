import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global dark-mode notifier.
final ValueNotifier<bool> darkModeNotifier = ValueNotifier<bool>(false);
const String _darkModePrefsKey = 'act_dark_mode_enabled';

Future<void> loadSavedDarkMode() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_darkModePrefsKey);
    if (saved != null) darkModeNotifier.value = saved;
  } catch (_) {}
}

Future<void> setDarkMode(bool value) async {
  darkModeNotifier.value = value;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModePrefsKey, value);
  } catch (_) {}
}

/// ACT brand colors.
/// Official ACT palette: deep red, charcoal black, clean white, gold accent.
class ActColors {
  // Primary — ACT's signature red
  static const Color primary     = Color(0xFFB30000); // ACT deep red
  static const Color primaryDark = Color(0xFF8C0000);
  static const Color primaryLight = Color(0xFFE53935);

  // Secondary accent — ACT gold/amber
  static const Color accent      = Color(0xFFD4A017);
  static const Color accentDark  = Color(0xFFB8860B);

  // Neutrals
  static const Color charcoal    = Color(0xFF1C1C1E);
  static const Color darkSurface = Color(0xFF2A2A2E);
  static const Color midGray     = Color(0xFF6B6B70);

  // Semantic
  static const Color success     = Color(0xFF1B7D4B);
  static const Color successLight = Color(0xFF4CAF50);
  static const Color danger      = Color(0xFFB30000);
  static const Color warning     = Color(0xFFD4A017);
  static const Color info        = Color(0xFF1565C0);

  // Light theme surfaces
  static const Color lightBg      = Color(0xFFF5F5F5);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard    = Color(0xFFFFFFFF);
  static const Color lightBorder  = Color(0xFFE0E0E0);

  // Dark theme surfaces
  static const Color darkBg      = Color(0xFF121212);
  static const Color darkCard    = Color(0xFF1E1E1E);
  static const Color darkBorder  = Color(0xFF2C2C2C);

  // Score colors (ACT composite 1-36)
  static Color scoreColor(double score) {
    if (score >= 32) return const Color(0xFF1B7D4B);  // excellent
    if (score >= 26) return const Color(0xFF2E7D32);  // good
    if (score >= 20) return const Color(0xFFD4A017);  // average
    if (score >= 14) return const Color(0xFFE65100);  // below avg
    return const Color(0xFFB30000);                    // needs work
  }
}

class AppTheme {
  static ThemeData light = ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    scaffoldBackgroundColor: ActColors.lightBg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: ActColors.primary,
      brightness: Brightness.light,
      primary: ActColors.primary,
      secondary: ActColors.accent,
      error: ActColors.danger,
    ),
    cardTheme: CardThemeData(
      color: ActColors.lightCard,
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: ActColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 19,
        fontWeight: FontWeight.w700,
        fontFamily: 'Roboto',
        letterSpacing: 0.3,
      ),
      iconTheme: IconThemeData(color: Colors.white),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: ActColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ActColors.primary,
        side: const BorderSide(color: ActColors.primary, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: ActColors.primary, width: 2),
      ),
    ),
    fontFamily: 'Roboto',
  );

  static ThemeData dark = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: ActColors.darkBg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: ActColors.primaryLight,
      brightness: Brightness.dark,
      primary: ActColors.primaryLight,
      secondary: ActColors.accent,
      error: ActColors.danger,
    ),
    cardTheme: CardThemeData(
      color: ActColors.darkCard,
      elevation: 2,
      shadowColor: Colors.black45,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: ActColors.darkCard,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 19,
        fontWeight: FontWeight.w700,
        fontFamily: 'Roboto',
        letterSpacing: 0.3,
      ),
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: ActColors.primaryLight,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ActColors.primaryLight,
        side: const BorderSide(color: ActColors.primaryLight, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: ActColors.primaryLight, width: 2),
      ),
    ),
    fontFamily: 'Roboto',
  );
}
