import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/category.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/services/account_service.dart';
import 'package:finance_app/src/core/services/budget_service.dart';
import 'package:finance_app/src/core/services/currency_service.dart';
import 'package:finance_app/src/core/services/report_service.dart';
import 'package:finance_app/src/core/services/transaction_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final asOf = DateTime(2026, 7, 15);
  late FinanceRepository ledger;

  setUp(() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    ledger = await (await FinanceRepository.load(db)).addAccount(const Account(
      id: 'cash',
      name: 'Savings',
      accountType: AccountType.bankSaving,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      initialBalance: 1000,
      currentBalance: 1000,
    ));
  });

  FinanceTransaction flow(
    String id,
    DateTime date,
    double amount, {
    TransactionType type = TransactionType.income,
    TransactionStatus status = TransactionStatus.actual,
  }) =>
      FinanceTransaction(
          id: id,
          accountId: 'cash',
          type: type,
          amount: amount,
          currency: 'MYR',
          transactionDate: date,
          status: status);

  test('an account with no sample months retains its deposit in both forecasts',
      () {
    final forecast = ledger.forecastSummary(asOf: asOf);
    expect(forecast.averageMonthlySavings, 0);
    expect(forecast.projectedSavingsInThreeMonths, 1000);
    expect(forecast.projectedSavingsInSixMonths, 1000);
    expect(
        ReportService.fromRepository(ledger)
            .forecastSummary(asOf: asOf)
            .projectedSavingsInThreeMonths,
        1000);
  });

  test(
      'forecasts use the latest active completed months and the closing balance as of today',
      () async {
    ledger = await ledger.addTransactions([
      flow('old', DateTime(2025, 12), 100),
      for (var month = 4; month <= 6; month++) ...[
        flow('income-$month', DateTime(2026, month), 1000.0 * (month - 3)),
        flow('expense-$month', DateTime(2026, month), 100.0 * (month - 3),
            type: TransactionType.expense),
      ],
      flow('partial-month', DateTime(2026, 7, 15, 15), 5000),
      flow('future', DateTime(2026, 7, 31), 20000),
    ]);
    for (final summary in [
      ledger.forecastSummary(asOf: asOf),
      ReportService.fromRepository(ledger).forecastSummary(asOf: asOf),
    ]) {
      expect(summary.averageMonthlyIncome, 2000);
      expect(summary.averageMonthlyExpense, 200);
      expect(summary.averageMonthlySavings, 1800);
      expect(summary.projectedSavingsInThreeMonths, 16900);
      expect(summary.projectedSavingsInSixMonths, 22300);
    }
    expect(ledger.forecastSummary(months: 1, asOf: asOf).averageMonthlySavings,
        2700);
  });

  test(
      'forward projection excludes expired plans and adds each cash transfer only once',
      () async {
    ledger = await ledger.addAccount(const Account(
        id: 'investment',
        name: 'Broker',
        accountType: AccountType.stock,
        reportGroup: ReportGroup.investment,
        currency: 'MYR',
        currentBalance: 0));
    ledger = await ledger.addTransactions([
      flow('today', DateTime(2026, 7, 15, 18), 25),
      flow('expired', DateTime(2026, 7, 15, 10), 900,
          status: TransactionStatus.planned),
      flow('tomorrow', DateTime(2026, 7, 16), 50),
      flow('next-month', DateTime(2026, 8), 10, type: TransactionType.expense),
      FinanceTransaction(
          id: 'move',
          accountId: 'cash',
          toAccountId: 'investment',
          type: TransactionType.transfer,
          amount: 20,
          currency: 'MYR',
          transactionDate: DateTime(2026, 7, 18),
          status: TransactionStatus.planned),
    ]);
    for (final points in [
      ledger.futureCashFlowProjection(asOf: asOf, months: 2),
      ReportService(
        accounts: ledger.accounts,
        transactions: ledger.transactions,
        categories: ledger.categories,
        accountService: AccountService.fromRepository(ledger),
        budgetService: BudgetService.fromRepository(ledger),
        currencyService: CurrencyService.fromRepository(ledger),
      ).futureCashFlowProjection(asOf: asOf, months: 2),
    ]) {
      expect([
        points.first.income,
        points.first.expense,
        points.first.transfers,
        points.first.net,
        points.first.endingCash
      ], [
        50,
        0,
        -20,
        30,
        1055
      ]);
      expect(points.last.endingCash, 1045);
    }
  });

  test('upcoming expense rows and reserve share the day after the cutoff',
      () async {
    final cutoff = DateTime(2026, 7, 30, 9);
    ledger = await ledger.addTransactions([
      flow('yesterday', DateTime(2026, 7, 29, 12), 100,
          type: TransactionType.expense),
      flow('tonight', DateTime(2026, 7, 30, 23, 59), 80,
          type: TransactionType.expense),
      flow('midnight', DateTime(2026, 7, 31), 10,
          type: TransactionType.expense, status: TransactionStatus.planned),
      flow('refund', DateTime(2026, 7, 31, 15), -3,
          type: TransactionType.expense),
      flow('following-month', DateTime(2026, 8), 25,
          type: TransactionType.expense),
    ]);
    final service = TransactionService.fromRepository(ledger);
    expect(service.upcomingExpenseTransactions(asOf: cutoff).map((e) => e.id),
        ['midnight', 'refund', 'following-month']);
    expect(service.totalFutureExpense(monthsAhead: 1, asOf: cutoff), 7);
  });

  test('account adapter reads the stored reconciliation and names in a trace',
      () async {
    ledger = await ledger.addCategory(const Category(
        id: 'food', name: 'Pet Food', type: CategoryType.expense));
    ledger = await ledger.addTransaction(FinanceTransaction(
        id: 'food-receipt',
        accountId: 'cash',
        categoryId: 'food',
        type: TransactionType.expense,
        amount: 50,
        currency: 'MYR',
        transactionDate: DateTime(2026, 7, 16)));
    ledger = await ledger.setAccountReconciledMonth('cash', '2026-06');
    final view = AccountService.fromRepository(ledger);
    expect(view.reconciledMonthForAccount('cash'), '2026-06');
    expect(view.isAccountReconciledForMonth('cash', '2026-05'), isTrue);
    expect(view.isAccountReconciledForMonth('cash', '2026-07'), isFalse);
    final trace = view.accountBalanceTrace('cash', asOf);
    expect(trace.entries.single.title, 'Pet Food');
    expect(trace.entries.single.subtitle, contains('Savings'));
    expect(trace.endingBalance, 1000);
  });
}
