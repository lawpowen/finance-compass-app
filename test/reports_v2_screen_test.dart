import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/asset_snapshot.dart';
import 'package:finance_app/src/core/models/budget.dart';
import 'package:finance_app/src/core/models/category.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/core/utils/month_key.dart';
import 'package:finance_app/src/features/reports/reports_v2_screen.dart';
import 'package:finance_app/src/features/shared/compass_ui.dart';
import 'package:finance_app/src/features/shared/finance_donut.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('parent rankings reconcile refunds and uncategorized expenses',
      (tester) async {
    final day = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final repo = await _categoryReportLedger(day);
    await _pumpReports(tester, repo);
    expect(_text(tester, 'reports-category-0-name'), 'Home');
    expect(_text(tester, 'reports-category-0-amount'), compassMoney(70));
    expect(_text(tester, 'reports-category-1-name'), 'Travel');
    expect(_text(tester, 'reports-category-1-amount'), compassMoney(-20));
    expect(
        _text(tester, 'reports-category-total'), '已分类支出合计 ${compassMoney(50)}');
    expect(_text(tester, 'reports-unclassified-total'),
        '未分类支出 ${compassMoney(10)}');
    expect(
        _text(tester, 'reports-all-expense-total'), '支出净额 ${compassMoney(60)}');
    expect(tester.takeException(), isNull);
  });

  test(
      'category JSON and planning CSV retain duplicate names, unclassified amounts and refunds',
      () async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month + 1, 1);
    final month = monthKeyFromDate(day);
    var repo = await _categoryReportLedger(day);
    for (final id in ['a', 'b']) {
      repo = await repo.addBudget(Budget(
          id: 'budget-$id',
          categoryId: id,
          monthKey: monthKeyFromDate(now),
          amount: 50));
    }
    final payload = repo.buildAiSummaryPayload(monthKeys: [month]);
    final budgetRows =
        (payload['budget_rows_current_month'] as List).cast<Map>();
    expect(
        budgetRows.map((r) => r['category_id']), unorderedEquals(['a', 'b']));
    expect((payload['budgets_current_month'] as Map).length, 2);
    expect((payload['expense_by_month'] as Map)[month], 60);
    expect((payload['planned_expense_by_month'] as Map)[month], 22);
    final categoryRows = ((payload['category_rows_by_month'] as Map)[month]
        as Map)['expense'] as List;
    final byId = {for (final row in categoryRows.cast<Map>()) row['id']: row};
    expect(byId['home']!['actual'], 30);
    expect(byId['home']!['subtree_actual'], 70);
    expect(byId['a']!['actual'], 40);
    expect(byId['b']!['actual'], -20);
    expect(byId['a']!['path'], ['Home', 'Other']);
    expect(byId['b']!['path'], ['Travel', 'Other']);
    expect(byId[null]!['actual'], 10);
    expect(byId[null]!['planned'], 15);
    expect(byId['a']!['planned'], 7);
    final legacy =
        (payload['expense_categories_by_month'] as Map)[month] as Map;
    expect(legacy.values, unorderedEquals([30, 40, -20, 10]));
    final csv = utf8.decode(repo.exportFuturePlanningCsvBytes(months: 1));
    expect(csv, contains('Home / Other,a,Actual,MYR,40.00,40.00'));
    expect(csv, contains('Travel / Other,b,Actual,MYR,-20.00,-20.00'));
    expect(csv, contains('Uncategorized,,Actual,MYR,10.00,10.00'));
    expect(csv, contains('Uncategorized,,Planned,MYR,15.00,15.00'));
    expect(csv, contains('Total Actual,,Actual,MYR,60.00,60.00'));
    expect(csv, contains('Total Planned,,Planned,MYR,22.00,22.00'));
    expect(csv, contains('Total Known,,Actual + Planned,MYR,82.00,82.00'));
  });

  test('unpriced spending survives summary and CSV with native units',
      () async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month + 1, 1);
    final month = monthKeyFromDate(day);
    var repo = await _emptyRepository();
    repo = await repo.addAccount(const Account(
        id: 'chf',
        name: 'Swiss',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'CHF',
        currentBalance: 0));
    repo = await repo.addTransaction(FinanceTransaction(
        id: 'chf-tx',
        accountId: 'chf',
        type: TransactionType.expense,
        amount: 13,
        currency: 'CHF',
        transactionDate: day));
    final payload = repo.buildAiSummaryPayload(monthKeys: [month]);
    expect(payload['unpriced_currencies'], contains('CHF'));
    expect(payload['months'], [month]);
    final buckets = (payload['category_rows'] as Map)['expense'] as List;
    expect(buckets.single['id'], isNull);
    expect(buckets.single['unpriced_actual'], {'CHF': 13.0});
    final csv = utf8.decode(repo.exportFuturePlanningCsvBytes(months: 1));
    expect(csv, contains('Uncategorized,,Unpriced actual,CHF,13.00,13.00'));
    expect(csv, isNot(contains('Uncategorized,,Actual,MYR,0.00')));
  });

  testWidgets('all report totals, expense ranks and chart labels use TWD',
      (tester) async {
    var repository = await _emptyRepository();
    repository = await repository.updateExchangeRates(
      const {'TWD': 1, 'MYR': 7},
      const ['TWD', 'MYR'],
    );
    repository = await repository.addAccount(const Account(
      id: 'cash',
      name: '台币现金',
      accountType: AccountType.cash,
      reportGroup: ReportGroup.cash,
      currency: 'TWD',
      initialBalance: 1000,
      currentBalance: 1000,
    ));
    repository = await _addExpenseCategories(repository, {'food': '伙食费'});
    final now = DateTime.now();
    final date = DateTime(now.year, now.month, 1);
    repository = await repository.addTransactions([
      FinanceTransaction(
        id: 'twd-in',
        type: TransactionType.income,
        accountId: 'cash',
        amount: 100,
        currency: 'TWD',
        transactionDate: date,
      ),
      FinanceTransaction(
        id: 'twd-out',
        type: TransactionType.expense,
        accountId: 'cash',
        categoryId: 'food',
        amount: 245,
        currency: 'TWD',
        transactionDate: date,
      ),
    ]);

    await _pumpReports(tester, repository);
    expect(_text(tester, 'reports-cash-inflow'), 'TWD 100.00');
    expect(_text(tester, 'reports-cash-outflow'), 'TWD 245.00');
    expect(_text(tester, 'reports-cash-net'), '- TWD 145.00');
    expect(_text(tester, 'reports-category-0-amount'), 'TWD 245.00');
    expect(_text(tester, 'reports-category-total'), '已分类支出合计 TWD 245.00');
    expect(find.textContaining(RegExp(r'月均净流入.*TWD')), findsOneWidget);
    expect(find.textContaining('MYR'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected range drives net worth, cash flow and categories',
      (tester) async {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 1);
    final twoYearsAgo = DateTime(now.year - 2, now.month, 1);
    var repository = await _emptyRepository();
    repository = await repository.addAccount(_cash);
    repository = await _addExpenseCategories(repository, {
      'rpt-food': 'Food',
      'rpt-travel': 'Travel',
    });
    repository = await repository.addTransactions([
      _income('old-income', 500, twoYearsAgo),
      _expense('old-travel', 70, twoYearsAgo, categoryId: 'rpt-travel'),
      _income('recent-income', 1000, thisMonth),
      _expense('recent-food', 30, thisMonth, categoryId: 'rpt-food'),
    ]);
    await _pumpReports(tester, repository);

    expect(_text(tester, 'reports-cash-inflow'), compassMoney(1000));
    expect(_text(tester, 'reports-cash-outflow'), compassMoney(30));
    expect(
      _text(tester, 'reports-net-worth-change'),
      contains(compassMoney(970, decimals: 0)),
    );
    expect(_text(tester, 'reports-category-0-name'), 'Food');
    expect(find.byKey(const Key('reports-category-1-name')), findsNothing);

    await _selectRange(tester, '${now.year}年至今', '最近 12 个月');
    expect(find.text('最近12个月'), findsOneWidget);
    expect(_text(tester, 'reports-cash-inflow'), compassMoney(1000));
    expect(find.byKey(const Key('reports-category-1-name')), findsNothing);

    await _selectRange(tester, '最近12个月', '全部时间');
    expect(_text(tester, 'reports-cash-inflow'), compassMoney(1500));
    expect(_text(tester, 'reports-cash-outflow'), compassMoney(100));
    expect(
      _text(tester, 'reports-net-worth-change'),
      allOf(contains('全部时间'), contains(compassMoney(1400, decimals: 0))),
    );
    expect(_text(tester, 'reports-category-0-name'), 'Travel');
    expect(_text(tester, 'reports-category-0-amount'), compassMoney(70));
    expect(_text(tester, 'reports-category-1-name'), 'Food');
    expect(
      _text(tester, 'reports-period-label'),
      contains('${now.year - 2}年${now.month}月'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('period cash flow excludes planned and counts full repayments',
      (tester) async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, 1);
    var repository = await _emptyRepository();
    for (final account in const [
      _cash,
      Account(
        id: 'card',
        name: 'Card',
        accountType: AccountType.creditCard,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        currentBalance: 0,
      ),
      Account(
        id: 'loan',
        name: 'Loan',
        accountType: AccountType.loan,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        currentBalance: -70000,
      ),
      Account(
        id: 'overpaid-card',
        name: 'Overpaid card',
        accountType: AccountType.creditCard,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        currentBalance: 1000,
      ),
      Account(
        id: 'reserve-cash',
        name: 'Reserve cash',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 100,
      ),
    ]) {
      repository = await repository.addAccount(account);
    }
    repository = await _addExpenseCategories(repository, {
      'rpt-food': 'Food',
      'rpt-shopping': 'Shopping',
    });
    repository = await repository.addTransactions([
      _income('income', 1000, day),
      _expense('cash-food', 100, day, categoryId: 'rpt-food'),
      _expense(
        'card-shopping',
        300,
        day,
        accountId: 'card',
        categoryId: 'rpt-shopping',
      ),
      FinanceTransaction(
        id: 'card-payment',
        type: TransactionType.transfer,
        accountId: 'cash',
        toAccountId: 'card',
        amount: 200,
        currency: 'MYR',
        transactionDate: day,
      ),
      FinanceTransaction(
        id: 'loan-payment',
        type: TransactionType.transfer,
        accountId: 'cash',
        toAccountId: 'loan',
        amount: 1316,
        toAmount: 1193.67,
        currency: 'MYR',
        toCurrency: 'MYR',
        transactionDate: day,
      ),
      _expense(
        'planned-food',
        999,
        day,
        categoryId: 'rpt-food',
        status: TransactionStatus.planned,
      ),
    ]);
    await _pumpReports(tester, repository);

    expect(_text(tester, 'reports-cash-inflow'), compassMoney(1000));
    // Cash spend 100 + card repayment 200 + full loan repayment 1316; the
    // card purchase and the planned expense are not cash outflow.
    expect(_text(tester, 'reports-cash-outflow'), compassMoney(1616));
    expect(_text(tester, 'reports-cash-net'), compassMoney(-616));
    final cashFlowTrend = find.byKey(const Key('reports-cash-flow-trend'));
    expect(
      find.descendant(of: cashFlowTrend, matching: find.byType(CustomPaint)),
      findsOneWidget,
    );
    final trendSemantics = tester.widget<Semantics>(find.descendant(
      of: cashFlowTrend,
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.value != null,
      ),
    ));
    expect(trendSemantics.properties.value, contains(compassMoney(-616)));
    final composition = tester.widget<FinanceDonutPanel>(
      find.byKey(const Key('reports-asset-composition')),
    );
    expect(repository.totalAssetsByGroup(ReportGroup.cash), lessThan(0));
    expect(composition.slices.map((slice) => slice.value), [100, 0, 0, 1000]);
    expect(composition.totalValue, compassMoney(1100, decimals: 0));
    expect(
      find.text('负债 ${compassMoney(69522.33, decimals: 0)}'),
      findsOneWidget,
    );
    expect(
      find.text('信用卡溢缴款 ${compassMoney(1000, decimals: 0)}'),
      findsOneWidget,
    );
    expect(_text(tester, 'reports-category-0-name'), 'Shopping');
    expect(_text(tester, 'reports-category-0-amount'), compassMoney(300));
    expect(_text(tester, 'reports-category-1-name'), 'Food');
    expect(_text(tester, 'reports-category-1-amount'), compassMoney(100));
    for (final (label, explanation) in [
      ('实际现金流', '信用卡和贷款还款按全额计入'),
      ('支出分类排行', '按交易发生日统计已分类支出'),
    ]) {
      expect(find.textContaining(explanation), findsNothing);
      await tester.tap(find.byTooltip('查看$label说明'));
      await tester.pumpAndSettle();
      expect(find.textContaining(explanation), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('expense ranking shows the top five with exact amounts',
      (tester) async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, 1);
    const amounts = {
      'A': 12.34,
      'B': 60.5,
      'C': 45.25,
      'D': 30.0,
      'E': 99.99,
      'F': 5.0,
    };
    var repository = await _emptyRepository();
    repository = await repository.addAccount(_cash);
    repository = await _addExpenseCategories(repository, {
      for (final name in amounts.keys) 'rpt-$name': 'Cat $name',
    });
    repository = await repository.addTransactions([
      for (final entry in amounts.entries)
        _expense(
          'spend-${entry.key}',
          entry.value,
          day,
          categoryId: 'rpt-${entry.key}',
        ),
    ]);
    await _pumpReports(tester, repository);

    const expected = ['E', 'B', 'C', 'D', 'A'];
    for (var index = 0; index < expected.length; index++) {
      expect(
        _text(tester, 'reports-category-$index-name'),
        'Cat ${expected[index]}',
      );
      expect(
        _text(tester, 'reports-category-$index-amount'),
        compassMoney(amounts[expected[index]]!),
      );
    }
    expect(find.byKey(const Key('reports-category-5-name')), findsNothing);
    expect(find.text('Cat F'), findsNothing);
    expect(
      _text(tester, 'reports-category-total'),
      allOf(contains(compassMoney(253.08)), contains('共 6 个分类')),
    );
  });

  test('report overview no longer references the legacy ReportsScreen', () {
    final source = File('lib/src/features/reports/reports_v2_screen.dart')
        .readAsStringSync();
    expect(source, isNot(contains("import 'reports_screen.dart'")));
    expect(RegExp(r'\bReportsScreen\b').hasMatch(source), isFalse);
  });

  testWidgets('report sections stay on page and never push a route',
      (tester) async {
    final observer = _PushCounter();
    await _pumpReports(
      tester,
      FinanceRepository.preview(),
      observers: [observer],
    );
    final initialPushes = observer.pushes;
    for (final title in const [
      '实际现金流',
      '支出分类排行 · 前 5',
      '资产构成',
      '本月预算',
      '投资与退休账户',
    ]) {
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
    }
    expect(observer.pushes, initialPushes);
    expect(find.text('健康信号'), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty data shows empty states instead of zero gains',
      (tester) async {
    await _pumpReports(tester, await _emptyRepository());

    expect(find.text('尚未添加账户'), findsOneWidget);
    expect(find.text('所选期间没有实际现金流记录'), findsOneWidget);
    expect(find.text('所选期间没有已分类支出'), findsOneWidget);
    expect(find.text('暂无资产余额'), findsOneWidget);
    expect(find.text('本月尚未设置预算'), findsOneWidget);
    expect(find.text('尚未添加投资或退休账户'), findsOneWidget);
    expect(find.textContaining('+'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('report help and figures fit 320px with each active theme',
      (tester) async {
    final repository = await _populatedRepository();
    const viewport = Size(320, 844);
    for (final style in [
      AppThemeStyle.monochrome,
      AppThemeStyle.dopamine,
      AppThemeStyle.liquidGlass,
    ]) {
      await _pumpReports(tester, repository, size: viewport, style: style);
      final scrollable = find.byType(Scrollable).first;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
      for (final (label, explanation) in [
        ('所选期间', '日期范围影响净资产趋势与变化'),
        ('资产构成', '信用卡溢缴款单独列示'),
      ]) {
        final help = find.byTooltip('查看$label说明');
        await tester.scrollUntilVisible(help, 160, scrollable: scrollable);
        await tester.pumpAndSettle();
        await tester.tap(help);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.textContaining(explanation), findsOneWidget);
        await tester.tap(find.text('知道了'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('desktop aligns trend cards and separates the month-end snapshot',
      (tester) async {
    final repository = await _populatedRepository();
    await _pumpReports(tester, repository, size: const Size(960, 900));

    final netWorthTrend = find.byKey(const Key('reports-net-worth-trend'));
    final cashFlowTrend = find.byKey(const Key('reports-cash-flow-trend'));
    final cashFlow = find.text('实际现金流');
    final assets = find.byKey(const Key('reports-asset-composition'));
    final budget = find.text('本月预算');
    final periodHeading = find.text('所选期间');
    final spend = find.text('支出分类排行 · 前 5');
    final snapshotHeading = find.text('本月末快照');
    final cutoff = repository.currentMonthCutoffDate();
    final cutoffDate = '${cutoff.year}年${cutoff.month}月${cutoff.day}日';
    final netWorthCard = find
        .ancestor(of: netWorthTrend, matching: find.byType(CompassCard))
        .first;
    final cashFlowCard = find
        .ancestor(of: cashFlowTrend, matching: find.byType(CompassCard))
        .first;
    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    for (final width in [960.0, 1440.0]) {
      position.jumpTo(0);
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      final netWorthRect = tester.getRect(netWorthCard);
      final cashFlowRect = tester.getRect(cashFlowCard);
      expect(netWorthRect.right, lessThan(cashFlowRect.left));
      expect(netWorthRect.top, cashFlowRect.top);
      expect(netWorthRect.height, cashFlowRect.height);
      expect(tester.getSize(netWorthTrend).height,
          tester.getSize(cashFlowTrend).height);
      expect(
          tester.getBottomLeft(periodHeading).dy, lessThan(netWorthRect.top));
      final spendingOffset = tester.getTopLeft(spend).dy;
      expect(spendingOffset, greaterThan(cashFlowRect.bottom));
      expect(find.text('分类'), findsOneWidget);
      expect(find.text('金额'), findsOneWidget);
      expect(find.text('占比'), findsOneWidget);
      await tester.scrollUntilVisible(snapshotHeading, 220,
          scrollable: scrollable);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(snapshotHeading).dy + position.pixels,
          greaterThan(spendingOffset));
      await tester.scrollUntilVisible(assets, 220, scrollable: scrollable);
      await tester.pumpAndSettle();
      expect(
          tester.getRect(assets).right, lessThan(tester.getTopLeft(budget).dx));
      expect(find.text(cutoffDate), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'width $width');
    }

    position.jumpTo(0);
    await tester.pumpAndSettle();
    await _selectRange(tester, '${DateTime.now().year}年至今', '全部时间');
    expect(_text(tester, 'reports-net-worth-change'), contains('全部时间'));
    await tester.scrollUntilVisible(assets, 220, scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(find.text(cutoffDate), findsOneWidget);

    position.jumpTo(0);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(_text(tester, 'reports-net-worth-change'), contains('全部时间'));
    expect(periodHeading, findsNothing);
    expect(snapshotHeading, findsNothing);
    final mobileLane = tester.getTopLeft(cashFlow).dx;
    await tester.scrollUntilVisible(assets, 180,
        scrollable: find.byType(Scrollable).first);
    expect(tester.getTopLeft(assets).dx, mobileLane);
    expect(tester.takeException(), isNull);
  });

  testWidgets('390x844 phone viewport lays out every populated section',
      (tester) async {
    const viewport = Size(390, 844);
    const capture = bool.fromEnvironment('CAPTURE_REPORTS_QA');
    if (capture) {
      await _loadCaptureFonts(tester);
    }
    final repository = await _populatedRepository();
    final semantics = tester.ensureSemantics();
    final boundaryKey = GlobalKey();
    await _pumpReports(
      tester,
      repository,
      size: viewport,
      boundaryKey: boundaryKey,
    );
    expect(tester.takeException(), isNull);

    // Every section has data, so no empty state may appear.
    for (final emptyState in const [
      '尚未添加账户，添加账户后可查看净资产变化。',
      '所选期间没有实际现金流记录',
      '所选期间没有已分类支出',
      '暂无资产余额',
      '本月尚未设置预算',
      '尚未添加投资或退休账户',
      '净投入不大于零，收益率不适用',
    ]) {
      expect(find.text(emptyState), findsNothing, reason: emptyState);
    }

    final scrollable = find.byType(Scrollable).first;
    final sections = <String, List<Finder>>{
      '净资产': [
        find.textContaining('月末净资产 · '),
        find.byKey(const Key('reports-net-worth-change')),
        find.byKey(const Key('reports-net-worth-trend')),
      ],
      '实际现金流': [
        find.text('实际现金流'),
        find.byKey(const Key('reports-cash-inflow')),
        find.byKey(const Key('reports-cash-outflow')),
        find.byKey(const Key('reports-cash-net')),
        find.byKey(const Key('reports-cash-flow-trend')),
        find.textContaining('现金结余率'),
      ],
      '分类排行': [
        find.text('支出分类排行 · 前 5'),
        for (var index = 0; index < 5; index++) ...[
          find.byKey(Key('reports-category-$index-name')),
          find.byKey(Key('reports-category-$index-amount')),
        ],
        find.byKey(const Key('reports-category-total')),
      ],
      '资产构成': [
        find.text('资产构成'),
        find.byKey(const Key('reports-asset-composition')),
        find.text('总资产'),
        for (final label in const ['现金', '投资', '退休']) find.text(label),
        find.textContaining('负债 '),
      ],
      '预算': [
        find.text('本月预算'),
        find.byKey(const Key('reports-budget-rate')),
        find.textContaining('已用 '),
        find.textContaining('其中预计'),
      ],
      '投资': [
        find.text('投资与退休账户'),
        find.text('当前市值'),
        find.text('净投入'),
        find.byKey(const Key('reports-investment-pnl')),
        find.textContaining('资金收益率'),
      ],
    };

    // Money values must stay on one line; FittedBox may only shrink them.
    const singleLineKeys = {
      'reports-cash-inflow',
      'reports-cash-outflow',
      'reports-cash-net',
      'reports-category-0-amount',
      'reports-budget-rate',
      'reports-investment-pnl',
    };

    // Walk the important items in page order. Each one must be reachable by
    // scrolling, then sit fully on screen, inside the phone width and not
    // covered by anything else.
    for (final entry in sections.entries) {
      for (final item in entry.value) {
        if (item.evaluate().isEmpty) {
          await tester.scrollUntilVisible(item, 160, scrollable: scrollable);
        } else {
          await tester.ensureVisible(item);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: entry.key);
        _expectFullyOnScreen(tester, item, viewport, section: entry.key);

        final key = tester.widget(item).key;
        if (key is ValueKey<String> && singleLineKeys.contains(key.value)) {
          final paragraph = tester.renderObject<RenderParagraph>(item);
          expect(paragraph.didExceedMaxLines, isFalse, reason: key.value);
          expect(
            paragraph.getMaxIntrinsicWidth(double.infinity),
            lessThanOrEqualTo(paragraph.size.width + 0.5),
            reason: '${key.value} wrapped onto a second line',
          );
        }
        if (key == const Key('reports-category-0-name')) {
          // The long name is ellipsized visually, but its full text stays in
          // the (card-merged) label read by assistive technology.
          expect(tester.getSemantics(item).label, contains(_longCategoryName));
        }
      }
    }

    // Walk the whole page in small drags to catch any late overflow and prove
    // the last section is reachable at the end of the scroll extent.
    await tester.drag(scrollable, const Offset(0, 5000));
    await tester.pumpAndSettle();
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.pixels, position.minScrollExtent);
    expect(position.maxScrollExtent, greaterThan(0));
    var steps = 0;
    while (position.pixels < position.maxScrollExtent && steps++ < 60) {
      await tester.drag(scrollable, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'at ${position.pixels}');
    }
    expect(position.pixels, position.maxScrollExtent);
    _expectFullyOnScreen(
      tester,
      find.textContaining('资金收益率'),
      viewport,
      section: '页面底部',
    );

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();

    if (capture) {
      // One tall frame at the same 390px width renders the whole page.
      tester.view.physicalSize = Size(
        viewport.width,
        viewport.height + position.maxScrollExtent,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('artifacts/qa/reports-v2-390.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
      });
    }
  });

  testWidgets('unchanged net worth is not labelled as a gain', (tester) async {
    var repository = await _emptyRepository();
    repository = await repository.addAccount(
      const Account(
        id: 'savings',
        name: 'Savings',
        accountType: AccountType.bankSaving,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 1000,
      ),
    );
    await _pumpReports(tester, repository);

    final change = _text(tester, 'reports-net-worth-change');
    expect(change, contains(compassMoney(0, decimals: 0)));
    expect(change, contains('0.0%'));
    expect(change, isNot(contains('+')));
  });
}

const _cash = Account(
  id: 'cash',
  name: 'Cash',
  accountType: AccountType.bankSaving,
  reportGroup: ReportGroup.cash,
  currency: 'MYR',
  currentBalance: 0,
);

Future<FinanceRepository> _emptyRepository() async {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  return FinanceRepository.load(database);
}

Future<FinanceRepository> _categoryReportLedger(DateTime day) async {
  var repo = await _emptyRepository();
  repo = await repo.addAccount(_cash);
  for (final c in const [
    Category(id: 'home', name: 'Home', type: CategoryType.expense),
    Category(id: 'travel', name: 'Travel', type: CategoryType.expense),
    Category(
        id: 'a', name: 'Other', type: CategoryType.expense, parentId: 'home'),
    Category(
        id: 'b', name: 'Other', type: CategoryType.expense, parentId: 'travel'),
  ]) {
    repo = await repo.addCategory(c);
  }
  return repo.addTransactions([
    _expense('parent', 30, day, categoryId: 'home'),
    _expense('child', 40, day, categoryId: 'a'),
    _expense('refund', -20, day, categoryId: 'b'),
    _expense('uncategorized', 10, day),
    _expense('future-child', 7, day,
        categoryId: 'a', status: TransactionStatus.planned),
    _expense('future-none', 15, day, status: TransactionStatus.planned),
  ]);
}

Future<FinanceRepository> _addExpenseCategories(
  FinanceRepository repository,
  Map<String, String> names,
) async {
  var updated = repository;
  for (final entry in names.entries) {
    updated = await updated.addCategory(
      Category(id: entry.key, name: entry.value, type: CategoryType.expense),
    );
  }
  return updated;
}

FinanceTransaction _income(String id, double amount, DateTime date) =>
    FinanceTransaction(
      id: id,
      type: TransactionType.income,
      accountId: 'cash',
      amount: amount,
      currency: 'MYR',
      transactionDate: date,
    );

FinanceTransaction _expense(
  String id,
  double amount,
  DateTime date, {
  String accountId = 'cash',
  String? categoryId,
  TransactionStatus status = TransactionStatus.actual,
}) =>
    FinanceTransaction(
      id: id,
      type: TransactionType.expense,
      accountId: accountId,
      amount: amount,
      currency: 'MYR',
      transactionDate: date,
      categoryId: categoryId,
      status: status,
    );

Future<void> _pumpReports(
  WidgetTester tester,
  FinanceRepository repository, {
  List<NavigatorObserver> observers = const [],
  // Keep the 390px phone width; the tall surface builds every section.
  Size size = const Size(390, 3200),
  Key? boundaryKey,
  AppThemeStyle style = AppThemeStyle.abyss,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildFinanceTheme(style),
      navigatorObservers: observers,
      home: RepaintBoundary(
        key: boundaryKey,
        child: Scaffold(body: ReportsV2Screen(repository: repository)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _longCategoryName = '家庭日常生活用品、超市采购与线上网购合计支出';

/// Current-month data that fills every report section with long names and
/// six- and seven-digit amounts, the worst realistic case for a 390px width.
Future<FinanceRepository> _populatedRepository() async {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, 1);
  var repository = await _emptyRepository();
  for (final account in const [
    Account(
      id: 'cash',
      name: 'Cash',
      accountType: AccountType.bankSaving,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      currentBalance: 1284567.89,
      initialBalance: 1284567.89,
    ),
    Account(
      id: 'card',
      name: 'Card',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      currentBalance: 0,
      creditLimit: 50000,
      statementDay: 25,
      paymentDueDay: 14,
    ),
    Account(
      id: 'invest',
      name: 'Brokerage',
      accountType: AccountType.trading,
      reportGroup: ReportGroup.investment,
      currency: 'MYR',
      currentBalance: 0,
    ),
    Account(
      id: 'epf',
      name: 'EPF',
      accountType: AccountType.pension,
      reportGroup: ReportGroup.retirement,
      currency: 'MYR',
      currentBalance: 0,
    ),
  ]) {
    repository = await repository.addAccount(account);
  }
  repository = await repository.addAssetSnapshot(AssetSnapshot(
    id: 'invest-snapshot',
    accountId: 'invest',
    snapshotDate: day,
    marketValue: 386543.21,
    costBasis: 412000,
  ));
  repository = await repository.addAssetSnapshot(AssetSnapshot(
    id: 'epf-snapshot',
    accountId: 'epf',
    snapshotDate: day,
    marketValue: 1432109.87,
    costBasis: 1200000,
  ));
  repository = await _addExpenseCategories(repository, {
    'qa-home': _longCategoryName,
    'qa-housing': '房贷与物业管理费',
    'qa-education': 'Children education & tuition',
    'qa-travel': '旅行',
    'qa-insurance': '保险',
    'qa-fun': '娱乐',
  });
  for (final entry in const {
    'qa-home': 30000.0,
    'qa-housing': 42000.0,
    'qa-education': 9000.0,
  }.entries) {
    repository = await repository.addBudget(Budget(
      id: 'budget-${entry.key}',
      categoryId: entry.key,
      monthKey: monthKeyFromDate(day),
      amount: entry.value,
    ));
  }
  return repository.addTransactions([
    _income('qa-salary', 188888.88, day),
    _expense('qa-home-spend', 26543.21, day, categoryId: 'qa-home'),
    _expense('qa-housing-spend', 38210.55, day, categoryId: 'qa-housing'),
    _expense('qa-education-spend', 8765.43, day, categoryId: 'qa-education'),
    _expense('qa-travel-spend', 12345.67, day, categoryId: 'qa-travel'),
    _expense('qa-insurance-spend', 4321, day, categoryId: 'qa-insurance'),
    _expense('qa-fun-spend', 999.99, day, categoryId: 'qa-fun'),
    _expense(
      'qa-card-spend',
      23456.78,
      day,
      accountId: 'card',
      categoryId: 'qa-home',
    ),
    _expense(
      'qa-planned-spend',
      3000,
      day,
      categoryId: 'qa-education',
      status: TransactionStatus.planned,
    ),
  ]);
}

void _expectFullyOnScreen(
  WidgetTester tester,
  Finder finder,
  Size viewport, {
  required String section,
}) {
  expect(finder, findsOneWidget, reason: '$section: $finder');
  final rect = tester.getRect(finder);
  final reason = '$section: $finder at $rect';
  // Half a pixel absorbs floating-point noise from scroll offsets and
  // FittedBox scaling.
  const tolerance = 0.5;
  expect(rect.width, greaterThan(0), reason: reason);
  expect(rect.height, greaterThan(0), reason: reason);
  expect(rect.left, greaterThanOrEqualTo(-tolerance), reason: reason);
  expect(
    rect.right,
    lessThanOrEqualTo(viewport.width + tolerance),
    reason: reason,
  );
  expect(rect.top, greaterThanOrEqualTo(-tolerance), reason: reason);
  expect(
    rect.bottom,
    lessThanOrEqualTo(viewport.height + tolerance),
    reason: reason,
  );
  expect(finder.hitTestable(), findsOneWidget, reason: '$reason is covered');
}

/// Swaps the square test glyphs for a local CJK font and the SDK's Material
/// icons so the exported PNG is readable. Only used when capturing.
Future<void> _loadCaptureFonts(WidgetTester tester) async {
  await tester.runAsync(() async {
    final config = jsonDecode(
      await File('.dart_tool/package_config.json').readAsString(),
    ) as Map<String, dynamic>;
    final flutterPackage = (config['packages'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((package) => package['name'] == 'flutter');
    final flutterRoot =
        Directory.fromUri(Uri.parse(flutterPackage['rootUri'] as String))
            .parent
            .parent;
    final fonts = {
      'Roboto': [
        'C:/Windows/Fonts/NotoSansSC-VF.ttf',
        'C:/Windows/Fonts/msyh.ttc',
        '/System/Library/Fonts/PingFang.ttc',
        '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
      ],
      'MaterialIcons': [
        '${flutterRoot.path}/bin/cache/artifacts/material_fonts/'
            'MaterialIcons-Regular.otf',
      ],
    };
    for (final entry in fonts.entries) {
      final path = entry.value.firstWhere(
        (candidate) => File(candidate).existsSync(),
        orElse: () => '',
      );
      if (path.isEmpty) {
        continue;
      }
      final bytes = await File(path).readAsBytes();
      await (FontLoader(entry.key)
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  });
}

String _text(WidgetTester tester, String key) {
  final widget = tester.widget<Text>(find.byKey(Key(key)));
  return widget.data ?? widget.textSpan!.toPlainText();
}

Future<void> _selectRange(
  WidgetTester tester,
  String current,
  String option,
) async {
  await tester.tap(find.text(current));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

class _PushCounter extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}
