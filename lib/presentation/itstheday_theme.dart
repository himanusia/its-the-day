import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The visual language is a quiet paper canvas with a small set of saturated
/// state accents. Surfaces stay neutral so progress and actions carry the
/// emphasis instead of every container competing for attention.
abstract final class ItsTheDayPalette {
  static const ink = Color(0xFF17211E);
  static const night = Color(0xFF121A18);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceElevated = Color(0xFF27332F);
  static const paper = Color(0xFFFBFAF6);
  static const cloud = Color(0xFFF5F7F1);
  static const graphite = Color(0xFF17211E);
  static const mint = Color(0xFFB8F1CE);
  static const mintStrong = Color(0xFF0A8060);
  static const amber = Color(0xFFFFD17D);
  static const amberStrong = Color(0xFF9B5A00);
  static const coral = Color(0xFFFFA08E);
  static const coralStrong = Color(0xFFB33D34);
  static const sky = Color(0xFF9EDAFF);
  static const skyStrong = Color(0xFF2877A8);
  static const lavender = Color(0xFFC7B8FF);
  static const line = Color(0xFF8A938C);
}

ThemeData itsthedayDarkTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: ItsTheDayPalette.mintStrong,
        brightness: Brightness.dark,
      ).copyWith(
        primary: ItsTheDayPalette.mint,
        onPrimary: ItsTheDayPalette.ink,
        primaryContainer: const Color(0xFF176B57),
        onPrimaryContainer: const Color(0xFFC8FFE2),
        secondary: ItsTheDayPalette.amber,
        onSecondary: ItsTheDayPalette.ink,
        secondaryContainer: const Color(0xFF66501E),
        onSecondaryContainer: const Color(0xFFFFE9B2),
        tertiary: ItsTheDayPalette.sky,
        onTertiary: ItsTheDayPalette.ink,
        error: ItsTheDayPalette.coral,
        onError: ItsTheDayPalette.ink,
        errorContainer: const Color(0xFF6E2E32),
        onErrorContainer: const Color(0xFFFFDAD6),
        surface: ItsTheDayPalette.night,
        onSurface: ItsTheDayPalette.cloud,
        surfaceContainerLowest: ItsTheDayPalette.ink,
        surfaceContainerLow: const Color(0xFF1B2622),
        surfaceContainer: const Color(0xFF22312B),
        surfaceContainerHigh: const Color(0xFF2A3B34),
        surfaceContainerHighest: ItsTheDayPalette.surfaceElevated,
        outline: const Color(0xFF8B99AC),
        outlineVariant: const Color(0xFF3B485C),
      );

  return _baseTheme(
    scheme: scheme,
    brightness: Brightness.dark,
    scaffold: ItsTheDayPalette.ink,
    appBarForeground: ItsTheDayPalette.cloud,
    overlayStyle: SystemUiOverlayStyle.light,
    inputFill: ItsTheDayPalette.surface,
    textForeground: const Color(0xFFEAF3ED),
  );
}

ThemeData itsthedayLightTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: ItsTheDayPalette.mintStrong,
        brightness: Brightness.light,
      ).copyWith(
        primary: ItsTheDayPalette.mintStrong,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFC8F2D9),
        onPrimaryContainer: const Color(0xFF063826),
        secondary: ItsTheDayPalette.amberStrong,
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFFFFE0A8),
        onSecondaryContainer: const Color(0xFF342000),
        tertiary: ItsTheDayPalette.skyStrong,
        onTertiary: Colors.white,
        tertiaryContainer: const Color(0xFFD4EEFF),
        onTertiaryContainer: const Color(0xFF082B40),
        error: ItsTheDayPalette.coralStrong,
        onError: Colors.white,
        errorContainer: const Color(0xFFFFDAD6),
        onErrorContainer: const Color(0xFF410002),
        surface: ItsTheDayPalette.surface,
        onSurface: ItsTheDayPalette.graphite,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFFBFAF6),
        surfaceContainer: const Color(0xFFF2F1EB),
        surfaceContainerHigh: const Color(0xFFEAE9E2),
        surfaceContainerHighest: const Color(0xFFE1E2DA),
        outline: ItsTheDayPalette.line,
        outlineVariant: const Color(0xFFC5CBC3),
      );

  return _baseTheme(
    scheme: scheme,
    brightness: Brightness.light,
    scaffold: ItsTheDayPalette.paper,
    appBarForeground: ItsTheDayPalette.graphite,
    overlayStyle: SystemUiOverlayStyle.dark,
    inputFill: Colors.white,
    textForeground: ItsTheDayPalette.graphite,
  );
}

ThemeData _baseTheme({
  required ColorScheme scheme,
  required Brightness brightness,
  required Color scaffold,
  required Color appBarForeground,
  required SystemUiOverlayStyle overlayStyle,
  required Color inputFill,
  required Color textForeground,
}) {
  final radius = BorderRadius.circular(14);
  final cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(18),
    side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .7)),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scaffold,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: appBarForeground,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: _textTheme(textForeground).titleLarge,
      systemOverlayStyle: overlayStyle,
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: cardShape,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: inputFill,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      labelStyle: TextStyle(color: scheme.onSurface.withValues(alpha: .68)),
      floatingLabelStyle: TextStyle(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
      ),
      hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: .52)),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline.withValues(alpha: .82)),
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      selectedColor: scheme.primaryContainer,
      disabledColor: scheme.surfaceContainer,
      secondarySelectedColor: scheme.primaryContainer,
      labelStyle: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      secondaryLabelStyle: TextStyle(color: scheme.onPrimaryContainer),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      titleTextStyle: _textTheme(textForeground).titleLarge,
      contentTextStyle: _textTheme(textForeground).bodyLarge,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: .7),
      space: 1,
      thickness: 1,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
    ),
    textTheme: _textTheme(textForeground),
  );
}

TextTheme _textTheme(Color foreground) {
  return TextTheme(
    displayLarge: TextStyle(
      color: foreground,
      fontSize: 54,
      fontWeight: FontWeight.w800,
      letterSpacing: -2.2,
      height: 1.0,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
    displayMedium: TextStyle(
      color: foreground,
      fontSize: 38,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.2,
      height: 1.04,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
    displaySmall: TextStyle(
      color: foreground,
      fontSize: 31,
      fontWeight: FontWeight.w800,
      letterSpacing: -.8,
      height: 1.05,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
    headlineMedium: TextStyle(
      color: foreground,
      fontSize: 27,
      fontWeight: FontWeight.w800,
      letterSpacing: -.7,
      height: 1.1,
    ),
    headlineSmall: TextStyle(
      color: foreground,
      fontSize: 22,
      fontWeight: FontWeight.w800,
      letterSpacing: -.45,
      height: 1.15,
    ),
    titleLarge: TextStyle(
      color: foreground,
      fontSize: 19,
      fontWeight: FontWeight.w800,
      letterSpacing: -.2,
      height: 1.2,
    ),
    titleMedium: TextStyle(
      color: foreground,
      fontSize: 16,
      fontWeight: FontWeight.w700,
      height: 1.25,
    ),
    bodyLarge: TextStyle(color: foreground, fontSize: 16, height: 1.4),
    bodyMedium: TextStyle(color: foreground, fontSize: 14, height: 1.35),
    bodySmall: TextStyle(color: foreground, fontSize: 12, height: 1.3),
    labelLarge: TextStyle(
      color: foreground,
      fontSize: 13,
      fontWeight: FontWeight.w800,
      letterSpacing: .25,
      height: 1.2,
    ),
    labelMedium: TextStyle(
      color: foreground,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: .85,
      height: 1.2,
    ),
    labelSmall: TextStyle(
      color: foreground,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: .4,
    ),
  );
}
