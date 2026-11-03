import 'package:flutter/material.dart';

/// Central visual tokens for the 2026 NineSoft reference UI.
///
/// Keep these values centralized: document editors, reports, navigation and
/// settings all consume the same palette so mobile and desktop remain visually
/// consistent without changing any accounting or API behavior.
abstract final class NizamiColors {
  static const navy = Color(0xFF0B356F);
  static const navyDark = Color(0xFF072A59);
  static const navyLight = Color(0xFF164D8C);
  static const blue = Color(0xFF1769E8);
  static const blueDark = Color(0xFF0D52C4);
  static const blueSoft = Color(0xFFEAF3FF);
  static const teal = Color(0xFF14A966);
  static const tealDark = Color(0xFF078B50);
  static const ink = Color(0xFF10213F);
  static const muted = Color(0xFF6C7A92);
  static const cyanSoft = Color(0xFFEAF7F4);
  static const green = Color(0xFF19A64A);
  static const red = Color(0xFFE43E49);
  static const amber = Color(0xFFF59E0B);
  static const purple = Color(0xFF7C3AED);
  static const canvas = Color(0xFFF4F7FB);
  static const surfaceSoft = Color(0xFFF9FBFE);
  static const border = Color(0xFFDCE4EF);
  static const darkCanvas = Color(0xFF09111F);

  static const successSoft = Color(0xFFEAF8EC);
  static const dangerSoft = Color(0xFFFDECEE);
  static const warningSoft = Color(0xFFFFF5E4);
  static const purpleSoft = Color(0xFFF4EEFF);
}

abstract final class NizamiTheme {
  static ThemeData get light => _theme(Brightness.light);
  static ThemeData get dark => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: NizamiColors.blue,
      brightness: brightness,
      primary: dark ? const Color(0xFF8AB8FF) : NizamiColors.navy,
      secondary: dark ? const Color(0xFF76A9FF) : NizamiColors.blue,
      surface: dark ? const Color(0xFF121D2E) : Colors.white,
      error: NizamiColors.red,
    );

    final baseTextTheme = ThemeData(useMaterial3: true, brightness: brightness)
        .textTheme
        .apply(
          fontFamily: 'NizamiArabic',
          fontFamilyFallback: const [
            'NizamiArabic',
            'ArialMTBlack',
            'Segoe UI',
          ],
        );

    TextStyle? latinDigits(TextStyle? style) => style?.copyWith(
      locale: const Locale('en'),
      fontFeatures: const [FontFeature('lnum'), FontFeature('tnum')],
    );

    final textTheme = baseTextTheme.copyWith(
      displayLarge: latinDigits(baseTextTheme.displayLarge),
      displayMedium: latinDigits(baseTextTheme.displayMedium),
      displaySmall: latinDigits(baseTextTheme.displaySmall),
      headlineLarge: latinDigits(baseTextTheme.headlineLarge),
      headlineMedium: latinDigits(baseTextTheme.headlineMedium),
      headlineSmall: latinDigits(baseTextTheme.headlineSmall),
      titleLarge: latinDigits(baseTextTheme.titleLarge),
      titleMedium: latinDigits(baseTextTheme.titleMedium),
      titleSmall: latinDigits(baseTextTheme.titleSmall),
      bodyLarge: latinDigits(baseTextTheme.bodyLarge),
      bodyMedium: latinDigits(baseTextTheme.bodyMedium),
      bodySmall: latinDigits(baseTextTheme.bodySmall),
      labelLarge: latinDigits(baseTextTheme.labelLarge),
      labelMedium: latinDigits(baseTextTheme.labelMedium),
      labelSmall: latinDigits(baseTextTheme.labelSmall),
    );

    final borderColor = dark
        ? Colors.white.withValues(alpha: .12)
        : NizamiColors.border;
    final fieldFill = dark ? const Color(0xFF142238) : const Color(0xFFFCFDFF);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          dark ? NizamiColors.darkCanvas : NizamiColors.canvas,
      fontFamily: 'NizamiArabic',
      fontFamilyFallback: const ['ArialMTBlack', 'GESS', 'Segoe UI'],
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      iconTheme: IconThemeData(
        color: dark ? const Color(0xFFE8EEF8) : NizamiColors.ink,
        size: 23,
        applyTextScaling: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: borderColor),
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: dark ? const Color(0xFF101B2D) : Colors.white,
        foregroundColor: dark ? Colors.white : NizamiColors.ink,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: dark ? Colors.white : NizamiColors.ink,
          fontFamily: 'GESS',
          fontSize: 21,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        isDense: true,
        fillColor: fieldFill,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: dark ? Colors.white54 : NizamiColors.muted,
        ),
        labelStyle: textTheme.bodySmall?.copyWith(
          color: dark ? Colors.white70 : NizamiColors.ink,
          fontWeight: FontWeight.w600,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        prefixIconColor: dark ? Colors.white60 : NizamiColors.navy,
        suffixIconColor: dark ? Colors.white60 : NizamiColors.navy,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: dark ? Colors.white.withValues(alpha: .07) : const Color(0xFFE8EDF4),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NizamiColors.blue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NizamiColors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NizamiColors.red, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: dark ? Colors.white.withValues(alpha: .09) : NizamiColors.border,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: NizamiColors.navy,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontFamily: 'GESS',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 46),
          foregroundColor: dark ? const Color(0xFF9BC0FF) : NizamiColors.navy,
          side: BorderSide(color: borderColor),
          backgroundColor: dark ? const Color(0xFF111E30) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontFamily: 'GESS',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: dark ? const Color(0xFF8AB8FF) : NizamiColors.blue,
          textStyle: const TextStyle(
            fontFamily: 'GESS',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: NizamiColors.navy,
        foregroundColor: Colors.white,
        elevation: 5,
        shape: CircleBorder(),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark ? const Color(0xFF172741) : NizamiColors.blueSoft,
        selectedColor: dark ? const Color(0xFF234F91) : const Color(0xFFD7E8FF),
        labelStyle: TextStyle(color: scheme.onSurface, fontFamily: 'GESS'),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontFamily: 'GESS',
        ),
        side: BorderSide(color: borderColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(
          dark ? const Color(0xFF172741) : const Color(0xFFEAF2FF),
        ),
        headingTextStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: dark ? Colors.white : NizamiColors.ink,
        ),
        dataTextStyle: textTheme.bodyMedium?.copyWith(
          color: dark ? Colors.white : NizamiColors.ink,
        ),
        dividerThickness: .7,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        selectedItemColor: NizamiColors.navy,
        unselectedItemColor: dark ? Colors.white54 : const Color(0xFF4F6077),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 74,
        backgroundColor: scheme.surface,
        elevation: 0,
        indicatorColor: dark ? const Color(0xFF233C60) : const Color(0xFFDDEBFF),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelMedium?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected
                ? (dark ? Colors.white : NizamiColors.navy)
                : (dark ? Colors.white60 : const Color(0xFF536278)),
          );
        }),
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
