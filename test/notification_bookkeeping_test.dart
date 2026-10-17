import 'dart:convert';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/notifications/notification_bookkeeper.dart';
import 'package:finance_app/src/core/notifications/notification_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const payment =
    'Payment of MYR 12.34 to SHOP was successful. Ref: ABC12345 Card: **1234';
const bindings = [
  {'package': 'example.bank', 'accountId': 'bank', 'marker': 'Card: **1234'}
];
Map<String, dynamic> event(String id,
        {String text = payment, String? key, String title = 'Payment'}) =>
    {
      'id': id,
      'key': key ?? id,
      'package': 'example.bank',
      'text': text,
      'title': title,
      'postedAt': DateTime.now().millisecondsSinceEpoch,
    };

void main() {
  late AppDatabase db;
  late NotificationBookkeeper bookkeeper;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bookkeeper = NotificationBookkeeper(db);
    await db.insertAccount(const Account(
        id: 'bank',
        name: 'Bank',
        accountType: AccountType.bankSaving,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        initialBalance: 100,
        currentBalance: 100));
  });
  tearDown(() => db.close());

  test('strict successful payment parses reference and money', () {
    final parsed = parsePaymentNotification(payment);
    expect(parsed.isClear, isTrue);
    expect(parsed.amount, 12.34);
    expect(parsed.currency, 'MYR');
    expect(parsed.reference, 'ABC12345');
    expect(parsed.merchant, 'SHOP');
  });

  for (final text in [
    'Payment failed MYR 12.34',
    'OTP 123456 MYR 12.34',
    'Refund of MYR 12.34 successful',
    'Transfer MYR 12.34 successful',
    'Payment pending MYR 12.34',
    'Payment of MYR 12.34 to SHOP was successful.',
    '$payment Balance MYR 87.66',
    'If $payment',
    payment.replaceFirst('12.34', '0.00'),
    payment.replaceFirst('12.34', '12.345'),
    payment.replaceFirst('12.34', '-12.34'),
  ]) {
    test('uncertain input stays pending: $text',
        () => expect(parsePaymentNotification(text).isClear, isFalse));
  }

  test('atomic auto-post, replay and undo preserve balances', () async {
    final input = event('one');
    await bookkeeper.ingest(input, bindings, enabled: true);
    await bookkeeper.ingest(input, bindings, enabled: true);
    expect((await db.fetchTransactions()).length, 1);
    expect((await db.fetchAccounts()).single.currentBalance,
        closeTo(87.66, 0.001));
    expect((await bookkeeper.record('one'))!['state'], 'posted');
    await bookkeeper.undo('one');
    await bookkeeper.ingest(input, bindings, enabled: true);
    expect(await db.fetchTransactions(), isEmpty);
    expect((await db.fetchAccounts()).single.currentBalance, 100);
    expect((await bookkeeper.record('one'))!['state'], 'undone');
  });

  test(
      'same reference or changed notification is reviewable, not another debit',
      () async {
    await bookkeeper.ingest(event('one', key: 'same'), bindings, enabled: true);
    await bookkeeper.ingest(event('two'), bindings, enabled: true);
    await bookkeeper.ingest(
        event('three',
            key: 'same', text: payment.replaceFirst('12.34', '20.00')),
        bindings,
        enabled: true);
    expect((await db.fetchTransactions()).length, 1);
    expect((await bookkeeper.record('two'))!['state'], 'pending');
    expect((await bookkeeper.record('three'))!['state'], 'pending');
  });

  test('unknown amount, ambiguous binding, disabled mode and title fail closed',
      () async {
    await bookkeeper.ingest(
        event('one', text: 'You have a payment Card: **1234'), bindings,
        enabled: true);
    await bookkeeper.ingest(event('two'), [...bindings, ...bindings],
        enabled: true);
    await bookkeeper.ingest(event('three'), bindings, enabled: false);
    await bookkeeper.ingest(event('four', title: 'Payment failed'), bindings,
        enabled: true);
    await bookkeeper.ingest(
        event('five', text: payment.replaceFirst('MYR', 'USD')), bindings,
        enabled: true);
    await bookkeeper.ingest(event('six'), [], enabled: true);
    expect(await db.fetchTransactions(), isEmpty);
    expect((await bookkeeper.records()).every((r) => r['state'] == 'pending'),
        isTrue);
  });

  test('manual confirmation can correct to income and cannot double-submit',
      () async {
    await bookkeeper.ingest(
        event('one', text: 'Unknown MYR 20.00 Card: **1234'), bindings,
        enabled: true);
    final draft = FinanceTransaction(
        id: 'draft',
        type: TransactionType.income,
        accountId: 'bank',
        amount: 20,
        currency: 'MYR',
        transactionDate: DateTime(2026, 1, 2));
    await bookkeeper.confirm('one', draft);
    await expectLater(bookkeeper.confirm('one', draft), throwsStateError);
    expect((await db.fetchTransactions()).single.transactionDate,
        DateTime(2026, 1, 2));
    expect((await db.fetchAccounts()).single.currentBalance, 120);
  });

  test('failed confirmation rolls back receipt and balance', () async {
    await bookkeeper.ingest(
        event('one', text: 'Unknown Card: **1234'), bindings,
        enabled: true);
    await expectLater(
        bookkeeper.confirm(
            'one',
            FinanceTransaction(
                id: 'draft',
                type: TransactionType.expense,
                accountId: 'missing',
                amount: 12,
                currency: 'MYR',
                transactionDate: DateTime.now())),
        throwsStateError);
    expect((await bookkeeper.record('one'))!['state'], 'pending');
    expect((await db.fetchAccounts()).single.currentBalance, 100);
    expect(await db.fetchTransactions(), isEmpty);
  });

  test('missing receipt routes existing notification transaction to review',
      () async {
    await db.insertTransaction(FinanceTransaction(
        id: 'notification_one',
        type: TransactionType.expense,
        accountId: 'bank',
        amount: 1,
        currency: 'MYR',
        transactionDate: DateTime.now()));
    await bookkeeper.ingest(event('one'), bindings, enabled: true);
    expect((await bookkeeper.record('one'))!['state'], 'pending');
    expect((await db.fetchAccounts()).single.currentBalance, 99);
  });

  test('delayed or reconfigured event requires confirmation', () async {
    await bookkeeper.ingest({
      ...event('old'),
      'postedAt': DateTime.now()
          .subtract(const Duration(hours: 25))
          .millisecondsSinceEpoch
    }, bindings, enabled: true);
    await bookkeeper.ingest(
        {...event('changed'), 'configurationChanged': true}, bindings,
        enabled: true);
    expect(await db.fetchTransactions(), isEmpty);
    expect((await bookkeeper.records()).every((r) => r['state'] == 'pending'),
        isTrue);
  });

  test('explicit income credits bound account', () async {
    await bookkeeper.ingest(
        event('income',
            text:
                'Received MYR 25.00 from COMPANY successfully. Transaction ID: INCOME123 Account: **1234'),
        [
          {
            'package': 'example.bank',
            'accountId': 'bank',
            'marker': 'Account: **1234'
          }
        ],
        enabled: true);
    expect((await db.fetchTransactions()).single.type, TransactionType.income);
    expect((await db.fetchAccounts()).single.currentBalance, 125);
  });

  test('nearby manual transaction routes to review rather than suppressing',
      () async {
    await db.insertTransaction(FinanceTransaction(
        id: 'manual',
        type: TransactionType.expense,
        accountId: 'bank',
        amount: 12.34,
        currency: 'MYR',
        transactionDate: DateTime.now()));
    await bookkeeper.ingest(event('one'), bindings, enabled: true);
    expect((await bookkeeper.record('one'))!['state'], 'pending');
    expect((await db.fetchTransactions()).length, 1);
  });

  test('ignore is durable and does not change balance', () async {
    final input = event('one', text: 'Unknown Card: **1234');
    await bookkeeper.ingest(input, bindings, enabled: true);
    await bookkeeper.ignore('one');
    await bookkeeper.ingest(input, bindings, enabled: true);
    expect((await bookkeeper.record('one'))!['state'], 'ignored');
    expect((await db.fetchAccounts()).single.currentBalance, 100);
  });

  test(
      'full snapshot preserves receipts and AI summary excludes raw notifications',
      () async {
    await bookkeeper.ingest(
        event('one', text: 'PRIVATE_RAW_TEXT Card: **1234'), bindings,
        enabled: true);
    final repo = await FinanceRepository.load(db);
    final payload = await repo.buildJsonSnapshotPayload();
    expect(jsonEncode(payload), contains('PRIVATE_RAW_TEXT'));
    final ai = utf8.decode(repo.exportAiSummaryBytes(monthKeys: ['2026-10']));
    expect(ai, isNot(contains('PRIVATE_RAW_TEXT')));
  });
}
