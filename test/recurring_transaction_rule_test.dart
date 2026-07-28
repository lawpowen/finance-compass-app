import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart' hide Account;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recurring rule creates planned transaction drafts with rule id', () {
    final base = FinanceTransaction(
      id: 'txn_salary',
      type: TransactionType.income,
      accountId: 'acc_bank',
      amount: 3000,
      currency: 'MYR',
      transactionDate: DateTime(2026, 4, 28),
      status: TransactionStatus.actual,
      description: 'Salary',
    );
    final rule = RecurringTransactionRule.fromTransaction(
      id: 'rule_salary',
      name: '工资',
      transaction: base,
    );
    final generated = rule.toTransaction(
      id: 'txn_salary_2026_05',
      date: DateTime(2026, 5, 28),
      status: TransactionStatus.planned,
    );

    expect(generated.recurringRuleId, 'rule_salary');
    expect(generated.status, TransactionStatus.planned);
    expect(generated.amount, 3000);
    expect(generated.description, 'Salary');
  });

  test('recurring rule preserves cross-currency transfer amounts', () {
    final base = FinanceTransaction(
      id: 'txn_transfer',
      type: TransactionType.transfer,
      accountId: 'acc_myr',
      toAccountId: 'acc_twd',
      amount: 150,
      currency: 'MYR',
      toAmount: 1000,
      toCurrency: 'TWD',
      transactionDate: DateTime(2026, 4, 28),
      status: TransactionStatus.actual,
    );
    final rule = RecurringTransactionRule.fromTransaction(
      id: 'rule_transfer',
      name: 'FX transfer',
      transaction: base,
    );

    final generated = rule.toTransaction(
      id: 'txn_transfer_2026_05',
      date: DateTime(2026, 5, 28),
      status: TransactionStatus.planned,
    );

    expect(generated.amount, 150);
    expect(generated.currency, 'MYR');
    expect(generated.toAmount, 1000);
    expect(generated.toCurrency, 'TWD');
    expect(generated.transferInAmount, 1000);
    expect(generated.transferInCurrency, 'TWD');
  });

  test('recurring rule created from a planned transaction stays planned', () {
    final base = FinanceTransaction(
      id: 'txn_plan',
      type: TransactionType.expense,
      accountId: 'acc_bank',
      amount: 88,
      currency: 'MYR',
      transactionDate: DateTime(2026, 7, 18),
      status: TransactionStatus.planned,
    );

    final rule = RecurringTransactionRule.fromTransaction(
      id: 'rule_plan',
      name: 'Planned rule',
      transaction: base,
    );

    expect(rule.status, TransactionStatus.planned);
  });

  test('saving a rule automatically creates three full months of plans',
      () async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month + 1, 15);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    var repository = await FinanceRepository.load(database);
    repository = await repository.addAccount(
      const Account(
        id: 'recurring_cash',
        name: 'Recurring cash',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        initialBalance: 1000,
        currentBalance: 1000,
      ),
    );
    repository = await repository.addRecurringTransactionRule(
      name: 'Actual installments',
      transaction: FinanceTransaction(
        id: 'actual_seed',
        type: TransactionType.expense,
        accountId: 'recurring_cash',
        amount: 100,
        currency: 'MYR',
        transactionDate: start,
        status: TransactionStatus.actual,
      ),
    );
    repository = await repository.addRecurringTransactionRule(
      name: 'Planned installments',
      transaction: FinanceTransaction(
        id: 'planned_seed',
        type: TransactionType.expense,
        accountId: 'recurring_cash',
        amount: 80,
        currency: 'MYR',
        transactionDate: start,
        status: TransactionStatus.planned,
      ),
    );

    final actualRule = repository.recurringTransactionRules
        .singleWhere((item) => item.name == 'Actual installments');
    final plannedRule = repository.recurringTransactionRules
        .singleWhere((item) => item.name == 'Planned installments');
    final actualRows = repository.transactions
        .where((item) => item.recurringRuleId == actualRule.id);
    final plannedRows = repository.transactions
        .where((item) => item.recurringRuleId == plannedRule.id);
    expect(actualRows, isNotEmpty);
    expect(actualRows, hasLength(3));
    expect(actualRows.map((item) => item.status),
        everyElement(TransactionStatus.planned));
    expect(plannedRows, hasLength(3));
    expect(plannedRows, isNotEmpty);
    expect(plannedRows.map((item) => item.status),
        everyElement(TransactionStatus.planned));

    await database.close();
  });
}
