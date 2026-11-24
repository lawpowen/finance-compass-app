import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../database/database_provider.dart';
import 'app_theme_style.dart';

class AppSettingsController extends ChangeNotifier {
  AppSettingsController({AppDatabase? database}) : _database = database;

  final AppDatabase? _database;

  bool _isLoaded = false;

  AppDatabase get _preferencesDatabase =>
      _database ?? DatabaseProvider.instance;
  AppThemeStyle get themeStyle => AppThemeStyle.monochrome;
  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    final rawValue = await _preferencesDatabase.getMetaValue('theme_style');
    if (rawValue != null && rawValue != themeStyle.name) {
      await _preferencesDatabase.setMetaValue('theme_style', themeStyle.name);
    }
    _isLoaded = true;
    notifyListeners();
  }
}
