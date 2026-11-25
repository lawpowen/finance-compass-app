import 'dart:convert';

import '../utils/currency_formatter.dart';

class AssetGoalHistoryPoint {
  const AssetGoalHistoryPoint({
    required this.date,
    required this.label,
    required this.totalAssets,
  });

  final DateTime date;
  final String label;
  final double totalAssets;
}

class AssetGoal {
  const AssetGoal({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.currency,
    this.reachedAt,
  });

  final String id;
  final String name;
  final double targetAmount;
  final String currency;
  final DateTime? reachedAt;

  AssetGoal copyWith({
    String? id,
    String? name,
    double? targetAmount,
    DateTime? reachedAt,
    bool clearReachedAt = false,
  }) {
    return AssetGoal(
      id: id ?? this.id,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      currency: currency,
      reachedAt: clearReachedAt ? null : (reachedAt ?? this.reachedAt),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'target_amount': targetAmount,
        'currency': currency,
        'reached_at': reachedAt?.toIso8601String(),
      };

  factory AssetGoal.fromJson(
    Map<String, dynamic> json, {
    required String legacyCurrency,
  }) {
    final currency =
        normalizeCurrency(json['currency'] as String? ?? legacyCurrency);
    if (currency.isEmpty) {
      throw FormatException('无效的目标币种：$currency');
    }
    return AssetGoal(
      id: json['id'] as String,
      name: json['name'] as String? ?? '资产目标',
      targetAmount: (json['target_amount'] as num).toDouble(),
      currency: currency,
      reachedAt: json['reached_at'] == null
          ? null
          : DateTime.tryParse(json['reached_at'] as String),
    );
  }

  static List<AssetGoal> readMetadata(
    Map<String, String> meta,
    String legacyCurrency,
  ) {
    final raw = meta['asset_goals_json'];
    if (raw != null && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((item) => AssetGoal.fromJson(
                Map<String, dynamic>.from(item as Map),
                legacyCurrency: legacyCurrency,
              ))
          .toList()
        ..sort((a, b) => a.targetAmount.compareTo(b.targetAmount));
    }
    final amount = double.tryParse(meta['asset_goal_amount'] ?? '');
    if (amount == null || !amount.isFinite || amount <= 0) return const [];
    return [
      AssetGoal(
        id: 'goal_legacy',
        name: '资产目标',
        targetAmount: amount,
        currency: legacyCurrency,
        reachedAt: DateTime.tryParse(meta['asset_goal_reached_at'] ?? ''),
      ),
    ];
  }
}

class AssetGoalProgressSummary {
  const AssetGoalProgressSummary({
    required this.goal,
    required this.targetAmountInBase,
    required this.valuationAvailable,
    required this.currentAssets,
    required this.reachedAt,
    required this.history,
  });

  final AssetGoal goal;
  final double targetAmountInBase;
  final bool valuationAvailable;
  final double currentAssets;
  final DateTime? reachedAt;
  final List<AssetGoalHistoryPoint> history;

  double get progressRatio => valuationAvailable && targetAmountInBase > 0
      ? currentAssets / targetAmountInBase
      : 0;

  bool get isReached =>
      valuationAvailable && _reachesGoal(currentAssets, targetAmountInBase);
}

// Allow for floating-point FX round-off when two amounts are economically equal.
bool _reachesGoal(double assets, double target) =>
    target > 0 && (assets >= target || target - assets <= target * 1e-14);

/// Non-credit assets in one reporting currency, indexed by effective instant.
/// Peaks record only new day-end highs. An exact intraday cutoff gets its own
/// final observation without making an intraday spike a historical milestone.
class AssetGoalTimeline {
  AssetGoalTimeline(List<double> openings,
      Map<int, List<({int account, double value})>> changes) {
    final leaves = openings.isEmpty ? 1 : openings.length;
    final tree = List<double>.filled(leaves * 2, 0);
    tree.setRange(leaves, leaves + openings.length, openings);
    for (var i = leaves - 1; i > 0; i--) {
      tree[i] = tree[2 * i] + tree[2 * i + 1];
    }
    opening = tree[1];
    var high = opening;
    final instants = changes.keys.toList()..sort();
    DateTime? day;
    void closeDay() {
      if (day != null && tree[1] > high) {
        high = tree[1];
        _highs.add((day: day, value: high));
      }
    }

    for (final instant in instants) {
      final time = DateTime.fromMicrosecondsSinceEpoch(instant);
      final nextDay = DateTime(time.year, time.month, time.day);
      if (nextDay != day) {
        closeDay();
        day = nextDay;
      }
      for (final change in changes[instant]!) {
        // Replace the account's contribution outright. Subtracting an old
        // observation from a running double would lose small balances.
        var i = leaves + change.account;
        tree[i] = change.value;
        while (i > 1) {
          i ~/= 2;
          tree[i] = tree[2 * i] + tree[2 * i + 1];
        }
      }
      _points.add((instant: instant, value: tree[1]));
    }
    closeDay();
  }

  late final double opening;
  final _points = <({int instant, double value})>[];
  final _highs = <({DateTime day, double value})>[];

  double valueAt(DateTime cutoff) {
    final time = cutoff.microsecondsSinceEpoch;
    final end = _lowerBound(_points.length, (i) => _points[i].instant > time);
    return end == 0 ? opening : _points[end - 1].value;
  }

  DateTime? firstReached(double target, DateTime cutoff) {
    if (target <= 0 || _reachesGoal(opening, target)) return null;
    final index = _lowerBound(
        _highs.length, (i) => _reachesGoal(_highs[i].value, target));
    final local = cutoff.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    if (index < _highs.length && _highs[index].day.isBefore(day)) {
      return _highs[index].day;
    }
    return _reachesGoal(valueAt(cutoff), target) ? day : null;
  }

  static int _lowerBound(int length, bool Function(int) matches) {
    var low = 0;
    var high = length;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      if (matches(mid)) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low;
  }
}

/// Values and history are in the ledger base currency. The goal retains the
/// denomination in which the user set it.
List<AssetGoalProgressSummary> summarizeAssetGoals({
  required List<AssetGoal> goals,
  required DateTime cutoff,
  required AssetGoalTimeline timeline,
  required double Function(double amount, String currency) convertToBase,
  required bool assetsPriced,
  required bool Function(String currency) hasExchangeRate,
  required List<AssetGoalHistoryPoint> history,
}) {
  if (goals.isEmpty) return const [];
  final targets = {
    for (final goal in goals)
      goal.id: convertToBase(goal.targetAmount, goal.currency)
  };
  final priced = {
    for (final goal in goals)
      if (assetsPriced && hasExchangeRate(goal.currency)) goal.id
  };
  final current = timeline.valueAt(cutoff);
  return [
    for (final goal in goals)
      AssetGoalProgressSummary(
        goal: goal,
        valuationAvailable: priced.contains(goal.id),
        currentAssets: current,
        targetAmountInBase: targets[goal.id]!,
        reachedAt: priced.contains(goal.id)
            ? timeline.firstReached(targets[goal.id]!, cutoff)
            : null,
        history: history,
      ),
  ]..sort((left, right) {
      if (left.isReached != right.isReached) return left.isReached ? 1 : -1;
      if (left.isReached) {
        final leftDate = left.reachedAt ?? DateTime(9999);
        final rightDate = right.reachedAt ?? DateTime(9999);
        return leftDate.compareTo(rightDate);
      }
      return left.targetAmountInBase.compareTo(right.targetAmountInBase);
    });
}
