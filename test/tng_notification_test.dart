import 'package:drift/native.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/notifications/notification_bookkeeper.dart';
import 'package:finance_app/src/core/notifications/notification_parser.dart';
import 'package:flutter_test/flutter_test.dart';

// Synthetic employer, using the phrase in the official Payroll Handbook.
// The handbook is not evidence of an Android NotificationListener payload.
const payroll = 'You have received payment from SAMPLE EMPLOYER : RM1,700.00';
const tngBinding = {
  'package': tngEwalletPackage,
  'accountId': 'wallet',
  'marker': '',
  'reviewOnly': true,
};

void main() {
  late AppDatabase db;
  late NotificationBookkeeper bookkeeper;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bookkeeper = NotificationBookkeeper(db);
    await db.insertAccount(const Account(
      id: 'wallet',
      name: 'TNG',
      accountType: AccountType.eWallet,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      initialBalance: 100,
      currentBalance: 100,
    ));
  });
  tearDown(() => db.close());

  Map<String, dynamic> event(String text,
          {String package = tngEwalletPackage}) =>
      {
        'id': 'sample',
        'key': 'sample',
        'package': package,
        'title': 'TNG eWallet',
        'text': text,
        'postedAt': DateTime.now().millisecondsSinceEpoch,
      };

  test('official payroll phrase supplies a draft without authorizing auto-post',
      () {
    final parsed =
        parsePaymentNotification(payroll, sourcePackage: tngEwalletPackage);
    expect(parsed.isClear, isFalse);
    expect(parsed.type, TransactionType.income);
    expect(parsed.amount, 1700);
    expect(parsed.currency, 'MYR');
    expect(parsed.merchant, 'SAMPLE EMPLOYER');
    expect(parsed.reference, isNull);
  });

  test('payroll preview is scoped to the official package', () {
    final parsed =
        parsePaymentNotification(payroll, sourcePackage: 'another.app');
    expect(parsed.type, isNull);
    expect(parsed.isClear, isFalse);
  });

  // Negative cases are synthetic, not claimed to be real TNG notifications.
  for (final text in [
    'Payment of MYR 12.34 to SHOP was successful. Ref: ABC12345 Card: **1234',
    'Reload successful RM100.00',
    'Cashback reward RM5.00',
    'Approve payment RM20.00',
    'Refund successful RM12.34',
    'Paid RM12.34. Balance RM87.66',
  ]) {
    test('TNG content requires review: $text', () async {
      // Even a marker binding created by an older app cannot auto-post TNG.
      await bookkeeper.ingest(
          event(text),
          [
            {
              ...tngBinding,
              'marker': text.contains('Card: **1234') ? 'Card: **1234' : 'RM',
              'reviewOnly': false
            },
          ],
          enabled: true);
      expect((await bookkeeper.record('sample'))!['state'], 'pending');
      expect((await bookkeeper.record('sample'))!['accountId'], 'wallet');
      expect(await db.fetchTransactions(), isEmpty);
      expect((await db.fetchAccounts()).single.currentBalance, 100);
    });
  }

  test(
      'source-only binding preselects the account and manual confirmation posts once',
      () async {
    await bookkeeper.ingest(event(payroll), [tngBinding], enabled: true);
    final item = (await bookkeeper.record('sample'))!;
    expect(item['state'], 'pending');
    expect(item['accountId'], 'wallet');
    expect(item['type'], 'income');
    expect((await db.fetchAccounts()).single.currentBalance, 100);
    final draft = FinanceTransaction(
      id: 'draft',
      type: TransactionType.income,
      accountId: 'wallet',
      amount: 1700,
      currency: 'MYR',
      transactionDate: DateTime.now(),
    );
    await bookkeeper.confirm('sample', draft);
    await expectLater(bookkeeper.confirm('sample', draft), throwsStateError);
    expect((await db.fetchTransactions()).length, 1);
    expect((await db.fetchAccounts()).single.currentBalance, 1800);
  });

  test('ambiguous source-only bindings do not pick an account', () async {
    await bookkeeper.ingest(event(payroll), [tngBinding, tngBinding],
        enabled: true);
    expect((await bookkeeper.record('sample'))!['accountId'], isNull);
    expect(await db.fetchTransactions(), isEmpty);
  });

  test(
      'a review-only binding also prevents generic clear templates from posting',
      () async {
    const text = 'Payment of MYR 12.34 to SHOP was successful. Ref: ABC12345';
    await bookkeeper.ingest(
        event(text, package: 'another.app'),
        [
          {...tngBinding, 'package': 'another.app'},
        ],
        enabled: true);
    final item = (await bookkeeper.record('sample'))!;
    expect(item['state'], 'pending');
    expect(item['accountId'], 'wallet');
    expect(await db.fetchTransactions(), isEmpty);
  });

  test('an empty marker without review-only permission cannot match an account',
      () async {
    await bookkeeper.ingest(
        event(payroll),
        [
          {...tngBinding, 'reviewOnly': false},
        ],
        enabled: true);
    expect((await bookkeeper.record('sample'))!['accountId'], isNull);
    expect(await db.fetchTransactions(), isEmpty);
  });

  test('a display label or similar package cannot match the TNG binding',
      () async {
    await bookkeeper.ingest(
        event(payroll, package: '$tngEwalletPackage.fake'), [tngBinding],
        enabled: true);
    expect((await bookkeeper.record('sample'))!['accountId'], isNull);
    expect(await db.fetchTransactions(), isEmpty);
  });
}
