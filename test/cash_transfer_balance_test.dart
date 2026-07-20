import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/mutations/transaction_mutations.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/settings/app_settings_controller.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/home/home_screen.dart';
import 'package:finance_app/src/features/transactions/transaction_composer_page.dart';
import 'package:finance_app/src/features/transactions/transaction_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('actual cash transfer updates both stored and displayed balances',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await _repositoryWithCashAccounts(database);

    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'cash-transfer',
        type: TransactionType.transfer,
        accountId: 'source',
        toAccountId: 'target',
        amount: 250,
        currency: 'MYR',
        toCurrency: 'MYR',
        transactionDate: DateTime(2026, 7, 20),
        status: TransactionStatus.actual,
      ),
    );

    expect(_balance(repository, 'source'), 750);
    expect(_balance(repository, 'target'), 350);
    expect(
      repository.accountBalanceAt('source', DateTime(2026, 7, 31)),
      750,
    );
    expect(
      repository.accountBalanceAt('target', DateTime(2026, 7, 31)),
      350,
    );

    final reloaded = await FinanceRepository.load(database);
    expect(_balance(reloaded, 'source'), 750);
    expect(_balance(reloaded, 'target'), 350);
  });

  test('cash transfer mutation publishes the receiving balance immediately',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = await _repositoryWithCashAccounts(database);
    final container = ProviderContainer(
      overrides: [
        financeRepositoryProvider.overrideWith(
          () => _TestRepositoryNotifier(repository),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(financeRepositoryProvider.future);
    await container.read(transactionMutationsProvider.notifier).addTransaction(
          FinanceTransaction(
            id: 'provider-cash-transfer',
            type: TransactionType.transfer,
            accountId: 'source',
            toAccountId: 'target',
            amount: 250,
            currency: 'MYR',
            toCurrency: 'MYR',
            transactionDate: DateTime(2026, 7, 20),
            status: TransactionStatus.actual,
          ),
        );

    final refreshed = await container.read(financeRepositoryProvider.future);
    expect(_balance(refreshed, 'source'), 750);
    expect(_balance(refreshed, 'target'), 350);
  });

  testWidgets('new composer saves the selected receiving cash account',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await _repositoryWithCashAccounts(database);
    TransactionFormResult? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.abyss)
            .copyWith(splashFactory: NoSplash.splashFactory),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result =
                    await Navigator.of(context).push<TransactionFormResult>(
                  MaterialPageRoute(
                    builder: (_) => TransactionComposerPage(
                      repository: repository,
                    ),
                  ),
                );
              },
              child: const Text('新增转账'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('新增转账'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('转账').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '250');
    await tester.ensureVisible(find.text('转入账户'));
    await tester.tap(find.text('转入账户'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('现金账户 B'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存交易'));
    await tester.tap(find.text('保存交易'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    final transfer = result!.transactions.single;
    expect(transfer.type, TransactionType.transfer);
    expect(transfer.status, TransactionStatus.actual);
    expect(transfer.accountId, 'source');
    expect(transfer.toAccountId, 'target');
    expect(transfer.amount, 250);

    repository = await repository.addTransaction(transfer);
    expect(_balance(repository, 'source'), 750);
    expect(_balance(repository, 'target'), 350);
  });

  testWidgets('account overview refreshes both sides of a live cash transfer',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = await _repositoryWithCashAccounts(
      database,
      sourceName: 'Grab',
      targetName: 'UOB One',
    );
    final container = ProviderContainer(
      overrides: [
        financeRepositoryProvider.overrideWith(
          () => _TestRepositoryNotifier(repository),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.abyss)
              .copyWith(splashFactory: NoSplash.splashFactory),
          home: HomeScreen(settingsController: AppSettingsController()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('账户').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('现金').last);
    await tester.pumpAndSettle();
    expect(find.text('MYR 1,000.00'), findsOneWidget);
    expect(find.text('MYR 100.00'), findsOneWidget);

    await container.read(transactionMutationsProvider.notifier).addTransaction(
          FinanceTransaction(
            id: 'grab-to-uob-one',
            type: TransactionType.transfer,
            accountId: 'source',
            toAccountId: 'target',
            amount: 250,
            currency: 'MYR',
            toCurrency: 'MYR',
            transactionDate: DateTime(2026, 7, 20),
            status: TransactionStatus.actual,
          ),
        );
    await tester.pumpAndSettle();

    expect(find.text('MYR 750.00'), findsOneWidget);
    expect(find.text('MYR 350.00'), findsOneWidget);
  });
}

Future<FinanceRepository> _repositoryWithCashAccounts(
  AppDatabase database, {
  String sourceName = '现金账户 A',
  String targetName = '现金账户 B',
}) async {
  var repository = await FinanceRepository.load(database);
  for (final account in [
    Account(
      id: 'source',
      name: sourceName,
      accountType: AccountType.cash,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      currentBalance: 1000,
    ),
    Account(
      id: 'target',
      name: targetName,
      accountType: AccountType.cash,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      currentBalance: 100,
    ),
  ]) {
    repository = await repository.addAccount(account);
  }
  return repository;
}

double _balance(FinanceRepository repository, String accountId) =>
    repository.accounts
        .firstWhere((account) => account.id == accountId)
        .currentBalance;

class _TestRepositoryNotifier extends FinanceRepositoryNotifier {
  _TestRepositoryNotifier(this.repository);

  final FinanceRepository repository;

  @override
  Future<FinanceRepository> build() async => repository;
}
