import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exact forecast range includes only dated cash and credit movements',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    repository = await repository.addAccount(
      const Account(
        id: 'cash',
        name: '现金',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 0,
      ),
    );
    repository = await repository.addAccount(
      const Account(
        id: 'invest',
        name: '投资',
        accountType: AccountType.trading,
        reportGroup: ReportGroup.investment,
        currency: 'MYR',
        currentBalance: 0,
      ),
    );
    repository = await repository.addTransactions([
      _transaction('income', TransactionType.income, 100, DateTime(2026, 8, 2)),
      _transaction(
          'expense', TransactionType.expense, 40, DateTime(2026, 8, 5)),
      _transaction(
        'outside',
        TransactionType.expense,
        50,
        DateTime(2026, 9, 1),
      ),
      FinanceTransaction(
        id: 'transfer',
        type: TransactionType.transfer,
        accountId: 'cash',
        toAccountId: 'invest',
        amount: 20,
        currency: 'MYR',
        transactionDate: DateTime(2026, 8, 8),
        status: TransactionStatus.planned,
      ),
      FinanceTransaction(
        id: 'investment-expense',
        type: TransactionType.expense,
        accountId: 'invest',
        amount: 999,
        currency: 'MYR',
        transactionDate: DateTime(2026, 8, 9),
        status: TransactionStatus.planned,
      ),
    ]);

    expect(
      repository.cashFlowNetBetween(
        startInclusive: DateTime(2026, 8, 1),
        endInclusive: DateTime(2026, 8, 31),
      ),
      40,
    );
  });
}

FinanceTransaction _transaction(
  String id,
  TransactionType type,
  double amount,
  DateTime date,
) =>
    FinanceTransaction(
      id: id,
      type: type,
      accountId: 'cash',
      amount: amount,
      currency: 'MYR',
      transactionDate: date,
      status: TransactionStatus.planned,
    );
