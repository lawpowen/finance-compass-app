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

void main() {
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
      [('Dining', 1600), ('交通', 1000), ('Insurance', 800), ('其他', 600)],
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
