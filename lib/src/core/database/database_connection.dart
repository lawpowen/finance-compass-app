import 'package:drift/drift.dart';

import 'database_connection_native.dart'
    if (dart.library.js_interop) 'database_connection_web.dart' as platform;

/// Opens the platform-appropriate persistent database.
///
/// Native targets retain the private SQLite file. Web targets use Drift's
/// browser-backed WASM SQLite implementation, which stays in the current
/// browser profile and is never sent to the hosting server.
LazyDatabase openDatabaseConnection() => platform.openDatabaseConnection();
