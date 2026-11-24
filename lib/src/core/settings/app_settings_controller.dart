import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../database/database_provider.dart';
import 'app_theme_style.dart';

class AppSettingsController extends ChangeNotifier {
  AppSettingsController({AppDatabase? database}) : _database = database;

  final AppDatabase? _database;

  AppThemeStyle _themeStyle = AppThemeStyle.monochrome;
  bool _isLoaded = false;

  AppDatabase get _preferencesDatabase =>
      _database ?? DatabaseProvider.instance;
  AppThemeStyle get themeStyle => _themeStyle;
  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    final rawValue = await _preferencesDatabase.getMetaValue('theme_style');
    final normalized = AppThemeStyle.normalize(rawValue);
    _themeStyle = normalized;
    if (rawValue != null && rawValue != normalized.name) {
      await _preferencesDatabase.setMetaValue('theme_style', normalized.name);
    }
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setThemeStyle(AppThemeStyle style) async {
    final target = AppThemeStyle.selectableStyles.contains(style)
        ? style
        : AppThemeStyle.monochrome;
    await _preferencesDatabase.setMetaValue('theme_style', target.name);
    _themeStyle = target;
    notifyListeners();
  }
}
