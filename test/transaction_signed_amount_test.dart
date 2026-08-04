import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('zero and negative actual amounts apply and reverse algebraically',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    repository = await repository.addAccount(
      const Account(
        id: 'cash',
        name: '现金账户',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 100,
      ),
    );

    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'zero-expense',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 0,
        currency: 'MYR',
        transactionDate: DateTime(2026, 7, 18),
      ),
    );
    expect(repository.accounts.single.currentBalance, 100);

    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'negative-expense',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: -25,
        currency: 'MYR',
        transactionDate: DateTime(2026, 7, 18),
      ),
    );
    expect(repository.accounts.single.currentBalance, 125);

    repository = await repository.deleteExistingTransaction('negative-expense');
    expect(repository.accounts.single.currentBalance, 100);
    expect(repository.transactions.map((item) => item.id),
        isNot(contains('negative-expense')));
  });

  test('negative transfer applies both legs and deletion restores them',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    for (final account in const [
      Account(
        id: 'source',
        name: '来源账户',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 100,
      ),
      Account(
        id: 'target',
        name: '目标账户',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 50,
      ),
    ]) {
      repository = await repository.addAccount(account);
    }

    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'negative-transfer',
        type: TransactionType.transfer,
        accountId: 'source',
        toAccountId: 'target',
        amount: -20,
        toAmount: -20,
        currency: 'MYR',
        toCurrency: 'MYR',
        transactionDate: DateTime(2026, 7, 18),
      ),
    );
    expect(
        repository.accounts
            .firstWhere((item) => item.id == 'source')
            .currentBalance,
        120);
    expect(
        repository.accounts
            .firstWhere((item) => item.id == 'target')
            .currentBalance,
        30);

    repository =
        await repository.deleteExistingTransaction('negative-transfer');
    expect(
        repository.accounts
            .firstWhere((item) => item.id == 'source')
            .currentBalance,
        100);
    expect(
        repository.accounts
            .firstWhere((item) => item.id == 'target')
            .currentBalance,
        50);
  });
}
