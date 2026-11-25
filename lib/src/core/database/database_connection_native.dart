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
    await createPreSchemaMigrationBackup(file, directory);
    return NativeDatabase.createInBackground(file);
  });
}

/// Publishes one self-contained SQLite file and its logical table dump.
/// The SQLite backup API includes committed WAL pages. Both artifacts and the
/// version check refer to the same read snapshot even if another app writes.
Future<Directory?> createPreSchemaMigrationBackup(
  File databaseFile,
  Directory documentsDirectory,
) async {
  if (!await databaseFile.exists()) return null;
  final source =
      sqlite.sqlite3.open(databaseFile.path, mode: sqlite.OpenMode.readOnly);
  Directory? staging;
  sqlite.Database? image;
  try {
    source.execute('BEGIN');
    final version = source.userVersion;
    if (version <= 0 || version >= 9) return null;

    final parent =
        Directory(p.join(documentsDirectory.path, 'finance_compass_backups'));
    await parent.create(recursive: true);
    staging = await parent.createTemp('.pending_');
    image = sqlite.sqlite3.open(p.join(staging.path, 'finance_app.sqlite'));
    await source.backup(image, nPage: -1).drain<void>();
    source.execute('COMMIT');
    // A single-file recovery point is portable to devices without the source WAL.
    image.execute('PRAGMA journal_mode = DELETE');
    final check = image.select('PRAGMA quick_check');
    if (image.userVersion != version ||
        check.length != 1 ||
        check.first.values.first != 'ok' ||
        image.select('PRAGMA foreign_key_check').isNotEmpty) {
      throw StateError('升级前 SQLite 恢复点未通过完整性检查。');
    }

    const names = [
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
    for (final name in names) {
      final exists = image.select(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
          [name]);
      if (exists.isEmpty) continue;
      tables[name] = image
          .select('SELECT * FROM $name')
          .map(Map<String, Object?>.from)
          .toList();
    }
    image.dispose();
    image = null;
    final now = DateTime.now().toUtc().toIso8601String();
    await File(p.join(staging.path, 'snapshot.json')).writeAsString(
      const JsonEncoder.withIndent(' ').convert({
        'backup_type': 'pre_schema_migration',
        'source_schema_version': version,
        'target_schema_version': 9,
        'exported_at': now,
        'tables': tables,
      }),
      flush: true,
    );
    final stamp = now.replaceAll(':', '-').replaceAll('.', '-');
    final suffix = p.basename(staging.path).substring('.pending_'.length);
    final published =
        await staging.rename(p.join(parent.path, 'pre_v9_${stamp}_$suffix'));
    staging = null;
    return published;
  } finally {
    image?.dispose();
    source.dispose();
    if (staging != null) await staging.delete(recursive: true);
  }
}
