import '../data/finance_repository.dart';
import '../database/app_database.dart' show AppDatabase;
import '../models/account.dart';
import '../models/account_valuation.dart';
import '../models/asset_snapshot.dart';
import '../models/transaction.dart';

import 'currency_service.dart';

/// Read adapter for callers that supply a snapshot of asset records.
class AssetService with InvestmentValuationQueries {
  AssetService({
    required List<Account> accounts,
    required List<FinanceTransaction> transactions,
    required List<AssetSnapshot> snapshots,
    required Map<String, String> metaValues,
    required CurrencyService currencyService,
    required AppDatabase database,
  }) : this.fromRepository(FinanceRepository.fromSnapshot(
          database: database,
          accounts: accounts,
          transactions: transactions,
          snapshots: snapshots,
          metaValues: {...currencyService.metaValues, ...metaValues},
        ));

  const AssetService.fromRepository(this._ledger);

  final FinanceRepository _ledger;

  @override
  AccountValuationBook get valuationBook => _ledger.valuationBook;

  @override
  DateTime currentMonthCutoffDate() => _ledger.currentMonthCutoffDate();

  List<AssetGoal> get assetGoals => _ledger.assetGoals;

  List<AssetGoalHistoryPoint> totalAssetHistory({
    DateTime? cutoffDate,
    bool includeCredit = true,
  }) =>
      _ledger.totalAssetHistory(
          cutoffDate: cutoffDate, includeCredit: includeCredit);

  List<AssetGoalProgressSummary> assetGoalSummaries({DateTime? cutoffDate}) =>
      _ledger.assetGoalSummaries(cutoffDate: cutoffDate);
}
