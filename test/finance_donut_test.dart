import 'package:finance_app/src/features/shared/finance_donut.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'approved ring keeps its geometry, centered amount and percentages',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: FinanceDonutPanel(
              title: '预算分配',
              totalLabel: '已分配',
              totalValue: 'MYR 4,000',
              slices: [
                FinanceDonutSlice(label: '日常', value: 1600, color: Colors.teal),
                FinanceDonutSlice(
                    label: '交通', value: 1000, color: Colors.orange),
                FinanceDonutSlice(
                    label: '保险', value: 800, color: Colors.purple),
                FinanceDonutSlice(label: '其他', value: 600, color: Colors.grey),
              ],
              footer: Text('已用 2,600 · 预计 400 · 剩余 1,000'),
            ),
          ),
        ),
      ),
    );

    final ring = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is CustomPainter,
    );
    expect(ring, findsOneWidget);
    expect(tester.getSize(ring), const Size(146, 146));
    final centerAmount = tester.getCenter(find.text('MYR 4,000'));
    expect(tester.getCenter(ring).dx, closeTo(centerAmount.dx, .5));
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('20%'), findsOneWidget);
    expect(find.text('15%'), findsOneWidget);
    expect(find.text('已用 2,600 · 预计 400 · 剩余 1,000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty composition has zero shares', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FinanceDonutPanel(
            title: '资产构成',
            totalLabel: '总资产',
            totalValue: 'MYR 0',
            slices: [
              FinanceDonutSlice(label: '现金', value: 0, color: Colors.teal),
              FinanceDonutSlice(label: '投资', value: 0, color: Colors.purple),
            ],
          ),
        ),
      ),
    );

    expect(find.text('MYR 0'), findsOneWidget);
    expect(find.text('0%'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
