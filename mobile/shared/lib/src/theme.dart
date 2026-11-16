import 'package:flutter/material.dart';

/// Brand colors taken from the website (src/styles.css, converted from oklch).
class AlasColors {
  static const primary = Color(0xFF225A39);
  static const primaryDark = Color(0xFF68AA78);
  static const logoGreen = Color(0xFF254F3D);
  static const cream = Color(0xFFF3EADB);
  static const background = Color(0xFFFBF6EE);
  static const backgroundDark = Color(0xFF1B110B);
  static const card = Color(0xFFFFFDF9);
  static const cardDark = Color(0xFF261A13);
  static const foreground = Color(0xFF2F1D12);
  static const foregroundDark = Color(0xFFEEE7DB);
  static const secondary = Color(0xFF452818);
  static const secondaryDark = Color(0xFFD1C2AB);
  static const muted = Color(0xFFEFE7D8);
  static const mutedDark = Color(0xFF2E241D);
  static const mutedForeground = Color(0xFF6D5D52);
  static const mutedForegroundDark = Color(0xFFAAA091);
  static const accent = Color(0xFFD4E8CF);
  static const accentDark = Color(0xFF1F3420);
  static const accentForeground = Color(0xFF11361F);
  static const accentForegroundDark = Color(0xFFE4E3CC);
  static const border = Color(0xFFD5C8B9);
  static const borderDark = Color(0xFF41352D);
  static const destructive = Color(0xFFD4302E);
  static const hero = Color(0xFF30180B);
  static const sale = Color(0xFFB4462B);
  static const warning = Color(0xFFB7791F);
}

const _pkg = 'alas_shared';

ThemeData buildAlasTheme({required Brightness brightness, required String languageCode}) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: dark ? AlasColors.primaryDark : AlasColors.primary,
    onPrimary: dark ? const Color(0xFF180C06) : const Color(0xFFFBF8F1),
    secondary: dark ? AlasColors.secondaryDark : AlasColors.secondary,
    onSecondary: dark ? const Color(0xFF1B110B) : const Color(0xFFFBF8F1),
    tertiary: AlasColors.sale,
    onTertiary: Colors.white,
    error: AlasColors.destructive,
    onError: Colors.white,
    surface: dark ? AlasColors.cardDark : AlasColors.card,
    onSurface: dark ? AlasColors.foregroundDark : AlasColors.foreground,
    surfaceContainerLowest: dark ? AlasColors.backgroundDark : AlasColors.background,
    surfaceContainerLow: dark ? AlasColors.cardDark : AlasColors.card,
    surfaceContainer: dark ? AlasColors.mutedDark : AlasColors.muted,
    surfaceContainerHighest: dark ? AlasColors.mutedDark : AlasColors.muted,
    primaryContainer: dark ? AlasColors.accentDark : AlasColors.accent,
    onPrimaryContainer: dark ? AlasColors.accentForegroundDark : AlasColors.accentForeground,
    onSurfaceVariant: dark ? AlasColors.mutedForegroundDark : AlasColors.mutedForeground,
    outline: dark ? AlasColors.borderDark : AlasColors.border,
    outlineVariant: dark ? AlasColors.borderDark : AlasColors.border,
  );
  final arabic = languageCode == 'ar';
  final family = arabic ? 'NotoKufiArabic' : 'Manrope';
  final fallback = arabic ? const ['Manrope'] : const ['NotoKufiArabic'];
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
  final textTheme = base.textTheme
      .apply(
        fontFamily: 'packages/$_pkg/$family',
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      )
      .copyWith();
  TextStyle? withFallback(TextStyle? s) =>
      s?.copyWith(fontFamilyFallback: [for (final f in fallback) 'packages/$_pkg/$f'], height: arabic ? 1.55 : 1.35);
  final radius = BorderRadius.circular(10);
  return base.copyWith(
    scaffoldBackgroundColor: dark ? AlasColors.backgroundDark : AlasColors.background,
    textTheme: TextTheme(
      displayLarge: withFallback(textTheme.displayLarge),
      displayMedium: withFallback(textTheme.displayMedium),
      displaySmall: withFallback(textTheme.displaySmall),
      headlineLarge: withFallback(textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700)),
      headlineMedium: withFallback(textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
      headlineSmall: withFallback(textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      titleLarge: withFallback(textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      titleMedium: withFallback(textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      titleSmall: withFallback(textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500)),
      bodyLarge: withFallback(textTheme.bodyLarge),
      bodyMedium: withFallback(textTheme.bodyMedium),
      bodySmall: withFallback(textTheme.bodySmall),
      labelLarge: withFallback(textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
      labelMedium: withFallback(textTheme.labelMedium),
      labelSmall: withFallback(textTheme.labelSmall),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? AlasColors.backgroundDark : AlasColors.background,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: withFallback(textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 19)),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: scheme.outline)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outline, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.outline)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.outline)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.primary, width: 1.6)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 50),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: withFallback(textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 15)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 50),
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: withFallback(textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide(color: scheme.outline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: withFallback(textTheme.labelMedium),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(withFallback(textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w500))),
      height: 66,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      contentTextStyle: withFallback(textTheme.bodyMedium?.copyWith(color: Colors.white)),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: scheme.surface, showDragHandle: true),
  );
}
