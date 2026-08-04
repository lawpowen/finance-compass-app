import 'dart:io';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    hide Account, Budget, Category;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/budget.dart';
import 'package:finance_app/src/core/models/category.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/settings/app_settings_controller.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/reports/reports_v2_screen.dart';
import 'package:finance_app/src/features/budgets/budgets_v2_screen.dart';
import 'package:finance_app/src/features/categories/category_manage_screen.dart';
import 'package:finance_app/src/features/settings/settings_reference_pages.dart';
import 'package:finance_app/src/features/settings/settings_v2_screen.dart';
import 'package:finance_app/src/features/transactions/transaction_automation_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('feature source contains no no-op or empty interaction handlers', () {
    final files = Directory('lib/src/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final offenders = <String>[];
    final noOpHandler = RegExp(r'on(?:Tap|Pressed|Changed|Selected):\s*_noop');
    final emptyHandler =
        RegExp(r'on(?:Tap|Pressed|Changed|Selected):\s*\([^)]*\)\s*\{\s*\}');
    for (final file in files) {
      final source = file.readAsStringSync();
      if (noOpHandler.hasMatch(source) || emptyHandler.hasMatch(source)) {
        offenders.add(file.path);
      }
    }
    expect(offenders, isEmpty);
  });

  test('directional affordances have a nearby real interaction contract', () {
    final files = Directory('lib/src/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final offenders = <String>[];
    final affordance = RegExp(
      r'Icons\.(?:chevron_right_rounded|keyboard_arrow_(?:up|down)_rounded|arrow_drop_down_rounded|expand_(?:more|less))',
    );
    final interaction = RegExp(
      r'on(?:Tap|Pressed|Changed|Selected):|PopupMenuButton|DropdownButton|ReorderableDragStartListener|Semantics\(',
    );
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final match in affordance.allMatches(source)) {
        final start = (match.start - 3000).clamp(0, source.length);
        final end = (match.end + 900).clamp(0, source.length);
        final context = source.substring(start, end);
        if (!interaction.hasMatch(context)) {
          final line =
              '\n'.allMatches(source.substring(0, match.start)).length + 1;
          offenders.add('${file.path}:$line');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  testWidgets('recurring rule rows edit frequency and expose generation range',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
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
    repository = await repository.addRecurringTransactionRule(
      name: 'Monthly test',
      transaction: FinanceTransaction(
        id: 'seed',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 50,
        currency: 'MYR',
        transactionDate: DateTime.now(),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        financeRepositoryProvider.overrideWith(
          () => _TestRepositoryNotifier(repository),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.abyss),
          home: RecurringPlanPage(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monthly test'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('重复频率'));
    await tester.tap(find.text('重复频率'));
    await tester.pumpAndSettle();
    expect(find.text('每 3 个月'), findsOneWidget);
    await tester.tap(find.text('每 3 个月'));
    await tester.pumpAndSettle();
    expect(find.text('每 3 个月'), findsOneWidget);

    await tester.ensureVisible(find.text('补生成预计交易'));
    await tester.tap(find.text('补生成预计交易'));
    await tester.pumpAndSettle();
    expect(find.text('12 个月'), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('保存更改'));
    await tester.tap(find.text('保存更改'));
    await tester.pumpAndSettle();
    final updated = await container.read(financeRepositoryProvider.future);
    expect(updated.recurringTransactionRules.single.intervalMonths, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('report range selector changes the overview range',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = await FinanceRepository.load(database);
    final year = DateTime.now().year;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.abyss),
        home: Scaffold(body: ReportsV2Screen(repository: repository)),
      ),
    );
    await tester.tap(find.text('$year年至今'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最近 12 个月'));
    await tester.pumpAndSettle();
    expect(find.text('最近12个月'), findsOneWidget);
  });

  testWidgets('currency display choices are persisted', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = await FinanceRepository.load(database);
    final container = ProviderContainer(
      overrides: [
        financeRepositoryProvider.overrideWith(
          () => _TestRepositoryNotifier(repository),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.abyss),
          home: CurrencyDisplayPage(
            repository: repository,
            settingsController: AppSettingsController(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('RM'));
    await tester.tap(find.text('1 234,56'));
    await tester.scrollUntilVisible(find.text('应用并保存'), 420);
    await tester.tap(find.text('应用并保存'));
    await tester.pumpAndSettle();
    expect(await database.getMetaValue('currency_symbol_style'), 'symbol');
    expect(
        await database.getMetaValue('number_separator_style'), 'space_comma');
  });

  testWidgets('budget effective month is selectable and returned on save',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    repository = await repository.addCategory(
      const Category(
        id: 'food',
        name: 'Food',
        type: CategoryType.expense,
      ),
    );
    final now = DateTime.now();
    final initialMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final next = DateTime(now.year, now.month + 1);
    final nextMonth = '${next.year}-${next.month.toString().padLeft(2, '0')}';
    Budget? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.abyss),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await Navigator.push<Budget>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BudgetEditorPage(
                      repository: repository,
                      monthKey: initialMonth,
                    ),
                  ),
                );
              },
              child: const Text('新增预算'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('新增预算'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '500');
    await tester.tap(find.text('生效月份'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('${next.year}年${next.month}月'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('${next.year}年${next.month}月'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('保存更改'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('保存更改'));
    await tester.pumpAndSettle();
    expect(result?.monthKey, nextMonth);
  });

  testWidgets('new effective month preserves the earlier budget rule',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    repository = await repository.addCategory(
      const Category(
        id: 'entertainment',
        name: 'Entertainment',
        type: CategoryType.expense,
      ),
    );
    const aprilRule = Budget(
      id: 'budget-april',
      categoryId: 'entertainment',
      monthKey: '2026-04',
      amount: 200,
    );
    repository = await repository.addBudget(aprilRule);
    Budget? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.abyss),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await Navigator.push<Budget>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BudgetEditorPage(
                      repository: repository,
                      initialBudget: aprilRule,
                      monthKey: '2026-08',
                    ),
                  ),
                );
              },
              child: const Text('调整八月预算'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('调整八月预算'));
    await tester.pumpAndSettle();
    expect(find.text('从该月起持续生效，直到同一类别设置新的月份预算。'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '400');
    await tester.scrollUntilVisible(
      find.text('保存更改'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('保存更改'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.id, isNot(aprilRule.id));
    expect(result!.monthKey, '2026-08');
    repository = await repository.addBudget(result!);
    double activeAmount(String month) => repository
        .activeBudgetsForMonth(month)
        .singleWhere((budget) => budget.categoryId == 'entertainment')
        .amount;
    expect(activeAmount('2026-04'), 200);
    expect(activeAmount('2026-07'), 200);
    expect(activeAmount('2026-08'), 400);
    expect(activeAmount('2026-09'), 400);
  });

  testWidgets('category section disclosure arrow expands and collapses',
      (tester) async {
    final repository = FinanceRepository.preview();
    final container = ProviderContainer(
      overrides: [
        financeRepositoryProvider.overrideWith(
          () => _TestRepositoryNotifier(repository),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.abyss),
          home: CategoryManageScreen(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final beforeRows =
        find.byIcon(Icons.chevron_right_rounded).evaluate().length;
    await tester.tap(find.byKey(const Key('category-section-支出')));
    await tester.pumpAndSettle();
    final afterRows =
        find.byIcon(Icons.chevron_right_rounded).evaluate().length;
    expect(afterRows, lessThan(beforeRows));
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);

    await tester.tap(find.byKey(const Key('category-section-支出')));
    await tester.pumpAndSettle();
    expect(
      find.byIcon(Icons.chevron_right_rounded).evaluate().length,
      beforeRows,
    );
  });

  testWidgets(
      'settings about page exposes public downloads and optional support',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = FinanceRepository.preview();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.abyss),
        home: Scaffold(
          body: SettingsV2Screen(
            repository: repository,
            settingsController: AppSettingsController(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('关于与支持'));
    await tester.pumpAndSettle();

    expect(find.text('关于 Finance Compass'), findsOneWidget);
    expect(find.text('下载最新版本'), findsOneWidget);
    expect(find.text('请开发者喝杯咖啡'), findsOneWidget);
    expect(find.textContaining('支持完全自愿'), findsOneWidget);
    expect(find.textContaining('不接入支付 SDK'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Touch n Go 开发支持收款二维码，收款人 LAW PO WEN'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _TestRepositoryNotifier extends FinanceRepositoryNotifier {
  _TestRepositoryNotifier(this.repository);

  final FinanceRepository repository;

  @override
  Future<FinanceRepository> build() async => repository;
}
