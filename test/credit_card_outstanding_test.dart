import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    hide Account, Category;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/credit_card_billing.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/accounts/accounts_v2_screen.dart';
import 'package:finance_app/src/features/shared/compass_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class _CardRepository extends FinanceRepositoryNotifier {
  _CardRepository(this.repository);

  final FinanceRepository repository;

  @override
  Future<FinanceRepository> build() async => repository;
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

  testWidgets(
      'accounts credit tab separates month-end debt from future commitments',
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
    const undatedCard = Account(
      id: 'undated',
      name: 'Undated',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      currentBalance: 0,
    );
    final repository = await _repositoryWith(
      [liveCard, gapCard, _overpaidCard, undatedCard],
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

    expect(find.text('Overpaid'), findsOneWidget);
    expect(find.textContaining(' · 1234'), findsNothing);
    expect(find.text('负债总额  MYR 50.00'), findsOneWidget);
    expect(
      find.byKey(const Key('accounts-net-worth')),
      findsOneWidget,
    );
    expect(
        tester.widget<Text>(find.byKey(const Key('accounts-net-worth'))).data,
        'MYR 30.00');
    expect(find.textContaining('含未来承诺余额 - MYR 350.00'), findsOneWidget);
    expect(find.textContaining('含未来承诺余额 - MYR 120.00'), findsOneWidget);
    expect(find.text('信用卡溢缴款'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('accounts-card-credit')),
            matching: find.text('MYR 80.00')),
        findsOneWidget);
    expect(find.text('暂无欠款'), findsOneWidget);
    expect(find.text('账期待设置'), findsOneWidget);
    expect(find.text('当前为估算提醒'), findsOneWidget);
    expect(find.textContaining('账期日期待设置'), findsNothing);
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
        _charge('future', 'debt', 1000, DateTime(today.year, today.month + 2)),
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
    expect(
        find.descendant(
            of: find.byKey(const Key('accounts-card-credit')),
            matching: find.text('MYR 30.00')),
        findsOneWidget);

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
    expect(
        find.descendant(
            of: find.byKey(const Key('accounts-card-credit')),
            matching: find.text('MYR 80.00')),
        findsOneWidget);
    expect(find.text('MYR 30.00'), findsNothing);
    await tester.tap(find.text('信用'));
    await tester.pumpAndSettle();
    expect(find.text('额度已用 9%'), findsOneWidget); // 470 / 5000 at cutoff
    expect(find.text('额度已用 29%'), findsNothing);
    expect(find.textContaining('本期应还 '), findsNothing);

    tester.view.physicalSize = const Size(960, 844);
    await tester.pumpAndSettle();
    final creditLabel = find.text('信用卡溢缴款');
    final creditAmount = find.descendant(
        of: find.byKey(const Key('accounts-card-credit')),
        matching: find.text('MYR 80.00'));
    expect(creditLabel, findsOneWidget);
    expect(creditAmount, findsOneWidget);
    expect(tester.getTopLeft(creditAmount).dx,
        greaterThan(tester.getTopRight(creditLabel).dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('due amount, month-end debt and committed usage stay distinct',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final today = DateUtils.dateOnly(DateTime.now());
    final statementDay = today.day == 1 ? 15 : today.day - 1;
    Account card(String id, double limit) => Account(
          id: id,
          name: id,
          accountType: AccountType.creditCard,
          reportGroup: ReportGroup.credit,
          currency: 'MYR',
          currentBalance: 0,
          creditLimit: limit,
          statementDay: statementDay,
          paymentDueDay: today.day,
        );
    final period = calculateCreditCardBillingPeriod(
        statementDay: statementDay, paymentDueDay: today.day, now: today);
    final repo = await _repositoryWith([
      card('PayLater', 1000),
      card('Other', 0)
    ], [
      _charge('billed', 'PayLater', 241.94, period.statementDate),
      _charge('unbilled', 'PayLater', 58.06, today),
      _charge('instalment', 'PayLater', 200,
          DateTime(today.year, today.month + 2, 1)),
      _charge(
          'planned', 'PayLater', 500, DateTime(today.year, today.month + 2, 2),
          status: TransactionStatus.planned),
      _charge('same-balance', 'Other', 20, period.statementDate),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        financeRepositoryProvider.overrideWith(() => _CardRepository(repo))
      ],
      child: MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.monochrome),
        home: Scaffold(body: AccountsV2Screen(repository: repo)),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('信用'));
    await tester.pumpAndSettle();

    final row = find
        .ancestor(of: find.text('PayLater'), matching: find.byType(InkWell))
        .first;
    expect(
        find.descendant(of: row, matching: find.text('今日到期')), findsOneWidget);
    expect(
        find.descendant(of: row, matching: find.text('月末欠款')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('MYR 300.00')),
        findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('本期应还 MYR 241.94')),
        findsOneWidget);
    expect(find.text('本期应还 MYR 20.00'), findsNothing);
    expect(find.descendant(of: row, matching: find.text('额度已用 50%')),
        findsOneWidget);
    final usage = tester
        .widget<CompassDualProgressBar>(find.descendant(
            of: row, matching: find.byType(CompassDualProgressBar)))
        .actualRatio;
    expect(usage, 0.5);
    final otherRow = find
        .ancestor(of: find.text('Other'), matching: find.byType(InkWell))
        .first;
    expect(
        find.descendant(
            of: otherRow, matching: find.byType(CompassDualProgressBar)),
        findsNothing);
    await tester.tap(find.text('PayLater'));
    await tester.pumpAndSettle();
    expect(find.text('额度使用 50%'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        usage);
    expect(tester.takeException(), isNull);
  });
}
