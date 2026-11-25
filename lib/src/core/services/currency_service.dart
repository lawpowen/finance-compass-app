import '../data/finance_repository.dart';
import '../database/app_database.dart' show AppDatabase;

/// Read-only currency queries over a ledger revision.
class CurrencyService {
  CurrencyService(
      {required AppDatabase database, required Map<String, String> metaValues})
      : this.fromRepository(FinanceRepository.fromSnapshot(
            database: database, metaValues: metaValues));
  const CurrencyService.fromRepository(this.repository);

  final FinanceRepository repository;
  AppDatabase get database => repository.database;
  Map<String, String> get metaValues => repository.metaValues;
  String get baseCurrency => repository.baseCurrency;
  List<String> get currencyPriority => repository.currencyPriority;
  String? get secondaryCurrency => repository.secondaryCurrency;
  Map<String, double> get exchangeRatesToBase => repository.exchangeRatesToBase;
  bool hasExchangeRate(String code) => repository.hasExchangeRate(code);
  double convertAmount(
          {required double amount,
          required String fromCurrency,
          required String toCurrency}) =>
      repository.convertAmount(
          amount: amount, fromCurrency: fromCurrency, toCurrency: toCurrency);
  double convertToBase(double amount, String code) =>
      repository.convertToBase(amount, code);
  double convertFromBase(double amount, String code) =>
      repository.convertFromBase(amount, code);
  String conversionHintForAmount(double amount, String code) =>
      repository.conversionHintForAmount(amount, code);
}
