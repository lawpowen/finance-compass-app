import 'package:flutter/material.dart';

import '../settings/app_theme_style.dart';

class FinanceThemePalette {
  const FinanceThemePalette({
    required this.seed,
    required this.background,
    required this.backgroundTop,
    required this.backgroundBottom,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.cardTint,
    required this.cardBorderStrong,
    required this.textPrimary,
    required this.textMuted,
    required this.gradient,
    required this.income,
    required this.expense,
    this.monochrome = false,
  });

  final Color seed;
  final Color background;
  final Color backgroundTop;
  final Color backgroundBottom;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color cardTint;
  final Color cardBorderStrong;
  final Color textPrimary;
  final Color textMuted;
  final List<Color> gradient;
  final Color income;
  final Color expense;
  final bool monochrome;
}

@immutable
class FinanceThemeTokens extends ThemeExtension<FinanceThemeTokens> {
  const FinanceThemeTokens({required this.palette});

  final FinanceThemePalette palette;

  @override
  FinanceThemeTokens copyWith({FinanceThemePalette? palette}) =>
      FinanceThemeTokens(palette: palette ?? this.palette);

  @override
  FinanceThemeTokens lerp(
    covariant ThemeExtension<FinanceThemeTokens>? other,
    double t,
  ) {
    if (other is! FinanceThemeTokens) return this;
    return t < .5 ? this : other;
  }
}

FinanceThemePalette financePaletteOf(BuildContext context) =>
    Theme.of(context).extension<FinanceThemeTokens>()?.palette ??
    paletteForStyle(
      Theme.of(context).brightness == Brightness.dark
          ? AppThemeStyle.abyss
          : AppThemeStyle.tide,
    );

Color financeForegroundOn(Color background) {
  final luminance = background.computeLuminance();
  final contrastWithBlack = (luminance + .05) / .05;
  final contrastWithWhite = 1.05 / (luminance + .05);
  return contrastWithBlack >= contrastWithWhite ? Colors.black : Colors.white;
}

FinanceThemePalette paletteForStyle(AppThemeStyle style) {
  const incomeColor = Color(0xFF356046);
  const expenseColor = Color(0xFFA13E48);

  switch (style) {
    case AppThemeStyle.monochrome:
      return const FinanceThemePalette(
        seed: Color(0xFF151515),
        background: Color(0xFFFAFAF8),
        backgroundTop: Color(0xFFFAFAF8),
        backgroundBottom: Color(0xFFFAFAF8),
        surface: Color(0xFFFFFFFF),
        surfaceAlt: Color(0xFFECECEC),
        border: Color(0xFFD5D5D5),
        cardTint: Color(0xFFFFFFFF),
        cardBorderStrong: Color(0xFF969696),
        textPrimary: Color(0xFF151515),
        textMuted: Color(0xFF5A5A5A),
        gradient: [Color(0xFFCDCDCD), Color(0xFFF3F3F3)],
        income: Color(0xFF454545),
        expense: Color(0xFF151515),
        monochrome: true,
      );
    case AppThemeStyle.tide:
      return const FinanceThemePalette(
        seed: Color(0xFF4C7269),
        background: Color(0xFFF6F8FA),
        backgroundTop: Color(0xFFFAFBFC),
        backgroundBottom: Color(0xFFF1F4F7),
        surface: Color(0xFFFCFDFE),
        surfaceAlt: Color(0xFFEEF2F6),
        border: Color(0xFFE2E7ED),
        cardTint: Color(0xFFEFF5F3),
        cardBorderStrong: Color(0xFFB8D4CE),
        textPrimary: Color(0xFF3D6058),
        textMuted: Color(0xFF5C6770),
        gradient: [Color(0xFFA8D5CC), Color(0xFFE2EDE9)],
        income: incomeColor,
        expense: expenseColor,
      );
    case AppThemeStyle.ocean:
      return const FinanceThemePalette(
        seed: Color(0xFF397388),
        background: Color(0xFFF3F7FA),
        backgroundTop: Color(0xFFF8FBFD),
        backgroundBottom: Color(0xFFEAF0F5),
        surface: Color(0xFFFBFCFE),
        surfaceAlt: Color(0xFFE8EFF5),
        border: Color(0xFFD8E2EA),
        cardTint: Color(0xFFEAF3F8),
        cardBorderStrong: Color(0xFFA3C9DA),
        textPrimary: Color(0xFF3A6A7E),
        textMuted: Color(0xFF536976),
        gradient: [Color(0xFF7BB8D4), Color(0xFFD0E6F0)],
        income: incomeColor,
        expense: expenseColor,
      );
    case AppThemeStyle.sky:
      return const FinanceThemePalette(
        seed: Color(0xFF48688F),
        background: Color(0xFFF4F6FB),
        backgroundTop: Color(0xFFFAFBFE),
        backgroundBottom: Color(0xFFECF0F8),
        surface: Color(0xFFFCFDFF),
        surfaceAlt: Color(0xFFEDF1F9),
        border: Color(0xFFDAE2EF),
        cardTint: Color(0xFFECF1FC),
        cardBorderStrong: Color(0xFFB0C6E4),
        textPrimary: Color(0xFF446387),
        textMuted: Color(0xFF55647B),
        gradient: [Color(0xFF9FC4F0), Color(0xFFDAE6F8)],
        income: incomeColor,
        expense: expenseColor,
      );
    case AppThemeStyle.ember:
      return const FinanceThemePalette(
        seed: Color(0xFF915B3E),
        background: Color(0xFFF8F6F5),
        backgroundTop: Color(0xFFFCFAF9),
        backgroundBottom: Color(0xFFF3EEEB),
        surface: Color(0xFFFEFDFC),
        surfaceAlt: Color(0xFFF5EDE6),
        border: Color(0xFFEBE0D9),
        cardTint: Color(0xFFF8EDE5),
        cardBorderStrong: Color(0xFFDDBAA0),
        textPrimary: Color(0xFF7A5E48),
        textMuted: Color(0xFF6F594B),
        gradient: [Color(0xFFF0D0BA), Color(0xFFF8EBE0)],
        income: incomeColor,
        expense: expenseColor,
      );
    case AppThemeStyle.forest:
      return const FinanceThemePalette(
        seed: Color(0xFF546D47),
        background: Color(0xFFF5F7F3),
        backgroundTop: Color(0xFFFAFBF8),
        backgroundBottom: Color(0xFFEFF3EB),
        surface: Color(0xFFFDFFFC),
        surfaceAlt: Color(0xFFEFF3E9),
        border: Color(0xFFDFE5DA),
        cardTint: Color(0xFFEFF5EA),
        cardBorderStrong: Color(0xFFB8CBAD),
        textPrimary: Color(0xFF4D6643),
        textMuted: Color(0xFF59664E),
        gradient: [Color(0xFFC0D4B2), Color(0xFFE4ECD9)],
        income: incomeColor,
        expense: expenseColor,
      );
    case AppThemeStyle.dune:
      return const FinanceThemePalette(
        seed: Color(0xFF885A32),
        background: Color(0xFFFAF5EF),
        backgroundTop: Color(0xFFFDFAF6),
        backgroundBottom: Color(0xFFF4E8DB),
        surface: Color(0xFFFFFDF9),
        surfaceAlt: Color(0xFFF5EADD),
        border: Color(0xFFEDE0D2),
        cardTint: Color(0xFFF8ECE0),
        cardBorderStrong: Color(0xFFDABB96),
        textPrimary: Color(0xFF7A5C3E),
        textMuted: Color(0xFF705844),
        gradient: [Color(0xFFE8C8A0), Color(0xFFF5E8D6)],
        income: incomeColor,
        expense: expenseColor,
      );
    case AppThemeStyle.aurora:
      return const FinanceThemePalette(
        seed: Color(0xFF6656A2),
        background: Color(0xFFF5F3FA),
        backgroundTop: Color(0xFFFAF9FE),
        backgroundBottom: Color(0xFFEEEAF6),
        surface: Color(0xFFFEFDFF),
        surfaceAlt: Color(0xFFF0EDF9),
        border: Color(0xFFE0DDF2),
        cardTint: Color(0xFFF0EDFC),
        cardBorderStrong: Color(0xFFBEB4E4),
        textPrimary: Color(0xFF5C5098),
        textMuted: Color(0xFF675C7B),
        gradient: [Color(0xFFA89EED), Color(0xFFD4CFFF)],
        income: incomeColor,
        expense: expenseColor,
      );
    case AppThemeStyle.night:
      return const FinanceThemePalette(
        seed: Color(0xFF7197D1),
        background: Color(0xFF0A0A0A),
        backgroundTop: Color(0xFF101418),
        backgroundBottom: Color(0xFF080808),
        surface: Color(0xFF1A1F2E),
        surfaceAlt: Color(0xFF141820),
        border: Color(0xFF2A2F3E),
        cardTint: Color(0xFF141820),
        cardBorderStrong: Color(0xFF2A2F3E),
        textPrimary: Color(0xFFE8E8E8),
        textMuted: Color(0xFFA0A0A0),
        gradient: [Color(0x4D4A6FA5), Color(0x1A4A6FA5)],
        income: Color(0xFF7BC89A),
        expense: Color(0xFFE8AAAA),
      );
    case AppThemeStyle.abyss:
      return const FinanceThemePalette(
        seed: Color(0xFF58D4C4),
        background: Color(0xFF011720),
        backgroundTop: Color(0xFF00131B),
        backgroundBottom: Color(0xFF001B25),
        surface: Color(0xFF06232C),
        surfaceAlt: Color(0xFF0B2B34),
        border: Color(0xFF284149),
        cardTint: Color(0xFF06232C),
        cardBorderStrong: Color(0xFF36545C),
        textPrimary: Color(0xFFF1F3F2),
        textMuted: Color(0xFFA4AAAD),
        gradient: [Color(0x3058D4C4), Color(0x0658D4C4)],
        income: Color(0xFF58D4C4),
        expense: Color(0xFFFF7417),
      );
    case AppThemeStyle.graphite:
      return const FinanceThemePalette(
        seed: Color(0xFFA5A5A5),
        background: Color(0xFF1A1A1A),
        backgroundTop: Color(0xFF202020),
        backgroundBottom: Color(0xFF161616),
        surface: Color(0xFF2A2A2A),
        surfaceAlt: Color(0xFF242424),
        border: Color(0xFF383838),
        cardTint: Color(0xFF242424),
        cardBorderStrong: Color(0xFF383838),
        textPrimary: Color(0xFFE0E0E0),
        textMuted: Color(0xFFA0A0A0),
        gradient: [Color(0x4D888888), Color(0x1A888888)],
        income: Color(0xFF7BC89A),
        expense: Color(0xFFE8AAAA),
      );
    case AppThemeStyle.darkGreen:
      return const FinanceThemePalette(
        seed: Color(0xFF6CAC90),
        background: Color(0xFF0D1210),
        backgroundTop: Color(0xFF121816),
        backgroundBottom: Color(0xFF0A0E0C),
        surface: Color(0xFF1A2420),
        surfaceAlt: Color(0xFF151C18),
        border: Color(0xFF2A3830),
        cardTint: Color(0xFF151C18),
        cardBorderStrong: Color(0xFF2A3830),
        textPrimary: Color(0xFFE0E8E4),
        textMuted: Color(0xFFA0A8A4),
        gradient: [Color(0x4D4A8B6E), Color(0x1A4A8B6E)],
        income: Color(0xFF7BC89A),
        expense: Color(0xFFE8AAAA),
      );
    case AppThemeStyle.darkWood:
      return const FinanceThemePalette(
        seed: Color(0xFFBB9574),
        background: Color(0xFF141010),
        backgroundTop: Color(0xFF1A1614),
        backgroundBottom: Color(0xFF100E0C),
        surface: Color(0xFF241E1A),
        surfaceAlt: Color(0xFF1E1814),
        border: Color(0xFF382E28),
        cardTint: Color(0xFF1E1814),
        cardBorderStrong: Color(0xFF382E28),
        textPrimary: Color(0xFFE8E0D8),
        textMuted: Color(0xFFA8A098),
        gradient: [Color(0x4DA08060), Color(0x1AA08060)],
        income: Color(0xFF7BC89A),
        expense: Color(0xFFE8AAAA),
      );
  }
}

ThemeData buildFinanceTheme(AppThemeStyle style, {Locale? locale}) {
  final deviceLocale =
      locale ?? WidgetsBinding.instance.platformDispatcher.locale;
  final language = deviceLocale.languageCode;
  final script = deviceLocale.scriptCode;
  final isChinese = language == 'zh' || language == 'yue';
  final prefersTraditional = isChinese &&
      (script == 'Hant' ||
          (script == null &&
              (language == 'yue' ||
                  const {'TW', 'HK', 'MO'}
                      .contains(deviceLocale.countryCode))));
  final fontFamily = prefersTraditional ? 'MiSans TC' : 'MiSans';
  final fontFallback =
      prefersTraditional ? const ['MiSans'] : const ['MiSans TC'];
  final palette = paletteForStyle(style);
  final isDark = style.isDark;
  final generatedScheme = ColorScheme.fromSeed(
    seedColor: palette.seed,
    brightness: isDark ? Brightness.dark : Brightness.light,
    dynamicSchemeVariant: palette.monochrome
        ? DynamicSchemeVariant.monochrome
        : DynamicSchemeVariant.tonalSpot,
  );
  final colorScheme = generatedScheme.copyWith(
    primary: palette.seed,
    onPrimary: financeForegroundOn(palette.seed),
    secondary: palette.income,
    onSecondary: financeForegroundOn(palette.income),
    tertiary: palette.expense,
    onTertiary: financeForegroundOn(palette.expense),
    surface: palette.surface,
    onSurface: palette.textPrimary,
    outline: palette.border,
    outlineVariant: palette.border.withValues(alpha: .6),
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    colorScheme: colorScheme,
    extensions: [FinanceThemeTokens(palette: palette)],
    scaffoldBackgroundColor: palette.background,
    textTheme: TextTheme(
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.45,
        color: palette.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.15,
        color: palette.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: palette.textPrimary,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: palette.textPrimary,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.3,
        color: palette.textMuted,
      ),
      labelLarge: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: palette.textMuted,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: palette.textMuted,
      ),
    ),
    cardTheme: CardThemeData(
      color: palette.cardTint,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: palette.cardTint,
          width: 0.5,
        ),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: palette.textPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontFamilyFallback: fontFallback,
        color: palette.textPrimary,
        fontSize: 21,
        fontWeight: FontWeight.w700,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surface,
      modalBackgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    dividerTheme: DividerThemeData(
      color: palette.border.withValues(alpha: 0.5),
      thickness: 0.5,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surfaceAlt.withValues(alpha: 0.6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.border, width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.border, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.seed, width: 1.0),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.seed,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        elevation: 0,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: palette.textPrimary,
        shape: const CircleBorder(),
        side: BorderSide.none,
      ),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: EdgeInsets.zero,
      iconColor: palette.textMuted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.surface.withValues(alpha: 0.92),
      indicatorColor: Colors.transparent,
      height: 72,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallback,
            color: states.contains(WidgetState.selected)
                ? palette.seed
                : palette.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          )),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? palette.seed : palette.textMuted,
          size: 24,
        );
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark
          ? palette.surfaceAlt.withValues(alpha: 0.95)
          : palette.textPrimary.withValues(alpha: 0.88),
      contentTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontFamilyFallback: fontFallback,
        color: isDark ? palette.textPrimary : Colors.white,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
