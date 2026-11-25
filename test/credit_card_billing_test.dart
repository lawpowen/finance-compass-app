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

  group('bank posting day on the source card', () {
    const uob = Account(
      id: 'uob',
      name: 'UOB Lazada Credit Card',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      currentBalance: -241.94,
      creditLimit: 3000,
      statementDay: 25,
      paymentDueDay: 14,
    );
    const laz = Account(
      id: 'laz',
      name: 'Laz PayLater',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      currentBalance: 0,
      creditLimit: 1000,
      statementDay: 10,
      paymentDueDay: 25,
    );
    final cut = DateTime(2026, 11, 25);
    final nextCut = DateTime(2026, 12, 25);
    final nextDay = DateTime(2026, 11, 26);
    FinanceTransaction sourceRow(String id, double amount, DateTime day,
            {DateTime? posting}) =>
        FinanceTransaction(
            id: id,
            accountId: uob.id,
            type: TransactionType.expense,
            currency: 'MYR',
            amount: amount,
            transactionDate: day,
            cardPostingDate: posting);

    test(
        'cut-day purchase keeps actual debt, skips this statement and appears in next history',
        () {
      final entries = [
        sourceRow('purchase', 241.94, DateTime(2026, 11, 25, 15),
            posting: nextDay)
      ];
      final summary = calculateCreditCardBilling(
          account: uob, transactions: entries, now: cut);
      expect(summary.outstandingBalance, 241.94);
      expect(summary.billedBalance, 0);
      expect(summary.unbilledBalance, 241.94);
      expect(
          hasCreditCardBilledActivity(
              account: uob, transactions: entries, now: cut),
          isFalse);
      final periods = availableCreditCardBillingPeriods(
          account: uob, transactions: entries, now: cut);
      expect(periods.map((p) => p.statementDate), [nextCut, cut]);
      expect(
          calculateCreditCardOriginalStatementAmount(
              accountId: uob.id, transactions: entries, period: periods.last),
          0);
      final laterAdvance = FinanceTransaction(
          id: 'unrelated-advance',
          accountId: 'bank',
          toAccountId: uob.id,
          type: TransactionType.transfer,
          currency: 'MYR',
          amount: 60,
          transactionDate: DateTime(2026, 12, 2));
      expect(
          calculateCreditCardOriginalStatementAmount(
              accountId: uob.id,
              transactions: [...entries, laterAdvance],
              period: periods.last),
          0);
      expect(
          calculateCreditCardOriginalStatementAmount(
              accountId: uob.id, transactions: entries, period: periods.first),
          241.94);
      expect(
          calculateCreditCardBilling(
                  account: uob, transactions: entries, now: nextCut)
              .billedBalance,
          241.94);
    });

    test(
        'incoming PayLater payment is effective before the payer posts the charge',
        () {
      final transfer = FinanceTransaction(
          id: 'payer-to-laz',
          accountId: uob.id,
          toAccountId: laz.id,
          type: TransactionType.transfer,
          currency: 'MYR',
          amount: 241.94,
          transactionDate: DateTime(2026, 11, 25, 17),
          cardPostingDate: nextDay);
      final entries = [
        FinanceTransaction(
            id: 'purchase',
            accountId: laz.id,
            type: TransactionType.expense,
            currency: 'MYR',
            amount: 241.94,
            transactionDate: DateTime(2026, 11, 4)),
        transfer
      ];
      expect(creditCardSourceBillingDate(transfer, uob.id), nextDay);
      expect(creditCardSourceBillingDate(transfer, laz.id), cut);
      final before = calculateCreditCardBilling(
          account: laz, transactions: entries, now: DateTime(2026, 11, 24));
      expect(before.billedBalance, 241.94);
      expect(before.dueDate, cut);
      final paid = calculateCreditCardBilling(
          account: laz, transactions: entries, now: cut);
      expect(paid.billedBalance, 0);
      expect(paid.openStatements, isEmpty);
      final december = calculateCreditCardBilling(
          account: uob, transactions: entries, now: nextCut);
      expect(december.openStatements.single.period.statementDate, nextCut);
      expect(december.dueDate, DateTime(2027, 1, 14));
      expect(december.billedBalance, 241.94);
    });

    test(
        'farther postings remain committed without consuming next-cycle surplus',
        () {
      final entries = [
        sourceRow('far', 200, cut, posting: DateTime(2027, 1, 1)),
        sourceRow('soon', 100, DateTime(2026, 11, 27)),
        FinanceTransaction(
            id: 'advance',
            accountId: 'bank',
            toAccountId: uob.id,
            type: TransactionType.transfer,
            currency: 'MYR',
            amount: 50,
            transactionDate: cut),
      ];
      final summary = calculateCreditCardBilling(
          account: uob, transactions: entries, now: cut, balanceAtCutoff: -150);
      expect(summary.outstandingBalance, 150);
      expect(summary.openStatements, isEmpty);
      expect(summary.unbilledBalance, 50);
      expect(
          availableCreditCardBillingPeriods(
                  account: uob, transactions: entries, now: cut)
              .map((p) => p.statementDate),
          [nextCut, DateTime(2027, 1, 25), cut]);
    });

    test(
        'future confirmed spend counts in the cycle containing its posting day',
        () {
      final spend = sourceRow(
          'future economic and later bank posting', 90, DateTime(2026, 12, 20),
          posting: DateTime(2026, 12, 26));
      final early = calculateCreditCardBilling(
          account: uob, transactions: [spend], now: cut, balanceAtCutoff: 0);
      expect(early.unbilledBalance, 0);
      expect(early.billedBalance, 0);
      final onCut = calculateCreditCardBilling(
          account: uob,
          transactions: [spend],
          now: nextCut,
          balanceAtCutoff: -90);
      expect(onCut.unbilledBalance, 90);
      expect(onCut.billedBalance, 0);
    });

    test('a delayed refund cannot pay a closed bill before the bank posts it',
        () {
      final entries = [
        sourceRow('billed', 180, DateTime(2026, 11, 2)),
        sourceRow('pending-refund', -60, cut, posting: nextDay)
      ];
      final pending = calculateCreditCardBilling(
          account: uob, transactions: entries, now: cut, balanceAtCutoff: -120);
      expect(pending.outstandingBalance, 120);
      expect(pending.billedBalance, 180);
      expect(pending.unbilledBalance, 0);
      final posted = calculateCreditCardBilling(
          account: uob,
          transactions: entries,
          now: nextDay,
          balanceAtCutoff: -120);
      expect(posted.billedBalance, 120);
    });
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

  group('outstanding statements', () {
    const fifoCard = Account(
      id: 'fifo',
      name: 'FIFO card',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      currentBalance: 0,
      creditLimit: 500,
      statementDay: 25,
      paymentDueDay: 10,
    );
    FinanceTransaction charge(String id, DateTime day, double amount) =>
        FinanceTransaction(
            id: id,
            accountId: fifoCard.id,
            type: TransactionType.expense,
            transactionDate: day,
            currency: 'MYR',
            amount: amount);
    FinanceTransaction pay(String id, DateTime day, double amount) =>
        FinanceTransaction(
            id: id,
            accountId: 'bank',
            toAccountId: fifoCard.id,
            type: TransactionType.transfer,
            transactionDate: day,
            currency: 'MYR',
            toCurrency: 'MYR',
            amount: amount);

    test(
        'later closes preserve the original overdue statement and FIFO repayments',
        () {
      final entries = [
        charge('may', DateTime(2026, 5, 3), 100),
        charge('june', DateTime(2026, 6, 1), 80),
        pay('partial', DateTime(2026, 6, 9), 40),
      ];
      CreditCardBillingSummary at(DateTime day, double balance) =>
          calculateCreditCardBilling(
              account: fifoCard,
              transactions: entries,
              now: day,
              balanceAtCutoff: balance);
      final june = at(DateTime(2026, 6, 25), -140);
      expect(june.openStatements.map((s) => s.amount), [60, 80]);
      expect(june.billedBalance, 60);
      expect(june.dueDate, DateTime(2026, 6, 10));
      expect(
          resolveCreditCardDisplayState(
              summary: june,
              hasBilledActivity: true,
              now: DateTime(2026, 6, 25)),
          CreditCardDisplayState.overdue);
      entries.add(pay('clear-old-and-part-new', DateTime(2026, 6, 26), 70));
      expect(at(DateTime(2026, 6, 26), -70).dueDate, DateTime(2026, 7, 10));
      entries.add(pay('reversal', DateTime(2026, 6, 27), -35));
      final reversed = at(DateTime(2026, 6, 27), -105);
      expect(reversed.openStatements.map((s) => s.amount), [25, 80]);
      expect(reversed.dueDate, DateTime(2026, 6, 10));
    });

    test('overpayment before a future confirmed charge covers that charge once',
        () {
      final entries = [
        charge('may', DateTime(2026, 5, 3), 100),
        pay('overpay', DateTime(2026, 5, 30), 110),
        charge('future', DateTime(2026, 6, 8), 30),
      ];
      final at = calculateCreditCardBilling(
          account: fifoCard,
          transactions: entries,
          now: DateTime(2026, 6, 2),
          balanceAtCutoff: 10);
      expect(at.openStatements, isEmpty);
      expect(at.outstandingBalance, 0);
      expect(at.unbilledBalance, 20);
      final closed = calculateCreditCardBilling(
          account: fifoCard,
          transactions: entries,
          now: DateTime(2026, 6, 25),
          balanceAtCutoff: -20);
      expect(closed.openStatements.single.amount, 20);
    });

    test(
        'an undated opening balance stays on the origin cycle during projection',
        () {
      final at = calculateCreditCardBilling(
          account: fifoCard,
          transactions: const [],
          now: DateTime(2026, 7, 27),
          balanceAtCutoff: -50,
          openingAsOf: DateTime(2026, 6, 2));
      expect(
          at.openStatements.single.period.statementDate, DateTime(2026, 5, 25));
      expect(at.openStatements.single.amount, 50);
    });
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

  test(
      'a backdated card repayment settles the PayLater bill on its posting day',
      () {
    const payLater = Account(
      id: 'paylater',
      name: 'Shopee PayLater',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      currentBalance: 0,
      creditLimit: 1000,
      statementDay: 10,
      paymentDueDay: 25,
    );
    final entries = [
      FinanceTransaction(
          id: 'purchase',
          type: TransactionType.expense,
          accountId: payLater.id,
          amount: 241.94,
          currency: 'MYR',
          transactionDate: DateTime(2026, 11, 3)),
      FinanceTransaction(
          id: 'repayment',
          type: TransactionType.transfer,
          accountId: card.id,
          toAccountId: payLater.id,
          amount: 241.94,
          currency: 'MYR',
          transactionDate: DateTime(2026, 11, 25),
          recordDate: DateTime(2026, 12, 2)),
    ];
    final before = calculateCreditCardBilling(
        account: payLater,
        transactions: entries,
        now: DateTime(2026, 11, 24),
        balanceAtCutoff: -241.94);
    final paid = calculateCreditCardBilling(
        account: payLater,
        transactions: entries,
        now: DateTime(2026, 11, 25),
        balanceAtCutoff: 0);
    final payer = calculateCreditCardBilling(
        account: card,
        transactions: entries,
        now: DateTime(2026, 11, 25),
        balanceAtCutoff: -241.94);
    final closed = calculateCreditCardBilling(
        account: card,
        transactions: entries,
        now: DateTime(2026, 11, 30),
        balanceAtCutoff: -241.94);
    expect(before.billedBalance, 241.94);
    expect(before.dueDate, DateTime(2026, 11, 25));
    expect(paid.openStatements, isEmpty);
    expect(paid.outstandingBalance, 0);
    expect(payer.billedBalance, 0);
    expect(payer.unbilledBalance, 241.94);
    expect(closed.billedBalance, 241.94);
    expect(closed.dueDate, DateTime(2026, 12, 10));
    expect(
        calculateCreditCardOriginalStatementAmount(
            accountId: payLater.id,
            transactions: entries,
            period: calculateCreditCardBillingPeriod(
                statementDay: 10,
                paymentDueDay: 25,
                now: DateTime(2026, 11, 25))),
        241.94);
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

  group('original statement amount', () {
    // Cycle 2026-05-26..06-25, statement 06-25, due 07-14.
    final june = calculateCreditCardBillingPeriodForStatement(
      statementDay: 25,
      paymentDueDay: 14,
      statementDate: DateTime(2026, 6, 25),
    );
    FinanceTransaction record(
      String id,
      TransactionType type,
      double amount,
      DateTime date,
    ) =>
        FinanceTransaction(
          id: id,
          type: type,
          accountId: 'card',
          amount: amount,
          currency: 'MYR',
          transactionDate: date,
        );
    FinanceTransaction repayment(double amount, {double? toAmount}) =>
        FinanceTransaction(
          id: 'repay_$amount',
          type: TransactionType.transfer,
          accountId: 'bank',
          toAccountId: 'card',
          amount: amount,
          toAmount: toAmount,
          currency: 'MYR',
          toCurrency: 'MYR',
          transactionDate: DateTime(2026, 7, 5),
        );
    double original(
      List<FinanceTransaction> transactions, {
      double? override,
    }) =>
        calculateCreditCardOriginalStatementAmount(
          accountId: 'card',
          transactions: transactions,
          period: june,
          statementAmountOverride: override,
        );

    test('an overpayment after the cut does not inflate the statement', () {
      final transactions = [
        record('spend', TransactionType.expense, 100, DateTime(2026, 6, 10)),
        repayment(150),
      ];

      expect(original(transactions), 100);
    });

    test('a fully refunded cycle stays at zero despite a repayment', () {
      final transactions = [
        record('spend', TransactionType.expense, 100, DateTime(2026, 6, 10)),
        record('refund', TransactionType.income, 100, DateTime(2026, 6, 12)),
        repayment(100),
      ];

      expect(original(transactions), 0);
    });

    test('transfer out and adjustment are source records', () {
      final transactions = [
        record('out', TransactionType.transfer, 60, DateTime(2026, 6, 1)),
        record('credit', TransactionType.adjustment, 20, DateTime(2026, 6, 2)),
        repayment(90),
      ];

      expect(original(transactions), 40);
    });

    test('a cycle without source records falls back to its repayment', () {
      final transactions = [
        record('earlier', TransactionType.expense, 70, DateTime(2026, 5, 20)),
        record('later', TransactionType.expense, 30, DateTime(2026, 6, 30)),
        repayment(184.52),
      ];

      expect(original(transactions), closeTo(184.52, 0.001));
      expect(original(const []), 0);
    });

    test(
        'fallback preserves explicit zero and uses the canonical ordinary amount',
        () {
      expect(original([repayment(120, toAmount: 0)]), 0);
      expect(original([repayment(120)]), 120);
    });

    test('fallback clamps a reversed repayment at zero', () {
      // No source record; repay 100 then reverse 150 via a negative transfer.
      final transactions = [repayment(100), repayment(-150)];

      expect(original(transactions), 0);
    });

    test('a manual override wins over transactions and fallback', () {
      expect(
        original(
          [
            record(
                'spend', TransactionType.expense, 100, DateTime(2026, 6, 10)),
            repayment(150),
          ],
          override: 130,
        ),
        130,
      );
      expect(original([repayment(150)], override: 90), 90);
      expect(original(const [], override: -5), 0);
    });

    test('negative repayment reversal after statement does not throw in clamp',
        () {
      const configuredCard = Account(
        id: 'card',
        name: 'Configured Card',
        accountType: AccountType.creditCard,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        currentBalance: -150,
        creditLimit: 5000,
        statementDay: 25,
        paymentDueDay: 14,
      );
      final summary = calculateCreditCardBilling(
        account: configuredCard,
        transactions: [
          record('spend', TransactionType.expense, 100, DateTime(2026, 6, 10)),
          FinanceTransaction(
            id: 'reversal',
            type: TransactionType.transfer,
            accountId: 'cash',
            toAccountId: 'card',
            amount: -50,
            currency: 'MYR',
            transactionDate: DateTime(2026, 6, 28),
          ),
        ],
        now: DateTime(2026, 7, 1),
      );

      expect(summary.outstandingBalance, 150);
      expect(summary.billedBalance, 150);
      expect(summary.unbilledBalance, 0);
    });
  });
}
