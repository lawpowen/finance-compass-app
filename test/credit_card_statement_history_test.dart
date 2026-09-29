import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart' hide Account;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/credit_card_billing.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/features/accounts/credit_card_detail_screen.dart';
import 'package:finance_app/src/features/shared/compass_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('credit-card repayment uses the loan-style cash account flow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final period = calculateCreditCardBillingPeriod(
      statementDay: 25,
      paymentDueDay: 14,
      now: now,
    );
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    const cash = Account(
      id: 'repayment-cash',
      name: 'Repayment cash',
      accountType: AccountType.bankSaving,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      currentBalance: 2000,
    );
    const card = Account(
      id: 'repayment-card',
      name: 'Repayment card',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      currentBalance: 0,
      creditLimit: 5000,
      statementDay: 25,
      paymentDueDay: 14,
    );
    repository = await repository.addAccount(cash);
    repository = await repository.addAccount(card);
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'repayment-purchase',
        type: TransactionType.expense,
        accountId: card.id,
        amount: 500,
        currency: 'MYR',
        transactionDate: period.statementDate,
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
          home: CreditCardDetailScreen(
            account: card,
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('record-credit-card-repayment')));
    await tester.pumpAndSettle();
    expect(find.text('选择还款账户'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('credit-card-repayment-source-repayment-cash')),
    );
    await tester.pumpAndSettle();
    expect(find.text('记录信用卡还款'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('credit-card-repayment-amount')),
      '300',
    );
    await tester.tap(
      find.byKey(const Key('credit-card-repayment-confirm')),
    );
    await tester.pumpAndSettle();

    final updated = await container.read(financeRepositoryProvider.future);
    final repayment = updated.transactions.singleWhere(
      (item) => item.description == '信用卡还款',
    );
    expect(repayment.type, TransactionType.transfer);
    expect(repayment.accountId, cash.id);
    expect(repayment.toAccountId, card.id);
    expect(repayment.amount, 300);
    expect(updated.accountBalanceAt(cash.id, DateTime.now()), 1700);
    expect(updated.accountBalanceAt(card.id, DateTime.now()), -200);
    expect(tester.takeException(), isNull);
  });

  testWidgets('credit-card repayment rejects non-finite amounts',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final period = calculateCreditCardBillingPeriod(
      statementDay: 25,
      paymentDueDay: 14,
      now: DateTime.now(),
    );
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    const cash = Account(
      id: 'repayment-cash',
      name: 'Repayment cash',
      accountType: AccountType.bankSaving,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      currentBalance: 2000,
    );
    const card = Account(
      id: 'repayment-card',
      name: 'Repayment card',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      currentBalance: 0,
      creditLimit: 5000,
      statementDay: 25,
      paymentDueDay: 14,
    );
    repository = await repository.addAccount(cash);
    repository = await repository.addAccount(card);
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'repayment-purchase',
        type: TransactionType.expense,
        accountId: card.id,
        amount: 500,
        currency: 'MYR',
        transactionDate: period.statementDate,
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
          home: CreditCardDetailScreen(
            account: card,
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('record-credit-card-repayment')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('credit-card-repayment-source-repayment-cash')),
    );
    await tester.pumpAndSettle();

    for (final input in ['NaN', 'Infinity', '-Infinity']) {
      await tester.enterText(
        find.byKey(const Key('credit-card-repayment-amount')),
        input,
      );
      await tester.tap(find.byKey(const Key('credit-card-repayment-confirm')));
      await tester.pump();

      expect(
        find.text('记录信用卡还款'),
        findsOneWidget,
        reason: '$input must keep the repayment dialog open',
      );
      expect(find.text('请输入大于 0 的还款金额。'), findsOneWidget);
      // Let the snackbar expire so the next input shows a fresh one.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    }

    final updated = await container.read(financeRepositoryProvider.future);
    expect(
      updated.transactions.where((item) => item.description == '信用卡还款'),
      isEmpty,
    );
    expect(updated.transactions, hasLength(1));
    expect(updated.accountBalanceAt(card.id, DateTime.now()), -500);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paid cycle with later actual installments offers prepayment',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final period = calculateCreditCardBillingPeriod(
      statementDay: 25,
      paymentDueDay: 14,
      now: now,
    );
    // Installments start two cycles ahead, so the next statement stays empty.
    final installmentPeriods = <CreditCardBillingPeriod>[];
    var statementDate = period.nextStatementDate;
    for (var i = 0; i < 3; i++) {
      final next = calculateCreditCardBillingPeriodForStatement(
        statementDay: 25,
        paymentDueDay: 14,
        statementDate: statementDate,
      );
      statementDate = next.nextStatementDate;
      installmentPeriods.add(
        calculateCreditCardBillingPeriodForStatement(
          statementDay: 25,
          paymentDueDay: 14,
          statementDate: statementDate,
        ),
      );
    }
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    const cash = Account(
      id: 'prepay-cash',
      name: 'Prepay cash',
      accountType: AccountType.bankSaving,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      currentBalance: 2000,
    );
    const card = Account(
      id: 'prepay-card',
      name: 'Prepay card',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      currentBalance: 0,
      creditLimit: 5000,
      statementDay: 25,
      paymentDueDay: 14,
    );
    repository = await repository.addAccount(cash);
    repository = await repository.addAccount(card);
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'prepay-purchase',
        type: TransactionType.expense,
        accountId: card.id,
        amount: 100,
        currency: 'MYR',
        transactionDate: period.statementDate,
      ),
    );
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'prepay-cleared',
        type: TransactionType.transfer,
        accountId: cash.id,
        toAccountId: card.id,
        amount: 100,
        currency: 'MYR',
        toCurrency: 'MYR',
        transactionDate: now,
      ),
    );
    for (final (index, installment) in installmentPeriods.indexed) {
      repository = await repository.addTransaction(
        FinanceTransaction(
          id: 'prepay-installment-$index',
          type: TransactionType.expense,
          accountId: card.id,
          amount: 100,
          currency: 'MYR',
          transactionDate: installment.statementDate,
          status: TransactionStatus.actual,
        ),
      );
    }
    expect(repository.creditCardOutstandingBalance(card.id), 300);
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
          home: CreditCardDetailScreen(
            account: card,
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // "本期账单" is both the amount label and a tab; distant debt stays out
    // of the current cycle.
    expect(find.text('本期账单'), findsWidgets);
    expect(find.text('下期已使用额度'), findsNothing);
    expect(find.text('本期已还清'), findsWidgets);
    expect(find.text('无需还款'), findsNothing);
    final button = find.byKey(const Key('record-credit-card-repayment'));
    expect(
      find.descendant(of: button, matching: find.text('提前还款')),
      findsOneWidget,
    );
    expect(tester.widget<CompassPrimaryButton>(button).onPressed, isNotNull);

    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('credit-card-repayment-source-prepay-cash')),
    );
    await tester.pumpAndSettle();
    final amountField = tester.widget<TextField>(
      find.byKey(const Key('credit-card-repayment-amount')),
    );
    expect(amountField.controller!.text, '300.00');

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('记录信用卡还款'), findsNothing);
    final updated = await container.read(financeRepositoryProvider.future);
    expect(updated.transactions, hasLength(5));
    expect(updated.creditCardOutstandingBalance(card.id), 300);
    expect(tester.takeException(), isNull);
  });

  testWidgets('statement picker switches the detail page to a past cycle',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final currentPeriod = calculateCreditCardBillingPeriod(
      statementDay: 25,
      paymentDueDay: 14,
      now: now,
    );
    final pastPeriod = calculateCreditCardBillingPeriodForStatement(
      statementDay: 25,
      paymentDueDay: 14,
      statementDate: DateTime(
        currentPeriod.statementDate.year,
        currentPeriod.statementDate.month - 1,
        1,
      ),
    );
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    const card = Account(
      id: 'history_card',
      name: 'History card',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: 0,
      currentBalance: 0,
      creditLimit: 5000,
      statementDay: 25,
      paymentDueDay: 14,
    );
    repository = await repository.addAccount(card);
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'past_purchase',
        type: TransactionType.expense,
        accountId: card.id,
        amount: 88,
        currency: 'MYR',
        transactionDate: pastPeriod.cycleStartDate.add(
          const Duration(days: 3),
        ),
        merchant: 'Past purchase',
      ),
    );
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'current_purchase',
        type: TransactionType.expense,
        accountId: card.id,
        amount: 32,
        currency: 'MYR',
        transactionDate: currentPeriod.cycleStartDate.add(
          const Duration(days: 3),
        ),
        merchant: 'Current purchase',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeRepositoryProvider.overrideWith(
            () => _TestRepositoryNotifier(repository),
          ),
        ],
        child: MaterialApp(
          home: CreditCardDetailScreen(
            account: card,
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('credit-card-statement-picker')));
    await tester.pumpAndSettle();
    expect(find.text('选择账单月份'), findsOneWidget);

    final pastKey = Key(
      'credit-card-statement-${pastPeriod.statementDate.year}-${pastPeriod.statementDate.month}',
    );
    await tester.ensureVisible(find.byKey(pastKey));
    await tester.tap(find.byKey(pastKey));
    await tester.pumpAndSettle();

    expect(
      find.text(
        '${pastPeriod.billingMonthDate.year}年${pastPeriod.billingMonthDate.month}月历史账单',
      ),
      findsOneWidget,
    );
    expect(find.text('Past purchase'), findsOneWidget);
    expect(find.text('Current purchase'), findsNothing);
    expect(find.text('返回本期'), findsOneWidget);
  });

  testWidgets('statement picker opens future actual statement details',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final currentPeriod = calculateCreditCardBillingPeriod(
      statementDay: 1,
      paymentDueDay: 10,
      now: now,
    );
    final futurePeriod = calculateCreditCardBillingPeriodForStatement(
      statementDay: 1,
      paymentDueDay: 10,
      statementDate: currentPeriod.nextStatementDate,
    );
    final transactionDate = now.add(const Duration(days: 2));
    expect(futurePeriod.containsBilled(transactionDate), isTrue);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    const card = Account(
      id: 'future_card',
      name: 'Shopee PayLater',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: 0,
      currentBalance: 0,
      creditLimit: 3000,
      statementDay: 1,
      paymentDueDay: 10,
    );
    repository = await repository.addAccount(card);
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'future_actual',
        type: TransactionType.expense,
        accountId: card.id,
        amount: 313.29,
        currency: 'MYR',
        transactionDate: transactionDate,
        status: TransactionStatus.actual,
        merchant: 'Confirmed installment',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeRepositoryProvider.overrideWith(
            () => _TestRepositoryNotifier(repository),
          ),
        ],
        child: MaterialApp(
          home: CreditCardDetailScreen(
            account: card,
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('未出账'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmed installment'), findsOneWidget);
    await tester.tap(find.byKey(const Key('credit-card-statement-picker')));
    await tester.pumpAndSettle();
    final futureKey = Key(
      'credit-card-statement-${futurePeriod.statementDate.year}-${futurePeriod.statementDate.month}',
    );
    await tester.ensureVisible(find.byKey(futureKey));
    expect(find.textContaining('已确定'), findsWidgets);
    await tester.tap(find.byKey(futureKey));
    await tester.pumpAndSettle();

    expect(
      find.text(
        '${futurePeriod.billingMonthDate.year}年${futurePeriod.billingMonthDate.month}月已确定账单',
      ),
      findsWidgets,
    );
    expect(find.text('Confirmed installment'), findsOneWidget);
    expect(find.text('返回本期'), findsOneWidget);
  });

  testWidgets('historical credit-card detail is read only and can return live',
      (tester) async {
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month, 0, 23, 59, 59);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    const card = Account(
      id: 'historical_card',
      name: 'Historical card',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: 0,
      currentBalance: 0,
      creditLimit: 5000,
      statementDay: 25,
      paymentDueDay: 14,
    );
    repository = await repository.addAccount(card);
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'historical_purchase',
        type: TransactionType.expense,
        accountId: card.id,
        amount: 88,
        currency: 'MYR',
        transactionDate: DateTime(cutoff.year, cutoff.month, 10),
        merchant: 'Historical purchase',
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
          home: CreditCardDetailScreen(
            account: card,
            repository: repository,
            cutoffDate: cutoff,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('credit-card-historical-banner')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    await tester.tap(find.byKey(const Key('credit-card-return-current')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('credit-card-historical-banner')), findsNothing);
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
  });
}

class _TestRepositoryNotifier extends FinanceRepositoryNotifier {
  _TestRepositoryNotifier(this.repository);

  final FinanceRepository repository;

  @override
  Future<FinanceRepository> build() async => repository;
}
