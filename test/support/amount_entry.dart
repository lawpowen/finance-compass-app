import 'package:finance_app/src/features/shared/finance_amount_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercise the actual keypad, expressing business fixtures in major units.
Future<void> enterAmount(
    WidgetTester tester, Finder field, String amount) async {
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  final value = double.parse(amount);
  final keys = [
    'C',
    ...value.abs().toStringAsFixed(2).replaceAll('.', '').split(''),
    if (value.isNegative) '±',
    '完成',
  ];
  for (final key in keys) {
    final button = find.byKey(ValueKey('amount-key-$key'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }
}

TextEditingController amountController(WidgetTester tester, Finder field) {
  final widget = tester.widget(field);
  return switch (widget) {
    FinanceAmountField() => widget.controller,
    TextFormField() => widget.controller!,
    TextField() => widget.controller!,
    _ => throw StateError('Not an amount field: $widget'),
  };
}
