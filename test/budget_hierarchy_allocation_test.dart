import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/budget.dart';
import 'package:finance_app/src/core/models/category.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/services/ai_analysis_service.dart';
import 'package:finance_app/src/core/utils/month_key.dart';
import 'package:flutter_test/flutter_test.dart';

Budget _rule(String id, String category, String month, double amount,
        {String currency = 'MYR', bool rollover = false}) =>
    Budget(
        id: id,
        categoryId: category,
        monthKey: month,
        amount: amount,
        currency: currency,
        rolloverEnabled: rollover);

FinanceTransaction _expense(
        String id, String? category, int month, double amount,
        {String currency = 'MYR',
        TransactionStatus status = TransactionStatus.actual}) =>
    FinanceTransaction(
        id: id,
        type: TransactionType.expense,
        accountId: currency,
        categoryId: category,
        amount: amount,
        currency: currency,
        transactionDate: DateTime(2026, month, 15),
        status: status);

void main() {
  test('missing FX follows only the affected budget, spend and carry chain',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await FinanceRepository.load(db);
    final now = DateTime.now();
    final month = monthKeyFromDate(now);
    final previous = monthKeyFromDate(DateTime(now.year, now.month - 1));
    final next = monthKeyFromDate(DateTime(now.year, now.month + 1));
    for (final currency in ['MYR', 'CAD']) {
      repo = await repo.addAccount(Account(
          id: currency,
          name: currency,
          currency: currency,
          accountType: AccountType.cash,
          reportGroup: ReportGroup.cash,
          currentBalance: 0));
    }
    for (final category in ['limit', 'spending', 'other']) {
      repo = await repo.addCategory(
          Category(id: category, name: category, type: CategoryType.expense));
    }
    repo = await repo.addBudget(
        _rule('old', 'limit', previous, 1000, currency: 'CAD', rollover: true));
    final currentRule = _rule('new', 'limit', month, 10);
    repo = await repo.addBudget(currentRule);
    final spendingRule = _rule('spend', 'spending', month, 50, rollover: true);
    repo = await repo.addBudget(spendingRule);
    repo = await repo
        .addBudget(_rule('next', 'spending', next, 90, currency: 'CAD'));
    repo = await repo.addBudget(_rule('other-limit', 'other', month, 50));
    for (final (category, currency, amount) in [
      ('limit', 'MYR', 20.0),
      ('spending', 'MYR', 70.0),
      ('spending', 'CAD', 40.0),
      ('other', 'MYR', 65.0),
    ]) {
      repo = await repo.addTransaction(FinanceTransaction(
          id: '$category-$currency',
          type: TransactionType.expense,
          accountId: currency,
          categoryId: category,
          amount: amount,
          currency: currency,
          transactionDate: DateTime(now.year, now.month, 1)));
    }
    final limit = repo.previewBudget(currentRule);
    expect(limit.baseValued, isTrue);
    expect(limit.carriedValued, isFalse);
    expect(limit.effectiveValued, isFalse);
    // Disabling outgoing rollover cuts the missing-rate dependency next month.
    expect(limit.nextEffectiveValued, isTrue);
    final spending = repo.previewBudget(spendingRule);
    expect(spending.actual, 70);
    expect(spending.actualValued, isFalse);
    expect(spending.plannedValued, isTrue);
    expect(spending.nextBaseValued, isFalse);
    expect(spending.nextCarriedValued, isFalse);
    expect(repo.budgetMonthIsValued(month), isFalse);
    expect(repo.budgetLimitIsValued('other', month), isTrue);

    final request = AiAnalysisService.buildRequestData(repo,
        includePlanned: true, monthCount: 1, futureMonthCount: 1);
    final rows = (request['budgets'] as List).cast<Map<String, dynamic>>();
    expect(
        rows.singleWhere((r) => r['category_id'] == 'limit')['budget'], isNull);
    expect(
        rows.singleWhere((r) => r['category_id'] == 'spending')['actual_spent'],
        isNull);
    expect(
        rows.singleWhere(
            (r) => r['category_id'] == 'other')['remaining_after_committed'],
        -15);
    final risks =
        (request['budget_risks'] as List).cast<Map<String, dynamic>>();
    expect(risks.where((r) => r['month'] == month).map((r) => r['category_id']),
        ['other']);
  });
  test(
      'active budgets partition a subtree using the closest rule in each month',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await FinanceRepository.load(db);
    for (final unit in ['MYR', 'USD']) {
      repo = await repo.addAccount(Account(
          id: unit,
          name: unit,
          currency: unit,
          accountType: AccountType.cash,
          reportGroup: ReportGroup.cash,
          currentBalance: 0));
    }
    repo = await repo.updateExchangeRates({'MYR': 1, 'USD': 4}, ['MYR', 'USD']);
    for (final (id, parent) in <(String, String?)>[
      ('food', null),
      ('out', 'food'),
      ('lunch', 'out'),
      ('drinks', 'out'),
      ('coffee', 'drinks'),
      ('snack', 'food'),
    ]) {
      repo = await repo.addCategory(Category(
          id: id, name: id, type: CategoryType.expense, parentId: parent));
    }
    final jan = _rule('jan', 'food', '2026-01', 1000, rollover: true);
    repo = await repo.addBudget(jan);
    repo = await repo.addBudget(_rule('feb-child', 'out', '2026-02', 100));
    repo = await repo.addBudget(_rule('mar-root', 'food', '2026-03', 900));
    repo = await repo.addTransactions([
      _expense('jan-root', 'food', 1, 20),
      _expense('jan-lunch', 'lunch', 1, 10,
          currency: 'USD', status: TransactionStatus.settled),
      _expense('jan-refund', 'snack', 1, -5),
      _expense('jan-plan', 'lunch', 1, 11, status: TransactionStatus.planned),
      _expense('feb-root', 'food', 2, 10),
      _expense('feb-snack', 'snack', 2, 20),
      _expense('feb-lunch', 'lunch', 2, 8, currency: 'USD'),
      _expense('feb-coffee', 'coffee', 2, 5),
      _expense('feb-unknown', null, 2, 60),
      _expense('feb-plan1', 'snack', 2, 7, status: TransactionStatus.planned),
      _expense('feb-plan2', 'lunch', 2, 4,
          currency: 'USD', status: TransactionStatus.planned),
    ]);
    repo = await repo.updateExistingCategory(const Category(
        id: 'snack',
        name: 'snack',
        type: CategoryType.expense,
        parentId: 'food',
        isArchived: true));
    expect(repo.budgetUsageFor('food', '2026-01').actual, 55);
    expect(repo.budgetUsageFor('food', '2026-01').planned, 11);
    final food = repo.budgetUsageFor('food', '2026-02');
    final out = repo.budgetUsageFor('out', '2026-02');
    expect(food.actual, 30);
    expect(food.planned, 7);
    expect(out.actual, 37);
    expect(out.planned, 16);
    expect(out.transactions.map((tx) => tx.id),
        unorderedEquals(['feb-lunch', 'feb-coffee', 'feb-plan2']));
    expect(food.transactions.map((tx) => tx.id),
        unorderedEquals(['feb-root', 'feb-snack', 'feb-plan1']));
    expect(repo.totalBudgetExpenseForMonth('2026-02'), 67);
    expect(repo.totalPlannedBudgetExpenseForMonth('2026-02'), 23);
    expect(repo.totalEffectiveBudgetForMonth('2026-02'), 2045);

    final stopped = repo
        .previewBudget(_rule('draft', 'food', '2026-02', 200, currency: 'USD'));
    expect(stopped.baseAmount, 800);
    expect(stopped.carried, 945);
    expect(stopped.effective, 1745);
    expect(stopped.nextCarried, 0);
    expect(stopped.nextEffective, 900);
    final continued = repo.previewBudget(_rule('draft', 'food', '2026-02', 200,
        currency: 'USD', rollover: true));
    expect(continued.nextCarried, 1708);
    expect(continued.nextEffective, 2608);

    // Previewing a first lunch budget claims its own receipts from "out" even
    // though that rule is not yet present in the persisted month.
    final lunchRule = _rule('lunch-rule', 'lunch', '2026-02', 40);
    final lunch = repo.previewBudget(lunchRule);
    expect(lunch.carried, 0);
    expect(lunch.actual, 32);
    expect(lunch.planned, 16);
    repo = await repo.addBudget(lunchRule);
    expect(repo.budgetUsageFor('lunch', '2026-02').actual, lunch.actual);
    expect(repo.budgetUsageFor('out', '2026-02').actual, 5);
    expect(repo.budgetUsageFor('out', '2026-02').planned, 0);
    expect(repo.totalBudgetExpenseForMonth('2026-02'), 67);
    expect(repo.totalPlannedBudgetExpenseForMonth('2026-02'), 23);
    expect(
        repo.previewBudget(_rule('mar-root', 'food', '2026-03', 900)).carried,
        1915);
  });
}
