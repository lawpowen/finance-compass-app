import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:finance_app/src/core/app_version.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/settings/app_settings_controller.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/features/settings/settings_v2_screen.dart';
import 'package:finance_app/src/features/shared/compass_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _version = kIsWeb ? '$appVersion · $webReleaseLabel' : appVersion;

void main() {
  testWidgets('mobile settings display the loaded version and open About',
      (tester) async {
    _setViewport(tester, const Size(390, 844));
    await _pumpSettings(tester);

    final version = find.text('版本信息');
    final profile = find.textContaining('个人账户');
    expect(find.text(_version), findsOneWidget);
    expect(tester.getTopLeft(version).dy,
        greaterThan(tester.getTopLeft(profile).dy));

    await tester.tap(version);
    await tester.pumpAndSettle();

    expect(find.text('关于 Finance Compass'), findsOneWidget);
    expect(find.text('当前版本 $_version'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local storage guidance opens and closes at 320 pixels',
      (tester) async {
    _setViewport(tester, const Size(320, 800));
    await tester.pumpWidget(const MaterialApp(home: FinanceCompassAboutPage()));
    await tester.pumpAndSettle();

    const description = '财务资料保存在本机。导出或分享由你主动发起。';
    expect(find.text(description), findsNothing);
    await tester.tap(find.byTooltip('查看本机账本说明'));
    await tester.pumpAndSettle();
    expect(find.text(description), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '知道了'));
    await tester.pumpAndSettle();
    expect(find.text(description), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'desktop groups account actions and version beside searchable settings',
      (tester) async {
    _setViewport(tester, const Size(960, 860));
    var updates = 0;
    await _pumpSettings(
      tester,
      syncSettings: TextButton(
        onPressed: () => updates++,
        child: const Text('更新应用'),
      ),
    );

    final profile = find.textContaining('个人账户');
    final version = find.text('版本信息');
    final update = find.text('更新应用');
    final search = find.widgetWithText(OutlinedButton, '搜索设置');
    expect(find.text(_version), findsOneWidget);
    expect(tester.getTopLeft(update).dy,
        greaterThan(tester.getBottomLeft(profile).dy));
    expect(tester.getTopLeft(version).dy,
        greaterThan(tester.getBottomLeft(update).dy));

    final finance = find.text('管理我的财务');
    final preferences = find.text('个性化');
    expect(tester.getTopLeft(search).dx,
        greaterThan(tester.getTopRight(profile).dx));
    expect(
      tester.getTopLeft(preferences).dx,
      tester.getTopLeft(finance).dx,
    );
    expect(
      tester.getCenter(_settingChevron('货币、汇率与显示')).dx,
      tester.getCenter(_settingChevron('类别、模板与周期规则')).dx,
    );
    await tester.tap(update);
    expect(updates, 1);

    await tester.tap(search);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '版本');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '版本信息'));
    await tester.pumpAndSettle();
    expect(find.text('当前版本 $_version'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(959, 860);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(version).dy,
        greaterThan(tester.getTopLeft(profile).dy));
    expect(tester.getTopLeft(update).dy,
        greaterThan(tester.getBottomLeft(version).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'appearance entry searches cleanly, previews without saving, and persists selected theme',
      (tester) async {
    _setViewport(tester, const Size(480, 900));
    final previous = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous);
    final preferences = AppDatabase.forTesting(NativeDatabase.memory());
    final controller = AppSettingsController(database: preferences);
    addTearDown(preferences.close);
    addTearDown(controller.dispose);
    await controller.load();

    final repository = FinanceRepository.preview();
    addTearDown(repository.database.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsV2Screen(
            repository: repository,
            settingsController: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('外观与主题'), findsOneWidget);
    expect(find.text('黑白极简'), findsOneWidget);

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '多巴胺');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '外观与主题'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('theme-option-monochrome')), findsOneWidget);
    expect(find.byKey(const Key('theme-option-dopamine')), findsOneWidget);
    expect(find.byKey(const Key('theme-option-liquidGlass')), findsOneWidget);
    expect(find.text('墨绿'), findsNothing);
    expect(find.text('沉木'), findsNothing);
    expect(find.text(AppThemeStyle.dopamine.description), findsNothing);
    await tester.tap(find.byTooltip('查看主题预览说明'));
    await tester.pumpAndSettle();
    expect(find.textContaining(AppThemeStyle.dopamine.description),
        findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '知道了'));
    await tester.pumpAndSettle();
    expect(controller.themeStyle, AppThemeStyle.monochrome);

    await tester.tap(_themeLabel(AppThemeStyle.dopamine));
    await tester.pumpAndSettle();
    expect(find.text('效果预览 · 多巴胺'), findsOneWidget);
    expect(controller.themeStyle, AppThemeStyle.monochrome);

    await tester.tap(find.byType(CompassBackButton));
    await tester.pumpAndSettle();
    expect(controller.themeStyle, AppThemeStyle.monochrome);

    await tester.tap(find.text('外观与主题'));
    await tester.pumpAndSettle();
    await tester.tap(_themeLabel(AppThemeStyle.liquidGlass));
    await tester.pumpAndSettle();
    expect(find.text('效果预览 · 苹果液态玻璃'), findsOneWidget);

    final apply = find.widgetWithText(FilledButton, '应用主题');
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();

    expect(controller.themeStyle, AppThemeStyle.liquidGlass);
    expect(find.text('苹果液态玻璃'), findsOneWidget);

    final reloaded = AppSettingsController(database: preferences);
    addTearDown(reloaded.dispose);
    await reloaded.load();
    expect(reloaded.themeStyle, AppThemeStyle.liquidGlass);
    expect(tester.takeException(), isNull);
  });

  testWidgets('appearance save failure keeps the previous applied theme',
      (tester) async {
    _setViewport(tester, const Size(480, 900));
    final controller = _FailingSettingsController();
    addTearDown(controller.dispose);
    final repository = FinanceRepository.preview();
    addTearDown(repository.database.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsV2Screen(
            repository: repository,
            settingsController: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('外观与主题'));
    await tester.pumpAndSettle();
    await tester.tap(_themeLabel(AppThemeStyle.dopamine));
    await tester.pumpAndSettle();

    final apply = find.widgetWithText(FilledButton, '应用主题');
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();

    expect(controller.themeStyle, AppThemeStyle.monochrome);
    expect(find.text('保存主题失败，请重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FailingSettingsController extends AppSettingsController {
  @override
  Future<void> setThemeStyle(AppThemeStyle style) {
    return Future<void>.error(StateError('disk full'));
  }
}

Finder _themeLabel(AppThemeStyle style) => find.descendant(
      of: find.byKey(Key('theme-option-${style.name}')),
      matching: find.text(style.label),
    );

Finder _settingChevron(String title) => find.descendant(
      of: find.widgetWithText(CompassSettingsRow, title),
      matching: find.byIcon(Icons.chevron_right_rounded),
    );

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpSettings(WidgetTester tester, {Widget? syncSettings}) async {
  final repository = FinanceRepository.preview();
  addTearDown(repository.database.close);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SettingsV2Screen(
          repository: repository,
          settingsController: AppSettingsController(),
          syncSettings: syncSettings,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
