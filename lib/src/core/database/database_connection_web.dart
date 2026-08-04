import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// Browser storage is intentionally scoped to this origin and browser profile.
/// The host only serves static files; it never receives this database.
LazyDatabase openDatabaseConnection() {
  return LazyDatabase(() async {
    final result = await WasmDatabase.open(
      databaseName: 'finance_compass.sqlite',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
      moveExistingIndexedDbToOpfs: true,
    );
    return result.resolvedExecutor;
  });
}
