import 'package:flutter/material.dart';

enum PlanDoneThemeKey {
  calmFocus,
  modernMinimal,
  warmMomentum,
  oceanBreeze,
  forestMist,
  sunriseAmber,
  slateBlue,
  roseQuartz,
  emberNight,
  mintLeaf,
  citrusPop,
  indigoPulse,
  sandDune,
  glacier,
  lavaStone,
  meadowLight,
  cobaltEdge,
  cherryBlossom,
  neonGrid,
  graphiteGold,
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
      PlanDoneThemeKey.oceanBreeze => 'Ocean Breeze',
      PlanDoneThemeKey.forestMist => 'Forest Mist',
      PlanDoneThemeKey.sunriseAmber => 'Sunrise Amber',
      PlanDoneThemeKey.slateBlue => 'Slate Blue',
      PlanDoneThemeKey.roseQuartz => 'Rose Quartz',
      PlanDoneThemeKey.emberNight => 'Ember Night',
      PlanDoneThemeKey.mintLeaf => 'Mint Leaf',
      PlanDoneThemeKey.citrusPop => 'Citrus Pop',
      PlanDoneThemeKey.indigoPulse => 'Indigo Pulse',
      PlanDoneThemeKey.sandDune => 'Sand Dune',
      PlanDoneThemeKey.glacier => 'Glacier',
      PlanDoneThemeKey.lavaStone => 'Lava Stone',
      PlanDoneThemeKey.meadowLight => 'Meadow Light',
      PlanDoneThemeKey.cobaltEdge => 'Cobalt Edge',
      PlanDoneThemeKey.cherryBlossom => 'Cherry Blossom',
      PlanDoneThemeKey.neonGrid => 'Neon Grid',
      PlanDoneThemeKey.graphiteGold => 'Graphite Gold',
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
      (PlanDoneThemeKey.oceanBreeze, Brightness.light) => const _ThemeSpec(
          primary: Color(0xFF0B5D8F),
          secondary: Color(0xFF2D8FC3),
          tertiary: Color(0xFF15B8A6),
          background: Color(0xFFEAF7FF),
          surface: Color(0xFFFFFFFF),
          textPrimary: Color(0xFF0E2A3A),
          textSecondary: Color(0xFF4C6E82),
          warning: Color(0xFFE98B2F),
          radius: 12,
        ),
      (PlanDoneThemeKey.oceanBreeze, Brightness.dark) => const _ThemeSpec(
          primary: Color(0xFF84D0FF),
          secondary: Color(0xFF56B8EE),
          tertiary: Color(0xFF58E0D1),
          background: Color(0xFF071722),
          surface: Color(0xFF102433),
          textPrimary: Color(0xFFE8F6FF),
          textSecondary: Color(0xFFB1CBDE),
          warning: Color(0xFFFFB86C),
          radius: 12,
        ),
      (PlanDoneThemeKey.forestMist, Brightness.light) => const _ThemeSpec(
          primary: Color(0xFF1F5B3A),
          secondary: Color(0xFF4E8A63),
          tertiary: Color(0xFF76A55A),
          background: Color(0xFFF1F8F2),
          surface: Color(0xFFFFFFFF),
          textPrimary: Color(0xFF1A2E22),
          textSecondary: Color(0xFF587565),
          warning: Color(0xFFC8752A),
          radius: 10,
        ),
      (PlanDoneThemeKey.forestMist, Brightness.dark) => const _ThemeSpec(
          primary: Color(0xFF90D1AA),
          secondary: Color(0xFF6AB989),
          tertiary: Color(0xFFB4D97C),
          background: Color(0xFF0D1A13),
          surface: Color(0xFF17261D),
          textPrimary: Color(0xFFE8F6EE),
          textSecondary: Color(0xFFAEC7B8),
          warning: Color(0xFFFFB073),
          radius: 10,
        ),
      (PlanDoneThemeKey.sunriseAmber, Brightness.light) => const _ThemeSpec(
          primary: Color(0xFFA85700),
          secondary: Color(0xFFDB7B23),
          tertiary: Color(0xFFFFB347),
          background: Color(0xFFFFF5E8),
          surface: Color(0xFFFFFFFF),
          textPrimary: Color(0xFF3F2300),
          textSecondary: Color(0xFF7D5A2F),
          warning: Color(0xFFD14A2A),
          radius: 14,
        ),
      (PlanDoneThemeKey.sunriseAmber, Brightness.dark) => const _ThemeSpec(
          primary: Color(0xFFFFC488),
          secondary: Color(0xFFFFA962),
          tertiary: Color(0xFFFFD983),
          background: Color(0xFF24160A),
          surface: Color(0xFF332113),
          textPrimary: Color(0xFFFFEEDA),
          textSecondary: Color(0xFFE4C39F),
          warning: Color(0xFFFF8A6A),
          radius: 14,
        ),
      (PlanDoneThemeKey.slateBlue, Brightness.light) => const _ThemeSpec(
          primary: Color(0xFF2D3A73),
          secondary: Color(0xFF5061A8),
          tertiary: Color(0xFF6D8BD8),
          background: Color(0xFFEEF1FA),
          surface: Color(0xFFFFFFFF),
          textPrimary: Color(0xFF1B2347),
          textSecondary: Color(0xFF5A6694),
          warning: Color(0xFFE58A3C),
          radius: 8,
        ),
      (PlanDoneThemeKey.slateBlue, Brightness.dark) => const _ThemeSpec(
          primary: Color(0xFFB4C3FF),
          secondary: Color(0xFF8FA3F6),
          tertiary: Color(0xFF9BC3FF),
          background: Color(0xFF10162D),
          surface: Color(0xFF182041),
          textPrimary: Color(0xFFE9EDFF),
          textSecondary: Color(0xFFB8C0EA),
          warning: Color(0xFFFFB77A),
          radius: 8,
        ),
      (PlanDoneThemeKey.roseQuartz, Brightness.light) => const _ThemeSpec(
          primary: Color(0xFF9B4C68),
          secondary: Color(0xFFC36C8D),
          tertiary: Color(0xFFE39CB2),
          background: Color(0xFFFFF0F4),
          surface: Color(0xFFFFFFFF),
          textPrimary: Color(0xFF3B1E2A),
          textSecondary: Color(0xFF7F5B69),
          warning: Color(0xFFD96A2E),
          radius: 16,
        ),
      (PlanDoneThemeKey.roseQuartz, Brightness.dark) => const _ThemeSpec(
          primary: Color(0xFFF3B1C6),
          secondary: Color(0xFFDF92AD),
          tertiary: Color(0xFFFFC8D6),
          background: Color(0xFF25131A),
          surface: Color(0xFF351E27),
          textPrimary: Color(0xFFFFE9F0),
          textSecondary: Color(0xFFE7B7C7),
          warning: Color(0xFFFFA06E),
          radius: 16,
        ),
      (PlanDoneThemeKey.emberNight, Brightness.light) => const _ThemeSpec(
          primary: Color(0xFF7A2A22),
          secondary: Color(0xFFB24B3E),
          tertiary: Color(0xFFD97A4D),
          background: Color(0xFFFFF2EE),
          surface: Color(0xFFFFFFFF),
          textPrimary: Color(0xFF361712),
          textSecondary: Color(0xFF7A564D),
          warning: Color(0xFFCF3F33),
          radius: 10,
        ),
      (PlanDoneThemeKey.emberNight, Brightness.dark) => const _ThemeSpec(
          primary: Color(0xFFFFB4A8),
          secondary: Color(0xFFFF8E7A),
          tertiary: Color(0xFFFFB781),
          background: Color(0xFF210F0C),
          surface: Color(0xFF331915),
          textPrimary: Color(0xFFFFE8E2),
          textSecondary: Color(0xFFE4B6AA),
          warning: Color(0xFFFF7B69),
          radius: 10,
        ),
      (PlanDoneThemeKey.mintLeaf, Brightness.light) => const _ThemeSpec(
          primary: Color(0xFF1D7A64),
          secondary: Color(0xFF3DAE91),
          tertiary: Color(0xFF70D7B8),
          background: Color(0xFFEFFFF8),
          surface: Color(0xFFFFFFFF),
          textPrimary: Color(0xFF13362D),
          textSecondary: Color(0xFF4C7A6E),
          warning: Color(0xFFD1842A),
          radius: 12,
        ),
      (PlanDoneThemeKey.mintLeaf, Brightness.dark) => const _ThemeSpec(
          primary: Color(0xFF8DE3CC),
          secondary: Color(0xFF62D1B1),
          tertiary: Color(0xFFA8F0D9),
          background: Color(0xFF0D1F1A),
          surface: Color(0xFF173029),
          textPrimary: Color(0xFFE6FFF7),
          textSecondary: Color(0xFFB3DCCF),
          warning: Color(0xFFFFB96F),
          radius: 12,
        ),
      (PlanDoneThemeKey.citrusPop, Brightness.light) => const _ThemeSpec(
          primary: Color(0xFF3C7D11),
          secondary: Color(0xFF75A81F),
          tertiary: Color(0xFFB8D63A),
          background: Color(0xFFFAFFE9),
          surface: Color(0xFFFFFFFF),
          textPrimary: Color(0xFF22360C),
          textSecondary: Color(0xFF61733A),
          warning: Color(0xFFC36A24),
          radius: 10,
        ),
      (PlanDoneThemeKey.citrusPop, Brightness.dark) => const _ThemeSpec(
          primary: Color(0xFFB3E56A),
          secondary: Color(0xFF93D048),
          tertiary: Color(0xFFD8F58F),
          background: Color(0xFF161F0A),
          surface: Color(0xFF243214),
          textPrimary: Color(0xFFF2FFDF),
          textSecondary: Color(0xFFC8DBA5),
          warning: Color(0xFFFFB86B),
          radius: 10,
        ),
      (PlanDoneThemeKey.indigoPulse, Brightness.light) => const _ThemeSpec(
          primary: Color(0xFF352E91),
          secondary: Color(0xFF5B52C8),
          tertiary: Color(0xFF7B77EB),
          background: Color(0xFFF1F0FF),
          surface: Color(0xFFFFFFFF),
          textPrimary: Color(0xFF1F1A4B),
          textSecondary: Color(0xFF6461A2),
          warning: Color(0xFFE18935),
          radius: 9,
        ),
      (PlanDoneThemeKey.indigoPulse, Brightness.dark) => const _ThemeSpec(
          primary: Color(0xFFC3BEFF),
          secondary: Color(0xFFA9A0FF),
          tertiary: Color(0xFFC9C6FF),
          background: Color(0xFF12112A),
          surface: Color(0xFF1E1C3F),
          textPrimary: Color(0xFFF0EEFF),
          textSecondary: Color(0xFFC2BFE6),
          warning: Color(0xFFFFBC74),
          radius: 9,
        ),
      (PlanDoneThemeKey.sandDune, Brightness.light) => const _ThemeSpec(
          primary: Color(0xFF8A6A3F),
          secondary: Color(0xFFB18A57),
          tertiary: Color(0xFFD8B17C),
          background: Color(0xFFFFF8EE),
          surface: Color(0xFFFFFFFF),
          textPrimary: Color(0xFF3B2D19),
          textSecondary: Color(0xFF7D6A4D),
          warning: Color(0xFFD1662C),
          radius: 14,
        ),
      (PlanDoneThemeKey.sandDune, Brightness.dark) => const _ThemeSpec(
          primary: Color(0xFFE6C99F),
          secondary: Color(0xFFD7B17B),
          tertiary: Color(0xFFF3D9B6),
          background: Color(0xFF221A12),
          surface: Color(0xFF34291D),
          textPrimary: Color(0xFFFFF0DF),
          textSecondary: Color(0xFFDCC8AE),
          warning: Color(0xFFFFAA74),
          radius: 14,
        ),
      (PlanDoneThemeKey.glacier, Brightness.light) => const _ThemeSpec(
          primary: Color(0xFF2F6F82),
          secondary: Color(0xFF5B98AC),
          tertiary: Color(0xFF88C5D8),
          background: Color(0xFFF0FAFD),
          surface: Color(0xFFFFFFFF),
          textPrimary: Color(0xFF16323D),
          textSecondary: Color(0xFF5D7D89),
          warning: Color(0xFFD47D2E),
          radius: 8,
        ),
      (PlanDoneThemeKey.glacier, Brightness.dark) => const _ThemeSpec(
          primary: Color(0xFFA2DCEC),
          secondary: Color(0xFF79C3D8),
          tertiary: Color(0xFFB7ECFA),
          background: Color(0xFF0D1C22),
          surface: Color(0xFF17303A),
          textPrimary: Color(0xFFE9F9FF),
          textSecondary: Color(0xFFB8D5DF),
          warning: Color(0xFFFFBA78),
          radius: 8,
        ),
      (PlanDoneThemeKey.lavaStone, Brightness.light) => const _ThemeSpec(
          primary: Color(0xFF4D3B38),
          secondary: Color(0xFF77605A),
          tertiary: Color(0xFFB57A62),
          background: Color(0xFFF7F2F1),
          surface: Color(0xFFFFFFFF),
          textPrimary: Color(0xFF271D1B),
          textSecondary: Color(0xFF6E5B56),
          warning: Color(0xFFC84E3A),
          radius: 6,
        ),
      (PlanDoneThemeKey.lavaStone, Brightness.dark) => const _ThemeSpec(
          primary: Color(0xFFD3BBB5),
          secondary: Color(0xFFBFA29A),
          tertiary: Color(0xFFFFA98A),
          background: Color(0xFF1C1413),
          surface: Color(0xFF2D2120),
          textPrimary: Color(0xFFF8ECE9),
          textSecondary: Color(0xFFD2B9B2),
          warning: Color(0xFFFF8A72),
          radius: 6,
        ),
      (PlanDoneThemeKey.meadowLight, Brightness.light) => const _ThemeSpec(
          primary: Color(0xFF2C7E3E),
          secondary: Color(0xFF4FAE66),
          tertiary: Color(0xFF86D491),
          background: Color(0xFFF2FCF2),
          surface: Color(0xFFFFFFFF),
          textPrimary: Color(0xFF173621),
          textSecondary: Color(0xFF5B7F65),
          warning: Color(0xFFCC7A2A),
          radius: 11,
        ),
      (PlanDoneThemeKey.meadowLight, Brightness.dark) => const _ThemeSpec(
          primary: Color(0xFFA7E8B6),
          secondary: Color(0xFF80D69A),
          tertiary: Color(0xFFC5F1CC),
          background: Color(0xFF102214),
          surface: Color(0xFF1C3522),
          textPrimary: Color(0xFFE9FFE9),
          textSecondary: Color(0xFFBEDBC1),
          warning: Color(0xFFFFB870),
          radius: 11,
        ),
      (PlanDoneThemeKey.cobaltEdge, Brightness.light) => const _ThemeSpec(
          primary: Color(0xFF0F3FA8),
          secondary: Color(0xFF3566CC),
          tertiary: Color(0xFF4F95F5),
          background: Color(0xFFEEF4FF),
          surface: Color(0xFFFFFFFF),
          textPrimary: Color(0xFF102448),
          textSecondary: Color(0xFF4F6797),
          warning: Color(0xFFE17E31),
          radius: 7,
        ),
      (PlanDoneThemeKey.cobaltEdge, Brightness.dark) => const _ThemeSpec(
          primary: Color(0xFF9DBDFF),
          secondary: Color(0xFF80A8FF),
          tertiary: Color(0xFF9BD3FF),
          background: Color(0xFF0B1630),
          surface: Color(0xFF15254A),
          textPrimary: Color(0xFFE8EFFF),
          textSecondary: Color(0xFFB5C5E8),
          warning: Color(0xFFFFB874),
          radius: 7,
        ),
      (PlanDoneThemeKey.cherryBlossom, Brightness.light) => const _ThemeSpec(
          primary: Color(0xFFB84B73),
          secondary: Color(0xFFD67095),
          tertiary: Color(0xFFF3A5BE),
          background: Color(0xFFFFF1F6),
          surface: Color(0xFFFFFFFF),
          textPrimary: Color(0xFF4A1F2E),
          textSecondary: Color(0xFF8D6070),
          warning: Color(0xFFD16A30),
          radius: 18,
        ),
      (PlanDoneThemeKey.cherryBlossom, Brightness.dark) => const _ThemeSpec(
          primary: Color(0xFFFFB3C8),
          secondary: Color(0xFFFF91B2),
          tertiary: Color(0xFFFFC7D9),
          background: Color(0xFF26131A),
          surface: Color(0xFF3A1F29),
          textPrimary: Color(0xFFFFE8F0),
          textSecondary: Color(0xFFE9B7C7),
          warning: Color(0xFFFFA36D),
          radius: 18,
        ),
      (PlanDoneThemeKey.neonGrid, Brightness.light) => const _ThemeSpec(
          primary: Color(0xFF1C1C1C),
          secondary: Color(0xFF3E3E3E),
          tertiary: Color(0xFF00C77A),
          background: Color(0xFFF6F7F8),
          surface: Color(0xFFFFFFFF),
          textPrimary: Color(0xFF101010),
          textSecondary: Color(0xFF545454),
          warning: Color(0xFFDD6D20),
          radius: 4,
        ),
      (PlanDoneThemeKey.neonGrid, Brightness.dark) => const _ThemeSpec(
          primary: Color(0xFFE6E6E6),
          secondary: Color(0xFFB9B9B9),
          tertiary: Color(0xFF34F5A7),
          background: Color(0xFF050806),
          surface: Color(0xFF101511),
          textPrimary: Color(0xFFE8F4EC),
          textSecondary: Color(0xFF9CB7A7),
          warning: Color(0xFFFFA764),
          radius: 4,
        ),
      (PlanDoneThemeKey.graphiteGold, Brightness.light) => const _ThemeSpec(
          primary: Color(0xFF3A3A3A),
          secondary: Color(0xFF666666),
          tertiary: Color(0xFFC9A227),
          background: Color(0xFFF7F7F3),
          surface: Color(0xFFFFFFFF),
          textPrimary: Color(0xFF202020),
          textSecondary: Color(0xFF616161),
          warning: Color(0xFFC56A2E),
          radius: 6,
        ),
      (PlanDoneThemeKey.graphiteGold, Brightness.dark) => const _ThemeSpec(
          primary: Color(0xFFD5D5D5),
          secondary: Color(0xFFA8A8A8),
          tertiary: Color(0xFFE3C55A),
          background: Color(0xFF111111),
          surface: Color(0xFF1B1B1B),
          textPrimary: Color(0xFFF3F3F3),
          textSecondary: Color(0xFFC7C7C7),
          warning: Color(0xFFFFB580),
          radius: 6,
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
