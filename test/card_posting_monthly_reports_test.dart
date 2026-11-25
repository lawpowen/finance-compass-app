import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/budget.dart';
import 'package:finance_app/src/core/models/category.dart';
import 'package:finance_app/src/core/models/credit_card_billing.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'December posting leaves November budget, reports and both balances on the economic date',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await FinanceRepository.load(db);
    const card = Account(
        id: 'source',
        name: 'Credit card',
        accountType: AccountType.creditCard,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        currentBalance: 0,
        creditLimit: 1000,
        statementDay: 30,
        paymentDueDay: 14);
    repo = await repo.addAccount(card);
    repo = await repo.addAccount(const Account(
        id: 'bank',
        name: 'Bank',
        accountType: AccountType.bankSaving,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        initialBalance: 100,
        currentBalance: 100));
    repo = await repo.addCategory(
        const Category(id: 'food', name: 'Food', type: CategoryType.expense));
    repo = await repo.addBudget(const Budget(
        id: 'limit', categoryId: 'food', monthKey: '2026-11', amount: 200));
    final day = DateTime(2026, 11, 30);
    final posting = DateTime(2026, 12, 2);
    repo = await repo.addTransactions([
      FinanceTransaction(
          id: 'purchase',
          accountId: card.id,
          type: TransactionType.expense,
          categoryId: 'food',
          amount: 60,
          currency: 'MYR',
          transactionDate: day.add(const Duration(hours: 12)),
          cardPostingDate: posting),
      FinanceTransaction(
          id: 'to-bank',
          accountId: card.id,
          toAccountId: 'bank',
          type: TransactionType.transfer,
          amount: 15,
          currency: 'MYR',
          transactionDate: day.add(const Duration(hours: 17)),
          cardPostingDate: posting),
    ]);

    expect(repo.budgetUsageFor('food', '2026-11').actual, 60);
    expect(repo.budgetUsageFor('food', '2026-12').actual, 0);
    expect(repo.totalExpenseForMonth('2026-11'), 60);
    expect(repo.totalExpenseForMonth('2026-12'), 0);
    expect(
        repo.categoryTotalsForMonths(
            type: CategoryType.expense, monthKeys: ['2026-11'])['food'],
        60);
    expect(
        repo.categoryTotalsForMonths(
            type: CategoryType.expense, monthKeys: ['2026-12']),
        isNot(contains('food')));
    expect(repo.transactionsForCategory('food', monthKey: '2026-11').single.id,
        'purchase');
    expect(repo.actualCashFlowSummaryForMonth('2026-11').inflow, 15);
    expect(repo.actualCashFlowSummaryForMonth('2026-12').inflow, 0);
    expect(repo.accountBalanceAt(card.id, DateTime(2026, 11, 30, 16)), -60);
    expect(repo.accountBalanceAt('bank', DateTime(2026, 11, 30, 16)), 100);
    expect(repo.accountBalanceAt('bank', DateTime(2026, 11, 30, 18)), 115);
    expect(repo.creditCardCommittedOutstandingBalance(card.id), 75);
    for (final (month, total) in [(11, 0), (12, 75)]) {
      final period = calculateCreditCardBillingPeriodForStatement(
          statementDay: 30,
          paymentDueDay: 14,
          statementDate: DateTime(2026, month, 30));
      expect(
          calculateCreditCardStatementAmount(
              accountId: card.id,
              transactions: repo.transactions,
              period: period),
          total);
    }
  });
}
