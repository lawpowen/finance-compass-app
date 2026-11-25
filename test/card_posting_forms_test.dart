import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/features/shared/card_posting_date_field.dart';
import 'package:finance_app/src/features/transactions/transaction_composer_page.dart';
import 'package:finance_app/src/features/transactions/transaction_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const card = Account(
    id: 'card',
    name: 'UOB',
    accountType: AccountType.creditCard,
    reportGroup: ReportGroup.credit,
    currency: 'MYR',
    currentBalance: 0,
    statementDay: 25);
const cash = Account(
    id: 'cash',
    name: 'Wallet',
    accountType: AccountType.cash,
    reportGroup: ReportGroup.cash,
    currency: 'MYR',
    currentBalance: 200);

FinanceRepository ledger() {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  return FinanceRepository.fromSnapshot(database: database, accounts: [
    card,
    cash
  ], transactionTemplates: [
    const TransactionTemplate(
        id: 'habit',
        name: 'Lunch',
        type: TransactionType.expense,
        accountId: 'card',
        amount: 20,
        currency: 'MYR')
  ]);
}

FinanceTransaction charge({DateTime? posting}) => FinanceTransaction(
    id: 'purchase',
    type: TransactionType.expense,
    accountId: 'card',
    currency: 'MYR',
    amount: 41,
    transactionDate: DateTime(2026, 11, 25, 16),
    recordDate: DateTime(2026, 12, 2, 9),
    cardPostingDate: posting);

Future<TransactionFormResult? Function()> open(
    WidgetTester tester, Widget page) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(520, 1600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  TransactionFormResult? saved;
  await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                body: FilledButton(
                    onPressed: () async {
                      saved = page is TransactionFormDialog
                          ? await showDialog<TransactionFormResult>(
                              context: context, builder: (_) => page)
                          : await Navigator.of(context)
                              .push<TransactionFormResult>(
                                  MaterialPageRoute(builder: (_) => page));
                    },
                    child: const Text('Open')),
              ))));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return () => saved;
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  for (final dialog in [false, true]) {
    Widget editor(FinanceTransaction original, {bool edit = true}) => dialog
        ? TransactionFormDialog(
            repository: ledger(),
            initialTransaction: edit ? original : null,
            draftTransaction: edit ? null : original)
        : TransactionComposerPage(
            repository: ledger(), draft: original, editExisting: edit);
    testWidgets(
        'posting shortcut, picker bounds and reset in ${dialog ? "dialog" : "composer"}',
        (tester) async {
      final original = charge();
      final result = await open(tester, editor(original));
      expect(find.text('跟随交易日期 · 计入 11月账单'), findsOneWidget);
      await tap(tester, find.byKey(const Key('card-posting-date-shortcut')));
      expect(find.text('2026年11月26日 · 计入 12月账单'), findsOneWidget);
      await tap(tester, find.byKey(const Key('card-posting-date-picker')));
      final picker =
          tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      expect(picker.firstDate, DateTime(2026, 11, 25));
      expect(picker.initialDate, DateTime(2026, 11, 26));
      final labels = MaterialLocalizations.of(
          tester.element(find.byType(DatePickerDialog)));
      await tap(
          tester,
          find.descendant(
              of: find.byType(DatePickerDialog), matching: find.text('27')));
      await tap(tester, find.text(labels.okButtonLabel));
      expect(find.text('2026年11月27日 · 计入 12月账单'), findsOneWidget);
      await tap(tester, find.byKey(const Key('card-posting-date-clear')));
      expect(find.text('跟随交易日期 · 计入 11月账单'), findsOneWidget);
      await tap(tester, find.byKey(const Key('card-posting-date-shortcut')));
      await tap(tester, find.text(dialog ? '保存' : '保存修改'));
      final tx = result()!.transactions.single;
      expect(tx.cardPostingDate, DateTime(2026, 11, 26));
      expect(tx.transactionDate, original.transactionDate);
      expect(tx.recordDate, original.recordDate);
    });
    testWidgets(
        'advancing the economic day drops an earlier posting in ${dialog ? "dialog" : "composer"}',
        (tester) async {
      final result =
          await open(tester, editor(charge(posting: DateTime(2026, 11, 26))));
      await tap(
          tester,
          dialog
              ? find.descendant(
                  of: find.widgetWithText(ListTile, '交易日期'),
                  matching: find.text('修改'))
              : find.text('交易日期'));
      final picker = find.byType(DatePickerDialog);
      final labels = MaterialLocalizations.of(tester.element(picker));
      await tap(tester, find.descendant(of: picker, matching: find.text('28')));
      await tap(tester, find.text(labels.okButtonLabel));
      expect(find.text('跟随交易日期 · 计入 12月账单'), findsOneWidget);
      await tap(tester, find.text(dialog ? '保存' : '保存修改'));
      expect(result()!.transactions.single.transactionDate,
          DateTime(2026, 11, 28));
      expect(result()!.transactions.single.cardPostingDate, isNull);
    });
    testWidgets(
        'changing to cash clears the posting override in ${dialog ? "dialog" : "composer"}',
        (tester) async {
      final result =
          await open(tester, editor(charge(posting: DateTime(2026, 11, 26))));
      await tap(
          tester,
          dialog
              ? find.byKey(const Key('entry-source-account'))
              : find.text('付款账户'));
      await tap(
          tester, find.text(dialog ? 'Wallet (MYR)' : 'Wallet · MYR').last);
      expect(find.byKey(const Key('card-posting-date-picker')), findsNothing);
      await tap(tester, find.text(dialog ? '保存' : '保存修改'));
      expect(result()!.transactions.single.accountId, 'cash');
      expect(result()!.transactions.single.cardPostingDate, isNull);
    });
    testWidgets(
        'copied card transaction starts without a posting override in ${dialog ? "dialog" : "composer"}',
        (tester) async {
      final result = await open(
          tester, editor(charge(posting: DateTime(2026, 11, 26)), edit: false));
      expect(find.textContaining('跟随交易日期'), findsOneWidget);
      await tap(tester, find.text('保存'));
      expect(result()!.transactions.single.cardPostingDate, isNull);
    });
  }

  testWidgets('applying a template removes the previous fixed posting day',
      (tester) async {
    final result = await open(
        tester,
        TransactionComposerPage(
            repository: ledger(),
            draft: charge(posting: DateTime(2026, 11, 26)),
            editExisting: true));
    await tap(tester, find.text('套用模板'));
    await tap(tester, find.textContaining('Lunch · '));
    expect(find.text('跟随交易日期 · 计入 11月账单'), findsOneWidget);
    await tap(tester, find.text('保存修改'));
    expect(result()!.transactions.single.cardPostingDate, isNull);
  });

  testWidgets('a first-day statement displays the month that just ended',
      (tester) async {
    const firstDayCard = Account(
        id: 'first',
        name: 'PayLater',
        currency: 'MYR',
        accountType: AccountType.creditCard,
        reportGroup: ReportGroup.credit,
        currentBalance: 0,
        statementDay: 1);
    DateTime? selected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => CardPostingDateField(
                    source: firstDayCard,
                    transactionDate: DateTime(2026, 12, 31),
                    value: selected,
                    onChanged: (value) => setState(() => selected = value))))));
    expect(find.text('跟随交易日期 · 计入 12月账单'), findsOneWidget);
    await tap(tester, find.byKey(const Key('card-posting-date-shortcut')));
    expect(selected, DateTime(2027, 1, 2));
    expect(find.text('2027年1月2日 · 计入 1月账单'), findsOneWidget);
  });

  testWidgets('a preset definition never offers a fixed posting day',
      (tester) async {
    final result = await open(
        tester,
        TransactionComposerPage(
            repository: ledger(),
            draft: charge(posting: DateTime(2026, 11, 26)),
            isPresetDefinition: true));
    expect(find.byType(CardPostingDateField), findsNothing);
    await tap(tester, find.text('保存'));
    expect(result()!.transactions.single.cardPostingDate, isNull);
  });

  test('monthly batch preserves the posting lag after month-end clamping', () {
    final base = FinanceTransaction(
        id: 'base',
        accountId: 'card',
        currency: 'MYR',
        type: TransactionType.expense,
        amount: 10,
        transactionDate: DateTime(2026, 1, 31, 23, 45),
        cardPostingDate: DateTime(2026, 2, 2));
    final series = buildRecurringTransactions(baseTransaction: base, months: 4);
    expect(series.map((t) => t.cardPostingDate), [
      DateTime(2026, 2, 2),
      DateTime(2026, 3, 2),
      DateTime(2026, 4, 2),
      DateTime(2026, 5, 2),
    ]);
    expect(series.map((t) => t.transactionDate.hour), everyElement(23));
  });
}
