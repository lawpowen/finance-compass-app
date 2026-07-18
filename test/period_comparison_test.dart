import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/src/core/models/period_comparison.dart';

void main() {
  group('PeriodComparison', () {
    test('returns exact delta and percentage change', () {
      const comparison = PeriodComparison(
        currentValue: 120,
        previousValue: 100,
        lowerIsBetter: false,
      );

      expect(comparison.delta, 20);
      expect(comparison.percentageChange, 20);
      expect(comparison.direction, PeriodChangeDirection.increase);
      expect(comparison.isFavorable, isTrue);
    });

    test('treats a lower expense as favorable', () {
      const comparison = PeriodComparison(
        currentValue: 80,
        previousValue: 100,
        lowerIsBetter: true,
      );

      expect(comparison.delta, -20);
      expect(comparison.percentageChange, -20);
      expect(comparison.direction, PeriodChangeDirection.decrease);
      expect(comparison.isFavorable, isTrue);
    });

    test('does not invent a percentage when the baseline is zero', () {
      const comparison = PeriodComparison(
        currentValue: 100,
        previousValue: 0,
        lowerIsBetter: false,
      );

      expect(comparison.delta, 100);
      expect(comparison.percentageChange, isNull);
    });

    test('reports no change when both periods are zero', () {
      const comparison = PeriodComparison(
        currentValue: 0,
        previousValue: 0,
        lowerIsBetter: false,
      );

      expect(comparison.percentageChange, 0);
      expect(comparison.direction, PeriodChangeDirection.unchanged);
      expect(comparison.isFavorable, isNull);
    });
  });
}
