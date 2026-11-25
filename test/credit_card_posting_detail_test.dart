import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/database_provider.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/features/accounts/credit_card_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'card payment posts to the next source bill but clears PayLater on the payment day',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const payer = Account(
      id: 'uob',
      name: 'UOB Lazada Credit Card',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      currentBalance: 0,
      creditLimit: 5000,
      statementDay: 25,
      paymentDueDay: 14,
    );
    const payLater = Account(
      id: 'laz',
      name: 'Laz PayLater',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: -241.94,
      currentBalance: -241.94,
      creditLimit: 2000,
      statementDay: 10,
      paymentDueDay: 25,
    );
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await FinanceRepository.load(db);
    repo = await repo.addAccount(payer);
    repo = await repo.addAccount(payLater);
    final paymentDay = DateTime(2026, 11, 25);
    repo = await repo.addTransactions([
      FinanceTransaction(
          id: 'ordinary',
          type: TransactionType.expense,
          accountId: payer.id,
          currency: 'MYR',
          amount: 12,
          merchant: 'November purchase',
          transactionDate: paymentDay),
      FinanceTransaction(
          id: 'later',
          type: TransactionType.expense,
          accountId: payer.id,
          currency: 'MYR',
          amount: 30,
          merchant: 'Later purchase',
          transactionDate: DateTime(2026, 11, 26, 12)),
    ]);
    final scope = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(scope.dispose);
    await scope.read(financeRepositoryProvider.future);
    Future<void> open(Account account, {DateTime? cutoff}) async {
      await tester.pumpWidget(UncontrolledProviderScope(
          container: scope,
          child: MaterialApp(
              home: CreditCardDetailScreen(
                  key: ValueKey(account.id),
                  account: account,
                  repository: repo,
                  cutoffDate: cutoff))));
      await tester.pumpAndSettle();
    }

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await open(payLater);
    await tap(find.byKey(const Key('record-credit-card-repayment')));
    await tap(find.byKey(const Key('credit-card-repayment-source-uob')));
    await tap(find.byKey(const Key('credit-card-repayment-date')));
    final picker = find.byType(DatePickerDialog);
    final localization = MaterialLocalizations.of(tester.element(picker));
    await tap(find.byTooltip(localization.inputDateModeButtonLabel));
    await tester.enterText(
        find.descendant(of: picker, matching: find.byType(TextFormField)),
        localization.formatCompactDate(paymentDay));
    await tap(find.descendant(
        of: picker, matching: find.text(localization.okButtonLabel)));
    await tap(find.text('顺延至转出卡下期账单'));
    expect(find.textContaining('计入 12月账单'), findsOneWidget);
    await tap(find.byKey(const Key('credit-card-repayment-confirm')));
    repo = await scope.read(financeRepositoryProvider.future);
    final transfer = repo.transactions
        .singleWhere((t) => t.type == TransactionType.transfer);
    expect(transfer.amount, 241.94);
    expect(DateUtils.dateOnly(transfer.transactionDate), paymentDay);
    expect(transfer.cardPostingDate, DateTime(2026, 11, 26));
    expect(
        repo
            .creditCardBillingSummary(payLater.id, now: paymentDay)
            .billedBalance,
        0);

    // Reopen at the end of the economic day. Tomorrow's known posting is
    // visible, while tomorrow's separate purchase is outside this historical cutoff.
    await open(payer,
        cutoff:
            DateTime(2026, 11, 26).subtract(const Duration(microseconds: 1)));
    expect(find.text('November purchase'), findsOneWidget);
    expect(find.text('信用卡转出 · Laz PayLater'), findsNothing);
    await tap(find.text('未出账'));
    expect(find.text('11月25日 · 入账 11月26日'), findsOneWidget);
    expect(find.text('信用卡转出 · Laz PayLater'), findsOneWidget);
    expect(find.text('Later purchase'), findsNothing);
    await tap(find.byKey(const Key('credit-card-statement-picker')));
    await tap(find.byKey(const Key('credit-card-statement-2026-12')));
    expect(find.text('11月25日 · 入账 11月26日'), findsOneWidget);
    expect(find.text('November purchase'), findsNothing);
    expect(find.text('Later purchase'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
