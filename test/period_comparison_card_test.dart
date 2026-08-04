import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/src/core/models/period_comparison.dart';
import 'package:finance_app/src/features/shared/period_comparison_card.dart';

void main() {
  testWidgets('shows both periods, the amount delta, and percentage',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: PeriodComparisonCard(
              label: '收入对比',
              currentPeriodLabel: '本月 2026-07',
              previousPeriodLabel: '上月 2026-06',
              comparison: PeriodComparison(
                currentValue: 120,
                previousValue: 100,
                lowerIsBetter: false,
              ),
              accentColor: Colors.green,
              icon: Icons.south_west_rounded,
            ),
          ),
        ),
      ),
    );

    expect(find.text('本月 2026-07'), findsOneWidget);
    expect(find.text('上月 2026-06'), findsOneWidget);
    expect(find.text('RM 120.00'), findsOneWidget);
    expect(find.text('RM 100.00'), findsOneWidget);
    expect(find.text('+RM 20.00'), findsOneWidget);
    expect(find.text('+20.0%'), findsOneWidget);
  });

  testWidgets('explains why percentage is unavailable', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: PeriodComparisonCard(
              label: '支出对比',
              currentPeriodLabel: '本月 2026-07',
              previousPeriodLabel: '上月 2026-06',
              comparison: PeriodComparison(
                currentValue: 50,
                previousValue: 0,
                lowerIsBetter: true,
              ),
              accentColor: Colors.red,
              icon: Icons.north_east_rounded,
            ),
          ),
        ),
      ),
    );

    expect(find.text('百分比不可用'), findsOneWidget);
    expect(find.text('上月 2026-06 为 0，百分比变化不具可比性。'), findsOneWidget);
    expect(find.text('+RM 50.00'), findsOneWidget);
  });
}
