import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import 'app_theme_style.dart';
import 'device_preferences_native.dart'
    if (dart.library.js_interop) 'device_preferences_web.dart';

class AppSettingsController extends ChangeNotifier {
  AppSettingsController({AppDatabase? database}) : _database = database;

  final AppDatabase? _database;
  static const _themeKey = 'theme_style';

  AppThemeStyle _themeStyle = AppThemeStyle.monochrome;
  bool _isLoaded = false;
  bool _checkedLocalLedger = false;
  int _preferenceRevision = 0;
  Future<void>? _lastWrite;

  AppThemeStyle get themeStyle => _themeStyle;
  bool get isLoaded => _isLoaded;

  Future<void> load({Duration timeout = const Duration(seconds: 2)}) async {
    final revision = ++_preferenceRevision;
    try {
      final style = await _storedTheme(revision).timeout(timeout);
      if (revision == _preferenceRevision) _themeStyle = style;
    } catch (_) {
      // Device preferences may be unavailable in restricted browsers.
      // A failed load keeps the current theme; explicit saves still report errors.
    }
    if (revision != _preferenceRevision) return;
    ++_preferenceRevision; // Retire pending work if the read timed out.
    _isLoaded = true;
    notifyListeners();
  }

  Future<AppThemeStyle> _storedTheme(int revision) async {
    final previousWrite = _lastWrite;
    if (previousWrite != null) await previousWrite;
    final rawValue = await (_database?.getMetaValue(_themeKey) ??
        readDevicePreference(_themeKey));
    final normalized = AppThemeStyle.normalize(rawValue);
    if (revision == _preferenceRevision &&
        rawValue != null &&
        rawValue != normalized.name) {
      await _persistTheme(normalized);
    }
    return normalized;
  }

  /// The local workspace supplies its opening snapshot. Sync snapshots and
  /// subsequent imports are never sources of device appearance.
  Future<void> adoptLocalLedgerTheme(
      Future<String?> Function() openingTheme) async {
    if (!kIsWeb || _database != null || _checkedLocalLedger) return;
    _checkedLocalLedger = true;
    try {
      final legacy = AppThemeStyle.normalize(await openingTheme());
      if (_lastWrite != null ||
          !initializeWebPreferenceIfMissing(_themeKey, legacy.name)) {
        return;
      }
      ++_preferenceRevision;
      _themeStyle = legacy;
      _isLoaded = true;
      notifyListeners();
    } catch (_) {
      // A locked ledger or restricted localStorage cannot block the workspace.
    }
  }

  Future<void> _persistTheme(AppThemeStyle style) {
    Future<void> write() =>
        _database?.setMetaValue(_themeKey, style.name) ??
        writeDevicePreference(_themeKey, style.name);
    final next = _lastWrite?.then((_) => write()) ?? write();
    // A failed save must not block the next explicit selection.
    _lastWrite = next.onError((_, __) {});
    return next;
  }

  Future<void> setThemeStyle(AppThemeStyle style) async {
    final target = AppThemeStyle.selectableStyles.contains(style)
        ? style
        : AppThemeStyle.monochrome;
    ++_preferenceRevision;
    await _persistTheme(target);
    _themeStyle = target;
    _isLoaded = true;
    notifyListeners();
  }
}
