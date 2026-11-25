import '../data/category_reporting.dart';
import '../data/finance_repository.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/forecast_summary.dart';
import '../models/monthly_summary.dart';
import '../models/transaction.dart';
import 'account_service.dart';
import 'budget_service.dart';
import 'currency_service.dart';

/// Reporting facade for code using a captured ledger revision. Forecasts,
/// statement allocations and category totals are the production queries.
class ReportService {
  ReportService({
    required List<Account> accounts,
    required List<FinanceTransaction> transactions,
    required List<Category> categories,
    required AccountService accountService,
    required BudgetService budgetService,
    required CurrencyService currencyService,
  }) : this.fromRepository(FinanceRepository.fromSnapshot(
          database: accountService.repository.database,
          accounts: accounts,
          transactions: transactions,
          categories: categories,
          snapshots: accountService.repository.snapshots,
          budgets: budgetService.repository.budgets,
          metaValues: currencyService.metaValues,
        ));
  const ReportService.fromRepository(this.repository);
  final FinanceRepository repository;

  List<MonthlySummary> monthlySummaries({required int months}) =>
      repository.monthlySummaries(months: months);
  List<MonthlySummary> futureExpenseSummaries({int months = 3}) =>
      repository.futureExpenseSummaries(months: months);
  CategoryReportIndex get categoryReports => repository.categoryReports;
  Map<String, double> categoryTotalsForMonths(
          {required CategoryType type, required List<String> monthKeys}) =>
      repository.categoryTotalsForMonths(type: type, monthKeys: monthKeys);
  ForecastSummary forecastSummary({int months = 3, DateTime? asOf}) =>
      repository.forecastSummary(months: months, asOf: asOf);
  List<CashFlowProjectionPoint> futureCashFlowProjection(
          {int months = 6, DateTime? asOf}) =>
      repository.futureCashFlowProjection(months: months, asOf: asOf);
  List<CreditCardPaymentReminder> creditCardPaymentReminders(
          {DateTime? asOf}) =>
      repository.creditCardPaymentReminders(asOf: asOf);
  double totalIncomeForMonth(String month) =>
      repository.totalIncomeForMonth(month);
  double totalExpenseForMonth(String month) =>
      repository.totalExpenseForMonth(month);
  CashFlowSummary actualCashFlowSummaryForMonth(String month) =>
      repository.actualCashFlowSummaryForMonth(month);
  double plannedIncomeForMonth(String month) =>
      repository.plannedIncomeForMonth(month);
  double plannedExpenseForMonth(String month) =>
      repository.plannedExpenseForMonth(month);
}
