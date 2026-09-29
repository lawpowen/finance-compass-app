import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    hide Account, Category;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/credit_card_billing.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/accounts/accounts_v2_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _card = Account(
  id: 'card',
  name: 'Card',
  accountType: AccountType.creditCard,
  reportGroup: ReportGroup.credit,
  currency: 'MYR',
  currentBalance: 0,
  creditLimit: 5000,
  statementDay: 15,
  paymentDueDay: 5,
);

const _overpaidCard = Account(
  id: 'overpaid',
  name: 'Overpaid',
  accountType: AccountType.creditCard,
  reportGroup: ReportGroup.credit,
  currency: 'MYR',
  initialBalance: 80,
  currentBalance: 80,
  creditLimit: 5000,
  statementDay: 15,
  paymentDueDay: 5,
);

FinanceTransaction _charge(
  String id,
  String accountId,
  double amount,
  DateTime date, {
  TransactionStatus status = TransactionStatus.actual,
}) {
  return FinanceTransaction(
    id: id,
    type: TransactionType.expense,
    accountId: accountId,
    amount: amount,
    currency: 'MYR',
    transactionDate: date,
    status: status,
  );
}

Future<FinanceRepository> _repositoryWith(
  List<Account> accounts,
  List<FinanceTransaction> transactions,
) async {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  var repository = await FinanceRepository.load(database);
  for (final account in accounts) {
    repository = await repository.addAccount(account);
  }
  if (transactions.isNotEmpty) {
    repository = await repository.addTransactions(transactions);
  }
  return repository;
}

void main() {
  // Statement day 15 at 2026-07-20: billed cycle 06-16..07-15, next cycle
  // 07-16..08-15.
  final now = DateTime(2026, 7, 20, 10);
  final ledger = [
    _charge('billed', 'card', 100, DateTime(2026, 7, 10)),
    _charge('later_today', 'card', 40, DateTime(2026, 7, 20, 18, 30)),
    _charge('next_cycle', 'card', 30, DateTime(2026, 8, 10)),
    _charge(
      'planned',
      'card',
      200,
      DateTime(2026, 8, 12),
      status: TransactionStatus.planned,
    ),
    _charge('two_cycles_ahead', 'card', 25, DateTime(2026, 9, 20)),
  ];

  test('current debt is committed live and clamped to zero when overpaid',
      () async {
    final repository = await _repositoryWith([_card, _overpaidCard], ledger);

    expect(repository.creditCardOutstandingBalance('card'), 195);
    expect(
      repository.creditCardOutstandingBalance(
        'card',
        cutoffDate: DateTime(2026, 7, 20, 23, 59, 59, 999),
      ),
      140,
    );
    expect(repository.creditCardOutstandingBalance('overpaid'), 0);
    expect(
      repository.creditCardOutstandingBalance(
        'overpaid',
        cutoffDate: DateTime(2026, 7, 31, 23, 59, 59, 999),
      ),
      0,
    );
  });

  test('overpaid credit is the positive balance, live and at a cutoff',
      () async {
    final repository = await _repositoryWith(
      [_card, _overpaidCard],
      [
        ...ledger,
        _charge('overpaid_spend', 'overpaid', 50, DateTime(2026, 8, 3)),
      ],
    );

    expect(repository.creditCardCreditBalance('overpaid'), 30);
    expect(
      repository.creditCardCreditBalance(
        'overpaid',
        cutoffDate: DateTime(2026, 7, 31, 23, 59, 59, 999),
      ),
      80,
    );
    expect(repository.creditCardCreditBalance('card'), 0);
    expect(
      repository.creditCardCreditBalance(
        'card',
        cutoffDate: DateTime(2026, 7, 31, 23, 59, 59, 999),
      ),
      0,
    );
  });

  test('historical billing summary stops at the exact cutoff moment', () async {
    final repository = await _repositoryWith([
      _card
    ], [
      _charge('billed', 'card', 100, DateTime(2026, 7, 10)),
      _charge('morning', 'card', 20, DateTime(2026, 7, 20, 10)),
      _charge('evening', 'card', 40, DateTime(2026, 7, 20, 18)),
    ]);

    final beforeBoth = repository.creditCardBillingSummary(
      'card',
      cutoffDate: DateTime(2026, 7, 20, 9),
    );
    expect(beforeBoth.outstandingBalance, 100);
    expect(beforeBoth.billedBalance, 100);
    expect(beforeBoth.unbilledBalance, 0);

    final noon = DateTime(2026, 7, 20, 12);
    final betweenThem = repository.creditCardBillingSummary(
      'card',
      cutoffDate: noon,
    );
    expect(
      betweenThem.outstandingBalance,
      120,
      reason: 'The 18:00 charge is after the cutoff and must not be owed.',
    );
    expect(
      betweenThem.billedBalance,
      100,
      reason: 'A later same-day charge must not be read as billed debt.',
    );
    expect(betweenThem.unbilledBalance, 20);
    expect(repository.creditCardOutstandingBalance('card', cutoffDate: noon),
        betweenThem.outstandingBalance);
  });

  test('billing summary reads the whole reference day for outstanding debt',
      () async {
    final repository = await _repositoryWith([_card], ledger);

    final live = repository.creditCardBillingSummary('card', now: now);
    expect(live.outstandingBalance, 140);
    expect(
      live.billedBalance,
      100,
      reason: 'A charge later today is unbilled, not a partial repayment.',
    );
    expect(live.unbilledBalance, 70);

    final historical = repository.creditCardBillingSummary(
      'card',
      cutoffDate: DateTime(2026, 7, 31, 23, 59, 59, 999),
    );
    expect(historical.outstandingBalance, 140);
    expect(historical.billedBalance, 100);
    expect(
      historical.unbilledBalance,
      40,
      reason: 'Records after a historical cutoff stay out of the cycle.',
    );
  });

  test('committed debt outside both cycles is not shown as no balance', () {
    final summary = CreditCardBillingSummary(
      outstandingBalance: 0,
      billedBalance: 0,
      unbilledBalance: 0,
      statementDate: DateTime(2026, 7, 15),
      dueDate: DateTime(2026, 8, 5),
      isEstimated: false,
    );

    expect(
      resolveCreditCardDisplayState(
        summary: summary,
        hasBilledActivity: false,
        now: now,
      ),
      CreditCardDisplayState.noBalance,
    );
    expect(
      resolveCreditCardDisplayState(
        summary: summary,
        hasBilledActivity: false,
        now: now,
        committedOutstanding: 25,
      ),
      CreditCardDisplayState.unbilledOnly,
    );
  });

  testWidgets('accounts credit tab shows committed, non-negative current debt',
      (tester) async {
    // Tall enough that every credit row is built, so absent text is real.
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final today = DateTime.now();
    const liveCard = Account(
      id: 'live',
      name: 'Live',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      currentBalance: 0,
      creditLimit: 5000,
      statementDay: 25,
      paymentDueDay: 14,
    );
    const gapCard = Account(
      id: 'gap',
      name: 'Gap',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      currentBalance: 0,
      creditLimit: 5000,
      statementDay: 25,
      paymentDueDay: 14,
    );
    final repository = await _repositoryWith(
      [liveCard, gapCard, _overpaidCard],
      [
        _charge(
          'yesterday',
          'live',
          50,
          today.subtract(const Duration(days: 1)),
        ),
        _charge(
          'instalment',
          'live',
          300,
          DateTime(today.year, today.month + 2, 10),
        ),
        _charge(
          'planned',
          'live',
          200,
          DateTime(today.year, today.month + 2, 11),
          status: TransactionStatus.planned,
        ),
        // Beyond the next statement for any statement day 25 cycle.
        _charge(
          'far_instalment',
          'gap',
          120,
          DateTime(today.year, today.month + 3, 10),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.abyss),
        home: Scaffold(body: AccountsV2Screen(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('信用'));
    await tester.pumpAndSettle();

    expect(find.text('Overpaid · 1234'), findsOneWidget);
    expect(find.text('负债总额  MYR 470.00'), findsOneWidget);
    expect(
      find.text('- MYR 390.00'),
      findsOneWidget,
      reason: 'Net assets keep the MYR 80 overpayment: 0 - 470 + 80.',
    );
    expect(find.text('MYR 350.00'), findsOneWidget);
    expect(find.text('MYR 120.00'), findsOneWidget);
    expect(find.text('MYR 80.00'), findsNothing);
    expect(find.text('暂无欠款'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('historical net assets keep the overpayment at the cutoff',
      (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final today = DateTime.now();
    final previousMonth = DateTime(today.year, today.month - 1);
    const debtCard = Account(
      id: 'debt',
      name: 'Debt',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: -400,
      currentBalance: -400,
      creditLimit: 5000,
      statementDay: 25,
      paymentDueDay: 14,
    );
    // Debt is 470 at both points. The overpaid card is +80 at the previous
    // month end; a charge on the 1st leaves +30 now.
    final repository = await _repositoryWith(
      [debtCard, _overpaidCard],
      [
        // Also makes the previous month selectable as a cutoff.
        _charge(
          'last_month',
          'debt',
          70,
          DateTime(previousMonth.year, previousMonth.month, 10),
        ),
        _charge(
          'this_month',
          'overpaid',
          50,
          DateTime(today.year, today.month, 1),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.abyss),
        home: Scaffold(body: AccountsV2Screen(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('- MYR 440.00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('account-cutoff-selector')));
    await tester.pumpAndSettle();
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
    expect(
      find.text('- MYR 390.00'),
      findsOneWidget,
      reason: 'Historical net assets: 0 - 470 + 80 at the cutoff.',
    );
    expect(find.text('MYR 470.00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
