import 'package:flutter/material.dart';

enum PlanDoneThemeKey {
  calmFocus,
  modernMinimal,
  warmMomentum,
}

class PlanDoneThemeTokens extends ThemeExtension<PlanDoneThemeTokens> {
  const PlanDoneThemeTokens({
    required this.accent,
    required this.warning,
    required this.textSecondary,
  });

  final Color accent;
  final Color warning;
  final Color textSecondary;

  @override
  PlanDoneThemeTokens copyWith({Color? accent, Color? warning, Color? textSecondary}) {
    return PlanDoneThemeTokens(
      accent: accent ?? this.accent,
      warning: warning ?? this.warning,
      textSecondary: textSecondary ?? this.textSecondary,
    );
  }

  @override
  PlanDoneThemeTokens lerp(ThemeExtension<PlanDoneThemeTokens>? other, double t) {
    if (other is! PlanDoneThemeTokens) return this;
    return PlanDoneThemeTokens(
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
    );
  }
}

extension PlanDoneThemeTokensLookup on ThemeData {
  PlanDoneThemeTokens get planDoneTokens => extension<PlanDoneThemeTokens>()!;
}

class PlanDoneThemes {
  static ThemeData resolve(PlanDoneThemeKey key, {Brightness brightness = Brightness.light}) {
    final spec = _specFor(key, brightness);
    return _themeData(spec: spec, brightness: brightness);
  }

  static String label(PlanDoneThemeKey key) {
    return switch (key) {
      PlanDoneThemeKey.calmFocus => 'Calm Focus',
      PlanDoneThemeKey.modernMinimal => 'Modern Minimal',
      PlanDoneThemeKey.warmMomentum => 'Warm Momentum',
    };
  }

  static _ThemeSpec _specFor(PlanDoneThemeKey key, Brightness brightness) {
    return switch ((key, brightness)) {
      (PlanDoneThemeKey.calmFocus, Brightness.light) => const _ThemeSpec(
          primary: Color(0xFF17406D),
          secondary: Color(0xFF2F7FDB),
          tertiary: Color(0xFF08A37B),
          background: Color(0xFFEAF2FA),
          surface: Color(0xFFFFFFFF),
          textPrimary: Color(0xFF102033),
          textSecondary: Color(0xFF4A617B),
          warning: Color(0xFFE87A2C),
          radius: 10,
        ),
      (PlanDoneThemeKey.calmFocus, Brightness.dark) => const _ThemeSpec(
          primary: Color(0xFF73B2FF),
          secondary: Color(0xFF99C8FF),
          tertiary: Color(0xFF4DE4C1),
          background: Color(0xFF081421),
          surface: Color(0xFF102033),
          textPrimary: Color(0xFFE8F2FF),
          textSecondary: Color(0xFFB4C8DE),
          warning: Color(0xFFFFB56D),
          radius: 10,
        ),
      (PlanDoneThemeKey.modernMinimal, Brightness.light) => const _ThemeSpec(
          primary: Color(0xFF111111),
          secondary: Color(0xFF585858),
          tertiary: Color(0xFF00AFA0),
          background: Color(0xFFF5F5F5),
          surface: Color(0xFFFFFFFF),
          textPrimary: Color(0xFF080808),
          textSecondary: Color(0xFF4A4A4A),
          warning: Color(0xFFE08A00),
          radius: 2,
        ),
      (PlanDoneThemeKey.modernMinimal, Brightness.dark) => const _ThemeSpec(
          primary: Color(0xFFF2F2F2),
          secondary: Color(0xFFBDBDBD),
          tertiary: Color(0xFF00D4C2),
          background: Color(0xFF050505),
          surface: Color(0xFF101010),
          textPrimary: Color(0xFFEAEAEA),
          textSecondary: Color(0xFFABABAB),
          warning: Color(0xFFFFB54A),
          radius: 2,
        ),
      (PlanDoneThemeKey.warmMomentum, Brightness.light) => const _ThemeSpec(
          primary: Color(0xFF6E2B2B),
          secondary: Color(0xFFC04A3A),
          tertiary: Color(0xFFDA8A2F),
          background: Color(0xFFFFF1E8),
          surface: Color(0xFFFFFBF8),
          textPrimary: Color(0xFF3A1D1A),
          textSecondary: Color(0xFF83584C),
          warning: Color(0xFFD4512A),
          radius: 18,
        ),
      (PlanDoneThemeKey.warmMomentum, Brightness.dark) => const _ThemeSpec(
          primary: Color(0xFFFFB4A7),
          secondary: Color(0xFFFF8C72),
          tertiary: Color(0xFFFFC66F),
          background: Color(0xFF2B1511),
          surface: Color(0xFF3C211B),
          textPrimary: Color(0xFFFFE8DF),
          textSecondary: Color(0xFFE8B9AA),
          warning: Color(0xFFFF8E63),
          radius: 18,
        ),
    };
  }

  static ThemeData _themeData({required _ThemeSpec spec, required Brightness brightness}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: spec.primary,
      brightness: brightness,
    ).copyWith(
      primary: spec.primary,
      secondary: spec.secondary,
      tertiary: spec.tertiary,
      surface: spec.surface,
      onSurface: spec.textPrimary,
      onPrimary: brightness == Brightness.dark ? const Color(0xFF101010) : Colors.white,
      onSecondary: brightness == Brightness.dark ? const Color(0xFF101010) : Colors.white,
      surfaceTint: spec.primary,
    );

    final tokens = PlanDoneThemeTokens(
      accent: spec.tertiary,
      warning: spec.warning,
      textSecondary: spec.textSecondary,
    );

    final borderRadius = BorderRadius.circular(spec.radius);
    final textTheme = (brightness == Brightness.dark
            ? Typography.material2021().white
            : Typography.material2021().black)
        .apply(
      bodyColor: spec.textPrimary,
      displayColor: spec.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: spec.background,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: brightness == Brightness.dark ? 0 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        border: OutlineInputBorder(borderRadius: borderRadius),
        enabledBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        selectedColor: colorScheme.primaryContainer,
        backgroundColor: colorScheme.surfaceContainer,
        side: BorderSide(color: colorScheme.outlineVariant),
        labelStyle: textTheme.labelMedium,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.tertiaryContainer,
        foregroundColor: colorScheme.onTertiaryContainer,
      ),
      extensions: [tokens],
    );
  }
}

class _ThemeSpec {
  const _ThemeSpec({
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.background,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.warning,
    required this.radius,
  });

  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color background;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color warning;
  final double radius;
}
