import 'dart:async';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/database/app_database.dart';
import 'package:finance_app/src/core/settings/app_settings_controller.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:flutter_test/flutter_test.dart';

class _HeldPreferenceDatabase extends AppDatabase {
  _HeldPreferenceDatabase() : super.forTesting(NativeDatabase.memory());

  final read = Completer<String?>();
  final writes = <String>[];
  Completer<void>? holdWrites;

  @override
  Future<String?> getMetaValue(String keyValue) => read.future;

  @override
  Future<void> setMetaValue(String keyValue, String valueText) async {
    writes.add(valueText);
    await holdWrites?.future;
  }
}

void main() {
  late _HeldPreferenceDatabase db;
  late AppSettingsController settings;

  setUp(() {
    db = _HeldPreferenceDatabase();
    settings = AppSettingsController(database: db);
    addTearDown(settings.dispose);
    addTearDown(db.close);
  });

  testWidgets('a stalled preference read times out and ignores a late result',
      (tester) async {
    final loaded = settings.load();
    await tester.pump(const Duration(seconds: 5));
    await loaded;
    expect(settings.isLoaded, isTrue);
    expect(settings.themeStyle, AppThemeStyle.monochrome);
    db.read.complete('liquidGlass');
    await tester.pump();
    expect(settings.themeStyle, AppThemeStyle.monochrome);
  });

  test('a denied preference store leaves a usable default', () async {
    final loaded = settings.load();
    db.read.completeError(StateError('preference storage unavailable'));
    await loaded;
    expect(settings.isLoaded, isTrue);
    expect(settings.themeStyle, AppThemeStyle.monochrome);
    expect(db.writes, isEmpty);
  });

  test('an old startup read cannot normalize over a newer theme selection',
      () async {
    final loaded = settings.load();
    await settings.setThemeStyle(AppThemeStyle.dopamine);
    db.read.complete('darkWood');
    await loaded;
    expect(settings.themeStyle, AppThemeStyle.dopamine);
    expect(db.writes, ['dopamine']);
  });

  test('a slow legacy repair is written before newer theme choices', () async {
    db.holdWrites = Completer<void>();
    final loaded = settings.load();
    db.read.complete('darkWood');
    await Future<void>.delayed(Duration.zero);
    expect(db.writes, ['monochrome']);
    final first = settings.setThemeStyle(AppThemeStyle.dopamine);
    final second = settings.setThemeStyle(AppThemeStyle.liquidGlass);
    await Future<void>.delayed(Duration.zero);
    expect(db.writes, ['monochrome']);
    db.holdWrites!.complete();
    await Future.wait([loaded, first, second]);
    expect(db.writes, ['monochrome', 'dopamine', 'liquidGlass']);
    expect(settings.themeStyle, AppThemeStyle.liquidGlass);
  });
}
