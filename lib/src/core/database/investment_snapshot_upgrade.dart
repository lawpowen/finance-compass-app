part of 'app_database.dart';

const _investmentSemanticsKey = 'investment_snapshot_semantics';
const _immutableInvestmentSemantics = 'immutable_v1';
const _investmentUpgradeAuditKey = 'investment_snapshot_upgrade_v1_json';

extension _InvestmentSnapshotUpgrade on AppDatabase {
  Future<void> _rebuildInvestmentCaches(List<model.Account> accountItems,
      List<model.AssetSnapshot> snapshotItems) async {
    final ids = {
      for (final item in snapshotItems) item.accountId,
      for (final account in accountItems)
        if (account.effectiveReportGroup == model.ReportGroup.investment ||
            account.effectiveReportGroup == model.ReportGroup.retirement)
          account.id,
    };
    for (final id in ids) {
      await _rebuildSnapshotAccount(id);
    }
  }

  /// Called inside the same transaction as opening the old ledger or restoring
  /// the backup. Only the latest legacy observation has a comparable materialized
  /// account balance. Earlier rows have no record of which transfers they absorbed.
  Future<bool> _prepareInvestmentSnapshotSemantics() async {
    final semantics = await getMetaValue(_investmentSemanticsKey);
    if (semantics == _immutableInvestmentSemantics) return false;
    if (semantics != null) {
      throw FormatException('不支持的投资快照口径：$semantics');
    }

    final accountItems = await fetchAccounts();
    final snapshotItems = await fetchAssetSnapshots();
    final byAccount = <String, List<model.AssetSnapshot>>{};
    for (final snapshot in snapshotItems) {
      (byAccount[snapshot.accountId] ??= []).add(snapshot);
    }
    final flowsByAccount = <String, List<model.FinanceTransaction>>{};
    if (accountItems.any((a) =>
        byAccount.containsKey(a.id) ||
        a.effectiveReportGroup == model.ReportGroup.investment ||
        a.effectiveReportGroup == model.ReportGroup.retirement)) {
      for (final tx in await fetchTransactions()) {
        if (!tx.affectsBalance) continue;
        (flowsByAccount[tx.accountId] ??= []).add(tx);
        if (tx.type == model.TransactionType.transfer &&
            tx.toAccountId != null &&
            tx.toAccountId != tx.accountId) {
          (flowsByAccount[tx.toAccountId!] ??= []).add(tx);
        }
      }
    }
    final audit = <String, Object?>{};
    for (final account in accountItems) {
      final rows = byAccount[account.id];
      final flows = flowsByAccount[account.id] ?? const [];
      if (rows == null) {
        if (account.effectiveReportGroup != model.ReportGroup.investment &&
            account.effectiveReportGroup != model.ReportGroup.retirement) {
          continue;
        }
        if (flows.isEmpty &&
            account.initialBalance == 0 &&
            account.currentBalance.isFinite &&
            account.currentBalance != 0) {
          await (update(accounts)..where((a) => a.id.equals(account.id))).write(
            AccountsCompanion(initialBalance: Value(account.currentBalance)),
          );
          audit[account.id] = {
            'original_initial_balance': account.initialBalance,
            'original_current_balance': account.currentBalance,
            'reason': 'sole_recorded_balance_used_as_opening',
          };
          continue;
        }
        final ledgerBalance = flows.fold(account.initialBalance,
            (value, tx) => value + accountTransactionDelta(account.id, tx));
        if (!_sameBalance(ledgerBalance, account.currentBalance)) {
          audit[account.id] = {
            'original_current_balance': account.currentBalance,
            'reason': 'opening_and_ledger_differ_from_cache',
          };
        }
        continue;
      }
      rows.sort(compareAssetSnapshots);
      final latest = rows.last;
      final post =
          flows.where((tx) => tx.transactionDate.isAfter(latest.snapshotDate));
      var folded = 0.0;
      var incomeExpense = 0.0;
      var positiveCapital = 0.0;
      var hasWithdrawal = false;
      for (final tx in post) {
        final delta = accountTransactionDelta(account.id, tx);
        if (tx.type == model.TransactionType.transfer ||
            tx.type == model.TransactionType.adjustment) {
          folded += delta;
          if (delta > 0) positiveCapital += delta;
          if (delta < 0) hasWithdrawal = true;
        } else {
          incomeExpense += delta;
        }
      }
      final tied = rows.length > 1 &&
          rows[rows.length - 2].snapshotDate == latest.snapshotDate;
      final matchesFolded = _sameBalance(
          account.currentBalance, latest.marketValue + incomeExpense);
      final matchesForward = _sameBalance(
          account.currentBalance, latest.marketValue + incomeExpense + folded);
      final canUnfold = !tied && matchesFolded && !matchesForward;
      final reasons = <String>[
        if (rows.length > 1) 'older_observation_flow_ownership_unknown',
        if (tied) 'latest_timestamp_tie',
        if (!matchesFolded && !matchesForward) 'cache_matches_neither_model',
      ];
      if (canUnfold) {
        // The old write path clamped cash independently of market value. If
        // a withdrawal could have hit zero, its original cash cannot be inferred.
        final cashRecoverable = latest.cashBalance >= folded &&
            (!hasWithdrawal || latest.cashBalance > positiveCapital);
        final observedMarket = latest.marketValue - folded;
        await (update(assetSnapshots)..where((s) => s.id.equals(latest.id)))
            .write(
          AssetSnapshotsCompanion(
            marketValue: Value(observedMarket),
            cashBalance: cashRecoverable
                ? Value(latest.cashBalance - folded)
                : const Value.absent(),
            unrealizedPnl: Value(latest.unrealizedPnl - folded),
          ),
        );
        reasons.add('latest_folded_capital_removed');
        if (!cashRecoverable) reasons.add('legacy_cash_clamp_unknown');
      }
      if (reasons.isNotEmpty) {
        audit[account.id] = {
          'original_current_balance': account.currentBalance,
          'latest_id': latest.id,
          'original_market_value': latest.marketValue,
          'original_cash_balance': latest.cashBalance,
          'original_cost_basis': latest.costBasis,
          'original_unrealized_pnl': latest.unrealizedPnl,
          'post_observation_capital': folded,
          'reasons': reasons,
        };
      }
    }
    if (audit.isNotEmpty) {
      await setMetaValue(_investmentUpgradeAuditKey, jsonEncode(audit));
    }
    await _rebuildInvestmentCaches(accountItems, snapshotItems);
    await setMetaValue(_investmentSemanticsKey, _immutableInvestmentSemantics);
    return true;
  }
}

bool _sameBalance(double a, double b) => (a - b).abs() <= 0.0000001;
