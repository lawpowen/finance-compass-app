import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    hide Account, Budget, Category;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/budget.dart';
import 'package:finance_app/src/core/models/category.dart';
import 'package:finance_app/src/core/providers/database_provider.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/settings/app_settings_controller.dart';
import 'package:finance_app/src/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'v3 import rejects missing transactions, bad meta, invalid/duplicate budgets without altering DB',
      () async {
    final directory = await Directory.systemTemp.createTemp('finance_phase1');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
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
    var repository = await FinanceRepository.load(database);
    repository = await repository.addAccount(
      const Account(
        id: 'orig_cash',
        name: 'Original Cash',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        initialBalance: 500,
        currentBalance: 500,
      ),
    );
    repository = await repository.addCategory(
      const Category(id: 'food', name: 'Food', type: CategoryType.expense),
    );

    // 1. Missing transactions section in v3 snapshot.
    await expectLater(
      repository.importJsonSnapshotBytes(
        Uint8List.fromList(utf8.encode(jsonEncode({
          'format_version': 3,
          'accounts': [
            {
              'id': 'wiped',
              'name': 'Wiped',
              'account_type': 'cash',
              'report_group': 'cash',
              'currency': 'MYR',
              'current_balance': 10,
            }
          ],
        }))),
      ),
      throwsFormatException,
    );

    // 2. Malformed meta.asset_goals_json fails before replacing live data.
    await expectLater(
      repository.importJsonSnapshotBytes(
        Uint8List.fromList(utf8.encode(jsonEncode({
          'format_version': 3,
          'meta': {'asset_goals_json': '{not-valid-json'},
          'accounts': [
            {
              'id': 'replaced',
              'name': 'Replaced',
              'account_type': 'cash',
              'report_group': 'cash',
              'currency': 'MYR',
              'current_balance': 99,
            }
          ],
          'transactions': const [],
        }))),
      ),
      throwsFormatException,
    );

    // 3. Invalid budget month_key & duplicate (category_id, month_key).
    for (final budgets in [
      [
        {
          'id': 'b1',
          'category_id': 'food',
          'month_key': '2026-13',
          'amount': 100,
        }
      ],
      [
        {
          'id': 'b1',
          'category_id': 'food',
          'month_key': '2026-11',
          'amount': 100,
        },
        {
          'id': 'b2',
          'category_id': 'food',
          'month_key': '2026-11',
          'amount': 200,
        }
      ],
    ]) {
      await expectLater(
        repository.importJsonSnapshotBytes(
          Uint8List.fromList(utf8.encode(jsonEncode({
            'format_version': 3,
            'accounts': [
              {
                'id': 'cash2',
                'name': 'Cash 2',
                'account_type': 'cash',
                'report_group': 'cash',
                'currency': 'MYR',
                'current_balance': 50,
              }
            ],
            'categories': [
              {'id': 'food', 'name': 'Food', 'type': 'expense'}
            ],
            'budgets': budgets,
            'transactions': const [],
          }))),
        ),
        throwsFormatException,
      );
    }

    // 4. Non-object item in transaction_templates is rejected.
    await expectLater(
      repository.importJsonSnapshotBytes(
        Uint8List.fromList(utf8.encode(jsonEncode({
          'format_version': 3,
          'accounts': [
            {
              'id': 'cash2',
              'name': 'Cash 2',
              'account_type': 'cash',
              'report_group': 'cash',
              'currency': 'MYR',
              'current_balance': 50,
            }
          ],
          'transactions': const [],
          'transaction_templates': ['not-an-object'],
        }))),
      ),
      throwsFormatException,
    );

    // Original database must remain completely untouched after every failure.
    final reloaded = await FinanceRepository.load(database);
    expect(reloaded.accounts.single.id, 'orig_cash');
    expect(reloaded.accounts.single.currentBalance, 500);
  });

  test('upsertBudget deduplicates pre-existing duplicate category/month rows',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    repository = await repository.addCategory(
      const Category(id: 'food', name: 'Food', type: CategoryType.expense),
    );

    // Seed two duplicate rows for same (category_id, month_key) directly.
    await database.into(database.budgets).insert(
          BudgetsCompanion.insert(
            id: 'dup1',
            categoryId: 'food',
            monthKey: '2026-11',
            amount: 100,
          ),
        );
    await database.into(database.budgets).insert(
          BudgetsCompanion.insert(
            id: 'dup2',
            categoryId: 'food',
            monthKey: '2026-11',
            amount: 150,
          ),
        );

    repository = await repository.addBudget(
      const Budget(
        id: 'new_id',
        categoryId: 'food',
        monthKey: '2026-11',
        amount: 300,
        currency: 'MYR',
      ),
    );
    expect(repository.budgets, hasLength(1));
    expect(repository.budgets.single.amount, 300);
  });

  test('FinanceRepositoryNotifier serializes concurrent local mutations',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);

    await container.read(financeRepositoryProvider.future);
    final notifier = container.read(financeRepositoryProvider.notifier);

    await Future.wait([
      notifier.mutate(
        (repo) => repo.addAssetGoal(name: 'Goal B', amount: 1000),
      ),
      notifier.mutate(
        (repo) => repo.addAssetGoal(name: 'Goal C', amount: 2000),
      ),
    ]);

    final published = container.read(financeRepositoryProvider).requireValue;
    expect(
        published.assetGoals.map((g) => g.name).toSet(), {'Goal B', 'Goal C'});
  });

  testWidgets(
      'SettingsScreen drags currency order on fresh ledger without error',
      (tester) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = await FinanceRepository.load(database);
    final controller = AppSettingsController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          home: Scaffold(
            body: SettingsScreen(
              repository: repository,
              settingsController: controller,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    list.onReorder!(0, 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
