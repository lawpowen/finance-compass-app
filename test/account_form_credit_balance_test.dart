import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/database_provider.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/accounts/account_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/amount_entry.dart';

Account _card(double balance) => Account(
      id: 'card',
      name: 'Card',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: balance,
      currentBalance: balance,
      creditLimit: 5000,
      statementDay: 25,
      paymentDueDay: 14,
    );

const _balanceField = Key('credit-card-balance-field');

/// Opens the form for [initial]; the returned getter reads the popped result.
Future<Account? Function()> _openForm(
  WidgetTester tester,
  Account? initial, {
  double width = 390,
  String defaultCurrency = 'MYR',
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Account? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildFinanceTheme(AppThemeStyle.abyss),
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () async {
              result = await showDialog<Account>(
                context: context,
                builder: (_) => AccountFormDialog(
                  initialAccount: initial,
                  defaultCurrency: defaultCurrency,
                ),
              );
            },
            child: const Text('编辑信用卡'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('编辑信用卡'));
  await tester.pumpAndSettle();
  return () => result;
}

Future<void> _save(WidgetTester tester) async {
  // The form is a lazy ListView; the first Scrollable is its viewport.
  await tester.scrollUntilVisible(
    find.text('保存更改'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('保存更改'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('new credit card can be switched back to cash', (tester) async {
    await _openForm(tester, null);
    final picker = find.byType(DropdownButton<AccountType>);
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('信用卡').last);
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButton<AccountType>>(picker).value,
        AccountType.creditCard);
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('现金').last);
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButton<AccountType>>(picker).value,
        AccountType.cash);
  });
  testWidgets('a new account derives its balance from the opening balance',
      (tester) async {
    final result = await _openForm(tester, null);
    await tester.enterText(find.byType(TextFormField).first, 'Savings');
    final opening = find.byKey(const Key('account-opening-balance'));
    await tester.scrollUntilVisible(
      opening,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await enterAmount(tester, opening, '123.45');
    final current = find.byKey(const Key('account-current-balance'));
    await tester.ensureVisible(current);
    expect(amountController(tester, current).text, '123.45');
    await _save(tester);
    expect(result()!.initialBalance, 123.45);
    expect(result()!.currentBalance, 123.45);
  });

  testWidgets(
      'existing account editor locks balances and currency from ledger history',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await FinanceRepository.load(db);
    repo = await repo.addAccount(_card(-300));
    repo = await repo.addTransaction(FinanceTransaction(
      id: 'purchase',
      type: TransactionType.expense,
      accountId: 'card',
      currency: 'MYR',
      amount: 20,
      transactionDate: DateTime(2026, 1, 10),
    ));
    final reloaded = await FinanceRepository.load(db);
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
          home: AccountFormDialog.edit(reloaded.accounts.single, reloaded)),
    ));
    await tester.pumpAndSettle();
    final currency = tester.widget<DropdownButton<String>>(
      find.byWidgetPredicate((w) => w is DropdownButton<String>),
    );
    expect(currency.onChanged, isNull);
    await tester.scrollUntilVisible(find.byKey(_balanceField), 150,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(_balanceField));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('amount-key-C')), findsNothing);
    expect(amountController(tester, find.byKey(_balanceField)).text, '-320.00');
  });

  test('debt accounts have one legal reporting group', () {
    expect(allowedReportGroups(AccountType.loan), [ReportGroup.credit]);
    expect(allowedReportGroups(AccountType.creditCard), [ReportGroup.credit]);
    expect(allowedReportGroups(AccountType.bankSaving), [ReportGroup.cash]);
    expect(allowedReportGroups(AccountType.fund),
        contains(ReportGroup.retirement));
  });
  testWidgets(
      'new account starts in the ledger currency, edited account keeps its currency',
      (tester) async {
    final result = await _openForm(tester, null, defaultCurrency: 'USD');
    final currency = find.byWidgetPredicate(
      (widget) => widget is DropdownButton<String>,
    );
    expect(tester.widget<DropdownButton<String>>(currency).value, 'USD');
    await tester.enterText(find.byType(TextFormField).first, 'Dollar account');
    await _save(tester);
    expect(result()!.currency, 'USD');

    await _openForm(tester, _card(-250), defaultCurrency: 'USD');
    expect(tester.widget<DropdownButton<String>>(currency).value, 'MYR');
  });

  testWidgets('credit card balance field is signed and explained',
      (tester) async {
    await _openForm(tester, _card(-250), width: 320);

    expect(find.text('信用卡余额'), findsOneWidget);
    final guidance = find.text('欠款填负数，溢缴款填正数');
    expect(guidance, findsNothing);
    await tester.tap(find.byTooltip('查看信用卡余额说明'));
    await tester.pumpAndSettle();
    expect(guidance, findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(guidance, findsNothing);
    expect(find.text('当前欠款'), findsNothing);
    expect(
      tester.widget<TextFormField>(find.byKey(_balanceField)).controller!.text,
      '-250.00',
      reason: 'The stored signed balance is shown as-is, never flipped.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving an untouched debt or overpayment keeps its sign',
      (tester) async {
    var result = await _openForm(tester, _card(-250));
    await _save(tester);
    expect(result()!.currentBalance, -250);

    result = await _openForm(tester, _card(80));
    await _save(tester);
    expect(result()!.currentBalance, 80);
  });

  testWidgets('edited debt stays negative and overpayment stays positive',
      (tester) async {
    var result = await _openForm(tester, _card(-250));
    await enterAmount(tester, find.byKey(_balanceField), '-300.5');
    await _save(tester);
    expect(result()!.currentBalance, -300.5);

    result = await _openForm(tester, _card(-250));
    await enterAmount(tester, find.byKey(_balanceField), '45');
    await _save(tester);
    expect(result()!.currentBalance, 45);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-finite credit card balance is rejected', (tester) async {
    final result = await _openForm(tester, _card(-250));
    for (final input in ['NaN', 'Infinity', '-Infinity']) {
      await tester.scrollUntilVisible(
        find.byKey(_balanceField),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      // Invalid restored/programmatic values must still fail form validation.
      amountController(tester, find.byKey(_balanceField)).text = input;
      await tester.pump();
      await _save(tester);
      await tester.scrollUntilVisible(
        find.byKey(_balanceField),
        -300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(result(), isNull, reason: '$input must not be saved');
      expect(find.text('请输入有效金额'), findsOneWidget);
      expect(find.text('信用卡余额'), findsOneWidget);
    }
  });
}
