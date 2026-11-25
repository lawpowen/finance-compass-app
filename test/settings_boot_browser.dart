@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:finance_app/src/core/settings/app_settings_controller.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:flutter_test/flutter_test.dart';

@JS('window.localStorage.getItem')
external String? _getItem(String key);

@JS('window.localStorage.setItem')
external void _setItem(String key, String value);

@JS('window.localStorage.removeItem')
external void _removeItem(String key);

void main() {
  const key = 'finance-compass.theme_style';

  setUp(() {
    final original = _getItem(key);
    addTearDown(
        () => original == null ? _removeItem(key) : _setItem(key, original));
    _removeItem(key);
  });

  test('new Web controllers read and persist the device theme in localStorage',
      () async {
    _setItem(key, 'liquidGlass');
    final first = AppSettingsController();
    addTearDown(first.dispose);
    await first.load();
    expect(first.themeStyle, AppThemeStyle.liquidGlass);
    await first.setThemeStyle(AppThemeStyle.dopamine);
    expect(_getItem(key), 'dopamine');

    final reopened = AppSettingsController();
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.themeStyle, AppThemeStyle.dopamine);
  });

  test('the opening local ledger can seed the device preference only once',
      () async {
    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    await settings.load();
    await settings.adoptLocalLedgerTheme(() async => 'liquidGlass');
    expect(_getItem(key), 'liquidGlass');
    expect(settings.themeStyle, AppThemeStyle.liquidGlass);
    var repeatedReads = 0;
    await settings.adoptLocalLedgerTheme(() async {
      repeatedReads++;
      return 'dopamine';
    });
    expect(repeatedReads, 0);

    final anotherLaunch = AppSettingsController();
    addTearDown(anotherLaunch.dispose);
    await anotherLaunch.load();
    await anotherLaunch.adoptLocalLedgerTheme(() async => 'dopamine');
    expect(_getItem(key), 'liquidGlass');
    expect(anotherLaunch.themeStyle, AppThemeStyle.liquidGlass);
  });

  test('a delayed local ledger cannot override a newer device selection',
      () async {
    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    final legacy = Completer<String?>();
    final migration = settings.adoptLocalLedgerTheme(() => legacy.future);
    await settings.setThemeStyle(AppThemeStyle.dopamine);
    legacy.complete('liquidGlass');
    await migration;
    expect(_getItem(key), 'dopamine');
    expect(settings.themeStyle, AppThemeStyle.dopamine);
  });

  test('a fresh local ledger establishes the default before any later import',
      () async {
    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    await settings.adoptLocalLedgerTheme(() async => null);
    expect(_getItem(key), 'monochrome');
    final afterImport = AppSettingsController();
    addTearDown(afterImport.dispose);
    await afterImport.load();
    await afterImport.adoptLocalLedgerTheme(() async => 'liquidGlass');
    expect(afterImport.themeStyle, AppThemeStyle.monochrome);
    expect(_getItem(key), 'monochrome');
  });
}
