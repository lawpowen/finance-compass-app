import '../data/finance_repository.dart';
import '../database/app_database.dart' show AppDatabase;
import '../models/account.dart';
import '../models/account_valuation.dart';
import '../models/asset_snapshot.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import 'currency_service.dart';

/// Account queries for snapshot-based consumers. A complete repository also
/// carries the category labels and reconciliation state used by account traces.
class AccountService {
  AccountService({
    required List<Account> accounts,
    required List<FinanceTransaction> transactions,
    required List<AssetSnapshot> snapshots,
    required CurrencyService currencyService,
    required AppDatabase database,
    List<Category> categories = const [],
    Map<String, String> metaValues = const {},
  }) : this.fromRepository(FinanceRepository.fromSnapshot(
          database: database,
          accounts: accounts,
          categories: categories,
          transactions: transactions,
          snapshots: snapshots,
          metaValues: {...currencyService.metaValues, ...metaValues},
        ));
  const AccountService.fromRepository(this.repository);

  final FinanceRepository repository;
  AccountValuationBook get valuationBook => repository.valuationBook;
  DateTime currentMonthCutoffDate() => repository.currentMonthCutoffDate();
  List<Account> accountsByGroup(ReportGroup group) =>
      repository.accountsByGroup(group);
  List<Account> investmentAccounts() => repository.investmentAccounts();
  String accountName(String id) => repository.accountName(id);
  double totalAssetsByGroup(ReportGroup group) =>
      repository.totalAssetsByGroup(group);
  double displayTotalAssetsByGroup(ReportGroup group, {DateTime? cutoffDate}) =>
      repository.displayTotalAssetsByGroup(group, cutoffDate: cutoffDate);
  double totalAssets({bool includeCredit = true}) =>
      repository.totalAssets(includeCredit: includeCredit);
  double displayTotalAssets(
          {bool includeCredit = true, DateTime? cutoffDate}) =>
      repository.displayTotalAssets(
          includeCredit: includeCredit, cutoffDate: cutoffDate);
  double totalTargetAssets() => repository.totalTargetAssets();
  double totalAssetsAt(DateTime date, {bool includeCredit = true}) =>
      repository.totalAssetsAt(date, includeCredit: includeCredit);
  double accountBalanceAt(String id, DateTime date) =>
      repository.accountBalanceAt(id, date);
  double accountBalanceAtBase(String id, DateTime date) =>
      repository.accountBalanceAtBase(id, date);
  double creditCardCommittedOutstandingBalance(String id) =>
      repository.creditCardCommittedOutstandingBalance(id);
  double transactionDeltaForAccount(
          String id, FinanceTransaction transaction) =>
      repository.transactionDeltaForAccount(id, transaction);
  AccountBalanceTrace accountBalanceTrace(String id, DateTime date) =>
      repository.accountBalanceTrace(id, date);
  String? reconciledMonthForAccount(String id) =>
      repository.reconciledMonthForAccount(id);
  bool isAccountReconciledForMonth(String id, String month) =>
      repository.isAccountReconciledForMonth(id, month);
}
