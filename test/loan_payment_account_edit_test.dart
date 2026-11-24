import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/shared/finance_amount_field.dart';
import 'package:finance_app/src/features/transactions/transaction_composer_page.dart';
import 'package:finance_app/src/features/transactions/transaction_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final status in [TransactionStatus.actual, TransactionStatus.planned]) {
    for (final sourceCurrency in ['MYR', 'USD']) {
      testWidgets(
          'changing $status loan payer to $sourceCurrency preserves principal and balances',
          (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        var repository = await FinanceRepository.load(database);
        for (final account in [
          const Account(
            id: 'old-payer',
            name: '原付款账户',
            accountType: AccountType.bankSaving,
            reportGroup: ReportGroup.cash,
            currency: 'MYR',
            currentBalance: 5000,
          ),
          Account(
            id: 'new-payer',
            name: '新付款账户',
            accountType: AccountType.bankSaving,
            reportGroup: ReportGroup.cash,
            currency: sourceCurrency,
            currentBalance: 8000,
          ),
          const Account(
            id: 'loan',
            name: '车贷',
            accountType: AccountType.loan,
            reportGroup: ReportGroup.credit,
            currency: 'MYR',
            currentBalance: -71097,
          ),
        ]) {
          repository = await repository.addAccount(account);
        }
        final original = FinanceTransaction(
          id: 'loan-payment',
          type: TransactionType.transfer,
          accountId: 'old-payer',
          toAccountId: 'loan',
          amount: 1316,
          toAmount: 1191.58,
          currency: 'MYR',
          toCurrency: 'MYR',
          transactionDate: DateTime(2026, 7, 23),
          description: '贷款月供 #1',
          status: status,
        );
        repository = await repository.addTransaction(original);
        TransactionFormResult? saved;
        await tester.pumpWidget(MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.abyss),
          home: Builder(
              builder: (context) => Scaffold(
                    body: FilledButton(
                      onPressed: () async {
                        saved = await Navigator.of(context)
                            .push<TransactionFormResult>(
                          MaterialPageRoute(
                              builder: (_) => TransactionComposerPage(
                                    repository: repository,
                                    draft: original,
                                    editExisting: true,
                                  )),
                        );
                      },
                      child: const Text('编辑月供'),
                    ),
                  )),
        ));
        await tester.tap(find.text('编辑月供'));
        await tester.pumpAndSettle();

        // Exercise the real account selector repeatedly, including switching back.
        for (final name in ['新付款账户', '原付款账户', '新付款账户']) {
          await tester.tap(find.byType(OutlinedButton).first);
          await tester.pumpAndSettle();
          await tester.tap(find.textContaining('$name ·'));
          await tester.pumpAndSettle();
          final fields = tester
              .widgetList<FinanceAmountField>(find.byType(FinanceAmountField))
              .toList();
          expect(fields[0].controller.text, '1316.00');
          expect(fields[1].controller.text, '1191.58');
        }
        const loanAmountHelp = '贷款月供 · 转出为本息合计，转入仅偿还本金';
        expect(find.text('本息 → 本金'), findsOneWidget);
        expect(find.text(loanAmountHelp), findsNothing);
        final help = find.byTooltip('查看转入金额说明');
        await tester.ensureVisible(help);
        await tester.tap(help);
        await tester.pumpAndSettle();
        expect(find.text(loanAmountHelp), findsOneWidget);
        await tester.tap(find.text('知道了'));
        await tester.pumpAndSettle();
        expect(find.text('重新换算'), findsNothing);
        await tester.tap(find.text('保存修改').first);
        await tester.pumpAndSettle();
        final edited = saved!.transactions.single;
        expect(edited.id, original.id);
        expect(edited.accountId, 'new-payer');
        expect(edited.toAccountId, 'loan');
        expect(edited.amount, 1316);
        expect(edited.toAmount, 1191.58);
        expect(edited.currency, sourceCurrency);
        expect(edited.toCurrency, 'MYR');
        expect(edited.status, status);
        repository = await repository.updateExistingTransaction(edited);
        final reloaded = await FinanceRepository.load(database);
        final actual = status == TransactionStatus.actual;
        for (final repo in [repository, reloaded]) {
          double balance(String id) =>
              repo.accounts.singleWhere((a) => a.id == id).currentBalance;
          expect(balance('old-payer'), 5000);
          expect(balance('new-payer'), actual ? 6684 : 8000);
          expect(balance('loan'), closeTo(actual ? -69905.42 : -71097, 0.001));
          expect(repo.transactions.single.toAmount, 1191.58);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
