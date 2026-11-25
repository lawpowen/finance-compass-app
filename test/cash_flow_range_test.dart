import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exact forecast range includes only dated cash and credit movements',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    repository = await repository.addAccount(
      const Account(
        id: 'cash',
        name: '现金',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 0,
      ),
    );
    repository = await repository.addAccount(
      const Account(
        id: 'invest',
        name: '投资',
        accountType: AccountType.trading,
        reportGroup: ReportGroup.investment,
        currency: 'MYR',
        currentBalance: 0,
      ),
    );
    repository = await repository.addTransactions([
      _transaction('income', TransactionType.income, 100, DateTime(2026, 8, 2)),
      _transaction(
          'expense', TransactionType.expense, 40, DateTime(2026, 8, 5)),
      _transaction(
        'outside',
        TransactionType.expense,
        50,
        DateTime(2026, 9, 1),
      ),
      FinanceTransaction(
        id: 'transfer',
        type: TransactionType.transfer,
        accountId: 'cash',
        toAccountId: 'invest',
        amount: 20,
        currency: 'MYR',
        transactionDate: DateTime(2026, 8, 8),
        status: TransactionStatus.planned,
      ),
      FinanceTransaction(
        id: 'investment-expense',
        type: TransactionType.expense,
        accountId: 'invest',
        amount: 999,
        currency: 'MYR',
        transactionDate: DateTime(2026, 8, 9),
        status: TransactionStatus.planned,
      ),
    ]);

    expect(
      repository.cashFlowNetBetween(
        startInclusive: DateTime(2026, 8, 1),
        endInclusive: DateTime(2026, 8, 31),
      ),
      40,
    );
  });
  test('closing a card does not remove an unpaid statement from cash needs',
      () async {
    var repo = await _ledger([
      _cash,
      const Account(
          id: 'closed',
          name: 'Closed card',
          accountType: AccountType.creditCard,
          reportGroup: ReportGroup.credit,
          currency: 'MYR',
          currentBalance: 0,
          creditLimit: 1000,
          statementDay: 1,
          paymentDueDay: 12),
    ]);
    repo = await repo.addTransaction(
        _spend('purchase', 'closed', 100, 'MYR', DateTime(2026, 9, 25)));
    repo = await repo.setAccountActive('closed', false);
    final forecast = repo.cashForecast(
        asOf: DateTime(2026, 10, 2), endInclusive: DateTime(2026, 10, 12));
    expect(forecast.openingCash - forecast.endingCash, 100);
    expect(repo.monthlyFundingNeedForMonth('2026-10').totalCashRequired, 100);
  });

  test('each card uses its own statement and the same end-of-day cash cutoff',
      () async {
    var repo = await _ledger([
      _cash,
      _invest,
      _card('first', 'MYR', 10, 25),
      _card('second', 'MYR', 20, 28),
    ]);
    repo = await repo.addTransactions([
      _spend('a', 'first', 100, 'MYR', DateTime(2026, 10, 5)),
      _spend('b', 'second', 200, 'MYR', DateTime(2026, 10, 12)),
      _pay('same-day', 'first', 40, DateTime(2026, 10, 10, 15)),
      _pay('scheduled', 'second', 50, DateTime(2026, 10, 22), planned: true),
      _pay('noncash-plan', 'second', 150, DateTime(2026, 10, 23),
          source: 'invest', planned: true),
    ]);
    var month = repo.monthlyFundingNeedForMonth('2026-10');
    expect(month.knownCashOutflow, 90);
    expect(month.creditDue, 300);
    expect(month.coveredDebtPayments, 90);
    expect(month.totalCashRequired, 300);
    final actualOnly =
        repo.monthlyFundingNeedForMonth('2026-10', includePlanned: false);
    expect(actualOnly.knownCashOutflow, 40);
    expect(actualOnly.coveredDebtPayments, 40);
    expect(actualOnly.totalCashRequired, 300);

    repo = await repo.addTransaction(_pay(
        'settled-from-investment', 'second', 70, DateTime(2026, 10, 24),
        source: 'invest'));
    month = repo.monthlyFundingNeedForMonth('2026-10');
    expect(month.creditDue, 230);
    expect(month.coveredDebtPayments, 90);
    expect(month.totalCashRequired, 230);
  });

  test(
      'foreign bills appear when due, cross-currency payments debit actual cash once',
      () async {
    var repo = await _ledger([
      _cash,
      _card('usd', 'USD', 5, 18),
      _card('cny', 'CNY', 25, 3),
      _card('local', 'MYR', 20, 28),
    ]);
    repo = await repo.updateExchangeRates(
        {'MYR': 1, 'USD': 4, 'CNY': .5, 'TWD': .15},
        ['MYR', 'USD', 'CNY', 'TWD']);
    repo = await repo.addTransactions([
      _spend('cny1', 'cny', 40, 'CNY', DateTime(2026, 9, 20)),
      _spend('local1', 'local', 80, 'MYR', DateTime(2026, 9, 24)),
      _spend('usd1', 'usd', 100, 'USD', DateTime(2026, 10, 3)),
      _spend('usd2', 'usd', 50, 'USD', DateTime(2026, 10, 24)),
      _pay('cash-fx', 'usd', 210, DateTime(2026, 10, 4, 15),
          planned: true, toAmount: 50, toCurrency: 'USD'),
    ]);
    final forecast = repo.cashForecast(
        asOf: DateTime(2026, 10, 1), endInclusive: DateTime(2026, 11, 28));
    expect(forecast.openingCash, 1000);
    expect(forecast.balanceAt(DateTime(2026, 10, 3)), 980);
    expect(forecast.balanceAt(DateTime(2026, 10, 4)), 770);
    expect(forecast.balanceAt(DateTime(2026, 10, 18)), 570);
    expect(forecast.balanceAt(DateTime(2026, 10, 28)), 490);
    expect(forecast.creditDue, 700);
    expect(forecast.uncoveredCreditDue, 500);
    expect(forecast.endingCash, 290);
  });

  for (final planned in [false, true]) {
    test('card pays PayLater before maturity, planned=$planned', () async {
      final payLater = _card('paylater', 'MYR', 1, 12);
      final payer = _card('payer', 'MYR', 20, 5);
      var repo = await _ledger([_cash, payLater, payer]);
      final paymentDay = DateTime(2026, 10, 11);
      repo = await repo.addTransactions([
        _spend('purchase', 'paylater', 100, 'MYR', DateTime(2026, 9, 26)),
        if (planned)
          _pay('refinance', payLater.id, 100, paymentDay,
              source: payer.id, planned: true),
        _pay('bank-payment', 'payer', 40, DateTime(2026, 11, 4), planned: true),
      ]);
      if (!planned) {
        repo = await repo.recordCreditCardRepayment(
            card: payLater,
            source: payer,
            amount: 100,
            paymentDate: paymentDay);
      }
      expect(
          repo
              .creditCardBillingSummary(payLater.id, now: paymentDay)
              .billedBalance,
          planned ? 100 : 0);
      expect(
          repo
              .creditCardBillingSummary(payer.id, now: DateTime(2026, 10, 20))
              .billedBalance,
          planned ? 0 : 100);
      final asOf = DateTime(2026, 10, 10);
      final forecast =
          repo.cashForecast(asOf: asOf, endInclusive: DateTime(2026, 11, 5));
      expect(forecast.balanceAt(DateTime(2026, 10, 11)), 1000);
      expect(forecast.balanceAt(DateTime(2026, 10, 12)), 1000);
      expect(forecast.balanceAt(DateTime(2026, 11, 4)), 960);
      expect(forecast.endingCash, 900);
      final november = repo.monthlyFundingNeedForMonth('2026-11', asOf: asOf);
      expect(november.creditDue, 100);
      expect(november.coveredDebtPayments, 40);
      expect(november.totalCashRequired, 100);
      expect(
          repo
              .monthlyFundingNeedForMonth('2026-10',
                  asOf: asOf, includePlanned: false)
              .creditDue,
          planned ? 100 : 0);
    });
  }

  test('a late card repayment releases only the refinanced part of a due bill',
      () async {
    var repo = await _ledger([
      _cash,
      _card('paylater', 'MYR', 1, 12),
      _card('payer', 'MYR', 20, 5),
    ]);
    repo = await repo.addTransactions([
      _spend('purchase', 'paylater', 100, 'MYR', DateTime(2026, 9, 26)),
      _pay('refinance', 'paylater', 80, DateTime(2026, 10, 13),
          source: 'payer'),
    ]);
    final asOf = DateTime(2026, 10, 10);
    final forecast =
        repo.cashForecast(asOf: asOf, endInclusive: DateTime(2026, 11, 5));
    expect(forecast.balanceAt(DateTime(2026, 10, 12)), 900);
    expect(forecast.balanceAt(DateTime(2026, 10, 13)), 980);
    expect(forecast.endingCash, 900);
    expect(forecast.creditDue, 100);
    final october = repo.monthlyFundingNeedForMonth('2026-10', asOf: asOf);
    expect(october.knownCashOutflow, 0);
    expect(october.creditDue, 20);
    expect(october.coveredDebtPayments, 0);
    expect(october.totalCashRequired, 20);
  });

  test(
      'a payer without billing dates uses the next-month estimate for a new card-funded charge',
      () async {
    var repo = await _ledger([
      _cash,
      _card('paylater', 'MYR', 1, 12),
      const Account(
          id: 'payer',
          name: 'Card without dates',
          currency: 'MYR',
          accountType: AccountType.creditCard,
          reportGroup: ReportGroup.credit,
          currentBalance: 0),
    ]);
    repo = await repo.addTransactions([
      _spend('purchase', 'paylater', 100, 'MYR', DateTime(2026, 10, 24)),
      FinanceTransaction(
          id: 'refinance',
          accountId: 'payer',
          toAccountId: 'paylater',
          type: TransactionType.transfer,
          amount: 100,
          currency: 'MYR',
          transactionDate: DateTime(2026, 11, 3),
          cardPostingDate: DateTime(2026, 12, 2)),
    ]);
    final forecast = repo.cashForecast(
        asOf: DateTime(2026, 10, 30), endInclusive: DateTime(2026, 12, 25));
    expect(forecast.balanceAt(DateTime(2026, 11, 12)), 1000);
    expect(forecast.balanceAt(DateTime(2026, 12, 24)), 1000);
    expect(forecast.endingCash, 900);
    final alreadyOccurred = repo.cashForecast(
        asOf: DateTime(2026, 11, 3), endInclusive: DateTime(2026, 12, 25));
    expect(alreadyOccurred.endingCash, 900);
  });

  for (final planned in [false, true]) {
    test(
        'UOB funds Laz on November 25 and cash is due only January 14, planned=$planned',
        () async {
      final uob = _card('uob', 'MYR', 25, 14);
      final laz = _card('laz', 'MYR', 10, 25);
      var repo = await _ledger([_cash, uob, laz]);
      final day = DateTime(2026, 11, 25);
      final posting = DateTime(2026, 11, 26);
      repo = await repo.addTransaction(
          _spend('laz-purchase', laz.id, 241.94, 'MYR', DateTime(2026, 11, 5)));
      if (planned) {
        repo = await repo.addTransaction(FinanceTransaction(
            id: 'planned-card-payment',
            type: TransactionType.transfer,
            accountId: uob.id,
            toAccountId: laz.id,
            amount: 241.94,
            currency: 'MYR',
            transactionDate: day,
            cardPostingDate: posting,
            status: TransactionStatus.planned));
      } else {
        repo = await repo.recordCreditCardRepayment(
            card: laz,
            source: uob,
            amount: 241.94,
            paymentDate: day,
            cardPostingDate: posting);
        expect(repo.creditCardCommittedOutstandingBalance(uob.id), 241.94);
        expect(
            repo.accountBalanceAt(laz.id, DateTime(2026, 11, 25, 23, 59, 59)),
            0);
        final reminders = repo.creditCardPaymentReminders(asOf: day);
        expect(reminders, isEmpty);
        final closed =
            repo.creditCardPaymentReminders(asOf: DateTime(2026, 12, 25));
        expect(closed.single.account.id, uob.id);
        expect(closed.single.amountDue, 241.94);
        expect(closed.single.dueDate, DateTime(2027, 1, 14));
      }
      for (final asOf in [DateTime(2026, 11, 24), if (!planned) day]) {
        final forecast =
            repo.cashForecast(asOf: asOf, endInclusive: DateTime(2027, 1, 14));
        expect(forecast.balanceAt(day), 1000);
        expect(forecast.balanceAt(DateTime(2026, 12, 14)), 1000);
        expect(forecast.balanceAt(DateTime(2027, 1, 13)), 1000);
        expect(forecast.endingCash, closeTo(758.06, 0.00001));
        expect(forecast.uncoveredCreditDue, 241.94);
      }
      final asOf = DateTime(2026, 11, 24);
      expect(
          repo
              .monthlyFundingNeedForMonth('2026-12', asOf: asOf)
              .totalCashRequired,
          0);
      expect(
          repo
              .monthlyFundingNeedForMonth('2027-01', asOf: asOf)
              .totalCashRequired,
          241.94);
    });
  }

  test('month-end purchase posted December 2 is funded on January 15',
      () async {
    final card = _card('payer', 'MYR', 30, 15);
    var repo = await _ledger([_cash, card]);
    repo = await repo.addTransaction(FinanceTransaction(
        id: 'cut-day-purchase',
        accountId: card.id,
        type: TransactionType.expense,
        currency: 'MYR',
        amount: 150,
        transactionDate: DateTime(2026, 11, 30, 16),
        cardPostingDate: DateTime(2026, 12, 2)));
    final forecast = repo.cashForecast(
        asOf: DateTime(2026, 11, 30), endInclusive: DateTime(2027, 1, 15));
    expect(forecast.balanceAt(DateTime(2026, 12, 15)), 1000);
    expect(forecast.balanceAt(DateTime(2027, 1, 14)), 1000);
    expect(forecast.endingCash, 850);
    expect(forecast.uncoveredCreditDue, 150);
    expect(repo.monthlyFundingNeedForMonth('2026-12').totalCashRequired, 0);
    expect(repo.monthlyFundingNeedForMonth('2027-01').totalCashRequired, 150);
  });

  test('both short-month statements can mature on the same payment date',
      () async {
    var repo = await _ledger([_cash, _card('card', 'MYR', 30, 31)]);
    repo = await repo.addTransactions([
      _spend('feb-charge', 'card', 100, 'MYR', DateTime(2026, 2, 2)),
      _spend('mar-charge', 'card', 70, 'MYR', DateTime(2026, 3, 2)),
      _pay('march-cash', 'card', 120, DateTime(2026, 3, 31), planned: true),
    ]);
    final forecast = repo.cashForecast(
        asOf: DateTime(2026, 2, 15), endInclusive: DateTime(2026, 3, 31));
    expect(forecast.creditDue, 170);
    expect(forecast.uncoveredCreditDue, 50);
    expect(forecast.endingCash, 830);
    final month =
        repo.monthlyFundingNeedForMonth('2026-03', asOf: DateTime(2026, 2, 15));
    expect(month.totalCashRequired, 170);
    expect(month.coveredDebtPayments, 120);
  });

  test(
      'a scheduled advance before a future month reduces that month opening obligation',
      () async {
    var repo = await _ledger([_cash, _card('card', 'MYR', 25, 10)]);
    repo = await repo.addTransactions([
      _spend('jan-charge', 'card', 100, 'MYR', DateTime(2026, 1, 20)),
      _pay('early-cash', 'card', 60, DateTime(2026, 1, 30), planned: true),
    ]);
    final feb =
        repo.monthlyFundingNeedForMonth('2026-02', asOf: DateTime(2026, 1, 26));
    expect(feb.creditDue, 40);
    expect(feb.knownCashOutflow, 0);
    expect(feb.coveredDebtPayments, 0);
    expect(feb.totalCashRequired, 40);
    final actual = repo.monthlyFundingNeedForMonth('2026-02',
        asOf: DateTime(2026, 1, 26), includePlanned: false);
    expect(actual.totalCashRequired, 100);
  });

  test(
      'a merchant refund after maturity stays on the card and funds a later bill',
      () async {
    var repo = await _ledger([_cash, _card('card', 'MYR', 1, 12)]);
    repo = await repo.addTransactions([
      _spend('sep-purchase', 'card', 100, 'MYR', DateTime(2026, 9, 25)),
      _spend('merchant-refund', 'card', -100, 'MYR', DateTime(2026, 10, 13)),
      _spend('oct-purchase', 'card', 160, 'MYR', DateTime(2026, 10, 16)),
    ]);
    final forecast = repo.cashForecast(
        asOf: DateTime(2026, 10, 11), endInclusive: DateTime(2026, 11, 15));
    expect(forecast.balanceAt(DateTime(2026, 10, 12)), 900);
    expect(forecast.balanceAt(DateTime(2026, 10, 13)), 900);
    expect(forecast.balanceAt(DateTime(2026, 11, 12)), 840);
    expect(repo.monthlyFundingNeedForMonth('2026-10').totalCashRequired, 100);
  });

  test(
      'a later cash settlement can replace only the bill amount left after a noncash payment',
      () async {
    var repo = await _ledger([_cash, _invest, _card('card', 'USD', 1, 12)]);
    repo = await repo.updateExchangeRates(
        {'MYR': 1, 'USD': 4, 'CNY': .5, 'TWD': .15},
        ['MYR', 'USD', 'CNY', 'TWD']);
    repo = await repo.addTransactions([
      _spend('purchase', 'card', 100, 'USD', DateTime(2026, 9, 25)),
      _pay('noncash', 'card', 160, DateTime(2026, 10, 13, 9),
          source: 'invest', toAmount: 40, toCurrency: 'USD'),
      _pay('cash', 'card', 320, DateTime(2026, 10, 13, 15),
          planned: true, toAmount: 80, toCurrency: 'USD'),
    ]);
    final forecast = repo.cashForecast(
        asOf: DateTime(2026, 10, 10), endInclusive: DateTime(2026, 10, 31));
    expect(forecast.balanceAt(DateTime(2026, 10, 12)), 600);
    // USD 40 settled via investments. Only the USD 60 remaining on that
    // bill offsets the late cash posting. The excess USD 20 is an advance.
    expect(forecast.endingCash, 520);
    expect(forecast.uncoveredCreditDue, 160);
  });

  test(
      'late repayment replaces the same projected bill and cannot debit it twice',
      () async {
    var repo = await _ledger([_cash, _card('card', 'MYR', 1, 12)]);
    repo = await repo.addTransactions([
      _spend('spent', 'card', 100, 'MYR', DateTime(2026, 9, 25)),
      _pay('late-payment', 'card', 100, DateTime(2026, 10, 20, 10)),
    ]);
    final forecast = repo.cashForecast(
        asOf: DateTime(2026, 10, 10), endInclusive: DateTime(2026, 10, 31));
    expect(forecast.openingCash, 1000);
    expect(forecast.balanceAt(DateTime(2026, 10, 12)), 900);
    expect(forecast.balanceAt(DateTime(2026, 10, 20)), 900);
    expect(forecast.uncoveredCreditDue, 0);
    expect(forecast.endingCash, 900);
    final bill =
        repo.creditCardPaymentReminders(asOf: DateTime(2026, 10, 10)).single;
    expect(bill.billingMonthDate.month, 9);
  });

  test(
      'cash funding allocates a cross-period advance and reversal only to their installment',
      () async {
    var repo = await _ledger([
      _cash,
      Account(
          id: 'loan',
          name: 'Loan',
          currency: 'MYR',
          accountType: AccountType.loan,
          reportGroup: ReportGroup.credit,
          initialBalance: -1200,
          currentBalance: -1200,
          loanPrincipal: 1200,
          loanAnnualInterestRate: 0,
          loanTermMonths: 3,
          loanStartDate: DateTime(2026, 1, 1),
          loanPaymentDay: 10,
          loanRepaymentMethod: LoanRepaymentMethod.equalPrincipal),
    ]);
    repo = await repo.addTransactions([
      _pay('prior-partial', 'loan', 120, DateTime(2026, 1, 25), number: 1),
      _pay('next-period', 'loan', 400, DateTime(2026, 2, 8), number: 2),
      _pay('part', 'loan', 100, DateTime(2026, 2, 9), number: 1, planned: true),
      _pay('reversal', 'loan', -40, DateTime(2026, 2, 12), number: 1),
      _pay('unallocated', 'loan', 25, DateTime(2026, 2, 15)),
    ]);
    final need = repo.monthlyFundingNeedForMonth('2026-02');
    expect(need.loanDue, 280);
    expect(need.knownCashOutflow, 525);
    expect(need.cashInflow, 40);
    expect(need.coveredDebtPayments, 60);
    expect(need.totalCashRequired, 745);
    expect(repo.monthlyFundingNeedForMonth('2026-03').loanDue, 0);
  });
}

const _cash = Account(
    id: 'cash',
    name: 'Cash',
    currency: 'MYR',
    accountType: AccountType.cash,
    reportGroup: ReportGroup.cash,
    currentBalance: 1000);
const _invest = Account(
    id: 'invest',
    name: 'Investment',
    currency: 'MYR',
    accountType: AccountType.trading,
    reportGroup: ReportGroup.investment,
    currentBalance: 500);

Account _card(String id, String currency, int statement, int due) => Account(
    id: id,
    name: id,
    currency: currency,
    accountType: AccountType.creditCard,
    reportGroup: ReportGroup.credit,
    currentBalance: 0,
    creditLimit: 3000,
    statementDay: statement,
    paymentDueDay: due);

Future<FinanceRepository> _ledger(List<Account> accounts) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  var repo = await FinanceRepository.load(db);
  for (final account in accounts) {
    repo = await repo.addAccount(account);
  }
  return repo;
}

FinanceTransaction _spend(String id, String account, double amount,
        String currency, DateTime date) =>
    FinanceTransaction(
        id: id,
        accountId: account,
        amount: amount,
        type: TransactionType.expense,
        currency: currency,
        transactionDate: date);

FinanceTransaction _pay(String id, String target, double amount, DateTime date,
        {String source = 'cash',
        double? toAmount,
        String toCurrency = 'MYR',
        int? number,
        bool planned = false}) =>
    FinanceTransaction(
        id: id,
        accountId: source,
        toAccountId: target,
        type: TransactionType.transfer,
        amount: amount,
        toAmount: toAmount ?? (number != null ? amount : null),
        currency: 'MYR',
        toCurrency: toCurrency,
        loanInstallmentNumber: number,
        transactionDate: date,
        status: planned ? TransactionStatus.planned : TransactionStatus.actual);

FinanceTransaction _transaction(
  String id,
  TransactionType type,
  double amount,
  DateTime date,
) =>
    FinanceTransaction(
      id: id,
      type: type,
      accountId: 'cash',
      amount: amount,
      currency: 'MYR',
      transactionDate: date,
      status: TransactionStatus.planned,
    );
