import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/budget.dart';
import 'package:finance_app/src/core/models/category.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/database_provider.dart';
import 'package:finance_app/src/core/settings/app_settings_controller.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/budgets/budgets_v2_screen.dart';
import 'package:finance_app/src/features/settings/settings_reference_pages.dart';
import 'package:finance_app/src/features/transactions/transactions_v2_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture approved screens at 390px', (tester) async {
    late Directory output;
    late AppDatabase database;
    late FinanceRepository repository;
    await tester.runAsync(() async {
      output = Directory('artifacts/design-qa');
      await output.create(recursive: true);
      database = AppDatabase.forTesting(NativeDatabase.memory());
      repository = await FinanceRepository.load(database);
      repository = await repository.addAccount(
        const Account(
          id: 'cash',
          name: '现金账户',
          accountType: AccountType.cash,
          reportGroup: ReportGroup.cash,
          currency: 'MYR',
          currentBalance: 12000,
          initialBalance: 12000,
        ),
      );
      repository = await repository.addAccount(
        const Account(
          id: 'credit',
          name: '主力信用卡',
          accountType: AccountType.creditCard,
          reportGroup: ReportGroup.credit,
          currency: 'MYR',
          currentBalance: 0,
          creditLimit: 10000,
          statementDay: 25,
          paymentDueDay: 14,
        ),
      );

      const categories = [
        Category(id: 'loan', name: 'Car Loan', type: CategoryType.expense),
        Category(
            id: 'daily', name: 'Daily expenses', type: CategoryType.expense),
        Category(id: 'transport', name: '交通', type: CategoryType.expense),
        Category(
            id: 'family', name: 'Pay for family', type: CategoryType.expense),
        Category(
            id: 'insurance', name: 'Insurance', type: CategoryType.expense),
        Category(id: 'fun', name: 'Entertainment', type: CategoryType.expense),
      ];
      for (final category in categories) {
        repository = await repository.addCategory(category);
      }

      const budgets = [
        Budget(id: 'b1', categoryId: 'loan', monthKey: '2026-07', amount: 1316),
        Budget(id: 'b2', categoryId: 'daily', monthKey: '2026-07', amount: 900),
        Budget(
            id: 'b3',
            categoryId: 'transport',
            monthKey: '2026-07',
            amount: 700),
        Budget(
            id: 'b4', categoryId: 'family', monthKey: '2026-07', amount: 500),
        Budget(
            id: 'b5',
            categoryId: 'insurance',
            monthKey: '2026-07',
            amount: 400),
        Budget(id: 'b6', categoryId: 'fun', monthKey: '2026-07', amount: 200),
      ];
      for (final budget in budgets) {
        repository = await repository.addBudget(budget);
      }

      final transactions = [
        _expense('t1', 'daily', 517),
        _expense('t2', 'transport', 355),
        _expense('t3', 'family', 112),
        _expense('t4', 'insurance', 41),
        _expense('t5', 'fun', 120, status: TransactionStatus.planned),
        FinanceTransaction(
          id: 'card-shopping',
          type: TransactionType.expense,
          accountId: 'credit',
          categoryId: 'daily',
          amount: 268,
          currency: 'MYR',
          transactionDate: DateTime(2026, 7, 14),
          merchant: 'Lazada',
        ),
        FinanceTransaction(
          id: 'cash-income',
          type: TransactionType.income,
          accountId: 'cash',
          amount: 8800,
          currency: 'MYR',
          transactionDate: DateTime(2026, 7, 15),
          merchant: '薪资收入',
        ),
        FinanceTransaction(
          id: 'credit-repayment',
          type: TransactionType.transfer,
          accountId: 'cash',
          toAccountId: 'credit',
          amount: 200,
          currency: 'MYR',
          transactionDate: DateTime(2026, 7, 16),
          description: '信用卡还款',
        ),
      ];
      repository = await repository.addTransactions(transactions);
    });

    await _capture(
      tester,
      outputPath: '${output.path}/budget-overview-390.png',
      database: database,
      child: BudgetsV2Screen(repository: repository),
    );

    await _capture(
      tester,
      outputPath: '${output.path}/appearance-carousel-390.png',
      database: database,
      child: AppearancePage(settingsController: AppSettingsController()),
    );

    await _capture(
      tester,
      outputPath: '${output.path}/transaction-basis-cards-390.png',
      database: database,
      child: TransactionsV2Screen(repository: repository),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(database.close);
  });
}

FinanceTransaction _expense(
  String id,
  String categoryId,
  double amount, {
  TransactionStatus status = TransactionStatus.actual,
}) =>
    FinanceTransaction(
      id: id,
      type: TransactionType.expense,
      accountId: 'cash',
      categoryId: categoryId,
      amount: amount,
      currency: 'MYR',
      transactionDate: DateTime(2026, 7, 10),
      status: status,
    );

Future<void> _capture(
  WidgetTester tester, {
  required String outputPath,
  required AppDatabase database,
  required Widget child,
}) async {
  final boundaryKey = GlobalKey();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildFinanceTheme(AppThemeStyle.abyss).copyWith(
          splashFactory: NoSplash.splashFactory,
        ),
        home: RepaintBoundary(
          key: boundaryKey,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(outputPath)
        .writeAsBytes(data!.buffer.asUint8List(), flush: true);
  });
}
