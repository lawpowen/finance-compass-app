import 'package:drift/native.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/services/currency_service.dart';
import 'package:finance_app/src/core/utils/currency_formatter.dart';
import 'package:finance_app/src/features/shared/compass_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('amounts that round to zero have no minus sign at the selected precision', () {
    setCompassMoneyStyle(useCurrencyCode: true, useEuropeanSeparators: false);
    addTearDown(() => setCompassMoneyStyle(useCurrencyCode: true, useEuropeanSeparators: false));
    for (final zero in [-0.0, 0.3 - (0.1 + 0.2), -0.0049]) {
      expect(formatMoney(zero, currency: 'MYR'), 'RM 0.00');
      expect(compassMoney(zero, currency: 'MYR'), 'MYR 0.00');
      expect(compassMoney(zero, showCurrency: false), '0.00');
    }
    expect(formatMoney(-0.005, currency: 'MYR'), '-RM 0.01');
    expect((-0.004).toMoneyDecimal(), '0.00');
    expect((-0.005).toMoneyDecimal(), '-0.01');
    expect(compassMoney(0.004, currency: 'MYR', showPositiveSign: true), 'MYR 0.00');
    expect(compassMoney(0.005, currency: 'MYR', showPositiveSign: true), '+ MYR 0.01');
    expect(compassMoney(-0.006, currency: 'MYR'), '- MYR 0.01');
    expect(compassMoney(-0.49, decimals: 0, showCurrency: false), '0');
    expect(compassMoney(-0.5, decimals: 0, showCurrency: false), '-1');
    setCompassMoneyStyle(useCurrencyCode: false, useEuropeanSeparators: true);
    expect(compassMoney(-0.004, currency: 'USD'), 'US\$ 0,00');
    expect(compassMoney(-0.004, currency: 'USD', decimals: 3), '- US\$ 0,004');
  });

  test('formats supported currencies with user-facing labels', () {
    expect(formatMoney(12.5, currency: 'MYR'), 'RM 12.50');
    expect(formatMoney(12.5, currency: 'USD'), 'US\$ 12.50');
    expect(formatMoney(12.5, currency: 'CNY'), 'RMB 12.50');
    expect(formatMoney(12.5, currency: 'TWD'), 'NT\$ 12.50');
  });

  test('preserves normalized historical currency codes', () {
    expect(normalizeCurrency('usd'), 'USD');
    expect(normalizeCurrency(' sgd '), 'SGD');
    expect(formatMoney(10, currency: 'sgd'), 'SGD 10.00');
  });

  test('converts between account currencies through MYR base rates', () {
    final rates = normalizedExchangeRatesToBase({
      'MYR': 1,
      'TWD': 0.15,
      'USD': 4.5,
    });

    expect(
      convertCurrencyAmount(
        amount: 150,
        fromCurrency: 'MYR',
        toCurrency: 'TWD',
        ratesToBase: rates,
      ),
      1000,
    );
    expect(
      convertCurrencyAmount(
        amount: 1000,
        fromCurrency: 'TWD',
        toCurrency: 'MYR',
        ratesToBase: rates,
      ),
      150,
    );
  });

  test(
      'missing quotes are rebased from MYR and explicit MYR anchors take precedence',
      () {
    final defaults =
        normalizedExchangeRatesToBase({'USD': 1}, baseCurrency: 'USD');
    expect(defaults['CNY'], closeTo(.65 / 4.7, 1e-12));
    final saved =
        normalizedExchangeRatesToBase({'MYR': .25}, baseCurrency: 'USD');
    expect(saved['CNY'], .65 * .25);
    expect(
        tryConvertCurrencyAmount(
            amount: 100,
            fromCurrency: 'EUR',
            toCurrency: 'USD',
            ratesToBase: saved,
            baseCurrency: 'USD'),
        isNull);
    expect(
        tryConvertCurrencyAmount(
            amount: 100,
            fromCurrency: 'EUR',
            toCurrency: 'EUR',
            ratesToBase: saved,
            baseCurrency: 'USD'),
        100);
    expect(
        formatConversionHint(
            amount: 100,
            fromCurrency: 'EUR',
            toCurrency: 'USD',
            ratesToBase: saved,
            baseCurrency: 'USD'),
        contains('未估值'));
    for (final rate in [double.nan, double.infinity, 0.0, -2.0]) {
      expect(
          () =>
              normalizedExchangeRatesToBase({'USD': rate}, baseCurrency: 'USD'),
          throwsFormatException);
    }
  });

  test(
      'unpriced historical accounts and goals survive a backup and accept their own quotes',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final empty = await FinanceRepository.load(db);
    var ledger = await empty.addAccount(const Account(
        id: 'myr',
        name: 'Cash',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        initialBalance: 300,
        currentBalance: 300));
    ledger = await ledger.addAccount(const Account(
        id: 'eur',
        name: 'Euro cash',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'EUR',
        initialBalance: -100,
        currentBalance: -100));
    ledger = await ledger.addAssetGoal(
        name: 'Mixed assets', amount: 10, currency: 'SGD');
    expect(ledger.unpricedCurrencies, {'EUR', 'SGD'});
    expect(ledger.totalAssets(), 300);
    expect(ledger.assetGoalSummaries().single.valuationAvailable, isFalse);
    expect(ledger.assetGoalSummaries().single.isReached, isFalse);
    expect(ledger.assetGoalSummaries().single.reachedAt, isNull);
    final snapshot = await ledger.buildJsonSnapshotPayload();
    ledger = await ledger.restoreSyncedSnapshot(snapshot);
    expect(ledger.accounts.singleWhere((a) => a.id == 'eur').currency, 'EUR');
    expect(ledger.assetGoals.single.currency, 'SGD');
    expect(ledger.unpricedCurrencies, {'EUR', 'SGD'});

    ledger = await ledger
        .updateExchangeRates({'EUR': 4, 'SGD': 3, 'USD': 4}, ['MYR', 'USD']);
    expect(ledger.unpricedCurrencies, isEmpty);
    expect(ledger.totalAssets(), -100);
    ledger = await ledger.updateExchangeRates({'MYR': .25}, ['USD', 'MYR']);
    expect(ledger.exchangeRatesToBase['EUR'], 1);
    expect(ledger.exchangeRatesToBase['SGD'], .75);
    expect(ledger.totalAssets(), -25);
    expect(ledger.assetGoalSummaries().single.valuationAvailable, isTrue);
    expect(ledger.assetGoalSummaries().single.targetAmountInBase, 7.5);
    final facade = CurrencyService(database: db, metaValues: ledger.metaValues);
    expect(facade.convertToBase(100, 'EUR'), ledger.convertToBase(100, 'EUR'));
    expect(facade.exchangeRatesToBase, ledger.exchangeRatesToBase);
  });

  test(
      'invalid quotes are rejected on write and import; already-damaged local rates remain unpriced',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var ledger = await FinanceRepository.load(db);
    ledger = await ledger.addAccount(const Account(
        id: 'usd',
        name: 'USD cash',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'USD',
        initialBalance: 20,
        currentBalance: 20));
    for (final rate in [double.infinity, double.nan, 0.0, -1.0]) {
      await expectLater(
          ledger.updateExchangeRates({'USD': rate}, ['MYR', 'USD']),
          throwsFormatException);
    }
    final snapshot = await ledger.buildJsonSnapshotPayload();
    (snapshot['meta'] as Map)['exchange_rates_to_base_json'] = '{"USD":"NaN"}';
    await expectLater(
        ledger.restoreSyncedSnapshot(snapshot), throwsFormatException);
    expect((await ledger.refresh()).accounts.single.currentBalance, 20);
    await db.setMetaValue(
        'exchange_rates_to_base_json', '{"USD":"Infinity","SGD":3}');
    ledger = await ledger.refresh();
    expect(ledger.unpricedCurrencies, {'USD'});
    expect(
        ledger.tryConvertAmount(
            amount: 20, fromCurrency: 'USD', toCurrency: 'MYR'),
        isNull);
    expect(ledger.convertToBase(20, 'SGD'), 60);
    expect(ledger.totalAssets(), 0);
    expect(ledger.accounts.single.currentBalance, 20);
  });

  test('uses selected base currency for default money display', () {
    setActiveBaseCurrency('TWD');
    expect(formatMoney(12.5), 'NT\$ 12.50');

    setActiveBaseCurrency('MYR');
    expect(formatMoney(12.5), 'RM 12.50');
  });

  test('Compass typography defaults to the ledger currency', () {
    addTearDown(() {
      setActiveBaseCurrency(baseCurrencyCode);
      setCompassMoneyStyle(useCurrencyCode: true, useEuropeanSeparators: false);
    });
    setActiveBaseCurrency('TWD');
    setCompassMoneyStyle(useCurrencyCode: true, useEuropeanSeparators: false);

    expect(compassMoney(-1234.5), '- TWD 1,234.50');
    expect(compassMoney(12.5, currency: 'USD'), 'USD 12.50');

    setCompassMoneyStyle(useCurrencyCode: false, useEuropeanSeparators: false);
    expect(compassMoney(12.5), 'NT\$ 12.50');
  });
}
