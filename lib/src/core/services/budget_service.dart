import '../data/finance_repository.dart';
import '../database/app_database.dart' show AppDatabase;
import '../models/budget.dart';
import '../models/budget_ledger.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import 'currency_service.dart';

/// Read-only month-effective budget and spending queries.
class BudgetService with BudgetQueries {
  BudgetService({
    required List<Budget> budgets,
    required List<FinanceTransaction> transactions,
    required List<Category> categories,
    required CurrencyService currencyService,
    required AppDatabase database,
  }) : this.fromRepository(FinanceRepository.fromSnapshot(
          database: database,
          budgets: budgets,
          transactions: transactions,
          categories: categories,
          metaValues: currencyService.metaValues,
        ));
  const BudgetService.fromRepository(this.repository);

  final FinanceRepository repository;
  @override
  BudgetLedger get budgetLedger => repository.budgetLedger;
  List<Budget> reusableBudgets() => repository.reusableBudgets();
  List<String> budgetMonthKeys({int futureMonths = 6}) =>
      repository.budgetMonthKeys(futureMonths: futureMonths);
  double totalBudgetAmount({String? monthKey}) =>
      repository.totalBudgetAmount(monthKey: monthKey);
  double budgetAmountInBase(Budget budget) =>
      repository.budgetAmountInBase(budget);
  double expenseTotalForCategory(String id, String month) =>
      repository.expenseTotalForCategory(id, month);
  double plannedExpenseTotalForCategory(String id, String month) =>
      repository.plannedExpenseTotalForCategory(id, month);
}
