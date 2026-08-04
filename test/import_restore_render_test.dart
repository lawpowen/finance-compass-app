import 'dart:io';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/category.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/settings/app_settings_controller.dart';
import 'package:finance_app/src/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _LoadedRepositoryNotifier extends FinanceRepositoryNotifier {
  _LoadedRepositoryNotifier(this.repository);

  final FinanceRepository repository;

  @override
  Future<FinanceRepository> build() async => repository;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('restored JSON renders every main page without a black screen',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late Directory directory;
    late AppDatabase sourceDatabase;
    late AppDatabase restoredDatabase;
    late FinanceRepository restored;
    const pathProviderChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    await tester.runAsync(() async {
      directory =
          await Directory.systemTemp.createTemp('finance_restore_render');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return directory.path;
        }
        return null;
      });

      sourceDatabase = AppDatabase.forTesting(NativeDatabase.memory());
      var source = await FinanceRepository.load(sourceDatabase);
      source = await source.addAccount(
        const Account(
          id: 'grab',
          name: 'Grab',
          accountType: AccountType.cash,
          reportGroup: ReportGroup.cash,
          currency: 'MYR',
          currentBalance: 750,
          initialBalance: 1000,
        ),
      );
      source = await source.addAccount(
        const Account(
          id: 'uob_one',
          name: 'UOB One',
          accountType: AccountType.bankSaving,
          reportGroup: ReportGroup.cash,
          currency: 'MYR',
          currentBalance: 350,
          initialBalance: 100,
        ),
      );
      source = await source.addCategory(
        const Category(
          id: 'transfer',
          name: 'Transfer',
          type: CategoryType.transfer,
        ),
      );
      source = await source.addTransaction(
        FinanceTransaction(
          id: 'grab_to_uob',
          type: TransactionType.transfer,
          accountId: 'grab',
          toAccountId: 'uob_one',
          categoryId: 'transfer',
          amount: 250,
          currency: 'MYR',
          recordDate: DateTime(2026, 7, 20),
          transactionDate: DateTime(2026, 7, 20),
        ),
      );
      final snapshotFile = File('${directory.path}/valid-backup.json');
      await snapshotFile.writeAsBytes(await source.exportJsonSnapshotBytes());
      await sourceDatabase.close();

      restoredDatabase = AppDatabase.forTesting(NativeDatabase.memory());
      restored = await FinanceRepository.load(restoredDatabase);
      restored = await restored.importJsonSnapshot(snapshotFile.path);
      expect(restored.accounts, hasLength(2));
      expect(restored.transactions.single.id, 'grab_to_uob');
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeRepositoryProvider.overrideWith(
            () => _LoadedRepositoryNotifier(restored),
          ),
        ],
        child: MaterialApp(
          home: HomeScreen(settingsController: AppSettingsController()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationBar), findsOneWidget);

    // HomeScreen uses an IndexedStack, so all six destinations are built from
    // the restored repository even though only the overview is visible.
    expect(find.byType(IndexedStack), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(() async {
      await restoredDatabase.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
      await directory.delete(recursive: true);
    });
  });
}
