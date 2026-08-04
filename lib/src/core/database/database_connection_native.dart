import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

LazyDatabase openDatabaseConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'finance_app.sqlite'));
    await _createPreSchemaMigrationBackup(file, directory);
    return NativeDatabase.createInBackground(file);
  });
}

Future<void> _createPreSchemaMigrationBackup(
  File databaseFile,
  Directory documentsDirectory,
) async {
  if (!await databaseFile.exists()) return;

  sqlite.Database? source;
  try {
    source =
        sqlite.sqlite3.open(databaseFile.path, mode: sqlite.OpenMode.readOnly);
    final version = source.userVersion;
    if (version <= 0 || version >= 9) return;

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final backupDirectory = Directory(p.join(documentsDirectory.path,
        'finance_compass_backups', 'pre_v9_$timestamp'));
    await backupDirectory.create(recursive: true);

    const tableNames = [
      'accounts',
      'categories',
      'budgets',
      'transactions',
      'asset_snapshots',
      'app_meta',
      'transaction_templates',
      'recurring_transaction_rules',
    ];
    final tables = <String, List<Map<String, Object?>>>{};
    for (final tableName in tableNames) {
      final exists = source.select(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
          [tableName]);
      if (exists.isEmpty) continue;
      tables[tableName] = source
          .select('SELECT * FROM $tableName')
          .map((row) => Map<String, Object?>.from(row))
          .toList();
    }
    final jsonBackup = File(p.join(backupDirectory.path, 'snapshot.json'));
    await jsonBackup.writeAsString(
      const JsonEncoder.withIndent(' ').convert({
        'backup_type': 'pre_schema_migration',
        'source_schema_version': version,
        'target_schema_version': 9,
        'exported_at': DateTime.now().toIso8601String(),
        'tables': tables,
      }),
      flush: true,
    );
    source.dispose();
    source = null;
    await databaseFile.copy(p.join(backupDirectory.path, 'finance_app.sqlite'));
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('${databaseFile.path}$suffix');
      if (await sidecar.exists()) {
        await sidecar
            .copy(p.join(backupDirectory.path, 'finance_app.sqlite$suffix'));
      }
    }
  } finally {
    source?.dispose();
  }
}
