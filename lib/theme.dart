import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens. Palette is grounded in the subject matter: hemoglobin
/// (garnet, desaturated -- clinical rather than alarm-red) as the primary
/// color, a teal reserved only for a successful/connected state, and a warm
/// off-white rather than stark white or the generic cream-tone default.
class HbColors {
  static const garnet = Color(0xFF7A2333); // primary -- hemoglobin
  static const garnetDark = Color(0xFF551725);
  static const ink = Color(0xFF1F2430); // body text
  static const teal = Color(0xFF2F6F79); // reserved: connected / success only
  static const neutral = Color(0xFF8B93A1); // disabled / inactive
  static const surface = Color(0xFFFFFFFF);
  static const background = Color(0xFFF7F5F3); // warm off-white, not cream
  static const warn = Color(0xFFB5651D); // unvalidated-correction caveat text
  static const line = Color(0xFFE4DFDA);
}

class HbTheme {
  static ThemeData build() {
    final base = ThemeData.light(useMaterial3: true);
    final serif = GoogleFonts.sourceSerif4();
    final sans = GoogleFonts.inter();

    return base.copyWith(
      scaffoldBackgroundColor: HbColors.background,
      colorScheme: base.colorScheme.copyWith(
        primary: HbColors.garnet,
        secondary: HbColors.teal,
        surface: HbColors.surface,
      ),
      textTheme: base.textTheme
          .copyWith(
            displayLarge: serif.copyWith(
                fontSize: 44, fontWeight: FontWeight.w600, color: HbColors.ink, height: 1.05),
            headlineMedium: serif.copyWith(
                fontSize: 22, fontWeight: FontWeight.w600, color: HbColors.ink),
            titleMedium: sans.copyWith(
                fontSize: 15, fontWeight: FontWeight.w600, color: HbColors.ink),
            bodyMedium: sans.copyWith(fontSize: 14, color: HbColors.ink),
            bodySmall: sans.copyWith(fontSize: 12, color: HbColors.neutral),
            labelLarge: sans.copyWith(
                fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.1),
          )
          .apply(bodyColor: HbColors.ink, displayColor: HbColors.ink),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: HbColors.garnet,
          foregroundColor: Colors.white,
          disabledBackgroundColor: HbColors.line,
          disabledForegroundColor: HbColors.neutral,
          padding: const EdgeInsets.symmetric(vertical: 18),
          textStyle: sans.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: HbColors.surface,
        labelStyle: sans.copyWith(color: HbColors.neutral, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: HbColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: HbColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: HbColors.garnet, width: 1.4),
        ),
      ),
    );
  }
}
