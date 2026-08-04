import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('export a validated release recovery JSON', () async {
    const sourcePath = String.fromEnvironment('SOURCE_DB');
    const outputPath = String.fromEnvironment('OUTPUT_JSON');
    expect(sourcePath, isNotEmpty, reason: 'SOURCE_DB is required');
    expect(outputPath, isNotEmpty, reason: 'OUTPUT_JSON is required');

    final source = File(sourcePath).absolute;
    final output = File(outputPath).absolute;
    expect(source.existsSync(), isTrue, reason: 'SQLite snapshot is missing');

    final database = AppDatabase.forTesting(NativeDatabase(source));
    late Map<String, dynamic> payload;
    try {
      final repository = await FinanceRepository.load(database);
      payload = await repository.buildJsonSnapshotPayload();
      _validatePayload(payload);

      await output.parent.create(recursive: true);
      await output.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
        flush: true,
      );

      final decoded = jsonDecode(await output.readAsString());
      expect(decoded, isA<Map<String, dynamic>>());
      _validatePayload(decoded as Map<String, dynamic>);
      expect(await output.length(), greaterThan(0));
    } finally {
      await database.close();
    }

    final restoreDirectory =
        await Directory.systemTemp.createTemp('finance_release_restore');
    const pathProviderChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return restoreDirectory.path;
      }
      return null;
    });
    final restoredDatabase = AppDatabase.forTesting(NativeDatabase.memory());
    try {
      final emptyRepository = await FinanceRepository.load(restoredDatabase);
      final restored = await emptyRepository.importJsonSnapshot(output.path);
      expect(restored.accounts.length, (payload['accounts'] as List).length);
      expect(
        restored.categories.length,
        (payload['categories'] as List).length,
      );
      expect(
        restored.transactions.length,
        (payload['transactions'] as List).length,
      );
      expect(
        restored.transactionTemplates.length,
        (payload['transaction_templates'] as List).length,
      );
      expect(
        restored.recurringTransactionRules.length,
        (payload['recurring_transaction_rules'] as List).length,
      );
    } finally {
      await restoredDatabase.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
      await restoreDirectory.delete(recursive: true);
    }

    // ignore: avoid_print
    print(
      jsonEncode({
        'path': output.path,
        'bytes': await output.length(),
        'format_version': payload['format_version'],
        'accounts': (payload['accounts'] as List).length,
        'categories': (payload['categories'] as List).length,
        'budgets': (payload['budgets'] as List).length,
        'transactions': (payload['transactions'] as List).length,
        'asset_snapshots': (payload['asset_snapshots'] as List).length,
        'transaction_templates':
            (payload['transaction_templates'] as List).length,
        'recurring_transaction_rules':
            (payload['recurring_transaction_rules'] as List).length,
        'restore_verified': true,
      }),
    );
  });
}

void _validatePayload(Map<String, dynamic> payload) {
  expect(payload['format_version'], 3);
  expect(payload['transaction_date_semantics'], 'occurrence_date');
  for (final key in const <String>[
    'accounts',
    'categories',
    'budgets',
    'transactions',
    'asset_snapshots',
    'transaction_templates',
    'recurring_transaction_rules',
  ]) {
    expect(payload[key], isA<List>(), reason: 'Missing export list: $key');
  }
  expect(payload['meta'], isA<Map<String, dynamic>>());
}
