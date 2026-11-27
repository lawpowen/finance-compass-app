import 'dart:convert';

const baseCurrencyCode = 'MYR';
const supportedCurrencies = ['MYR', 'USD', 'CNY', 'TWD'];
String activeBaseCurrencyCode = baseCurrencyCode;

const defaultExchangeRatesToBase = <String, double>{
  'MYR': 1,
  'USD': 4.7,
  'CNY': 0.65,
  'TWD': 0.14,
};

void setActiveBaseCurrency(String currency) {
  activeBaseCurrencyCode = normalizeCurrency(currency);
}

/// Keep the sign in step with the digits actually shown at this precision.
({String magnitude, int sign}) moneyDisplayParts(num value, {int decimals = 2}) {
  final magnitude = value.abs().toStringAsFixed(decimals);
  final roundedZero = value.abs() < 1 && double.parse(magnitude) == 0;
  final sign = roundedZero || value.isNaN ? 0 : value.sign.toInt();
  return (magnitude: magnitude, sign: sign);
}

extension MoneyDecimalText on num {
  String toMoneyDecimal() {
    final parts = moneyDisplayParts(this);
    return parts.sign < 0 ? '-${parts.magnitude}' : parts.magnitude;
  }
}

String formatMoney(double value, {String? currency, bool showPositiveSign = false}) {
  final displayCurrency = normalizeCurrency(currency ?? activeBaseCurrencyCode);
  final parts = moneyDisplayParts(value);
  final sign = parts.sign < 0 ? '-' : showPositiveSign && parts.sign > 0 ? '+' : '';
  return '$sign${currencyLabel(displayCurrency)} ${parts.magnitude}';
}

String formatMoneyValue(double value) {
  return value.abs().toStringAsFixed(2);
}

String currencyLabel(String currency) {
  switch (normalizeCurrency(currency)) {
    case 'MYR':
      return 'RM';
    case 'USD':
      return 'US\$';
    case 'CNY':
      return 'RMB';
    case 'TWD':
      return 'NT\$';
    default:
      return normalizeCurrency(currency);
  }
}

String currencyOptionLabel(String currency) {
  final normalized = normalizeCurrency(currency);
  final label = currencyLabel(normalized);
  return label == normalized ? normalized : '$normalized ($label)';
}

String normalizeCurrency(String currency) => currency.trim().toUpperCase();

List<String> normalizedCurrencyOrder(Iterable<String> requested) {
  final ordered = requested.map(normalizeCurrency).where((c) => c.isNotEmpty);
  return List.unmodifiable({...ordered, ...supportedCurrencies});
}

List<String> storedCurrencyOrder(String? raw) {
  if (raw != null) {
    try {
      final value = jsonDecode(raw);
      if (value is List) {
        return normalizedCurrencyOrder(value.whereType<String>());
      }
    } on FormatException {
      // A malformed local preference has no usable ordering.
    }
  }
  return List.unmodifiable(supportedCurrencies);
}

bool _validRate(double rate) => rate > 0 && rate.isFinite;

/// Quotes are units of the selected base per unit of the key currency.
Map<String, double> normalizedExchangeRatesToBase(
  Map<String, double>? rates, {
  String baseCurrency = baseCurrencyCode,
}) {
  final base = normalizeCurrency(baseCurrency);
  final quotes = <String, double>{};
  for (final entry in (rates ?? const <String, double>{}).entries) {
    final code = normalizeCurrency(entry.key);
    if (code.isEmpty || quotes.containsKey(code) || !_validRate(entry.value)) {
      throw FormatException('无效汇率：${entry.key}');
    }
    quotes[code] = entry.value;
  }
  quotes[base] = 1;
  // The built-in quotes are MYR-based. Bridge them through an explicit MYR
  // quote, the selected base's built-in quote, or another known currency.
  double? myrRate = quotes[baseCurrencyCode];
  final baseInMyr = defaultExchangeRatesToBase[base];
  if (myrRate == null && baseInMyr != null) myrRate = 1 / baseInMyr;
  if (myrRate == null) {
    for (final entry in defaultExchangeRatesToBase.entries) {
      final explicit = quotes[entry.key];
      if (explicit != null) {
        myrRate = explicit / entry.value;
        break;
      }
    }
  }
  if (myrRate != null) {
    for (final entry in defaultExchangeRatesToBase.entries) {
      final derived = entry.value * myrRate;
      if (_validRate(derived)) quotes.putIfAbsent(entry.key, () => derived);
    }
  }
  return Map.unmodifiable(quotes);
}

/// Import rejects malformed values. An already damaged local quote is kept
/// unavailable so the user can repair it without losing access to the ledger.
Map<String, double> readCurrencyQuotes(String? raw, String baseCurrency,
    {bool strict = false}) {
  final base = normalizeCurrency(baseCurrency);
  if (raw == null || raw.trim().isEmpty) {
    return normalizedExchangeRatesToBase(null, baseCurrency: base);
  }
  Object? data;
  try {
    data = jsonDecode(raw);
  } on FormatException {
    if (strict) rethrow;
  }
  if (data is! Map<String, dynamic>) {
    if (strict) throw const FormatException('汇率数据必须是对象。');
    return Map.unmodifiable({base: 1.0});
  }
  final quotes = <String, double>{};
  final invalid = <String>{};
  for (final entry in data.entries) {
    final code = normalizeCurrency(entry.key);
    final rate = double.tryParse('${entry.value}');
    if (code.isEmpty ||
        quotes.containsKey(code) ||
        invalid.contains(code) ||
        rate == null ||
        !_validRate(rate)) {
      if (strict) throw FormatException('无效汇率：${entry.key}');
      invalid.add(code);
    } else {
      quotes[code] = rate;
    }
  }
  quotes.removeWhere((code, _) => invalid.contains(code));
  final result =
      Map.of(normalizedExchangeRatesToBase(quotes, baseCurrency: base));
  for (final code in invalid.where((code) => code != base)) {
    result.remove(code);
  }
  return Map.unmodifiable(result);
}

double? exchangeRateToBase(
  String currency,
  Map<String, double> ratesToBase, {
  String baseCurrency = baseCurrencyCode,
}) {
  final code = normalizeCurrency(currency);
  if (code == normalizeCurrency(baseCurrency)) return 1;
  final quote = ratesToBase[code];
  return quote != null && _validRate(quote) ? quote : null;
}

double? tryConvertCurrencyAmount({
  required double amount,
  required String fromCurrency,
  required String toCurrency,
  required Map<String, double> ratesToBase,
  String baseCurrency = baseCurrencyCode,
}) {
  if (!amount.isFinite) return null;
  if (normalizeCurrency(fromCurrency) == normalizeCurrency(toCurrency)) {
    return amount;
  }
  final from =
      exchangeRateToBase(fromCurrency, ratesToBase, baseCurrency: baseCurrency);
  final to =
      exchangeRateToBase(toCurrency, ratesToBase, baseCurrency: baseCurrency);
  if (from == null || to == null) return null;
  final converted = amount * from / to;
  if (converted.isFinite) return converted;
  final alternative = (amount / to) * from;
  return alternative.isFinite ? alternative : null;
}

double convertCurrencyAmount({
  required double amount,
  required String fromCurrency,
  required String toCurrency,
  required Map<String, double> ratesToBase,
  String baseCurrency = baseCurrencyCode,
}) {
  final result = tryConvertCurrencyAmount(
      amount: amount,
      fromCurrency: fromCurrency,
      toCurrency: toCurrency,
      ratesToBase: ratesToBase,
      baseCurrency: baseCurrency);
  if (result == null) throw FormatException('无法折算 $fromCurrency → $toCurrency');
  return result;
}

String formatConversionHint({
  required double amount,
  required String fromCurrency,
  required String toCurrency,
  required Map<String, double> ratesToBase,
  String baseCurrency = baseCurrencyCode,
}) {
  final converted = tryConvertCurrencyAmount(
    amount: amount,
    fromCurrency: fromCurrency,
    toCurrency: toCurrency,
    ratesToBase: ratesToBase,
    baseCurrency: baseCurrency,
  );
  if (converted == null) return '$fromCurrency → $toCurrency 未估值';
  return '≈ ${formatMoney(converted, currency: toCurrency)}';
}
