import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    hide Account, Category;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/accounts/accounts_v2_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('account cutoff selector recalculates totals at prior month end',
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

    final now = DateTime.now();
    final previousMonth = DateTime(now.year, now.month - 1);
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'previous-expense',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 100,
        currency: 'MYR',
        transactionDate: DateTime(previousMonth.year, previousMonth.month, 10),
      ),
    );
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'current-expense',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 200,
        currency: 'MYR',
        transactionDate: DateTime(now.year, now.month, 10),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.abyss),
        home: Scaffold(body: AccountsV2Screen(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MYR 700.00'), findsWidgets);
    await tester.tap(find.byKey(const Key('account-cutoff-selector')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account-cutoff-month-list')), findsOneWidget);

    await tester.tap(
      find.byKey(
        Key('account-cutoff-${previousMonth.year}-${previousMonth.month}'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('account-historical-cutoff-banner')),
      findsOneWidget,
    );
    expect(find.text('MYR 900.00'), findsWidgets);
    expect(find.textContaining('历史统计 · 截至'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
