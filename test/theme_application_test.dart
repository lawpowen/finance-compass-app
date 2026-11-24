import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:finance_app/src/app.dart';
import 'package:finance_app/src/core/database/app_database.dart';
import 'package:finance_app/src/core/providers/database_provider.dart';
import 'package:finance_app/src/core/settings/app_settings_controller.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  return firstLuminance >= secondLuminance
      ? (firstLuminance + .05) / (secondLuminance + .05)
      : (secondLuminance + .05) / (firstLuminance + .05);
}

Color _compositeOver(Color foreground, Color background) {
  final alpha = foreground.a;
  if (alpha >= 1.0) return foreground;
  return Color.from(
    alpha: 1.0,
    red: foreground.r * alpha + background.r * (1 - alpha),
    green: foreground.g * alpha + background.g * (1 - alpha),
    blue: foreground.b * alpha + background.b * (1 - alpha),
  );
}

void main() {
  test('legacy and unknown appearance preferences are normalized to monochrome',
      () async {
    final previous = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous);
    for (final legacy in ['abyss', 'darkWood', 'unknown_theme']) {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final before = AppSettingsController(database: database);
      final after = AppSettingsController(database: database);
      addTearDown(before.dispose);
      addTearDown(after.dispose);
      await database.setMetaValue('theme_style', legacy);
      await before.load();
      await after.load();
      expect(after.themeStyle, AppThemeStyle.monochrome, reason: legacy);
      expect(await database.getMetaValue('theme_style'), 'monochrome',
          reason: legacy);
    }
  });

  test('selectable dopamine and liquidGlass themes persist across reloads',
      () async {
    final previous = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous);
    for (final style in [AppThemeStyle.dopamine, AppThemeStyle.liquidGlass]) {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final writer = AppSettingsController(database: database);
      final reader = AppSettingsController(database: database);
      addTearDown(writer.dispose);
      addTearDown(reader.dispose);
      await writer.load();
      await writer.setThemeStyle(style);
      expect(writer.themeStyle, style);
      await reader.load();
      expect(reader.themeStyle, style);
      expect(await database.getMetaValue('theme_style'), style.name);
    }
  });

  test('all themes keep accents and muted text readable', () {
    for (final style in AppThemeStyle.values) {
      final palette = paletteForStyle(style);
      final theme = buildFinanceTheme(style, locale: const Locale('en', 'US'));
      expect(theme.textTheme.bodyMedium?.fontFamily, 'MiSans');
      expect(theme.textTheme.headlineSmall?.fontFamily, 'MiSans');
      expect(theme.appBarTheme.titleTextStyle?.fontFamily, 'MiSans');
      expect(theme.navigationBarTheme.labelTextStyle?.resolve({})?.fontFamily,
          'MiSans');
      expect(theme.snackBarTheme.contentTextStyle?.fontFamily, 'MiSans');
      expect(_contrast(theme.colorScheme.onPrimary, palette.seed),
          greaterThanOrEqualTo(4.5),
          reason: style.name);
      expect(_contrast(theme.colorScheme.onTertiary, palette.expense),
          greaterThanOrEqualTo(4.5),
          reason: style.name);
      expect(
        _contrast(
          financeForegroundOn(palette.resolvedPrimaryAction),
          palette.resolvedPrimaryAction,
        ),
        greaterThanOrEqualTo(4.5),
        reason: '${style.name} primaryAction',
      );
      for (final surface in [
        palette.background,
        palette.backgroundBottom,
        palette.surface,
        palette.surfaceAlt,
        palette.cardTint,
        for (final bg in palette.backgroundGradientColors)
          _compositeOver(palette.resolvedCardSurface, bg),
      ]) {
        expect(_contrast(palette.textMuted, surface), greaterThanOrEqualTo(4.5),
            reason: style.name);
      }
      if (AppThemeStyle.selectableStyles.contains(style)) {
        for (final surface in [
          palette.surface,
          palette.surfaceAlt,
          for (final bg in palette.backgroundGradientColors)
            _compositeOver(palette.resolvedCardSurface, bg),
        ]) {
          for (final ink in [
            palette.income,
            palette.expense,
            palette.warning
          ]) {
            expect(_contrast(ink, surface), greaterThanOrEqualTo(4.5),
                reason: '${style.name} ink $ink on $surface');
          }
        }
      }
      if (style == AppThemeStyle.monochrome) {
        expect(palette.resolvedPrimaryAction, palette.seed);
        expect(palette.donutColors, isNotNull);
        expect(
          palette.donutColors!,
          everyElement(
            predicate<Color>(
                (color) => color.r == color.g && color.g == color.b),
          ),
        );
      }
    }
  });

  test('Traditional Chinese and Cantonese locales prefer Traditional glyphs',
      () {
    const traditional = <Locale>[
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      Locale('zh', 'TW'),
      Locale('zh', 'HK'),
      Locale('zh', 'MO'),
      Locale('yue', 'HK'),
      Locale.fromSubtags(languageCode: 'yue', scriptCode: 'Hant'),
    ];
    const simplified = <Locale>[
      Locale('en', 'US'),
      Locale('zh', 'CN'),
      Locale.fromSubtags(
          languageCode: 'zh', scriptCode: 'Hans', countryCode: 'TW'),
      Locale.fromSubtags(
          languageCode: 'yue', scriptCode: 'Hans', countryCode: 'HK'),
    ];
    for (final locale in [...traditional, ...simplified]) {
      final isTraditional = traditional.contains(locale);
      final expected = isTraditional ? 'MiSans TC' : 'MiSans';
      final fallback = isTraditional ? 'MiSans' : 'MiSans TC';
      final theme = buildFinanceTheme(AppThemeStyle.abyss, locale: locale);
      for (final text in [
        theme.textTheme.bodyMedium,
        theme.primaryTextTheme.titleMedium,
        theme.appBarTheme.titleTextStyle,
        theme.navigationBarTheme.labelTextStyle?.resolve({}),
        theme.snackBarTheme.contentTextStyle,
      ]) {
        expect(text?.fontFamily, expected, reason: locale.toLanguageTag());
        expect(text?.fontFamilyFallback, [fallback]);
      }
    }
  });

  testWidgets(
      'workspace normalizes legacy theme, keeps ledger meta untouched, and exposes theme entry',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 860);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previous = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous);
    final ledger = AppDatabase.forTesting(NativeDatabase.memory());
    final preferences = AppDatabase.forTesting(NativeDatabase.memory());
    final controller = AppSettingsController(database: preferences);
    addTearDown(ledger.close);
    addTearDown(preferences.close);
    addTearDown(controller.dispose);
    await preferences.setMetaValue('theme_style', 'darkWood');
    await ledger.setMetaValue('theme_style', 'ocean');
    await controller.load();
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(ledger)],
      child: FinanceApp(settingsController: controller),
    ));
    await tester.pumpAndSettle();

    final dashboard = tester.element(find.text('财务罗盘'));
    expect(financePaletteOf(dashboard).monochrome, isTrue);
    expect(Theme.of(dashboard).brightness, Brightness.light);
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is NavigationDestination && widget.label == '设置',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('通知与提醒'), findsOneWidget);
    expect(find.text('外观与主题'), findsOneWidget);
    expect(await ledger.getMetaValue('theme_style'), 'ocean');
  });
}
