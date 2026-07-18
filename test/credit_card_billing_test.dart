import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/credit_card_billing.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const card = Account(
    id: 'card',
    name: '日常信用卡',
    accountType: AccountType.creditCard,
    reportGroup: ReportGroup.credit,
    currency: 'MYR',
    currentBalance: -1200,
    creditLimit: 5000,
    statementDay: 31,
    paymentDueDay: 10,
  );

  test('clamps statement day and separates billed from unbilled spend', () {
    final summary = calculateCreditCardBilling(
      account: card,
      now: DateTime(2026, 4, 20),
      transactions: [
        FinanceTransaction(
          id: 'new_spend',
          type: TransactionType.expense,
          accountId: 'card',
          amount: 200,
          currency: 'MYR',
          transactionDate: DateTime(2026, 4, 2),
        ),
        FinanceTransaction(
          id: 'payment',
          type: TransactionType.transfer,
          accountId: 'bank',
          toAccountId: 'card',
          amount: 300,
          currency: 'MYR',
          transactionDate: DateTime(2026, 4, 5),
        ),
      ],
    );

    expect(summary.statementDate, DateTime(2026, 3, 31));
    expect(summary.dueDate, DateTime(2026, 4, 10));
    expect(summary.unbilledBalance, 200);
    expect(summary.billedBalance, 1000);
    expect(summary.isEstimated, isFalse);
  });

  test('surplus repayment reduces the remaining next statement amount', () {
    const reconciledCard = Account(
      id: 'uob_card',
      name: 'UOB Lazada Credit Card',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      currentBalance: -1563.68,
      creditLimit: 15000,
      statementDay: 25,
      paymentDueDay: 14,
    );
    final transactions = [
      FinanceTransaction(
        id: 'current_cycle_spend',
        type: TransactionType.expense,
        accountId: reconciledCard.id,
        amount: 1963.69,
        currency: 'MYR',
        transactionDate: DateTime(2026, 7, 10),
      ),
      FinanceTransaction(
        id: 'statement_and_surplus_payment',
        type: TransactionType.transfer,
        accountId: 'bank',
        toAccountId: reconciledCard.id,
        amount: 400.01,
        currency: 'MYR',
        transactionDate: DateTime(2026, 7, 14),
      ),
    ];

    final summary = calculateCreditCardBilling(
      account: reconciledCard,
      transactions: transactions,
      now: DateTime(2026, 7, 18),
      balanceAtCutoff: -1563.68,
    );

    expect(summary.billedBalance, 0);
    expect(summary.outstandingBalance, 1563.68);
    expect(summary.unbilledBalance, closeTo(1563.68, 0.001));
  });

  test('surplus repayment preserves confirmed spend before next cutoff', () {
    const reconciledCard = Account(
      id: 'uob_card',
      name: 'UOB Lazada Credit Card',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      currentBalance: -1663.68,
      creditLimit: 15000,
      statementDay: 25,
      paymentDueDay: 14,
    );
    final transactions = [
      FinanceTransaction(
        id: 'occurred_spend',
        type: TransactionType.expense,
        accountId: reconciledCard.id,
        amount: 1963.69,
        currency: 'MYR',
        transactionDate: DateTime(2026, 7, 10),
      ),
      FinanceTransaction(
        id: 'surplus_payment',
        type: TransactionType.transfer,
        accountId: 'bank',
        toAccountId: reconciledCard.id,
        amount: 400.01,
        currency: 'MYR',
        transactionDate: DateTime(2026, 7, 14),
      ),
      FinanceTransaction(
        id: 'confirmed_before_cutoff',
        type: TransactionType.expense,
        accountId: reconciledCard.id,
        amount: 100,
        currency: 'MYR',
        transactionDate: DateTime(2026, 7, 20),
        status: TransactionStatus.actual,
      ),
    ];

    final summary = calculateCreditCardBilling(
      account: reconciledCard,
      transactions: transactions,
      now: DateTime(2026, 7, 18),
      balanceAtCutoff: -1563.68,
    );

    expect(summary.billedBalance, 0);
    expect(summary.unbilledBalance, closeTo(1663.68, 0.001));
  });

  test('uses the legacy estimate until the card profile is complete', () {
    const legacy = Account(
      id: 'legacy',
      name: '旧卡',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      currentBalance: -88,
    );
    final summary = calculateCreditCardBilling(
      account: legacy,
      transactions: const [],
      now: DateTime(2026, 1, 31),
    );

    expect(summary.dueDate, DateTime(2026, 2, 25));
    expect(summary.billedBalance, 88);
    expect(summary.isEstimated, isTrue);
  });

  test('resolves the full billing cycle with real months', () {
    final period = calculateCreditCardBillingPeriod(
      statementDay: 12,
      paymentDueDay: 28,
      now: DateTime(2026, 7, 17),
    );

    expect(period.cycleStartDate, DateTime(2026, 6, 13));
    expect(period.statementDate, DateTime(2026, 7, 12));
    expect(period.dueDate, DateTime(2026, 7, 28));
    expect(period.nextStatementDate, DateTime(2026, 8, 12));
    expect(period.containsBilled(DateTime(2026, 6, 12)), isFalse);
    expect(period.containsBilled(DateTime(2026, 6, 13)), isTrue);
    expect(period.containsBilled(DateTime(2026, 7, 12)), isTrue);
    expect(period.containsUnbilled(DateTime(2026, 7, 13)), isTrue);
    expect(period.containsUnbilled(DateTime(2026, 8, 12)), isTrue);
    expect(period.containsUnbilled(DateTime(2026, 8, 13)), isFalse);
  });

  test('clamps month-end cycles without leaking earlier transactions', () {
    final period = calculateCreditCardBillingPeriod(
      statementDay: 31,
      paymentDueDay: 10,
      now: DateTime(2026, 3, 15),
    );

    expect(period.cycleStartDate, DateTime(2026, 2, 1));
    expect(period.statementDate, DateTime(2026, 2, 28));
    expect(period.nextStatementDate, DateTime(2026, 3, 31));
    expect(period.containsBilled(DateTime(2026, 1, 31)), isFalse);
    expect(period.containsBilled(DateTime(2026, 2, 28)), isTrue);
    expect(period.containsUnbilled(DateTime(2026, 3, 1)), isTrue);
  });

  test('display state does not call a paid statement overdue', () {
    final paid = CreditCardBillingSummary(
      outstandingBalance: 9017.81,
      billedBalance: 0,
      unbilledBalance: 9017.81,
      statementDate: DateTime(2026, 6, 25),
      dueDate: DateTime(2026, 7, 14),
      isEstimated: false,
    );

    expect(
      resolveCreditCardDisplayState(
        summary: paid,
        hasBilledActivity: true,
        now: DateTime(2026, 7, 17),
      ),
      CreditCardDisplayState.paidThisCycle,
    );
    expect(
      resolveCreditCardDisplayState(
        summary: paid,
        hasBilledActivity: false,
        now: DateTime(2026, 7, 17),
      ),
      CreditCardDisplayState.unbilledOnly,
    );
  });

  test('display state distinguishes due today, overdue and no balance', () {
    CreditCardBillingSummary due(DateTime dueDate, double amount) =>
        CreditCardBillingSummary(
          outstandingBalance: amount,
          billedBalance: amount,
          unbilledBalance: 0,
          statementDate: DateTime(2026, 6, 25),
          dueDate: dueDate,
          isEstimated: false,
        );

    expect(
      resolveCreditCardDisplayState(
        summary: due(DateTime(2026, 7, 17), 100),
        hasBilledActivity: true,
        now: DateTime(2026, 7, 17),
      ),
      CreditCardDisplayState.dueToday,
    );
    expect(
      resolveCreditCardDisplayState(
        summary: due(DateTime(2026, 7, 14), 100),
        hasBilledActivity: true,
        now: DateTime(2026, 7, 17),
      ),
      CreditCardDisplayState.overdue,
    );
    expect(
      resolveCreditCardDisplayState(
        summary: due(DateTime(2026, 7, 14), 0),
        hasBilledActivity: false,
        now: DateTime(2026, 7, 17),
      ),
      CreditCardDisplayState.noBalance,
    );
  });

  test('card-to-card transfer is a charge for source and payment for target',
      () {
    const targetCard = Account(
      id: 'target_card',
      name: '目标信用卡',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      currentBalance: 0,
      creditLimit: 5000,
      statementDay: 31,
      paymentDueDay: 10,
    );
    final transfer = FinanceTransaction(
      id: 'card_to_card',
      type: TransactionType.transfer,
      accountId: card.id,
      toAccountId: targetCard.id,
      amount: 400,
      currency: 'MYR',
      transactionDate: DateTime(2026, 3, 20),
    );

    final sourceSummary = calculateCreditCardBilling(
      account: card,
      transactions: [transfer],
      now: DateTime(2026, 4, 20),
      balanceAtCutoff: -400,
    );
    final targetSummary = calculateCreditCardBilling(
      account: targetCard,
      transactions: [transfer],
      now: DateTime(2026, 4, 20),
      balanceAtCutoff: 0,
    );

    expect(sourceSummary.billedBalance, 400);
    expect(sourceSummary.unbilledBalance, 0);
    expect(targetSummary.billedBalance, 0);
    expect(targetSummary.unbilledBalance, 0);
    expect(
      hasCreditCardBilledActivity(
        account: card,
        transactions: [transfer],
        now: DateTime(2026, 4, 20),
      ),
      isTrue,
    );
    expect(
      hasCreditCardBilledActivity(
        account: targetCard,
        transactions: [transfer],
        now: DateTime(2026, 4, 20),
      ),
      isFalse,
    );
  });

  test('lists historical periods and assigns April 29 to May statement', () {
    const historyCard = Account(
      id: 'history_card',
      name: '历史账单卡',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      currentBalance: -123,
      creditLimit: 5000,
      statementDay: 25,
      paymentDueDay: 14,
    );
    final aprilPurchase = FinanceTransaction(
      id: 'april_29',
      type: TransactionType.expense,
      accountId: historyCard.id,
      amount: 123,
      currency: 'MYR',
      transactionDate: DateTime(2026, 4, 29),
    );

    final periods = availableCreditCardBillingPeriods(
      account: historyCard,
      transactions: [aprilPurchase],
      now: DateTime(2026, 7, 18),
    );
    final mayStatement = periods.singleWhere(
      (item) => item.statementDate == DateTime(2026, 5, 25),
    );

    expect(periods.first.statementDate, DateTime(2026, 6, 25));
    expect(mayStatement.cycleStartDate, DateTime(2026, 4, 26));
    expect(mayStatement.dueDate, DateTime(2026, 6, 14));
    expect(mayStatement.containsBilled(aprilPurchase.transactionDate), isTrue);
    expect(
      calculateCreditCardStatementAmount(
        accountId: historyCard.id,
        transactions: [aprilPurchase],
        period: mayStatement,
      ),
      123,
    );
    expect(
      calculateCreditCardOriginalStatementAmount(
        accountId: historyCard.id,
        transactions: [aprilPurchase],
        period: mayStatement,
        statementAmountOverride: 212.32,
      ),
      212.32,
    );
  });

  test('future actual installments form browsable confirmed statements', () {
    const payLater = Account(
      id: 'shopee_paylater',
      name: 'Shopee PayLater',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      currentBalance: -870.07,
      creditLimit: 3000,
      statementDay: 31,
      paymentDueDay: 10,
    );
    final transactions = [
      FinanceTransaction(
        id: 'jul_installment',
        type: TransactionType.expense,
        accountId: payLater.id,
        amount: 313.29,
        currency: 'MYR',
        transactionDate: DateTime(2026, 7, 25),
        status: TransactionStatus.actual,
      ),
      FinanceTransaction(
        id: 'aug_installment',
        type: TransactionType.expense,
        accountId: payLater.id,
        amount: 313.31,
        currency: 'MYR',
        transactionDate: DateTime(2026, 8, 25),
        status: TransactionStatus.actual,
      ),
      FinanceTransaction(
        id: 'sep_installment',
        type: TransactionType.expense,
        accountId: payLater.id,
        amount: 243.47,
        currency: 'MYR',
        transactionDate: DateTime(2026, 9, 25),
        status: TransactionStatus.actual,
      ),
      FinanceTransaction(
        id: 'planned_october',
        type: TransactionType.expense,
        accountId: payLater.id,
        amount: 99,
        currency: 'MYR',
        transactionDate: DateTime(2026, 10, 25),
        status: TransactionStatus.planned,
      ),
    ];

    final summary = calculateCreditCardBilling(
      account: payLater,
      transactions: transactions,
      now: DateTime(2026, 7, 18),
      balanceAtCutoff: 0,
    );
    expect(summary.billedBalance, 0);
    expect(summary.unbilledBalance, closeTo(313.29, 0.001));

    final periods = availableCreditCardBillingPeriods(
      account: payLater,
      transactions: transactions,
      now: DateTime(2026, 7, 18),
    );
    expect(
      periods.take(3).map((item) => item.statementDate),
      [
        DateTime(2026, 7, 31),
        DateTime(2026, 8, 31),
        DateTime(2026, 9, 30),
      ],
    );
    expect(periods.any((item) => item.statementDate == DateTime(2026, 10, 31)),
        isFalse);

    final expected = {
      DateTime(2026, 7, 31): 313.29,
      DateTime(2026, 8, 31): 313.31,
      DateTime(2026, 9, 30): 243.47,
    };
    for (final entry in expected.entries) {
      final period = periods.singleWhere(
        (item) => item.statementDate == entry.key,
      );
      expect(period.dueDate.month, entry.key.month + 1);
      expect(period.dueDate.day, 10);
      expect(
        calculateCreditCardStatementAmount(
          accountId: payLater.id,
          transactions: transactions,
          period: period,
        ),
        closeTo(entry.value, 0.001),
      );
    }
  });

  test('day-one PayLater bills keep their bill month and original amount', () {
    const payLater = Account(
      id: 'shopee_paylater',
      name: 'Shopee PayLater',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      currentBalance: -524.22,
      creditLimit: 3180,
      statementDay: 1,
      paymentDueDay: 10,
    );
    final transactions = [
      FinanceTransaction(
        id: 'march_payment',
        type: TransactionType.transfer,
        accountId: 'uob_card',
        toAccountId: payLater.id,
        amount: 184.52,
        toAmount: 184.52,
        currency: 'MYR',
        toCurrency: 'MYR',
        transactionDate: DateTime(2026, 4, 5),
      ),
      FinanceTransaction(
        id: 'jul_1',
        type: TransactionType.expense,
        accountId: payLater.id,
        amount: 82.11,
        currency: 'MYR',
        transactionDate: DateTime(2026, 7, 8),
      ),
      FinanceTransaction(
        id: 'jul_2',
        type: TransactionType.expense,
        accountId: payLater.id,
        amount: 161.33,
        currency: 'MYR',
        transactionDate: DateTime(2026, 7, 10),
      ),
      FinanceTransaction(
        id: 'jul_3',
        type: TransactionType.expense,
        accountId: payLater.id,
        amount: 69.85,
        currency: 'MYR',
        transactionDate: DateTime(2026, 7, 21),
      ),
    ];
    final march = calculateCreditCardBillingPeriodForStatement(
      statementDay: 1,
      paymentDueDay: 10,
      statementDate: DateTime(2026, 4, 1),
    );
    expect(march.billingMonthDate, DateTime(2026, 3, 31));
    expect(
      calculateCreditCardOriginalStatementAmount(
        accountId: payLater.id,
        transactions: transactions,
        period: march,
      ),
      closeTo(184.52, 0.001),
      reason: 'A repayment must not turn the paid March bill into zero.',
    );

    final july = calculateCreditCardBillingPeriodForStatement(
      statementDay: 1,
      paymentDueDay: 10,
      statementDate: DateTime(2026, 8, 1),
    );
    expect(july.billingMonthDate, DateTime(2026, 7, 31));
    expect(july.dueDate, DateTime(2026, 8, 10));
    expect(
      calculateCreditCardOriginalStatementAmount(
        accountId: payLater.id,
        transactions: transactions,
        period: july,
      ),
      closeTo(313.29, 0.001),
    );

    final summary = calculateCreditCardBilling(
      account: payLater,
      transactions: transactions,
      now: DateTime(2026, 7, 18),
      balanceAtCutoff: 0,
    );
    expect(summary.unbilledBalance, closeTo(313.29, 0.001));
  });
}
