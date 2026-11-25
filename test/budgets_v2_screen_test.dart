import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/budget.dart';
import 'package:finance_app/src/core/models/category.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/core/utils/month_key.dart';
import 'package:finance_app/src/features/budgets/budgets_v2_screen.dart';
import 'package:finance_app/src/features/shared/compass_ui.dart';
import 'package:finance_app/src/features/shared/finance_donut.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/amount_entry.dart';

void main() {
  testWidgets('new budget uses USD ledger base and saves the entered cents',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await FinanceRepository.load(db);
    repo = await repo.updateExchangeRates(
        {'USD': 1, 'MYR': .25}, ['USD', 'MYR', 'CNY', 'TWD']);
    repo = await repo.addCategory(
        const Category(id: 'books', name: 'Books', type: CategoryType.expense));
    Budget? saved;
    await _openBudgetEditor(tester, repo, '2026-02', null, (b) => saved = b);
    await enterAmount(tester, find.byType(TextField).first, '100.49');
    await tester.tap(find.text('保存更改'));
    await tester.pumpAndSettle();
    expect(saved?.currency, 'USD');
    expect(saved?.amount, 100.49);
    repo = await repo.addBudget(saved!);
    final rule = repo.activeBudgetsForMonth('2026-02').single;
    expect(repo.budgetAmountInBase(rule), 100.49);
  });

  testWidgets(
      'budget preview recalculates by month and category and preserves the original currency and precision',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await FinanceRepository.load(db);
    repo = await repo.updateExchangeRates(
        {'USD': 1, 'MYR': .25}, ['USD', 'MYR', 'CNY', 'TWD']);
    repo = await repo.addCategory(const Category(
        id: 'food', name: 'Pet Food', type: CategoryType.expense));
    repo = await repo.addCategory(
        const Category(id: 'other', name: 'Other', type: CategoryType.expense));
    repo = await repo.addBudget(const Budget(
        id: 'jan',
        categoryId: 'food',
        monthKey: '2026-01',
        amount: 80,
        currency: 'MYR',
        rolloverEnabled: true));
    const feb = Budget(
        id: 'feb',
        categoryId: 'food',
        monthKey: '2026-02',
        amount: 10.4953,
        currency: 'MYR',
        rolloverEnabled: true);
    repo = await repo.addBudget(feb);
    repo = await repo.addBudget(const Budget(
        id: 'mar',
        categoryId: 'food',
        monthKey: '2026-03',
        amount: 50,
        currency: 'USD'));
    String effective() => tester
        .widget<Text>(find.byKey(const Key('budget-editor-effective')))
        .data!;
    Budget? saved;
    await _openBudgetEditor(tester, repo, '2026-02', feb, (b) => saved = b);
    expect(effective(), 'MYR 90.50');
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '10.4953');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(effective(), 'MYR 90.50');
    await tester.tap(find.text('预览下月预算'));
    await tester.pumpAndSettle();
    expect(find.textContaining('基础预算：MYR 200.00'), findsOneWidget);
    expect(find.textContaining('预计可用：MYR 200.00'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('支出类别'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    expect(effective(), 'MYR 10.50');
    await tester.tap(find.text('支出类别'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pet Food'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生效月份'));
    await tester.pumpAndSettle();
    await _selectBudgetMonth(tester, '2026年1月');
    expect(effective(), 'MYR 10.50');
    await tester.tap(find.text('生效月份'));
    await tester.pumpAndSettle();
    await _selectBudgetMonth(tester, '2026年2月');
    expect(effective(), 'MYR 90.50');
    await tester.tap(find.text('保存更改').hitTestable());
    await tester.pumpAndSettle();
    expect(saved?.id, feb.id);
    expect(saved?.currency, 'MYR');
    expect(saved?.amount, 10.4953);
    expect(saved?.rolloverEnabled, false);
    repo = await repo.addBudget(saved!);
    final persisted = (await FinanceRepository.load(repo.database))
        .budgets
        .singleWhere((item) => item.id == feb.id);
    expect(persisted.monthKey, '2026-02');
    expect(persisted.currency, 'MYR');
    expect(persisted.amount, 10.4953);
    expect(persisted.rolloverEnabled, false);
  });

  testWidgets(
      'an archived foreign budget can be edited in its source month only',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await FinanceRepository.load(db);
    repo = await repo.addCategory(const Category(
        id: 'legacy', name: 'Old category', type: CategoryType.expense));
    repo = await repo.addCategory(const Category(
        id: 'open', name: 'Open category', type: CategoryType.expense));
    const source = Budget(
        id: 'source',
        categoryId: 'legacy',
        monthKey: '2026-01',
        amount: 15.255,
        currency: 'SGD');
    repo = await repo.addBudget(source);
    repo = await repo.updateExistingCategory(const Category(
        id: 'legacy',
        name: 'Old category',
        type: CategoryType.expense,
        isArchived: true));
    Budget? result;
    await _openBudgetEditor(
        tester, repo, source.monthKey, source, (b) => result = b);
    expect(
        tester
            .widget<Text>(find.byKey(const Key('budget-editor-effective')))
            .data,
        '未估值');
    await tester.tap(find.text('保存更改'));
    await tester.pumpAndSettle();
    expect(result?.amount, 15.255);
    expect(result?.currency, 'SGD');
    expect(result?.categoryId, 'legacy');
    await _openBudgetEditor(tester, repo, '2026-02', source, (_) {});
    await tester.tap(find.text('支出类别'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Old category'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Open category'), findsOneWidget);
  });

  testWidgets(
      'parent detail lists only owned transactions and explains inherited deletion',
      (tester) async {
    tester.view.physicalSize = const Size(620, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await FinanceRepository.load(db);
    final now = DateTime.now();
    final sourceMonth = monthKeyFromDate(DateTime(now.year, now.month - 1));
    final previousMonth = monthKeyFromDate(DateTime(now.year, now.month - 2));
    final nextMonth = monthKeyFromDate(DateTime(now.year, now.month + 1));
    repo = await repo.addAccount(const Account(
        id: 'cash',
        name: 'Cash',
        currency: 'MYR',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currentBalance: 1000));
    for (final (id, parent) in [
      ('parent', null),
      ('child', 'parent'),
      ('own', 'parent')
    ]) {
      repo = await repo.addCategory(Category(
          id: id, name: id, type: CategoryType.expense, parentId: parent));
    }
    for (final (id, category, month, amount) in [
      ('old', 'parent', previousMonth, 150.0),
      ('source', 'parent', sourceMonth, 300.0),
      ('new', 'parent', nextMonth, 90.0),
      ('separate', 'own', sourceMonth, 50.0)
    ]) {
      repo = await repo.addBudget(Budget(
          id: id, categoryId: category, monthKey: month, amount: amount));
    }
    repo = await repo.addTransactions([
      FinanceTransaction(
          id: 'refund',
          accountId: 'cash',
          categoryId: 'child',
          merchant: 'Child refund',
          type: TransactionType.expense,
          amount: -10,
          currency: 'MYR',
          transactionDate: now),
      FinanceTransaction(
          id: 'independent',
          accountId: 'cash',
          categoryId: 'own',
          merchant: 'Child with own budget',
          type: TransactionType.expense,
          amount: 20,
          currency: 'MYR',
          transactionDate: now)
    ]);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          financeRepositoryProvider
              .overrideWith(() => _TestRepositoryNotifier(repo)),
        ],
        child: MaterialApp(
            theme: buildFinanceTheme(AppThemeStyle.abyss),
            home: Scaffold(body: BudgetsV2Screen(repository: repo)))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(InkWell, 'parent').last);
    await tester.pumpAndSettle();
    expect(find.text('Child refund'), findsOneWidget);
    expect(find.text('MYR 10.00'), findsOneWidget);
    expect(find.text('Child with own budget'), findsNothing);
    await tester.tap(find.text('删除预算'));
    await tester.pumpAndSettle();
    expect(find.textContaining('$sourceMonth起至 $nextMonth'), findsOneWidget);
    expect(find.textContaining('改用 $previousMonth'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repo.budgets.map((b) => b.id), contains('source'));
  });

  testWidgets(
      'saving after a remote budget deletion keeps the draft and does not recreate the rule',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await FinanceRepository.load(db);
    repo = await repo.addCategory(const Category(
        id: 'cat', name: 'Saved category', type: CategoryType.expense));
    final month = monthKeyFromDate(DateTime.now());
    repo = await repo.addBudget(
        Budget(id: 'rule', categoryId: 'cat', monthKey: month, amount: 10.99));
    final container = ProviderContainer(overrides: [
      financeRepositoryProvider
          .overrideWith(() => _TestRepositoryNotifier(repo))
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: buildFinanceTheme(AppThemeStyle.abyss),
            home: Scaffold(body: BudgetsV2Screen(repository: repo)))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(InkWell, 'Saved category').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑预算'));
    await tester.pumpAndSettle();
    await container
        .read(financeRepositoryProvider.notifier)
        .mutate((r) => r.deleteExistingBudget('rule'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存更改'));
    await tester.pumpAndSettle();
    expect(find.textContaining('此预算规则已被删除'), findsOneWidget);
    expect(find.byType(BudgetEditorPage), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '10.99');
    expect((await FinanceRepository.load(db)).budgets, isEmpty);
  });

  testWidgets(
      'monochrome shows readable amounts and opens the budget editor at 320 px',
      (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final today = DateTime.now();
    final now = DateTime(today.year, today.month, 1);
    final repository = await _seedBudgets(
      database,
      now,
      DateTime(now.year, now.month - 1),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        financeRepositoryProvider
            .overrideWith(() => _TestRepositoryNotifier(repository)),
      ],
      child: MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.monochrome),
        home: Scaffold(body: BudgetsV2Screen(repository: repository)),
      ),
    ));
    await tester.pumpAndSettle();
    final panel =
        tester.widget<FinanceDonutPanel>(find.byType(FinanceDonutPanel));
    expect(
        panel.slices.map((slice) => slice.color),
        everyElement(
          predicate<Color>((color) => color.r == color.g && color.g == color.b),
        ));
    expect(find.text('MYR 4,000'), findsOneWidget);
    expect(find.text('占比'), findsOneWidget);
    expect(find.text('剩余'), findsOneWidget);
    expect(find.text('超出 MYR 100'), findsOneWidget);
    expect(find.textContaining(RegExp(r'实际|预计|结转')), findsNothing);
    expect(find.byType(CompassDualProgressBar), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(FilledButton, '调整'));
    await tester.pumpAndSettle();
    expect(find.byType(BudgetEditorPage), findsOneWidget);
  });

  testWidgets('budget details move alongside the ring at desktop widths',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final today = DateTime.now();
    final now = DateTime(today.year, today.month, 1);
    final lastMonth = DateTime(now.year, now.month - 1, 1);
    final repository = await _seedBudgets(database, now, lastMonth);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeRepositoryProvider.overrideWith(
            () => _TestRepositoryNotifier(repository),
          ),
        ],
        child: MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.abyss),
          home: Scaffold(body: BudgetsV2Screen(repository: repository)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chart = find.byType(FinanceDonutPanel);
    final panel = tester.widget<FinanceDonutPanel>(chart);
    expect(panel.totalValue, 'MYR 4,000');
    expect(
      panel.slices.map((slice) => (slice.label, slice.value)),
      [('Dining', 1600), ('Transport', 1000), ('Insurance', 800), ('其他', 600)],
    );
    expect(find.text('超出 MYR 100'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.getSize(chart).width, 350);
    final details = find.text('预算明细');
    expect(tester.getTopLeft(details).dy,
        greaterThan(tester.getRect(chart).bottom));
    expect(find.text('占比'), findsOneWidget);
    expect(find.text('剩余'), findsOneWidget);
    expect(find.textContaining(RegExp(r'实际|预计|结转')), findsNothing);

    tester.view.physicalSize = const Size(960, 844);
    await tester.pumpAndSettle();
    expect(tester.getSize(chart).width, inInclusiveRange(320, 360));
    expect(tester.getTopLeft(details).dx,
        greaterThan(tester.getRect(chart).right));
    expect(tester.getTopLeft(details).dy,
        closeTo(tester.getTopLeft(chart).dy, 32));
    expect(tester.getCenter(find.text('占比')).dx,
        closeTo(tester.getCenter(find.text('40.0%')).dx, 1));
    final actualHeader = tester.getTopRight(find.text('实际支出'));
    final plannedHeader = tester.getTopRight(find.text('预计支出'));
    expect(actualHeader.dx, lessThan(plannedHeader.dx));
    expect(
        tester.getTopRight(find.text('2600')).dx, closeTo(actualHeader.dx, 1));
    expect(
        tester.getTopRight(find.text('1600')).dx, closeTo(plannedHeader.dx, 1));
    expect(find.text('剩余'), findsOneWidget);
    expect(find.text('超出'), findsNWidgets(2));
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '预计 1600',
      ),
      findsOneWidget,
    );
    expect(find.text('调整预算'), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsNothing);

    final previous = find.byIcon(Icons.chevron_left_rounded);
    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(tester.widget<FinanceDonutPanel>(chart).totalValue, 'MYR 1,600');
    expect(
        tester.widget<FinanceDonutPanel>(chart).slices.single.label, 'Dining');
    expect(find.text('已用 1,500 · 预计 0 · 剩余 100'), findsOneWidget);

    await tester.tap(find.text('调整预算'));
    await tester.pumpAndSettle();
    final editor = find.byType(BudgetEditorPage);
    expect(tester.widget<BudgetEditorPage>(editor).monthKey,
        monthKeyFromDate(lastMonth));
    Navigator.of(tester.element(editor)).pop();
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.widget<FinanceDonutPanel>(chart).totalValue, 'MYR 1,600');
    expect(tester.getTopLeft(details).dy,
        greaterThan(tester.getRect(chart).bottom));

    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(tester.widget<FinanceDonutPanel>(chart).totalValue, 'MYR 0');
    expect(tester.widget<FinanceDonutPanel>(chart).slices, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dopamine theme drives budget donut slices from theme tokens',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final today = DateTime.now();
    final now = DateTime(today.year, today.month, 1);
    final repository = await _seedBudgets(
      database,
      now,
      DateTime(now.year, now.month - 1),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        financeRepositoryProvider
            .overrideWith(() => _TestRepositoryNotifier(repository)),
      ],
      child: MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.dopamine),
        home: Scaffold(body: BudgetsV2Screen(repository: repository)),
      ),
    ));
    await tester.pumpAndSettle();
    final panel =
        tester.widget<FinanceDonutPanel>(find.byType(FinanceDonutPanel));
    final expectedColors = paletteForStyle(AppThemeStyle.dopamine).donutColors!;
    expect(
      panel.slices.map((slice) => slice.color).toList(),
      expectedColors.take(panel.slices.length).toList(),
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _selectBudgetMonth(WidgetTester tester, String label) async {
  final option = find.widgetWithText(ListTile, label).hitTestable();
  await tester.scrollUntilVisible(option, 200,
      scrollable: find.byType(Scrollable).last);
  await tester.pumpAndSettle();
  await tester.tap(option);
  await tester.pumpAndSettle();
  expect(find.text('选择生效月份'), findsNothing);
}

Future<void> _openBudgetEditor(WidgetTester tester, FinanceRepository repo,
    String month, Budget? initial, ValueChanged<Budget?> onSave) async {
  tester.view.physicalSize = const Size(700, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: buildFinanceTheme(AppThemeStyle.abyss),
    home: Builder(
        builder: (context) => Scaffold(
                body: TextButton(
              child: const Text('Open'),
              onPressed: () async =>
                  onSave(await Navigator.of(context).push<Budget>(
                MaterialPageRoute(
                    builder: (_) => BudgetEditorPage(
                        repository: repo,
                        monthKey: month,
                        initialBudget: initial)),
              )),
            ))),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<FinanceRepository> _seedBudgets(
  AppDatabase database,
  DateTime now,
  DateTime lastMonth,
) async {
  var repository = await FinanceRepository.load(database);
  repository = await repository.addAccount(
    const Account(
      id: 'cash',
      name: 'Cash',
      accountType: AccountType.cash,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      currentBalance: 1000,
    ),
  );
  final month = monthKeyFromDate(now);
  final previousMonth = monthKeyFromDate(lastMonth);
  for (final (name, amount) in <(String, double)>[
    ('Books', 350),
    ('Dining', 1600),
    ('Transport', 1000),
    ('Insurance', 800),
    ('Health', 250),
  ]) {
    repository = await repository.addCategory(
      Category(id: name, name: name, type: CategoryType.expense),
    );
    repository = await repository.addBudget(
      Budget(
        id: name,
        categoryId: name,
        monthKey: name == 'Dining' ? previousMonth : month,
        amount: amount,
        rolloverEnabled: name == 'Dining',
      ),
    );
  }

  return repository.addTransactions([
    FinanceTransaction(
      id: 'previous-expense',
      type: TransactionType.expense,
      accountId: 'cash',
      categoryId: 'Dining',
      currency: 'MYR',
      amount: 1500,
      transactionDate: lastMonth,
    ),
    FinanceTransaction(
      id: 'current-expense',
      type: TransactionType.expense,
      accountId: 'cash',
      categoryId: 'Dining',
      currency: 'MYR',
      amount: 2600,
      transactionDate: now,
    ),
    FinanceTransaction(
      id: 'planned-expense',
      type: TransactionType.expense,
      accountId: 'cash',
      categoryId: 'Transport',
      currency: 'MYR',
      amount: 1600,
      transactionDate: now,
      status: TransactionStatus.planned,
    ),
  ]);
}

class _TestRepositoryNotifier extends FinanceRepositoryNotifier {
  _TestRepositoryNotifier(this.repository);

  final FinanceRepository repository;

  @override
  Future<FinanceRepository> build() async => repository;
}
