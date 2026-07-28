import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart' hide Account;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/mutations/transaction_mutations.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/features/accounts/loan_detail_screen.dart';
import 'package:finance_app/src/features/accounts/account_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loan form saves complete terms at 390 logical pixels',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const incompleteLoan = Account(
      id: 'legacy_loan',
      name: '旧贷款',
      accountType: AccountType.loan,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: -120000,
      currentBalance: -120000,
    );
    Account? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.abyss),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showDialog<Account>(
                  context: context,
                  builder: (_) => const AccountFormDialog(
                    initialAccount: incompleteLoan,
                  ),
                );
              },
              child: const Text('编辑贷款'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('编辑贷款'));
    await tester.pumpAndSettle();

    expect(find.text('贷款金额'), findsOneWidget);
    expect(find.text('年利率'), findsOneWidget);
    expect(find.text('还款方式'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('loan-opening-balance')),
      '71097',
    );
    await tester.tap(find.text('保存更改'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.loanPrincipal, 120000);
    expect(result!.loanTermMonths, 60);
    expect(result!.loanRepaymentMethod, LoanRepaymentMethod.equalInstallment);
    expect(result!.initialBalance, -71097);
    expect(result!.currentBalance, -71097);
    expect(tester.takeException(), isNull);
  });

  testWidgets('planned and actual loan records use the full monthly payment',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    const cash = Account(
      id: 'cash',
      name: '还款户口',
      accountType: AccountType.bankSaving,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      initialBalance: 20000,
      currentBalance: 20000,
    );
    final loan = Account(
      id: 'loan',
      name: '车贷',
      accountType: AccountType.loan,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: -12000,
      currentBalance: -12000,
      loanPrincipal: 12000,
      loanAnnualInterestRate: 12,
      loanTermMonths: 12,
      loanStartDate: DateTime(2026, 7, 1),
      loanPaymentDay: 15,
      loanRepaymentMethod: LoanRepaymentMethod.equalPrincipal,
    );
    repository = await repository.addAccount(cash);
    repository = await repository.addAccount(loan);

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
          home: LoanDetailScreen(
            account: loan,
            repository: repository,
            promptForPlannedGeneration: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('生成预计还款交易？'), findsOneWidget);
    await tester.tap(find.text('暂不生成'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('loan-installment-1')), findsOneWidget);
    expect(find.text('生成 12 期预计交易'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('generate-loan-planned-transactions')),
    );
    await tester.tap(
      find.byKey(const Key('generate-loan-planned-transactions')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(cash.name));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生成'));
    await tester.pumpAndSettle();

    final planned = await container.read(financeRepositoryProvider.future);
    expect(
      planned.transactions
          .where((item) => item.status == TransactionStatus.planned),
      hasLength(12),
    );
    final firstPlanned = planned.transactions.singleWhere(
      (item) => item.description == '贷款月供 #1',
    );
    expect(firstPlanned.amount, 1120);
    expect(firstPlanned.toAmount, 1000);
    expect(find.text('预计交易已补齐'), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(0, 600));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const Key('record-loan-installment')));
    await tester.tap(find.byKey(const Key('record-loan-installment')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(cash.name));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认记录'));
    await tester.pumpAndSettle();

    final updated = await container.read(financeRepositoryProvider.future);
    final payment = updated.transactions.singleWhere(
      (item) =>
          item.type == TransactionType.transfer &&
          item.status == TransactionStatus.actual,
    );
    expect(payment.amount, 1120);
    expect(payment.toAmount, 1000);
    expect(payment.toAccountId, loan.id);
    expect(payment.description, '贷款月供 #1');
    expect(
      updated.transactions
          .where((item) => item.status == TransactionStatus.planned),
      hasLength(11),
    );
    expect(
      updated.accounts.singleWhere((item) => item.id == loan.id).currentBalance,
      -11000,
    );
    expect(
      updated.accounts.singleWhere((item) => item.id == cash.id).currentBalance,
      18880,
    );
    expect(find.textContaining('已记录'), findsWidgets);

    await container
        .read(transactionMutationsProvider.notifier)
        .deleteTransaction(payment.id);
    await tester.pumpAndSettle();
    final afterDelete = await container.read(financeRepositoryProvider.future);
    expect(
        afterDelete.transactions
            .where((item) => item.status == TransactionStatus.actual),
        isEmpty);
    expect(
      afterDelete.accounts
          .singleWhere((item) => item.id == loan.id)
          .currentBalance,
      -12000,
    );
    expect(find.text('记录第 1 期还款'), findsOneWidget);
  });

  test('deleting either legacy repayment part removes the whole installment',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    const cash = Account(
      id: 'legacy_delete_cash',
      name: '还款账户',
      accountType: AccountType.bankSaving,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      initialBalance: 5000,
      currentBalance: 5000,
    );
    const loan = Account(
      id: 'legacy_delete_loan',
      name: '旧车贷',
      accountType: AccountType.loan,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: -12000,
      currentBalance: -12000,
    );
    repository = await repository.addAccount(cash);
    repository = await repository.addAccount(loan);
    final date = DateTime(2026, 7, 23);
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'legacy_actual_principal',
        type: TransactionType.transfer,
        accountId: cash.id,
        toAccountId: loan.id,
        amount: 1191.58,
        currency: 'MYR',
        transactionDate: date,
        description: '贷款本金 #1',
      ),
    );
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'legacy_actual_interest',
        type: TransactionType.expense,
        accountId: cash.id,
        amount: 124.42,
        currency: 'MYR',
        transactionDate: date,
        description: '贷款利息 #1',
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

    await container
        .read(transactionMutationsProvider.notifier)
        .deleteTransaction('legacy_actual_interest');
    final updated = await container.read(financeRepositoryProvider.future);
    expect(updated.transactions, isEmpty);
    expect(
        updated.accounts
            .singleWhere((item) => item.id == cash.id)
            .currentBalance,
        5000);
    expect(
        updated.accounts
            .singleWhere((item) => item.id == loan.id)
            .currentBalance,
        -12000);
  });

  testWidgets(
      'legacy principal and interest plans upgrade to one monthly payment',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    const cash = Account(
      id: 'cash_upgrade',
      name: '还款户口',
      accountType: AccountType.bankSaving,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      initialBalance: 20000,
      currentBalance: 20000,
    );
    final loan = Account(
      id: 'loan_upgrade',
      name: '车贷',
      accountType: AccountType.loan,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: -12000,
      currentBalance: -12000,
      loanPrincipal: 12000,
      loanAnnualInterestRate: 12,
      loanTermMonths: 12,
      loanStartDate: DateTime(2026, 7, 1),
      loanPaymentDay: 15,
      loanRepaymentMethod: LoanRepaymentMethod.equalPrincipal,
    );
    repository = await repository.addAccount(cash);
    repository = await repository.addAccount(loan);
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'legacy_principal',
        type: TransactionType.transfer,
        accountId: cash.id,
        toAccountId: loan.id,
        amount: 1000,
        toAmount: 1000,
        currency: 'MYR',
        toCurrency: 'MYR',
        transactionDate: DateTime(2026, 8, 15),
        status: TransactionStatus.planned,
        description: '贷款本金 #1',
      ),
    );
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'legacy_interest',
        type: TransactionType.expense,
        accountId: cash.id,
        amount: 120,
        currency: 'MYR',
        transactionDate: DateTime(2026, 8, 15),
        status: TransactionStatus.planned,
        description: '贷款利息 #1',
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
          home: LoanDetailScreen(account: loan, repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final upgraded = await container.read(financeRepositoryProvider.future);
    final payment = upgraded.transactions.single;
    expect(payment.description, '贷款月供 #1');
    expect(payment.amount, 1120);
    expect(payment.toAmount, 1000);
    expect(payment.status, TransactionStatus.planned);
    expect(find.text('补齐 11 期预计交易'), findsOneWidget);
  });

  testWidgets('historical loan detail is read only until returning current',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    final now = DateTime.now();
    final loan = Account(
      id: 'historical_loan',
      name: '历史车贷',
      accountType: AccountType.loan,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: -12000,
      currentBalance: -12000,
      loanPrincipal: 12000,
      loanAnnualInterestRate: 12,
      loanTermMonths: 12,
      loanStartDate: DateTime(now.year, now.month - 3, 1),
      loanPaymentDay: 15,
      loanRepaymentMethod: LoanRepaymentMethod.equalPrincipal,
    );
    repository = await repository.addAccount(loan);
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
          home: LoanDetailScreen(
            account: loan,
            repository: repository,
            cutoffDate: DateTime(now.year, now.month - 1, 28, 23, 59, 59),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('loan-historical-banner')), findsOneWidget);
    expect(find.byKey(const Key('record-loan-installment')), findsNothing);
    expect(
      find.byKey(const Key('generate-loan-planned-transactions')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('loan-return-current')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loan-historical-banner')), findsNothing);
    expect(find.byKey(const Key('record-loan-installment')), findsOneWidget);
  });
}

class _TestRepositoryNotifier extends FinanceRepositoryNotifier {
  _TestRepositoryNotifier(this.repository);

  final FinanceRepository repository;

  @override
  Future<FinanceRepository> build() async => repository;
}
