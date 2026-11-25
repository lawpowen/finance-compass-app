class AssetSnapshot {
  const AssetSnapshot({
    required this.id,
    required this.accountId,
    required this.snapshotDate,
    required this.marketValue,
    this.costBasis = 0,
    this.cashBalance = 0,
    this.unrealizedPnl = 0,
  });

  final String id;
  final String accountId;
  final DateTime snapshotDate;
  final double marketValue;
  final double costBasis;
  final double cashBalance;
  final double unrealizedPnl;

  bool matchesObservation(AssetSnapshot? other) =>
      other != null &&
      id == other.id &&
      accountId == other.accountId &&
      snapshotDate.isAtSameMomentAs(other.snapshotDate) &&
      marketValue == other.marketValue &&
      costBasis == other.costBasis &&
      cashBalance == other.cashBalance &&
      unrealizedPnl == other.unrealizedPnl;
}
