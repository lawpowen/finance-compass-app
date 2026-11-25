import '../data/finance_repository.dart';
import '../models/transaction.dart';

/// Read-only view of the same transaction, template and recurring-rule tables
/// used by the app. Preset creation and generation use the ledger notifier.
class TransactionService {
  const TransactionService.fromRepository(this.repository);
  final FinanceRepository repository;

  List<FinanceTransaction> recentTransactions({int limit = 5}) =>
      repository.recentTransactions(limit: limit);
  List<FinanceTransaction> upcomingExpenseTransactions(
          {int limit = 8, DateTime? asOf}) =>
      repository.upcomingExpenseTransactions(limit: limit, asOf: asOf);
  double totalFutureExpense({int monthsAhead = 3, DateTime? asOf}) =>
      repository.totalFutureExpense(monthsAhead: monthsAhead, asOf: asOf);
  List<FinanceTransaction> transactionsForCategory(String id,
          {String? monthKey}) =>
      repository.transactionsForCategory(id, monthKey: monthKey);
  Map<String, double> expenseBreakdownForAccount(String id, String monthKey) =>
      repository.expenseBreakdownForAccount(id, monthKey);
  List<TransactionTemplate> get transactionTemplates =>
      repository.transactionTemplates;
  List<RecurringTransactionRule> get recurringTransactionRules =>
      repository.recurringTransactionRules;
}
