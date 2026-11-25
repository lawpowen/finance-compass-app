import 'dart:convert';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/accounts/accounts_v2_screen.dart';
import 'package:finance_app/src/features/dashboard/dashboard_v2_screen.dart';
import 'package:finance_app/src/features/shared/compass_ui.dart';
import 'package:finance_app/src/features/transactions/transaction_composer_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('repayment and statement reminders use their own preferences',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.now();
    var ledger = await FinanceRepository.load(database);
    ledger = await ledger.addAccount(Account(
      id: 'card',
      name: 'Daily card',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      currentBalance: 0,
      creditLimit: 1000,
      statementDay: now.day,
      paymentDueDay: now.day,
    ));
    ledger = await ledger.addTransaction(FinanceTransaction(
      id: 'charge',
      accountId: 'card',
      type: TransactionType.expense,
      currency: 'MYR',
      amount: 50,
      transactionDate: now,
    ));
    for (final (enabled, repayment, statement) in [
      (true, true, false),
      (true, false, true),
      (true, true, true),
      (false, true, true),
    ]) {
      await database.setMetaValue('notifications_enabled', '$enabled');
      await database.setMetaValue('notification_preferences_json',
          jsonEncode([repayment, statement, true, true, true, false, true]));
      ledger = await ledger.refresh();
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.abyss),
        home: Scaffold(body: DashboardV2Screen(repository: ledger)),
      )));
      await tester.pumpAndSettle();
      expect(find.text('Daily card · 账单结算'),
          enabled && statement ? findsOneWidget : findsNothing);
      expect(find.textContaining('还款日 '),
          enabled && repayment ? findsOneWidget : findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'forecast converts every statement and counts a planned FX repayment once',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    repository = await repository.updateExchangeRates(
      {'MYR': 1, 'USD': 4, 'CNY': .5, 'TWD': .14},
      ['MYR', 'USD', 'CNY', 'TWD'],
    );
    repository = await repository.addAccount(const Account(
      id: 'cash',
      name: 'Cash',
      accountType: AccountType.cash,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      initialBalance: 2000,
      currentBalance: 2000,
    ));
    final now = DateTime.now();
    DateTime offset(int days) => DateTime(now.year, now.month, now.day + days);
    final closed = offset(-1);
    final priorMonthEnd = DateTime(now.year, now.month, 0);
    for (final (id, currency, amount, purchaseDate, statementDay, dueDay) in [
      ('USD card', 'USD', 100.0, closed, closed.day, offset(9).day),
      ('CNY card', 'CNY', 300.0, closed, closed.day, offset(17).day),
      ('Local card', 'MYR', 90.0, priorMonthEnd, 1, 2),
    ]) {
      repository = await repository.addAccount(Account(
        id: id,
        name: id,
        accountType: AccountType.creditCard,
        reportGroup: ReportGroup.credit,
        currency: currency,
        currentBalance: 0,
        creditLimit: 2000,
        statementDay: statementDay,
        paymentDueDay: dueDay,
      ));
      repository = await repository.addTransaction(FinanceTransaction(
        id: 'purchase-$id',
        type: TransactionType.expense,
        accountId: id,
        currency: currency,
        amount: amount,
        transactionDate: purchaseDate,
      ));
    }
    repository = await repository.addTransaction(FinanceTransaction(
      id: 'planned-usd-repayment',
      type: TransactionType.transfer,
      accountId: 'cash',
      currency: 'MYR',
      amount: 200,
      toAccountId: 'USD card',
      toCurrency: 'USD',
      toAmount: 50,
      transactionDate: offset(1),
      status: TransactionStatus.planned,
    ));
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.abyss),
          home: Scaffold(body: DashboardV2Screen(repository: repository))),
    ));
    await tester.pumpAndSettle();

    // MYR 640 due (400 + 150 + 90), of which the transfer covers MYR 200.
    // The local statement is already due or falls tomorrow; USD and CNY
    // fall between successive chart samples on days 9 and 17.
    final chart =
        tester.widget<CompassAreaChart>(find.byType(CompassAreaChart));
    expect(chart.values, [2000, 1710, 1510, 1360, 1360, 1360]);
    expect(find.text(compassMoney(1360, currency: 'MYR')), findsWidgets);
    expect(find.text('未安排信用卡还款 ${compassMoney(440, currency: 'MYR')}'),
        findsOneWidget);
    final usdRow = find.textContaining('USD card · ');
    final cnyRow = find.textContaining('CNY card · ');
    final localRow = find.text('Local card · ${priorMonthEnd.month}月账单');
    expect(
        tester.getTopLeft(usdRow).dy, lessThan(tester.getTopLeft(cnyRow).dy));
    expect(
        tester.getTopLeft(cnyRow).dy, lessThan(tester.getTopLeft(localRow).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard keeps the forecast range when switching layouts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = await FinanceRepository.load(database);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildFinanceTheme(
            AppThemeStyle.abyss,
          ).copyWith(splashFactory: NoSplash.splashFactory),
          home: Scaffold(body: DashboardV2Screen(repository: repository)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('未来 30 天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('未来 60 天').last);
    await tester.pumpAndSettle();

    expect(find.text('未来 60 天'), findsOneWidget);
    final chart = find.byType(CompassAreaChart);
    final attention = find.text('需要关注');
    final distribution = find.byKey(const Key('dashboard-asset-composition'));
    final record = find.text('记账');
    expect(tester.getTopLeft(attention).dy,
        greaterThan(tester.getBottomRight(record).dy));
    expect(tester.getTopLeft(distribution).dy,
        greaterThan(tester.getTopLeft(attention).dy));
    final samples = tester.widget<CompassAreaChart>(chart).values;
    final flat = samples.every((sample) => sample == samples.first);
    expect(tester.getSize(chart).height, flat ? 92 : 190);

    tester.view.physicalSize = const Size(1024, 844);
    await tester.pumpAndSettle();

    expect(find.text('未来 60 天'), findsOneWidget);
    expect(tester.getSize(chart).height, flat ? 92 : 200);
    expect(tester.getTopLeft(attention).dy,
        greaterThan(tester.getBottomRight(chart).dy));
    final assetRect = tester.getRect(distribution);
    expect(assetRect.left, greaterThan(tester.getBottomRight(chart).dx));
    expect(tester.getTopLeft(attention).dx, lessThan(assetRect.left));
    expect(
        tester.getBottomRight(record).dy, lessThan(tester.getRect(chart).top));
    expect(find.textContaining('今日余额'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final accountsLink = find.byKey(const Key('dashboard-asset-accounts'));
    await tester.ensureVisible(accountsLink);
    await tester.tap(accountsLink);
    await tester.pumpAndSettle();
    expect(find.byType(AccountsV2Screen), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    await tester.ensureVisible(record);
    await tester.tap(record);
    await tester.pumpAndSettle();
    expect(find.byType(TransactionComposerPage), findsOneWidget);
  });

  testWidgets('forecast and attention explanations open on a 320px screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = await FinanceRepository.load(database);

    for (final style in [
      AppThemeStyle.monochrome,
      AppThemeStyle.dopamine,
      AppThemeStyle.liquidGlass,
    ]) {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: buildFinanceTheme(style),
          home: Scaffold(body: DashboardV2Screen(repository: repository)),
        ),
      ));
      await tester.pumpAndSettle();
      final scrollable = find.byType(Scrollable).first;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
      for (final (label, explanation) in [
        ('现金预测', '区间最低是这些取样点中的最低余额'),
        ('需要关注', '达到提醒阈值的预算'),
        ('资产构成', '负债单独列示'),
      ]) {
        final help = find.byWidgetPredicate(
          (widget) => widget is CompassHelpButton && widget.title == label,
        );
        await tester.scrollUntilVisible(
          help,
          150,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('查看$label说明'), findsOneWidget);
        expect(find.textContaining(explanation), findsNothing);
        await tester
            .tap(find.descendant(of: help, matching: find.byType(IconButton)));
        await tester.pumpAndSettle();
        expect(find.textContaining(explanation), findsOneWidget);
        await tester.tap(find.text('知道了'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      }
    }
  });
}
