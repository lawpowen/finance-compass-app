import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/category.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/ai_analysis_provider.dart';
import 'package:finance_app/src/core/services/ai_analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'AI history, forward transactions, balances and cash use one calendar cutoff',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await FinanceRepository.load(db);
    for (final id in ['cash', 'wallet', 'card']) {
      repo = await repo.addAccount(Account(
          id: id,
          name: id,
          accountType: id == 'card' ? AccountType.creditCard : AccountType.cash,
          reportGroup: id == 'card' ? ReportGroup.credit : ReportGroup.cash,
          initialBalance: id == 'cash' ? 1000 : 0,
          currentBalance: id == 'cash' ? 1000 : 0,
          currency: 'MYR'));
    }
    repo = await repo.addCategory(
        const Category(id: 'food', name: 'Food', type: CategoryType.expense));
    FinanceTransaction tx(
            String id, TransactionType type, double amount, DateTime date,
            {String? target, bool planned = false}) =>
        FinanceTransaction(
            id: id,
            description: id,
            type: type,
            amount: amount,
            categoryId: type == TransactionType.expense ? 'food' : null,
            accountId: 'cash',
            toAccountId: target,
            currency: 'MYR',
            transactionDate: date,
            status:
                planned ? TransactionStatus.planned : TransactionStatus.actual);
    repo = await repo.addTransactions([
      tx('unrealized-plan', TransactionType.expense, 5, DateTime(2024, 2, 1),
          planned: true),
      tx('lunch', TransactionType.expense, 20, DateTime(2024, 2, 15, 14)),
      tx('salary', TransactionType.income, 100, DateTime(2024, 2, 16)),
      tx('repayment', TransactionType.transfer, 40, DateTime(2024, 2, 17),
          target: 'card'),
      tx('internal', TransactionType.transfer, 50, DateTime(2024, 2, 18),
          target: 'wallet'),
      tx('refund', TransactionType.expense, -30, DateTime(2024, 2, 19)),
      tx('last-evening', TransactionType.expense, 30,
          DateTime(2024, 3, 31, 23, 59, 59)),
      tx('outside', TransactionType.expense, 40, DateTime(2024, 4, 1)),
    ]);
    repo = await repo.saveRecurringTransactionRule(
        RecurringTransactionRule.fromTransaction(
            id: 'rule',
            name: 'Monthly',
            transaction: tx('rule-source', TransactionType.expense, 10,
                DateTime(2024, 1, 31))));
    final clock = DateTime(2024, 2, 15, 9);
    final data = AiAnalysisService.buildRequestData(repo,
        includePlanned: false, monthCount: 1, futureMonthCount: 1, asOf: clock);
    expect(data['generated_at'], clock.toIso8601String());
    expect(data['total_assets'], 980);
    expect((data['assets_by_group'] as Map)['cash'], 980);
    expect(
        (data['recent_actual_transactions'] as List)
            .map((r) => r['description']),
        ['lunch']);
    expect((data['future_transactions'] as List).map((r) => r['description']),
        ['salary', 'repayment', 'internal', 'refund', 'last-evening']);
    final current = data['current_month'] as Map;
    expect(current['actual_income'], 0);
    expect(current['actual_expense'], 20);
    expect(current['actual_cash_net'], -20);
    expect((data['current_month_remaining'] as Map)['confirmed_future_income'],
        100);
    final category = (data['expense_categories'] as List)
        .singleWhere((r) => r['id'] == 'food');
    expect(category['actual_total'], 20);
    final rule = (data['recurring_transaction_rules'] as List).single;
    expect(rule['template_status'], 'actual');
    expect(rule['status_when_generated'], 'planned');
    final cash = (data['cash_flow_projection'] as List);
    expect(cash.first['transfers'], -40);
    expect(cash.first['net'], 90);
    expect(cash.first['ending_cash'], 1070);
    expect(cash.last['ending_cash'], 1040);
    final withPlans = AiAnalysisService.buildRequestData(repo,
        includePlanned: true, monthCount: 1, futureMonthCount: 1, asOf: clock);
    expect((withPlans['current_month'] as Map)['expense'], 25);
    expect((withPlans['current_month'] as Map)['income'], 0);
    expect(
        ((withPlans['cash_flow_projection'] as List).first
            as Map)['ending_cash'],
        1070);
  });

  test('dismissing an analysis error preserves the last summary', () {
    const state = AiAnalysisState(error: 'old error', summary: 'last result');
    final cleared = state.copyWith(clearError: true);
    expect(cleared.error, isNull);
    expect(cleared.summary, 'last result');
  });
}
