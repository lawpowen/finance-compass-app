import 'dart:js_interop';

@JS('window.localStorage.getItem')
external String? _getItem(String key);

@JS('window.localStorage.setItem')
external void _setItem(String key, String value);

Future<String?> readDevicePreference(String key) async =>
    _getItem('finance-compass.$key');

Future<void> writeDevicePreference(String key, String value) async =>
    _setItem('finance-compass.$key', value);

bool initializeWebPreferenceIfMissing(String key, String value) {
  final storageKey = 'finance-compass.$key';
  if (_getItem(storageKey) != null) return false;
  _setItem(storageKey, value);
  return true;
}
