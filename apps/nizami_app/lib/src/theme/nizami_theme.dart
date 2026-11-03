import 'package:flutter/material.dart';

abstract final class NizamiColors {
  static const navy = Color(0xFF092B50);
  static const navyDark = Color(0xFF061D39);
  static const navyLight = Color(0xFF0C4162);
  static const blue = Color(0xFF087FC3);
  static const blueDark = Color(0xFF06618C);
  static const blueSoft = Color(0xFFE6F5FB);
  static const teal = Color(0xFF00AF95);
  static const tealDark = Color(0xFF009B83);
  static const ink = Color(0xFF09254B);
  static const muted = Color(0xFF71829A);
  static const cyanSoft = Color(0xFFE6FBF6);
  static const green = Color(0xFF0AAB83);
  static const red = Color(0xFFEB4860);
  static const amber = Color(0xFFF4A123);
  static const purple = Color(0xFF9835E8);
  static const canvas = Color(0xFFF3FAFF);
  static const border = Color(0xFFE2EDF5);
  static const darkCanvas = Color(0xFF07111F);
}

abstract final class NizamiTheme {
  static ThemeData get light => _theme(Brightness.light);
  static ThemeData get dark => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: NizamiColors.teal,
      brightness: brightness,
      primary: dark ? const Color(0xFF56DBC7) : NizamiColors.tealDark,
      secondary: NizamiColors.blue,
      surface: dark ? const Color(0xFF122C40) : Colors.white,
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
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? NizamiColors.darkCanvas
          : NizamiColors.canvas,
      fontFamily: 'NizamiArabic',
      // Keep Arabic fallback ahead of the Latin display font. Putting Arial
      // first caused missing Arabic/icon glyphs to be rendered as tofu boxes
      // on some Android devices.
      fontFamilyFallback: const ['ArialMTBlack', 'GESS', 'Segoe UI'],
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: IconThemeData(
        color: scheme.onSurface,
        size: 24,
        // Material icons must always use Flutter's bundled icon font and must
        // never inherit the business text fonts.
        applyTextScaling: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: dark
                ? Colors.white.withValues(alpha: .08)
                : NizamiColors.border,
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: dark ? NizamiColors.darkCanvas : Colors.white,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontFamily: 'GESS',
          fontSize: 21,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        isDense: true,
        fillColor: dark ? const Color(0xFF132640) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: dark
                ? Colors.white.withValues(alpha: .12)
                : const Color(0xFFDCE9F1),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: dark
                ? Colors.white.withValues(alpha: .12)
                : const Color(0xFFDCE9F1),
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: dark
                ? Colors.white.withValues(alpha: .08)
                : const Color(0xFFDCE9F1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF06A98F), width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: dark ? Colors.white.withValues(alpha: .08) : NizamiColors.border,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: NizamiColors.tealDark,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 43),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'GESS',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 46),
          foregroundColor: scheme.primary,
          side: BorderSide(color: dark ? Colors.white24 : NizamiColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: NizamiColors.teal,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark ? const Color(0xFF142A47) : NizamiColors.blueSoft,
        selectedColor: NizamiColors.teal,
        labelStyle: TextStyle(color: scheme.onSurface, fontFamily: 'GESS'),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontFamily: 'GESS',
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(
          dark ? const Color(0xFF142A47) : const Color(0xFFEAF8FA),
        ),
        headingTextStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        dataTextStyle: textTheme.bodyMedium,
        dividerThickness: .7,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: dark ? Colors.white12 : NizamiColors.border,
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        selectedItemColor: NizamiColors.teal,
        unselectedItemColor: scheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 10,
      ),
    );
  }
}
