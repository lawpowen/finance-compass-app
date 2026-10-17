import 'package:drift/native.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/notifications/notification_bookkeeper.dart';
import 'package:finance_app/src/core/notifications/notification_parser.dart';
import 'package:finance_app/src/core/notifications/notification_sources.dart';
import 'package:flutter_test/flutter_test.dart';

// Public Android identities verified in MALAYSIA_BANK_NOTIFICATION_RESEARCH.
// All notification text below is synthetic; it is NOT a bank template.
const bankPackages = {
  'Maybank': 'com.maybank2u.life',
  'CIMB': 'com.cimb.cimbocto',
  'Public Bank': 'com.pbb.mypb',
  'RHB': 'com.rhbgroup.rhbmobilebanking',
  'Hong Leong Bank': 'my.com.hongleongconnect.mobileconnect',
  'AmBank': 'com.ambank.ambankonline',
  'Bank Islam': 'com.bankislam.bimbmobile',
  'Bank Rakyat': 'com.irakyatmob.bkrm',
  'BSN': 'com.bsn.mybsn',
  'Affin Bank': 'com.affin.mobilebanking',
};

const clearPayment =
    'Payment of MYR 12.34 to SHOP was successful. Ref: ABC12345 Card: **1234';

void main() {
  late AppDatabase db;
  late NotificationBookkeeper bookkeeper;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bookkeeper = NotificationBookkeeper(db);
    await db.insertAccount(const Account(
      id: 'bank',
      name: '银行账户',
      accountType: AccountType.bankSaving,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      initialBalance: 100,
      currentBalance: 100,
    ));
  });
  tearDown(() => db.close());

  Map<String, dynamic> event(String package, String text,
          {String id = 'one'}) =>
      {
        'id': id,
        'key': id,
        'package': package,
        'title': 'Transaction notification',
        'text': text,
        'postedAt': DateTime.now().millisecondsSinceEpoch,
      };

  Map<String, dynamic> binding(String package) => {
        'package': package,
        'accountId': 'bank',
        'marker': '',
        'reviewOnly': true,
      };

  test('catalog covers ten distinct banks and TNG without regional aliases',
      () {
    expect(malaysiaBankNotificationSources.length, 10);
    expect(reviewOnlyNotificationSources.length, 11);
    expect(
        reviewOnlyNotificationSources.map((s) => s.packageName).toSet().length,
        11);
    for (final bank in bankPackages.entries) {
      expect(notificationSourceFor(bank.value)?.institution, bank.key);
      expect(notificationSourceFor('${bank.value}.fake'), isNull);
      expect(notificationSourceFor(bank.value.toUpperCase()), isNull);
    }
    expect(notificationSourceFor(null), isNull);
    expect(notificationSourceFor('MAE by Maybank2u'), isNull);
  });

  for (final bank in bankPackages.entries) {
    test('${bank.key}: old automatic bindings cannot bypass required review',
        () async {
      for (final reviewOnly in [null, false]) {
        final id = '$reviewOnly';
        await bookkeeper.ingest(
          event(bank.value, clearPayment, id: id),
          [
            {
              'package': bank.value,
              'accountId': 'bank',
              'marker': 'Card: **1234',
              if (reviewOnly != null) 'reviewOnly': reviewOnly,
            },
          ],
          enabled: true,
        );
        final item = (await bookkeeper.record(id))!;
        expect(item['state'], 'pending');
        expect(item['accountId'], 'bank');
        expect(item['amount'], 12.34);
        expect(item['currency'], 'MYR');
        expect(item['type'], isNull);
        expect(item['reference'], isNull);
        expect(item['reason'], contains('尚未完成验证'));
      }
      expect(await db.fetchTransactions(), isEmpty);
      expect((await db.fetchAccounts()).single.currentBalance, 100);
    });

    test('${bank.key}: source-only intake confirms once and can be undone',
        () async {
      final notification = event(bank.value, 'Transaction amount MYR 12.34');
      final sources = [binding(bank.value)];
      await bookkeeper.ingest(notification, sources, enabled: true);
      await bookkeeper.ingest(notification, sources, enabled: true);
      final item = (await bookkeeper.record('one'))!;
      expect(item['state'], 'pending');
      expect(item['accountId'], 'bank');
      expect((await bookkeeper.records()).length, 1);
      expect(await db.fetchTransactions(), isEmpty);
      final draft = FinanceTransaction(
        id: 'draft',
        type: TransactionType.expense,
        accountId: 'bank',
        amount: 12.34,
        currency: 'MYR',
        transactionDate: DateTime.now(),
      );
      await bookkeeper.confirm('one', draft);
      await expectLater(bookkeeper.confirm('one', draft), throwsStateError);
      expect((await db.fetchTransactions()).length, 1);
      expect((await db.fetchAccounts()).single.currentBalance,
          closeTo(87.66, 0.001));
      await bookkeeper.undo('one');
      await bookkeeper.ingest(notification, sources, enabled: true);
      expect(await db.fetchTransactions(), isEmpty);
      expect((await db.fetchAccounts()).single.currentBalance, 100);
      expect((await bookkeeper.record('one'))!['state'], 'undone');
    });
  }

  test(
      'authorization, failed, reward, refund and multi-amount texts stay drafts',
      () {
    for (final package in bankPackages.values) {
      for (final text in [
        'Approve purchase MYR 12.34',
        'Sila luluskan transaksi RM12.34',
        'Payment failed MYR 12.34',
        'Refund MYR 12.34',
        'Cashback reward MYR 12.34',
        'Payment MYR 12.34 Balance MYR 87.66',
        'Received MYR 12.34 from COMPANY successfully. Ref: ABC12345 Account: **1234',
      ]) {
        final parsed = parsePaymentNotification(text, sourcePackage: package);
        expect(parsed.isClear, isFalse);
        expect(parsed.type, isNull);
        if (text.contains('Balance')) expect(parsed.amount, isNull);
      }
    }
  });

  test(
      'multiple accounts or a mismatched optional marker do not guess accounts',
      () async {
    final package = bankPackages['Maybank']!;
    final source = binding(package);
    await bookkeeper.ingest(event(package, clearPayment), [source, source],
        enabled: true);
    expect((await bookkeeper.record('one'))!['accountId'], isNull);
    await bookkeeper.ingest(
        event(package, clearPayment, id: 'other'),
        [
          {...source, 'marker': 'Card: **5678'},
        ],
        enabled: true);
    expect((await bookkeeper.record('other'))!['accountId'], isNull);
    expect(await db.fetchTransactions(), isEmpty);
  });

  test('similar package does not inherit a bank binding', () async {
    final package = bankPackages['Maybank']!;
    await bookkeeper.ingest(
        event('$package.fake', clearPayment), [binding(package)],
        enabled: true);
    expect((await bookkeeper.record('one'))!['accountId'], isNull);
    expect(await db.fetchTransactions(), isEmpty);
  });

  test('generic strict parser outside the catalog remains available', () {
    expect(
        parsePaymentNotification(clearPayment, sourcePackage: 'example.bank')
            .isClear,
        isTrue);
  });
}
