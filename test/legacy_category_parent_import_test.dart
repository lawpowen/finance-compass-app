import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _child = 'cat_1779414362993634';
const _parent = 'cat-communications';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('0.10.1 import resolves a parent name without changing other links',
      () async {
    final repository = await _repository();
    final bytes = _bytes(_legacy());
    final preview = await repository.previewImportBytes(bytes);
    expect(preview.hasUnresolvedCategoryParents, isFalse);
    expect(preview.categoryParentRepairs.single.parentName, '通訊費用');
    final restored = await repository.importJsonSnapshotBytes(bytes);

    expect(
        restored.categories.singleWhere((item) => item.id == _child).parentId,
        _parent);
    expect(restored.transactions.single.categoryId, _child);
    expect(restored.transactions.single.amount, 29.90);
    expect(restored.budgets.single.categoryId, _child);
    expect(restored.budgets.single.amount, 100);
  });

  for (final scenario in ['missing', 'ambiguous', 'cycle']) {
    test('$scenario parent requires explicit approval to detach', () async {
      final repository = await _repository();
      final snapshot = _legacy();
      final categories = snapshot['categories'] as List<Map<String, String>>;
      switch (scenario) {
        case 'missing':
          categories.removeAt(0);
        case 'ambiguous':
          categories
              .add({'id': 'cat-duplicate', 'name': '通訊費用', 'type': 'expense'});
        case 'cycle':
          categories.first['parent_id'] = _child;
      }
      final bytes = _bytes(snapshot);
      final preview = await repository.previewImportBytes(bytes);
      expect(preview.hasUnresolvedCategoryParents, isTrue);
      expect(preview.categoryParentRepairs.single.categoryName, '電話費');
      final original =
          repository.accounts.map((account) => account.id).toList();
      await expectLater(
        repository.importJsonSnapshotBytes(bytes),
        throwsA(isA<FormatException>()),
      );
      final reloaded = await repository.refresh();
      expect(reloaded.accounts.map((account) => account.id), original);

      final restored = await repository.importJsonSnapshotBytes(
        bytes,
        detachUnresolvedCategoryParents: true,
      );
      expect(restored.categories.length, categories.length);
      expect(
          restored.categories.singleWhere((item) => item.id == _child).parentId,
          isNull);
      expect(restored.transactions.single.categoryId, _child);
      expect(restored.budgets.single.categoryId, _child);
    });
  }

  for (final invalidGraph in ['cross-type', 'self-parent', 'cycle']) {
    test(
        'preview, import and sync reject a complete invalid graph: $invalidGraph',
        () async {
      final repo = await _repository();
      final snapshot = _legacy();
      snapshot['meta'] = <String, String>{};
      snapshot['asset_snapshots'] = [];
      snapshot['transaction_templates'] = [];
      snapshot['recurring_transaction_rules'] = [];
      final categories = snapshot['categories'] as List<Map<String, String>>;
      categories.last['parent_id'] = _parent;
      switch (invalidGraph) {
        case 'cross-type':
          categories.first['type'] = 'income';
        case 'self-parent':
          categories.last['parent_id'] = _child;
        case 'cycle':
          categories.first['parent_id'] = _child;
      }
      final bytes = _bytes(snapshot);
      await expectLater(repo.previewImportBytes(bytes), throwsFormatException);
      await expectLater(
          repo.importJsonSnapshotBytes(bytes,
              detachUnresolvedCategoryParents: true),
          throwsFormatException);
      await expectLater(
          repo.restoreSyncedSnapshot(snapshot), throwsFormatException);
      expect((await repo.refresh()).categories, isEmpty);
    });
  }

  test('the sync protocol still expects category IDs', () async {
    final repository = await _repository();
    await expectLater(
      repository.restoreSyncedSnapshot(_legacy()),
      throwsA(isA<FormatException>()),
    );
  });
}

Future<FinanceRepository> _repository() async {
  final directory = await Directory.systemTemp.createTemp('finance_parent');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  messenger.setMockMethodCallHandler(
    channel,
    (call) async => call.method == 'getApplicationDocumentsDirectory'
        ? directory.path
        : null,
  );
  addTearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  return FinanceRepository.load(database);
}

Uint8List _bytes(Map<String, dynamic> snapshot) =>
    Uint8List.fromList(utf8.encode(jsonEncode(snapshot)));

Map<String, dynamic> _legacy() => {
      'format_version': 3,
      'schema_version': 9,
      'accounts': [
        {
          'id': 'cash',
          'name': '現金',
          'account_type': 'cash',
          'report_group': 'cash',
          'currency': 'MYR',
          'initial_balance': 100,
          'current_balance': 70.10,
        },
      ],
      'categories': [
        {'id': _parent, 'name': '通訊費用', 'type': 'expense'},
        {
          'id': _child,
          'name': '電話費',
          'type': 'expense',
          'parent_id': '通訊費用',
        },
      ],
      'budgets': [
        {
          'id': 'phone-budget',
          'category_id': _child,
          'month_key': '2026-11',
          'amount': 100,
          'currency': 'MYR',
        },
      ],
      'transactions': [
        {
          'id': 'phone-expense',
          'account_id': 'cash',
          'category_id': _child,
          'type': 'expense',
          'amount': 29.90,
          'currency': 'MYR',
          'record_date': '2026-11-23T10:00:00',
          'transaction_date': '2026-11-23T10:00:00',
          'status': 'actual',
        },
      ],
    };
