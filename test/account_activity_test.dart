import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/database_provider.dart';
import 'package:finance_app/src/core/providers/mutations/account_mutations.dart';
import 'package:finance_app/src/core/providers/mutations/transaction_mutations.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/accounts/account_form_dialog.dart';
import 'package:finance_app/src/features/accounts/credit_card_detail_screen.dart';
import 'package:finance_app/src/features/accounts/repayment_account_picker.dart';
import 'package:finance_app/src/features/transactions/transaction_composer_page.dart';
import 'package:finance_app/src/features/transactions/transaction_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/amount_entry.dart';

Account bank(String id) => Account(
    id: id,
    name: id,
    accountType: AccountType.bankSaving,
    reportGroup: ReportGroup.cash,
    currency: 'MYR',
    initialBalance: 100,
    currentBalance: 100);

FinanceTransaction transfer(String id, String source, String target,
        {double amount = 10}) =>
    FinanceTransaction(
        id: id,
        type: TransactionType.transfer,
        accountId: source,
        toAccountId: target,
        amount: amount,
        currency: 'MYR',
        transactionDate: DateTime(2026, 1, 3));

Future<(AppDatabase, FinanceRepository)> setup() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  var repo = await FinanceRepository.load(db);
  for (final id in ['A', 'B', 'C']) {
    repo = await repo.addAccount(bank(id));
  }
  return (db, repo);
}

void main() {
  Account debt(String id,
          {AccountType type = AccountType.creditCard,
          String currency = 'MYR',
          bool active = true}) =>
      Account(
          id: id,
          name: id,
          accountType: type,
          reportGroup: ReportGroup.credit,
          currency: currency,
          isActive: active,
          currentBalance: 0,
          creditLimit: 5000,
          statementDay: 20,
          paymentDueDay: 10);

  test(
      'card repayment offers cash before other active cards in the same currency; loans require cash',
      () async {
    final (db, _) = await setup();
    final repo = FinanceRepository.fromSnapshot(database: db, accounts: [
      debt('payer'),
      debt('PayLater'),
      debt('loan', type: AccountType.loan),
      bank('cash'),
      debt('disabled', active: false),
      debt('USD card', currency: 'USD'),
      debt('second payer'),
      bank('other cash'),
    ]);
    expect(repo.repaymentSources('PayLater').map((a) => a.id),
        ['cash', 'other cash', 'payer', 'second payer']);
    expect(
        repo.repaymentSources('loan').map((a) => a.id), ['cash', 'other cash']);
    expect(repo.repaymentSources('disabled'), isEmpty);
    expect(repo.repaymentSources('cash'), isEmpty);
  });

  test(
      'saving a repayment rechecks account activity after the source was picked',
      () async {
    final (_, original) = await setup();
    final card = debt('PayLater');
    final payer = debt('other card');
    var oldLedger = await original.addAccount(card);
    oldLedger = await oldLedger.addAccount(payer);
    expect(oldLedger.repaymentSources(card.id).map((a) => a.id),
        contains(payer.id));
    await oldLedger.setAccountActive(payer.id, false);
    await expectLater(
        oldLedger.recordCreditCardRepayment(
          card: card,
          source: payer,
          amount: 30,
          paymentDate: DateTime.now(),
        ),
        throwsFormatException);
    expect((await oldLedger.refresh()).transactions, isEmpty);
  });

  testWidgets(
      'a backdated card-to-PayLater payment keeps its selected day and recording time',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (db, original) = await setup();
    final now = DateTime.now();
    final bill = debt('PayLater');
    final payer = debt('payer');
    var repo = await original.addAccount(bill);
    repo = await repo.addAccount(payer);
    repo = await repo.addTransaction(FinanceTransaction(
        id: 'purchase',
        type: TransactionType.expense,
        accountId: bill.id,
        currency: 'MYR',
        amount: 100,
        transactionDate: DateTime(now.year, now.month - 2, 1)));
    final scope = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(scope.dispose);
    await scope.read(financeRepositoryProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: scope,
        child: MaterialApp(
            home: CreditCardDetailScreen(account: bill, repository: repo))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('record-credit-card-repayment')));
    await tester.pumpAndSettle();
    final sourceTile =
        find.byKey(const Key('credit-card-repayment-source-payer'));
    expect(find.descendant(of: sourceTile, matching: find.text('信用卡 · MYR')),
        findsOneWidget);
    await tester.ensureVisible(sourceTile);
    await tester.tap(sourceTile);
    await tester.pumpAndSettle();
    await enterAmount(
        tester, find.byKey(const Key('credit-card-repayment-amount')), '70');
    await tester.tap(find.byKey(const Key('credit-card-repayment-date')));
    await tester.pumpAndSettle();
    final picker = find.byType(DatePickerDialog);
    expect(
        DateUtils.isSameDay(
            tester.widget<DatePickerDialog>(picker).initialDate, now),
        isTrue);
    final labels = MaterialLocalizations.of(tester.element(picker));
    await tester.tap(find.byTooltip(labels.previousMonthTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: picker, matching: find.text('15')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.descendant(of: picker, matching: find.text(labels.okButtonLabel)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('credit-card-repayment-confirm')));
    await tester.pumpAndSettle();
    final ledger = await scope.read(financeRepositoryProvider.future);
    final payment = ledger.transactions
        .singleWhere((t) => t.type == TransactionType.transfer);
    expect(payment.accountId, payer.id);
    expect(payment.toAccountId, bill.id);
    expect(payment.amount, 70);
    expect(payment.transactionDate, DateTime(now.year, now.month - 1, 15));
    expect(DateUtils.isSameDay(payment.recordDate, now), isTrue);
    expect(ledger.accounts.singleWhere((a) => a.id == bill.id).currentBalance,
        -30);
    expect(ledger.accounts.singleWhere((a) => a.id == payer.id).currentBalance,
        -70);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repayment source choices refresh while the sheet is open',
      (tester) async {
    final (db, initial) = await setup();
    const card = Account(
        id: 'card',
        name: 'Test card',
        accountType: AccountType.creditCard,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        currentBalance: -50);
    final repo = await initial.addAccount(card);
    final scope = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(scope.dispose);
    await scope.read(financeRepositoryProvider.future);
    Account? chosen;
    await tester.pumpWidget(UncontrolledProviderScope(
        container: scope,
        child: MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        chosen =
                            await pickRepaymentAccount(context, repo, card);
                      },
                      child: const Text('Pay')))),
        )));
    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();
    final old = find.byKey(const Key('credit-card-repayment-source-A'));
    expect(old, findsOneWidget);
    await scope.read(accountMutationsProvider.notifier).setActive('A', false);
    await tester.pumpAndSettle();
    expect(old, findsNothing);
    await tester.tap(find.byKey(const Key('credit-card-repayment-source-B')));
    await tester.pumpAndSettle();
    expect(chosen?.id, 'B');
  });

  test(
      'inactive accounts retain history and cannot acquire new transaction legs or presets',
      () async {
    final (db, original) = await setup();
    var repo = await original.addTransaction(transfer('history', 'A', 'B'));
    final rule = RecurringTransactionRule.fromTransaction(
        id: 'rule', name: 'Existing', transaction: transfer('seed', 'C', 'B'));
    repo = await repo.saveRecurringTransactionRule(rule);
    repo = await repo.setAccountActive('A', false);
    repo = await repo.setAccountActive('B', false);
    await expectLater(
        repo.generateRecurringTransactions('rule', asOf: DateTime(2026, 2)),
        throwsFormatException);
    expect(
        (await repo.refresh())
            .recurringTransactionRules
            .single
            .generatedMonthKeys,
        isEmpty);
    expect(repo.entryAccounts().map((a) => a.id), ['C']);
    expect(repo.entryAccounts(originalAccountId: 'B').map((a) => a.id),
        containsAll(['B', 'C']));

    await expectLater(
        repo.addTransaction(transfer('copy', 'A', 'B')), throwsFormatException);
    await expectLater(repo.addTransaction(transfer('new-target', 'C', 'B')),
        throwsFormatException);
    await expectLater(
        repo.addTransactionTemplate(
            name: 'New', transaction: transfer('draft', 'C', 'B')),
        throwsFormatException);
    await expectLater(
        repo.addRecurringTransactionRule(
            name: 'New', transaction: transfer('draft', 'C', 'B')),
        throwsFormatException);
    // Retaining the exact source and target still allows correcting an old record.
    repo = await repo
        .updateExistingTransaction(transfer('history', 'A', 'B', amount: 15));
    expect(repo.accounts.singleWhere((a) => a.id == 'A').currentBalance, 85);
    expect(repo.accounts.singleWhere((a) => a.id == 'B').currentBalance, 115);
    final encoded = await repo.buildJsonSnapshotPayload();
    await repo.restoreSyncedSnapshot(encoded);
    repo = await FinanceRepository.load(db);
    expect(repo.accounts.where((a) => a.isActive).single.id, 'C');
    expect(repo.transactions.single.id, 'history');
    repo = await repo.setAccountActive('A', true);
    await repo.addTransaction(transfer('again', 'A', 'C'));
  });

  testWidgets(
      'advanced form keeps original inactive legs only on an existing record',
      (tester) async {
    final (_, original) = await setup();
    final saved = transfer('existing', 'A', 'B');
    var repo = await original.addTransaction(saved);
    repo = await repo.setAccountActive('A', false);
    repo = await repo.setAccountActive('B', false);
    tester.view.physicalSize = const Size(520, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final editExisting in [false, true]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TransactionFormDialog(
        key: ValueKey(editExisting),
        repository: repo,
        initialTransaction: editExisting ? saved : null,
        draftTransaction: editExisting ? null : saved,
      ))));
      await tester.pumpAndSettle();
      DropdownButton<String> dropdown(String key) =>
          tester.widget(find.descendant(
              of: find.byKey(Key(key)),
              matching: find.byType(DropdownButton<String>)));
      final source = dropdown('entry-source-account');
      final target = dropdown('entry-target-account');
      expect(source.value, editExisting ? 'A' : null);
      expect(target.value, editExisting ? 'B' : null);
      expect(source.items!.map((item) => item.value).toSet(),
          editExisting ? {'A', 'C'} : {'C'});
      expect(target.items!.map((item) => item.value).toSet(),
          editExisting ? {'B', 'C'} : {'C'});
    }
  });

  testWidgets(
      'disabling or enabling saves only the status, even with a dirty invalid form',
      (tester) async {
    tester.view.physicalSize = const Size(520, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final (db, repo) = await setup();
    final scope = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(scope.dispose);
    await scope.read(financeRepositoryProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: scope,
        child: MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.abyss),
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showDialog<Account>(
                          context: context,
                          builder: (_) =>
                              AccountFormDialog.edit(bank('A'), repo)),
                      child: const Text('Edit')))),
        )));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    final name = find.byWidgetPredicate(
        (w) => w is TextFormField && w.controller?.text == 'A');
    await tester.enterText(name, '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await scope
        .read(transactionMutationsProvider.notifier)
        .addTransaction(transfer('later', 'A', 'C'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('停用账户'));
    await tester.tap(find.text('停用账户'));
    await tester.pumpAndSettle();
    final disabled = (await FinanceRepository.load(db))
        .accounts
        .singleWhere((a) => a.id == 'A');
    expect(disabled.isActive, isFalse);
    expect(disabled.name, 'A');
    expect(disabled.currentBalance, 90);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
        (await FinanceRepository.load(db))
            .accounts
            .singleWhere((a) => a.id == 'A')
            .isActive,
        isFalse);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('重新启用账户'));
    await tester.tap(find.text('重新启用账户'));
    await tester.pumpAndSettle();
    expect(
        (await FinanceRepository.load(db))
            .accounts
            .singleWhere((a) => a.id == 'A')
            .isActive,
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a new transfer drops inactive candidates and rechecks a deactivated selection',
      (tester) async {
    tester.view.physicalSize = const Size(520, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final (db, original) = await setup();
    final repo = await original.setAccountActive('A', false);
    final scope = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(scope.dispose);
    await scope.read(financeRepositoryProvider.future);
    final draft = transfer('draft', 'B', 'C');
    TransactionFormResult? result;
    await tester.pumpWidget(UncontrolledProviderScope(
        container: scope,
        child: MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.abyss),
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        result = await Navigator.of(context)
                            .push<TransactionFormResult>(MaterialPageRoute(
                                builder: (_) => TransactionComposerPage(
                                    repository: repo, draft: draft)));
                      },
                      child: const Text('Compose')))),
        )));
    await tester.tap(find.text('Compose'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OutlinedButton).first);
    await tester.pumpAndSettle();
    expect(find.text('A · MYR'), findsNothing);
    expect(find.text('B · MYR'), findsOneWidget);
    await scope.read(accountMutationsProvider.notifier).setActive('C', false);
    await tester.pumpAndSettle();
    expect(find.text('C · MYR'), findsNothing);
    await tester.tap(find.text('B · MYR'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存交易'));
    await tester.tap(find.text('保存交易'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.textContaining('转入账户已停用'), findsOneWidget);
    expect((await FinanceRepository.load(db)).transactions, isEmpty);
  });
}
