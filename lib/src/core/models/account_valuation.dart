import 'account.dart';
import 'asset_goal.dart' show AssetGoalTimeline;
import 'asset_snapshot.dart';
import 'transaction.dart';

// SQLite's BINARY collation uses UTF-8 byte order. Compare Unicode scalars
// here as well, including supplementary characters in imported IDs.
int _compareLedgerIds(String left, String right) {
  final a = left.runes.iterator;
  final b = right.runes.iterator;
  while (a.moveNext()) {
    if (!b.moveNext()) return 1;
    final order = a.current.compareTo(b.current);
    if (order != 0) return order;
  }
  return b.moveNext() ? -1 : 0;
}

int compareAssetSnapshots(AssetSnapshot left, AssetSnapshot right) {
  final byDate = left.snapshotDate.compareTo(right.snapshotDate);
  return byDate == 0 ? _compareLedgerIds(left.id, right.id) : byDate;
}

/// Signed movement in the account's own currency. A self-transfer has two legs.
double accountTransactionDelta(String accountId, FinanceTransaction transaction,
    {bool includePlanned = false}) {
  if (!includePlanned && !transaction.affectsBalance) return 0;
  final isSource = transaction.accountId == accountId;
  switch (transaction.type) {
    case TransactionType.adjustment:
    case TransactionType.income:
      return isSource ? transaction.amount : 0;
    case TransactionType.expense:
      return isSource ? -transaction.amount : 0;
    case TransactionType.transfer:
      final debit = isSource ? transaction.amount : 0.0;
      final credit = transaction.toAccountId == accountId
          ? transaction.transferInAmount
          : 0.0;
      return credit - debit;
  }
}

class InvestmentFlowSummary {
  const InvestmentFlowSummary(
      {required this.contribution, required this.withdrawal});
  final double contribution;
  final double withdrawal;
  double get netContribution => contribution - withdrawal;
}

class InvestmentValuation {
  const InvestmentValuation({
    required this.marketValue,
    required this.cashBalance,
    required this.cumulativeCost,
    required this.netInvestment,
  });

  final double marketValue;
  final double cashBalance;
  final double cumulativeCost;
  final double netInvestment;
  double get gain => marketValue - netInvestment;
  double? get returnRatio => netInvestment > 0 ? gain / netInvestment : null;
}

typedef BalanceMovement = ({FinanceTransaction transaction, double delta});

class BalanceProjection {
  const BalanceProjection(this.sourceLabel, this.sourceAmount, this.movements);
  final String sourceLabel;
  final double sourceAmount;
  final Iterable<BalanceMovement> movements;

  double get balance =>
      movements.fold(sourceAmount, (sum, item) => sum + item.delta);
}

/// Immutable transaction and observation indexes for one repository revision.
/// Both on-screen balances and their audit trails consume the same projection.
class AccountValuationBook {
  AccountValuationBook(List<Account> accounts,
      List<FinanceTransaction> transactions, List<AssetSnapshot> snapshots)
      : _accounts = {for (final account in accounts) account.id: account} {
    for (final snapshot in snapshots) {
      (_snapshots[snapshot.accountId] ??= []).add(snapshot);
    }
    for (final items in _snapshots.values) {
      items.sort(compareAssetSnapshots);
    }
    for (final transaction
        in transactions.where((item) => item.affectsBalance)) {
      final target = transaction.toAccountId;
      _addMovement(transaction.accountId, transaction);
      if (target != null &&
          target != transaction.accountId &&
          transaction.type == TransactionType.transfer) {
        _addMovement(target, transaction);
      }
    }
    for (final items in _movements.values) {
      items.sort((a, b) {
        final byDate = a.transaction.transactionDate
            .compareTo(b.transaction.transactionDate);
        return byDate == 0
            ? _compareLedgerIds(a.transaction.id, b.transaction.id)
            : byDate;
      });
    }
  }

  final Map<String, Account> _accounts;
  final _movements = <String, List<BalanceMovement>>{};
  final _snapshots = <String, List<AssetSnapshot>>{};

  double incomingFor(FinanceTransaction transaction) =>
      transaction.transferInAmount;

  double deltaFor(String id, FinanceTransaction transaction,
          {bool includePlanned = false}) =>
      accountTransactionDelta(id, transaction, includePlanned: includePlanned);

  void _addMovement(String id, FinanceTransaction transaction) {
    final delta = deltaFor(id, transaction);
    if (delta != 0) {
      (_movements[id] ??= []).add((transaction: transaction, delta: delta));
    }
  }

  Iterable<AssetSnapshot> snapshotsFor(String id) => _snapshots[id] ?? const [];

  AssetGoalTimeline goalTimeline(
      double Function(double, String) convertToBase) {
    final openings = <double>[];
    final updates = <int, List<({int account, double value})>>{};
    for (final account in _accounts.values) {
      if (account.effectiveReportGroup == ReportGroup.credit) continue;
      final index = openings.length;
      final observations = _snapshots[account.id] ?? const <AssetSnapshot>[];
      final movements = _movements[account.id] ?? const <BalanceMovement>[];
      void record(DateTime time, double balance) {
        (updates[time.microsecondsSinceEpoch] ??= []).add(
            (account: index, value: convertToBase(balance, account.currency)));
      }

      if (!_usesOpeningBalance(account, observations)) {
        // Match the ordinary account's reconciled cache even when its
        // opening balance and historical transactions don't explain it.
        var balance = account.currentBalance;
        int? nextInstant;
        for (final m in movements.reversed) {
          final time = m.transaction.transactionDate;
          if (nextInstant != time.microsecondsSinceEpoch) record(time, balance);
          nextInstant = time.microsecondsSinceEpoch;
          balance -= m.delta;
        }
        openings.add(convertToBase(balance, account.currency));
        continue;
      }

      var balance = account.initialBalance;
      openings.add(convertToBase(balance, account.currency));
      var i = 0;
      // The sorted observations replace all movement at or before their
      // timestamp. Equal-time observations are already in ID order.
      for (final snapshot in observations) {
        while (i < movements.length &&
            !movements[i]
                .transaction
                .transactionDate
                .isAfter(snapshot.snapshotDate)) {
          final m = movements[i++];
          if (m.transaction.transactionDate.isBefore(snapshot.snapshotDate)) {
            balance += m.delta;
            record(m.transaction.transactionDate, balance);
          }
        }
        balance = snapshot.marketValue;
        record(snapshot.snapshotDate, balance);
      }
      while (i < movements.length) {
        final m = movements[i++];
        balance += m.delta;
        record(m.transaction.transactionDate, balance);
      }
    }
    return AssetGoalTimeline(openings, updates);
  }

  bool _usesOpeningBalance(
          Account account, Iterable<AssetSnapshot> observations) =>
      observations.isNotEmpty ||
      account.effectiveReportGroup == ReportGroup.investment ||
      account.effectiveReportGroup == ReportGroup.retirement;

  BalanceProjection projection(String id, DateTime cutoff) {
    final account = _accounts[id]!;
    final observations = snapshotsFor(id);
    final anchor =
        observations.where((s) => !s.snapshotDate.isAfter(cutoff)).lastOrNull;
    final movements = _movements[id] ?? const [];
    if (account.accountType == AccountType.loan &&
        account.loanStartDate != null &&
        cutoff.isBefore(account.loanStartDate!)) {
      return const BalanceProjection('贷款合同尚未生效', 0, []);
    }
    if (anchor != null) {
      final date = anchor.snapshotDate;
      final dateLabel = date.toIso8601String().split('T').first;
      return BalanceProjection(
          '资产快照 $dateLabel', anchor.marketValue, _between(id, date, cutoff));
    }
    if (_usesOpeningBalance(account, observations)) {
      final source = observations.isEmpty ? '账户期初余额' : '账户期初余额（首张资产快照之前）';
      return BalanceProjection(
          source, account.initialBalance, _between(id, null, cutoff));
    }
    // Older ordinary accounts can have a reconciled balance with incomplete history.
    return BalanceProjection(
        '当前账户余额',
        account.currentBalance,
        movements.reversed
            .takeWhile((m) => m.transaction.transactionDate.isAfter(cutoff))
            .map((m) => (transaction: m.transaction, delta: -m.delta)));
  }

  Iterable<BalanceMovement> _between(
          String id, DateTime? after, DateTime cutoff) =>
      (_movements[id] ?? const <BalanceMovement>[])
          .takeWhile((m) => !m.transaction.transactionDate.isAfter(cutoff))
          .where((m) =>
              after == null || m.transaction.transactionDate.isAfter(after));

  InvestmentFlowSummary capitalFlows(
      String id, DateTime? after, DateTime cutoff) {
    var contribution = 0.0;
    var withdrawal = 0.0;
    for (final movement in _between(id, after, cutoff)) {
      final type = movement.transaction.type;
      if (type != TransactionType.transfer &&
          type != TransactionType.adjustment) {
        continue;
      }
      if (movement.delta > 0) {
        contribution += movement.delta;
      } else {
        withdrawal -= movement.delta;
      }
    }
    return InvestmentFlowSummary(
        contribution: contribution, withdrawal: withdrawal);
  }

  bool setsBaseline(AssetSnapshot candidate) {
    final firstOther = snapshotsFor(candidate.accountId)
        .where((item) => item.id != candidate.id)
        .firstOrNull;
    return firstOther == null ||
        compareAssetSnapshots(candidate, firstOther) < 0;
  }

  double suggestedBaseline(String id, DateTime cutoff) =>
      _accounts[id]!.initialBalance +
      capitalFlows(id, null, cutoff).netContribution;

  InvestmentValuation investmentAt(String id, DateTime cutoff,
      {AssetSnapshot? observation}) {
    final snapshots = snapshotsFor(id);
    final anchor = observation ??
        snapshots.where((s) => !s.snapshotDate.isAfter(cutoff)).lastOrNull;
    // A candidate observation replaces the same ID, including when its date moves.
    final firstStored = snapshots
        .where(
            (s) => s.id != observation?.id && !s.snapshotDate.isAfter(cutoff))
        .firstOrNull;
    var first = firstStored;
    if (observation != null &&
        (first == null || compareAssetSnapshots(observation, first) < 0)) {
      first = observation;
    }
    final capital = capitalFlows(id, first?.snapshotDate, cutoff);
    final opening = _accounts[id]!.initialBalance;
    final gross = (first?.costBasis ?? opening) + capital.contribution;
    var market = anchor?.marketValue ?? opening;
    var cash = anchor?.cashBalance ?? opening;
    for (final entry in _between(id, anchor?.snapshotDate, cutoff)) {
      market += entry.delta;
      cash += entry.delta;
    }
    return InvestmentValuation(
      marketValue: market,
      cashBalance: cash,
      cumulativeCost: gross,
      netInvestment: gross - capital.withdrawal,
    );
  }
}

/// Shared query contract for the repository and its asset-service facade.
mixin InvestmentValuationQueries {
  AccountValuationBook get valuationBook;
  DateTime currentMonthCutoffDate();

  List<AssetSnapshot> snapshotsForAccount(String id) =>
      List.of(valuationBook.snapshotsFor(id));
  List<AssetSnapshot> snapshotsForAccountUpTo(String id, DateTime date) =>
      valuationBook
          .snapshotsFor(id)
          .where((s) => !s.snapshotDate.isAfter(date))
          .toList();
  AssetSnapshot? firstSnapshotForAccount(String id) =>
      valuationBook.snapshotsFor(id).firstOrNull;
  AssetSnapshot? latestSnapshotForAccount(String id) =>
      valuationBook.snapshotsFor(id).lastOrNull;
  AssetSnapshot? latestSnapshotForAccountUpTo(String id, DateTime date) =>
      valuationBook
          .snapshotsFor(id)
          .where((s) => !s.snapshotDate.isAfter(date))
          .lastOrNull;

  InvestmentFlowSummary investmentFlowSummaryForAccount(String id,
          {DateTime? fromDateExclusive, DateTime? upToDate}) =>
      valuationBook.capitalFlows(
          id, fromDateExclusive, upToDate ?? currentMonthCutoffDate());
  InvestmentValuation investmentValuationAt(String id, DateTime date) =>
      valuationBook.investmentAt(id, date);
  InvestmentValuation snapshotValuation(AssetSnapshot snapshot) =>
      valuationBook.investmentAt(snapshot.accountId, snapshot.snapshotDate,
          observation: snapshot);
  bool snapshotSetsCostBaseline(AssetSnapshot candidate) =>
      valuationBook.setsBaseline(candidate);
  double suggestedSnapshotBaseline(String id, DateTime date) =>
      valuationBook.suggestedBaseline(id, date);

  double costBasisForAccount(String id, {DateTime? upToDate}) =>
      investmentValuationAt(id, upToDate ?? currentMonthCutoffDate())
          .cumulativeCost;
  double cashBalanceForAccount(String id, {DateTime? upToDate}) =>
      investmentValuationAt(id, upToDate ?? currentMonthCutoffDate())
          .cashBalance;
  double remainingCostBasisForAccount(String id, {DateTime? upToDate}) =>
      investmentValuationAt(id, upToDate ?? currentMonthCutoffDate())
          .netInvestment;
  double snapshotCostBasis(AssetSnapshot snapshot) =>
      snapshotValuation(snapshot).cumulativeCost;
  double snapshotRemainingCostBasis(AssetSnapshot snapshot) =>
      snapshotValuation(snapshot).netInvestment;
  double snapshotUnrealizedPnl(AssetSnapshot snapshot) =>
      snapshotValuation(snapshot).gain;
  double snapshotPnlRatio(AssetSnapshot snapshot) =>
      snapshotValuation(snapshot).returnRatio ?? 0;
}
