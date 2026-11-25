import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/transactions/transaction_automation_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Ledger extends FinanceRepositoryNotifier {
  _Ledger(this.initial);
  final FinanceRepository initial;
  @override
  Future<FinanceRepository> build() async => initial;
}

void main() {
  for (final recurring in [false, true]) {
    testWidgets(
        'live ${recurring ? 'rule' : 'template'} merges a clean remote field and respects deletion',
        (tester) async {
      tester.view.physicalSize = const Size(520, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      var repo = await FinanceRepository.load(db);
      repo = await repo.addAccount(const Account(
        id: 'wallet',
        name: 'My wallet',
        currency: 'MYR',
        currentBalance: 500,
        reportGroup: ReportGroup.cash,
        accountType: AccountType.cash,
      ));
      final seed = FinanceTransaction(
          id: 's',
          type: TransactionType.expense,
          accountId: 'wallet',
          amount: 10,
          currency: 'MYR',
          transactionDate: DateTime(2024, 1, 1),
          merchant: 'Cafe');
      repo = recurring
          ? await repo.saveRecurringTransactionRule(
              RecurringTransactionRule.fromTransaction(
                  id: 'preset', name: 'Before', transaction: seed))
          : await repo.saveTransactionTemplate(
              TransactionTemplate.fromTransaction(
                  id: 'preset', name: 'Before', transaction: seed));
      final container = ProviderContainer(overrides: [
        financeRepositoryProvider.overrideWith(() => _Ledger(repo)),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              theme: buildFinanceTheme(AppThemeStyle.abyss),
              home: recurring
                  ? RecurringPlanPage(repository: repo)
                  : QuickTemplateManagerPage(repository: repo))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Before'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Local name');
      final notifier = container.read(financeRepositoryProvider.notifier);
      await notifier.mutate((r) async {
        if (recurring) {
          final json = r.recurringTransactionRules.single.toJson()
            ..['amount'] = 99.0;
          return r.saveRecurringTransactionRule(
              RecurringTransactionRule.fromJson(json),
              requireExisting: true);
        }
        final json = r.transactionTemplates.single.toJson()..['amount'] = 99.0;
        return r.saveTransactionTemplate(TransactionTemplate.fromJson(json));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('99.00'), findsWidgets);
      expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          'Local name');
      final save = find.text('保存更改');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final saved = await FinanceRepository.load(db);
      expect(
          recurring
              ? saved.recurringTransactionRules.single.name
              : saved.transactionTemplates.single.name,
          'Local name');
      expect(
          recurring
              ? saved.recurringTransactionRules.single.amount
              : saved.transactionTemplates.single.amount,
          99);
      await tester.tap(find.text('Local name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Unpublished draft');
      await notifier.mutate((r) {
        if (recurring) {
          return r.saveRecurringTransactionRule(
              RecurringTransactionRule.fromJson(
                  r.recurringTransactionRules.single.toJson()
                    ..['name'] = 'Remote edit'));
        }
        return r.saveTransactionTemplate(TransactionTemplate.fromJson(
            r.transactionTemplates.single.toJson()..['name'] = 'Remote edit'));
      });
      await tester.pumpAndSettle();
      expect(find.text('重新载入记录'), findsOneWidget);
      expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          'Unpublished draft');

      await notifier.mutate((r) => recurring
          ? r.deleteRecurringTransactionRule('preset')
          : r.deleteTransactionTemplate('preset'));
      await tester.pumpAndSettle();
      expect(find.text('此记录已删除或账本已切换。'), findsOneWidget);
      expect(find.text('保存更改'), findsNothing);
      final originalTemplate = saved.transactionTemplates.firstOrNull;
      final originalRule = saved.recurringTransactionRules.firstOrNull;
      await expectLater(
          recurring
              ? saved.saveRecurringTransactionRule(originalRule!,
                  expected: originalRule)
              : saved.saveTransactionTemplate(originalTemplate!,
                  expected: originalTemplate),
          throwsFormatException);

      expect(tester.takeException(), isNull);
    });
  }
}
