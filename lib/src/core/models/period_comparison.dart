enum PeriodChangeDirection { increase, decrease, unchanged }

class PeriodComparison {
  const PeriodComparison({
    required this.currentValue,
    required this.previousValue,
    required this.lowerIsBetter,
  });

  final double currentValue;
  final double previousValue;
  final bool lowerIsBetter;

  double get delta => currentValue - previousValue;

  PeriodChangeDirection get direction {
    if (delta > 0) return PeriodChangeDirection.increase;
    if (delta < 0) return PeriodChangeDirection.decrease;
    return PeriodChangeDirection.unchanged;
  }

  double? get percentageChange {
    if (previousValue == 0) {
      return currentValue == 0 ? 0 : null;
    }
    return delta / previousValue * 100;
  }

  bool? get isFavorable {
    if (direction == PeriodChangeDirection.unchanged) return null;
    final increased = direction == PeriodChangeDirection.increase;
    return lowerIsBetter ? !increased : increased;
  }
}
