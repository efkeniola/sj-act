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

/// Adaptive color helpers for screens that build their own containers/text
/// instead of relying purely on CardTheme — added for the in-app purchase
/// screens (plan picker, checkout). Learned from a dark-mode bug in the
/// SAT app's equivalent screens (Colors.white cards + inherited near-white
/// dark-theme text = invisible), so ACT's version is built with these
/// from the start. Use these instead of raw Colors.white/grey/black in
/// any new screen that needs to look right in both themes.
extension AdaptiveColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Card/sheet background — matches CardTheme's surface colors.
  Color get surfaceColor => isDark ? ActColors.darkCard : ActColors.lightCard;

  /// A step above [surfaceColor] — for a "box within a card" (e.g. an
  /// order-summary panel sitting inside a screen's body).
  Color get panelColor => isDark ? const Color(0xFF262629) : const Color(0xFFF5F5F5);

  /// Primary readable text — near-black on light, near-white on dark.
  Color get textColor => isDark ? const Color(0xFFEDEEF0) : const Color(0xFF1A1C1E);

  /// Secondary/caption text — always has enough contrast against
  /// [surfaceColor]/[panelColor] in either theme.
  Color get mutedTextColor => isDark ? const Color(0xFFACACB0) : ActColors.midGray;

  /// Faint hairline / border — visible against either surface color.
  Color get hairlineColor => isDark ? ActColors.darkBorder : ActColors.lightBorder;

  /// Elevation shadow — near-invisible black shadows on a dark background
  /// are pointless, so this uses a stronger shadow there instead.
  Color get shadowColor => isDark ? Colors.black.withOpacity(0.45) : Colors.black.withOpacity(0.08);
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
    // Every TabBar in this app lives inside a red (or dark-card) AppBar, so
    // it must never fall back to Material 3's default label colors — those
    // resolve to the primary/onSurfaceVariant colors, which in light mode
    // are red-on-red and unreadable. Force explicit white labels here once,
    // for every screen, instead of patching each TabBar individually.
    tabBarTheme: const TabBarThemeData(
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white70,
      indicatorColor: Colors.white,
      dividerColor: Colors.transparent,
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
    // FilledButton has NO theme override without this block, so it falls
    // back to Flutter's Material 3 default foreground (colorScheme.onPrimary).
    // Because `primary` above is force-set to ActColors.primary/primaryLight
    // instead of a seed-derived tone, Flutter's auto-computed onPrimary can
    // resolve to a dark/near-black color — invisible on this app's red
    // FilledButtons (e.g. the "Activate" button) especially in dark mode.
    // Setting it explicitly here fixes every FilledButton in the app at once.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
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
    tabBarTheme: const TabBarThemeData(
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white70,
      indicatorColor: Colors.white,
      dividerColor: Colors.transparent,
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
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
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
