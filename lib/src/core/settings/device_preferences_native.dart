import '../database/database_provider.dart';

Future<String?> readDevicePreference(String key) =>
    DatabaseProvider.instance.getMetaValue(key);

Future<void> writeDevicePreference(String key, String value) =>
    DatabaseProvider.instance.setMetaValue(key, value);

bool initializeWebPreferenceIfMissing(String key, String value) => false;
