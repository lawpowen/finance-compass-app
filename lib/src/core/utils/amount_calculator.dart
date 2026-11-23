/// A fixed two-decimal keypad. Every digit entered is a minor currency unit.
/// Arithmetic uses exact fractions and rounds once, half away from zero.
class AmountCalculator {
  AmountCalculator(String initialText) {
    final match =
        RegExp(r'^(-?)(\d+)(?:\.(\d*))?$').firstMatch(initialText.trim());
    if (match != null) {
      final fraction = match.group(3) ?? '';
      var minor = BigInt.parse(match.group(2)!) * _hundred +
          BigInt.parse('${fraction}00'.substring(0, 2));
      if (fraction.length > 2 && int.parse(fraction[2]) >= 5) {
        minor += BigInt.one;
      }
      if (minor <= _limit) {
        _digits = minor.toString();
        _negative = match.group(1) == '-' && minor != BigInt.zero;
      } else {
        error = '金额超出可输入范围';
      }
    }
  }

  static final _hundred = BigInt.from(100);
  static final _limit = BigInt.parse('99999999999999');
  final _values = <BigInt>[];
  final _operators = <String>[];
  String _digits = '';
  bool _negative = false;
  bool _replaceEntry = true;
  bool _evaluated = false;
  String _lastExpression = '';
  bool dirty = false;
  String? error;

  bool get isEmpty => _digits.isEmpty && _values.isEmpty;
  BigInt get _current =>
      BigInt.parse(_digits.isEmpty ? '0' : _digits) *
      BigInt.from(_negative ? -1 : 1);
  String get display =>
      _negative && _current == BigInt.zero ? '-0.00' : _format(_current);
  String get expression {
    if (_lastExpression.isNotEmpty) return _lastExpression;
    return [
      for (var i = 0; i < _values.length; i++) ...[
        _format(_values[i]),
        _operators[i],
      ],
      if (_digits.isNotEmpty && _values.isNotEmpty) display,
    ].join(' ');
  }

  void digit(String value) {
    if (!RegExp(r'^\d{1,2}$').hasMatch(value)) return;
    final next = '${_replaceEntry ? '' : _digits}$value';
    final minor = BigInt.parse(next);
    if (minor > _limit) {
      error = '最多输入 12 位整数和 2 位小数';
      return;
    }
    if (_evaluated) _resetExpression();
    if (_replaceEntry) _negative = false;
    _digits = minor.toString();
    _replaceEntry = false;
    _changed();
  }

  void clear() {
    _resetExpression();
    _digits = '';
    _negative = false;
    _replaceEntry = false;
    _changed();
  }

  void toggleSign() {
    _lastExpression = '';
    _evaluated = false;
    _negative = !_negative;
    _replaceEntry = false;
    _changed();
  }

  void backspace() {
    _lastExpression = '';
    _evaluated = false;
    _replaceEntry = false;
    if (_digits.isNotEmpty) {
      _digits = _digits.substring(0, _digits.length - 1);
      if (_digits.isEmpty) _negative = false;
    } else if (_values.isNotEmpty) {
      final previous = _values.removeLast();
      _operators.removeLast();
      _digits = previous.abs().toString();
      _negative = previous.isNegative;
    }
    _changed();
  }

  void operation(String operator) {
    if (!const ['+', '−', '×', '÷'].contains(operator)) return;
    if (_digits.isEmpty && _operators.isNotEmpty) {
      _operators[_operators.length - 1] = operator;
    } else {
      if (_operators.length >= 32) {
        error = '请先计算当前算式，再继续';
        return;
      }
      _values.add(_current);
      _operators.add(operator);
      _digits = '';
    }
    _negative = false;
    _replaceEntry = false;
    _evaluated = false;
    _lastExpression = '';
    _changed();
  }

  bool evaluate() {
    if (_values.isEmpty) return error == null;
    if (_digits.isEmpty) {
      error = '请补全算式';
      return false;
    }
    final originalExpression = expression;
    final values = [..._values, _current];
    var sum = _Fraction(BigInt.zero, BigInt.one);
    var term = _Fraction(values.first, _hundred);
    var subtract = false;
    for (var i = 0; i < _operators.length; i++) {
      final next = _Fraction(values[i + 1], _hundred);
      switch (_operators[i]) {
        case '×':
          term = term.multiply(next);
        case '÷':
          if (next.numerator == BigInt.zero) {
            error = '不能除以 0';
            return false;
          }
          term = term.divide(next);
        case '+':
        case '−':
          sum = sum.add(subtract ? term.negate() : term);
          term = next;
          subtract = _operators[i] == '−';
      }
    }
    final result = sum.add(subtract ? term.negate() : term).roundedMinor;
    if (result.abs() > _limit) {
      error = '计算结果超出金额范围';
      return false;
    }
    _resetExpression();
    _digits = result.abs().toString();
    _negative = result.isNegative;
    _replaceEntry = true;
    _evaluated = true;
    _lastExpression = '$originalExpression =';
    _changed();
    return true;
  }

  void _resetExpression() {
    _values.clear();
    _operators.clear();
    _lastExpression = '';
    _evaluated = false;
  }

  void _changed() {
    dirty = true;
    error = null;
  }

  static String _format(BigInt minor) {
    final digits = minor.abs().toString().padLeft(3, '0');
    final split = digits.length - 2;
    return '${minor.isNegative ? '-' : ''}'
        '${digits.substring(0, split)}.${digits.substring(split)}';
  }
}

class _Fraction {
  _Fraction(BigInt numerator, BigInt denominator)
      : numerator = numerator ~/
            numerator.gcd(denominator) *
            BigInt.from(denominator.isNegative ? -1 : 1),
        denominator = denominator.abs() ~/ numerator.gcd(denominator);

  final BigInt numerator;
  final BigInt denominator;

  _Fraction add(_Fraction other) => _Fraction(
        numerator * other.denominator + other.numerator * denominator,
        denominator * other.denominator,
      );
  _Fraction multiply(_Fraction other) =>
      _Fraction(numerator * other.numerator, denominator * other.denominator);
  _Fraction divide(_Fraction other) =>
      _Fraction(numerator * other.denominator, denominator * other.numerator);
  _Fraction negate() => _Fraction(-numerator, denominator);
  BigInt get roundedMinor {
    final scaled = numerator.abs() * BigInt.from(100);
    final rounded = scaled ~/ denominator +
        ((scaled % denominator) * BigInt.two >= denominator
            ? BigInt.one
            : BigInt.zero);
    return numerator.isNegative ? -rounded : rounded;
  }
}
