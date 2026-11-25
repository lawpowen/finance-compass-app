import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/category.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/shared/finance_amount_field.dart';
import 'package:finance_app/src/features/transactions/transaction_automation_pages.dart';
import 'package:finance_app/src/features/transactions/transaction_composer_page.dart';
import 'package:finance_app/src/features/transactions/transaction_form_dialog.dart';
import 'package:finance_app/src/features/transactions/transactions_v2_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const cash = Account(
    id: 'bank',
    name: 'Bank',
    accountType: AccountType.cash,
    reportGroup: ReportGroup.cash,
    currency: 'MYR',
    currentBalance: 100);
const second = Account(
    id: 'other',
    name: 'Second',
    accountType: AccountType.cash,
    reportGroup: ReportGroup.cash,
    currency: 'MYR',
    currentBalance: 0);
const activeFood =
    Category(id: 'food', name: 'Lunch', type: CategoryType.expense);
const oldFood =
    Category(id: 'old', name: 'Old food', type: CategoryType.expense);
const archivedFood = Category(
    id: 'old', name: 'Old food', type: CategoryType.expense, isArchived: true);
FinanceTransaction _entry(
        {TransactionType type = TransactionType.expense,
        String? category,
        String? target,
        double? targetAmount,
        String? targetCurrency}) =>
    FinanceTransaction(
        id: 'tx',
        type: type,
        accountId: cash.id,
        categoryId: category,
        amount: 25,
        currency: cash.currency,
        toAccountId: target,
        toAmount: targetAmount,
        toCurrency: targetCurrency,
        transactionDate: DateTime.now());

Future<FinanceRepository> _repo() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  var repo = await FinanceRepository.load(db);
  for (final a in [cash, second]) {
    repo = await repo.addAccount(a);
  }
  for (final c in [
    activeFood,
    oldFood,
    const Category(id: 'move', name: 'Internal', type: CategoryType.transfer)
  ]) {
    repo = await repo.addCategory(c);
  }
  repo = await repo.saveTransactionTemplate(const TransactionTemplate(
      id: 'tpl',
      name: 'Weekly groceries',
      type: TransactionType.expense,
      accountId: 'bank',
      amount: 25,
      currency: 'MYR',
      categoryId: 'old',
      merchant: 'Lotus',
      description: 'Fresh produce'));
  return repo.updateExistingCategory(archivedFood);
}

Future<TransactionFormResult? Function()> _open(
    WidgetTester tester, Widget page,
    {bool dialog = false, ProviderContainer? container}) async {
  tester.view.physicalSize = const Size(520, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  TransactionFormResult? saved;
  final app = MaterialApp(
      theme: buildFinanceTheme(AppThemeStyle.abyss),
      home: Builder(
          builder: (context) => Scaffold(
              body: FilledButton(
                  onPressed: () async {
                    saved = dialog
                        ? await showDialog<TransactionFormResult>(
                            context: context, builder: (_) => page)
                        : await Navigator.push<TransactionFormResult>(
                            context, MaterialPageRoute(builder: (_) => page));
                  },
                  child: const Text('Open')))));
  await tester.pumpWidget(container == null
      ? app
      : UncontrolledProviderScope(container: container, child: app));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return () => saved;
}

Future<void> _press(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  for (final dialog in [false, true]) {
    for (final category in [null, 'old']) {
      testWidgets(
          '${dialog ? 'dialog' : 'composer'} historical edit retains category $category',
          (tester) async {
        final repo = await _repo();
        final original = _entry(category: category);
        final result = await _open(
            tester,
            dialog
                ? TransactionFormDialog(
                    repository: repo, initialTransaction: original)
                : TransactionComposerPage(
                    repository: repo, draft: original, editExisting: true),
            dialog: dialog);
        final note = find.byWidgetPredicate((w) =>
            w is TextField &&
            (w.decoration?.labelText == '说明' ||
                w.decoration?.hintText == '添加备注（选填）'));
        await tester.ensureVisible(note);
        await tester.enterText(note, 'updated');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        await _press(tester, find.text(dialog ? '保存' : '保存修改'));
        expect(result()!.transactions.single.categoryId, category);
        expect(result()!.transactions.single.description, 'updated');
      });
    }
    testWidgets(
        '${dialog ? 'dialog' : 'composer'} copy excludes archived category',
        (tester) async {
      final repo = await _repo();
      final draft = _entry(category: 'old');
      final result = await _open(
          tester,
          dialog
              ? TransactionFormDialog(repository: repo, draftTransaction: draft)
              : TransactionComposerPage(repository: repo, draft: draft),
          dialog: dialog);
      expect(find.textContaining('已归档'), findsNothing);
      await _press(tester, find.text('保存'));
      expect(result()!.transactions.single.categoryId, 'food');
    });
    testWidgets(
        '${dialog ? 'dialog' : 'composer'} preserves the draft when its category becomes archived',
        (tester) async {
      final repo = await _repo();
      final container = ProviderContainer(overrides: [
        financeRepositoryProvider.overrideWith(() => _Notifier(repo)),
      ]);
      addTearDown(container.dispose);
      await container.read(financeRepositoryProvider.future);
      final draft = _entry(category: activeFood.id);
      final result = await _open(
          tester,
          dialog
              ? TransactionFormDialog(repository: repo, draftTransaction: draft)
              : TransactionComposerPage(repository: repo, draft: draft),
          dialog: dialog,
          container: container);
      await container.read(financeRepositoryProvider.notifier).mutate(
          (current) => current.updateExistingCategory(const Category(
              id: 'food',
              name: 'Lunch',
              type: CategoryType.expense,
              isArchived: true)));
      await _press(tester, find.text('保存'));
      expect(result(), isNull);
      expect(find.text('所选类别已变更，请重新选择类别或确认为未分类。'), findsOneWidget);
      await _press(tester, find.text('保存'));
      expect(result()!.transactions.single.categoryId, isNull);
      expect(result()!.transactions.single.amount, 25);
    });
  }
  testWidgets(
      'changing type clears hidden transfer fields and does not assign a transfer category',
      (tester) async {
    final repo = await _repo();
    final draft = _entry(
        type: TransactionType.transfer,
        target: 'other',
        targetAmount: 9,
        targetCurrency: 'USD');
    final first = await _open(
        tester,
        TransactionComposerPage(
            repository: repo, draft: draft, editExisting: true));
    await _press(tester, find.text('支出'));
    await _press(tester, find.text('保存修改'));
    final expense = first()!.transactions.single;
    expect([expense.toAccountId, expense.toAmount, expense.toCurrency],
        everyElement(isNull));

    final second = await _open(
        tester,
        TransactionComposerPage(
            repository: repo, draft: expense, editExisting: true));
    await _press(tester, find.text('转账'));
    await _press(tester, find.text('选择'));
    await _press(tester, find.textContaining('Second ·'));
    await _press(tester, find.text('保存修改'));
    final transfer = second()!.transactions.single;
    expect(transfer.categoryId, isNull);
    expect(transfer.toAmount, isNull);
  });
  testWidgets('advanced form submits canonical same-currency ordinary transfer',
      (tester) async {
    final repo = await _repo();
    final result = await _open(
        tester,
        TransactionFormDialog(
            repository: repo,
            draftTransaction: _entry(
                type: TransactionType.transfer,
                target: 'other',
                targetCurrency: 'MYR')),
        dialog: true);
    await _press(tester, find.text('保存'));
    final saved = result()!.transactions.single;
    expect(saved.toAmount, isNull);
    expect(saved.toCurrency, 'MYR');
    expect(saved.categoryId, isNull);
  });
  testWidgets(
      'applying an archived-category template selects an active category, preserving recorded merchant',
      (tester) async {
    final repo = await _repo();
    final result =
        await _open(tester, TransactionComposerPage(repository: repo));
    await _press(tester, find.text('套用模板'));
    await _press(tester, find.textContaining('Weekly groceries ·'));
    await _press(tester, find.text('保存'));
    final saved = result()!.transactions.single;
    expect(saved.categoryId, 'food');
    expect(saved.merchant, 'Lotus');
    expect(saved.description, 'Fresh produce');
  });
  testWidgets(
      'missing transfer quote leaves the destination amount editable and blank',
      (tester) async {
    var repo = await _repo();
    repo = await repo.addAccount(const Account(
        id: 'eur',
        name: 'Foreign bank',
        accountType: AccountType.bankSaving,
        reportGroup: ReportGroup.cash,
        currency: 'EUR',
        currentBalance: 0));
    final result = await _open(
        tester,
        TransactionComposerPage(
            repository: repo,
            draft: _entry(
                type: TransactionType.transfer,
                target: 'eur',
                targetCurrency: 'EUR')));
    expect(find.text('缺少汇率，请输入实际到账金额'), findsOneWidget);
    final dest = tester
        .widgetList<FinanceAmountField>(find.byType(FinanceAmountField))
        .elementAt(1);
    expect(dest.controller.text, isEmpty);
    expect(dest.readOnly, isFalse);
    await _press(tester, find.text('保存'));
    expect(result(), isNull);
  });
  testWidgets(
      'lightning shortcut displays template title but posts the actual merchant',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = await _repo();
    final container = ProviderContainer(overrides: [
      financeRepositoryProvider.overrideWith(() => _Notifier(repo)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: buildFinanceTheme(AppThemeStyle.abyss),
            home: Scaffold(body: TransactionsV2Screen(repository: repo)))));
    await tester.pumpAndSettle();
    await _press(tester, find.byKey(const Key('transactions_v2_quick')));
    await _press(tester, find.text('Weekly groceries'));
    await _press(tester, find.text('保存'));
    final created = (await container.read(financeRepositoryProvider.future))
        .transactions
        .single;
    expect(created.merchant, 'Lotus');
    expect(created.categoryId, activeFood.id);
  });
  testWidgets('template editor renders the actual merchant and note',
      (tester) async {
    tester.view.physicalSize = const Size(520, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = await _repo();
    final container = ProviderContainer(overrides: [
      financeRepositoryProvider.overrideWith(() => _Notifier(repo)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: buildFinanceTheme(AppThemeStyle.abyss),
            home: QuickTemplateManagerPage(repository: repo))));
    await tester.pumpAndSettle();
    await _press(tester, find.text('Weekly groceries'));
    expect(find.text('Lotus'), findsOneWidget);
    expect(find.text('Fresh produce'), findsOneWidget);
  });
  testWidgets('paused rule badge follows the unsaved active switch',
      (tester) async {
    var repo = await _repo();
    repo = await repo.saveRecurringTransactionRule(RecurringTransactionRule(
        id: 'rule',
        name: 'Monthly groceries',
        type: TransactionType.expense,
        accountId: cash.id,
        amount: 25,
        currency: 'MYR',
        startDate: DateTime(2026, 1, 1),
        isActive: false));
    final container = ProviderContainer(overrides: [
      financeRepositoryProvider.overrideWith(() => _Notifier(repo)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: buildFinanceTheme(AppThemeStyle.abyss),
            home: RecurringPlanPage(repository: repo))));
    await tester.pumpAndSettle();
    await _press(tester, find.text('Monthly groceries'));
    expect(find.text('已暂停'), findsOneWidget);
    expect(find.text('运行中'), findsNothing);
    await _press(tester, find.byType(Switch));
    expect(find.text('运行中'), findsOneWidget);
  });
}

class _Notifier extends FinanceRepositoryNotifier {
  _Notifier(this.repo);
  final FinanceRepository repo;
  @override
  Future<FinanceRepository> build() async => repo;
}
