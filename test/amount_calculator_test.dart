import 'package:finance_app/src/core/utils/amount_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void digits(AmountCalculator calculator, String digits) {
  for (final digit in digits.split('')) {
    calculator.digit(digit);
  }
}

void main() {
  test('fixed two decimals for the requested examples and leading zeroes', () {
    for (final entry in {
      '1134': '11.34',
      '150': '1.50',
      '001': '0.01',
      '0': '0.00'
    }.entries) {
      final calculator = AmountCalculator('');
      digits(calculator, entry.key);
      expect(calculator.display, entry.value);
    }
  });

  test('opening an existing amount does not rescale it; first digit replaces',
      () {
    final calculator = AmountCalculator('-1134.00');
    expect(calculator.display, '-1134.00');
    expect(calculator.dirty, isFalse);
    digits(calculator, '150');
    expect(calculator.display, '1.50');
  });

  test('all operators accept fixed-decimal operands', () {
    for (final entry
        in {'+': '12.84', '−': '9.84', '×': '17.01', '÷': '7.56'}.entries) {
      final calculator = AmountCalculator('');
      digits(calculator, '1134');
      calculator.operation(entry.key);
      digits(calculator, '150');
      expect(calculator.evaluate(), isTrue);
      expect(calculator.display, entry.value);
    }
  });

  test('multiplication and division have precedence over addition', () {
    final calculator = AmountCalculator('10');
    calculator.operation('+');
    digits(calculator, '200');
    calculator.operation('×');
    digits(calculator, '300');
    expect(calculator.evaluate(), isTrue);
    expect(calculator.display, '16.00');
  });

  test('decimal arithmetic stays exact and rounds only the final result', () {
    final calculator = AmountCalculator('0.1');
    calculator.operation('+');
    digits(calculator, '20');
    calculator.evaluate();
    expect(calculator.display, '0.30');
    calculator.clear();
    digits(calculator, '100');
    calculator.operation('÷');
    digits(calculator, '300');
    calculator.operation('×');
    digits(calculator, '300');
    calculator.evaluate();
    expect(calculator.display, '1.00');
  });

  test('rounds half a cent away from zero for either sign', () {
    for (final initial in ['1', '-1']) {
      final calculator = AmountCalculator(initial);
      calculator.operation('÷');
      digits(calculator, '800');
      calculator.evaluate();
      expect(calculator.display, initial == '1' ? '0.13' : '-0.13');
    }
  });

  test('division by zero keeps operands and can be corrected', () {
    final calculator = AmountCalculator('10');
    calculator.operation('÷');
    digits(calculator, '0');
    expect(calculator.evaluate(), isFalse);
    expect(calculator.error, '不能除以 0');
    calculator.backspace();
    digits(calculator, '200');
    expect(calculator.evaluate(), isTrue);
    expect(calculator.display, '5.00');
  });

  test('incomplete expression is not silently committed', () {
    final calculator = AmountCalculator('1.50');
    calculator.operation('+');
    expect(calculator.evaluate(), isFalse);
    expect(calculator.error, '请补全算式');
    calculator.backspace();
    expect(calculator.display, '1.50');
    expect(calculator.evaluate(), isTrue);
  });

  test('backspace, clear and negative entry preserve cents', () {
    final calculator = AmountCalculator('');
    digits(calculator, '1134');
    calculator.backspace();
    expect(calculator.display, '1.13');
    calculator.toggleSign();
    expect(calculator.display, '-1.13');
    calculator.clear();
    expect(calculator.isEmpty, isTrue);
    calculator.toggleSign();
    expect(calculator.display, '-0.00');
    digits(calculator, '150');
    expect(calculator.display, '-1.50');
  });

  test('changing an operator and continuing from a result', () {
    final calculator = AmountCalculator('10');
    calculator.operation('+');
    calculator.operation('−');
    digits(calculator, '200');
    calculator.evaluate();
    expect(calculator.display, '8.00');
    calculator.operation('×');
    digits(calculator, '300');
    calculator.evaluate();
    expect(calculator.display, '24.00');
    digits(calculator, '150');
    expect(calculator.display, '1.50');
    expect(calculator.expression, isEmpty);
  });

  test('input and calculation limits prevent oversized results', () {
    final calculator = AmountCalculator('');
    digits(calculator, '99999999999999');
    calculator.digit('9');
    expect(calculator.error, isNotNull);
    expect(calculator.evaluate(), isFalse);
    calculator.operation('×');
    digits(calculator, '200');
    expect(calculator.evaluate(), isFalse);
    expect(calculator.error, '计算结果超出金额范围');
  });
}
