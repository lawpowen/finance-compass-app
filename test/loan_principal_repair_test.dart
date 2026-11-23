import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

const _marker = 'loan_principal_repair_v1';
const _cash = Account(
  id: 'cash',
  name: 'Cash',
  accountType: AccountType.bankSaving,
  reportGroup: ReportGroup.cash,
  currency: 'MYR',
  currentBalance: 5000,
  initialBalance: 5000,
);

Account _loan({
  String id = 'loan',
  double balance = -1200,
  double? annualRate = 12,
  double openingBalance = -1200,
  DateTime? trackingStart,
}) =>
    Account(
      id: id,
      name: id,
      accountType: AccountType.loan,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      currentBalance: balance,
      initialBalance: openingBalance,
      loanPrincipal: 1200,
      loanAnnualInterestRate: annualRate,
      loanTermMonths: 12,
      loanStartDate: DateTime(2026, 1, 1),
      loanTrackingStartDate: trackingStart,
      loanPaymentDay: 20,
      loanRepaymentMethod: LoanRepaymentMethod.equalPrincipal,
    );

FinanceTransaction _payment(
  int number, {
  double? incoming,
  double? amount,
  String? id,
  String loanId = 'loan',
  String payer = 'cash',
  String currency = 'MYR',
  TransactionStatus status = TransactionStatus.actual,
  DateTime? when,
}) =>
    FinanceTransaction(
      id: id ?? 'txn_loan_payment_${1000 + number}',
      type: TransactionType.transfer,
      accountId: payer,
      toAccountId: loanId,
      currency: currency,
      toCurrency: 'MYR',
      amount: amount ?? 113.0 - number,
      toAmount: incoming,
      description: '贷款月供 #$number',
      transactionDate: when ?? DateTime(2026, 1 + number, 20),
      status: status,
    );

double _balance(FinanceRepository repo, String id) =>
    repo.accounts.singleWhere((account) => account.id == id).currentBalance;

void main() {
  test('opening an old ledger restores principal and posted balances once',
      () async {
    final dir = await Directory.systemTemp.createTemp('loan-repair-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/ledger.sqlite');
    final old = AppDatabase.forTesting(NativeDatabase(file));
    final first = _payment(1, when: DateTime(2026, 2, 18));
    final second =
        _payment(2, incoming: 111, status: TransactionStatus.settled);
    final planned = _payment(3,
        id: 'txn_loan_payment_plan_2000_3', status: TransactionStatus.planned);
    final healthy = _payment(4, incoming: 99);
    try {
      await old.insertAccount(_cash);
      await old.insertAccount(_loan());
      await old.insertTransactions([first, second, planned, healthy]);
      final before = await FinanceRepository.load(old);
      expect(_balance(before, 'loan'), -878);
      expect(_balance(before, 'cash'), 4668);
      await old
          .customStatement('DELETE FROM app_meta WHERE key = ?', [_marker]);
    } finally {
      await old.close();
    }

    for (var reopen = 0; reopen < 2; reopen++) {
      final database = AppDatabase.forTesting(NativeDatabase(file));
      try {
        final repo = await FinanceRepository.load(database);
        expect(_balance(repo, 'loan'), -901);
        expect(_balance(repo, 'cash'), 4668);
        expect(repo.accountBalanceAt('loan', DateTime(2026, 2, 28)), -1100);
        final byId = {for (final row in repo.transactions) row.id: row};
        expect(byId.length, 4);
        expect(byId[first.id]!.toAmount, 100);
        expect(byId[first.id]!.transactionDate, first.transactionDate);
        expect(byId[second.id]!.toAmount, 100);
        expect(byId[second.id]!.status, TransactionStatus.settled);
        expect(byId[planned.id]!.toAmount, 100);
        expect(byId[planned.id]!.status, TransactionStatus.planned);
        expect(byId[healthy.id]!.toAmount, 99);

        final journal =
            jsonDecode((await database.getMetaValue(_marker))!) as List;
        final rows = {
          for (final item in journal.cast<Map>()) item['transaction_id']: item
        };
        expect(rows.keys, unorderedEquals([first.id, second.id, planned.id]));
        expect(rows[first.id]!['previous_to_amount'], isNull);
        expect(rows[second.id]!['previous_to_amount'], 111);
        expect(rows[planned.id]!['balance_delta'], 0);
      } finally {
        await database.close();
      }
    }
  });

  test(
      'full import repairs old rows even with a marker and uses tracking principal',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    Future<void> restore(List<Account> accounts,
            List<FinanceTransaction> payments, String marker) =>
        database.replaceAllWithSeedData(
          accountItems: accounts,
          categoryItems: [],
          budgetItems: [],
          transactionItems: payments,
          snapshotItems: [],
          metaValues: {_marker: marker},
        );

    // Up to the previous repayment period, the remaining principal was 600.
    // The first tracked payment is 100 principal + 6 interest in May.
    final trackingStart = DateTime(2026, 4, 1);
    const investment = Account(
      id: 'investment',
      name: 'Investment',
      accountType: AccountType.fund,
      reportGroup: ReportGroup.investment,
      currency: 'MYR',
      currentBalance: 4894,
      initialBalance: 5000,
    );
    final payments = [
      _payment(1,
          amount: 106,
          id: 'txn_loan_payment_plan_upgrade_2000_1',
          when: DateTime(2026, 5, 20),
          status: TransactionStatus.planned),
      _payment(1,
          amount: 106, payer: investment.id, when: DateTime(2026, 5, 19)),
    ];
    await restore([
      _cash,
      investment,
      _loan(balance: -494, openingBalance: -600, trackingStart: trackingStart),
    ], payments, '[]');
    final repaired = await FinanceRepository.load(database);
    expect(repaired.transactions.map((row) => row.toAmount), [100, 100]);
    expect(_balance(repaired, 'loan'), -500);
    expect(_balance(repaired, investment.id), 4894);

    final journal = (await database.getMetaValue(_marker))!;
    await restore(repaired.accounts, repaired.transactions, journal);
    final reimported = await FinanceRepository.load(database);
    expect(reimported.transactions.map((row) => row.toAmount), [100, 100]);
    expect(_balance(reimported, 'loan'), -500);
    expect(_balance(reimported, investment.id), 4894);
    expect(await database.getMetaValue(_marker), journal);
  });

  test('incomplete, duplicate, unrelated and uncertain rows are left alone',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    const usd = Account(
        id: 'usd',
        name: 'USD',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'USD',
        currentBalance: 1000);
    final rows = [
      _payment(1),
      _payment(1,
          id: 'txn_loan_payment_3001', status: TransactionStatus.settled),
      _payment(2, amount: 120),
      _payment(3, id: 'manual-transfer'),
      _payment(4,
          id: 'txn_loan_payment_plan_4000_4',
          status: TransactionStatus.planned,
          when: DateTime(2026, 5, 19)),
      _payment(5, payer: 'usd', currency: 'USD', incoming: 503),
      _payment(13, amount: 100),
      _payment(6, loanId: 'free-loan', amount: 100, incoming: 100),
      _payment(7, loanId: 'bad-loan'),
      _payment(8, loanId: 'cash'),
      _payment(9,
          id: 'txn_loan_payment_plan_4000_10',
          status: TransactionStatus.planned),
    ];
    await database.replaceAllWithSeedData(
      accountItems: [
        _cash,
        usd,
        _loan(),
        _loan(id: 'free-loan', annualRate: 0),
        _loan(id: 'bad-loan', annualRate: null)
      ],
      categoryItems: [],
      budgetItems: [],
      transactionItems: rows,
      snapshotItems: [],
    );
    final repo = await FinanceRepository.load(database);
    final byId = {for (final row in repo.transactions) row.id: row.toAmount};
    expect(byId, {for (final row in rows) row.id: row.toAmount});
    expect(_balance(repo, 'loan'), -1200);
    expect(await database.getMetaValue(_marker), '[]');
  });
}
