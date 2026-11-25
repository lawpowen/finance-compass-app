import 'dart:convert';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart' hide Account;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/models/transaction_preset.dart' as preset;
import 'package:finance_app/src/features/transactions/transaction_form_dialog.dart';
import 'package:finance_app/src/core/utils/anchored_month.dart';
import 'package:flutter_test/flutter_test.dart';

Future<FinanceRepository> _testLedger(AppDatabase db) async {
  final initial = await FinanceRepository.load(db);
  return initial.addAccount(const Account(
      id: 'cash',
      name: 'Cash',
      accountType: AccountType.cash,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      currentBalance: 500));
}

void main() {
  test('month-end rules and monthly batch preserve the original day', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await _testLedger(db);
    for (final year in [2024, 2025]) {
      final start = DateTime(year, 1, 31);
      final expected = [
        start,
        DateTime(year, 2, year == 2024 ? 29 : 28),
        DateTime(year, 3, 31),
        DateTime(year, 4, 30)
      ];
      final seed = FinanceTransaction(
          id: 'seed',
          type: TransactionType.expense,
          accountId: 'cash',
          amount: 10,
          currency: 'MYR',
          transactionDate: start);
      expect(
          buildRecurringTransactions(baseTransaction: seed, months: 4)
              .map((t) => t.transactionDate),
          expected);
      final rule = RecurringTransactionRule.fromTransaction(
          id: 'rent_$year', name: 'Rent $year', transaction: seed);
      repo = await repo.saveRecurringTransactionRule(rule);
      repo = await repo.generateRecurringTransactions(rule.id,
          asOf: DateTime(year - 1, 12, 1), monthsAhead: 4);
      final dates = repo.transactions
          .where((t) => t.recurringRuleId == rule.id)
          .map((t) => t.transactionDate)
          .toList()
        ..sort();
      expect(dates, expected);
    }
    expect(
        recurringDates(
                start: DateTime(1900, 1, 31),
                intervalMonths: 3,
                after: DateTime(2026, 1, 31),
                through: DateTime(2026, 5, 1))
            .single,
        DateTime(2026, 4, 30));
  });

  test('promoting a saved future plan and rebuilding a name retain occurrences',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await _testLedger(db);
    final now = DateTime.now();
    final seed = FinanceTransaction(
        id: 'existing',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 20,
        currency: 'MYR',
        status: TransactionStatus.planned,
        transactionDate: DateTime(now.year, now.month + 1, 15));
    repo = await repo.addTransaction(seed);
    repo =
        await repo.addRecurringTransactionRule(name: 'Rent', transaction: seed);
    final rule = repo.recurringTransactionRules.single;
    final seedRow = repo.transactions.singleWhere((t) => t.id == seed.id);
    expect(seedRow.recurringRuleId, rule.id);
    expect(repo.transactions.length, 3);
    final ids = repo.transactions.map((t) => t.id).toSet();
    final removed = ids.firstWhere((id) => id != seed.id);
    repo = await repo.deleteExistingTransactions([removed]);
    final changed = FinanceTransaction(
        id: 'new_draft',
        accountId: 'cash',
        type: TransactionType.expense,
        amount: 40,
        currency: 'MYR',
        transactionDate: seed.transactionDate);
    repo = await repo.addRecurringTransactionRule(
        name: 'Rent', transaction: changed);
    expect(repo.recurringTransactionRules.single.id, rule.id);
    expect(
        repo.transactions.map((t) => t.id).toSet(), ids.difference({removed}));
    await Future.wait([
      repo.generateRecurringTransactions(rule.id, monthsAhead: 6),
      repo.generateRecurringTransactions(rule.id, monthsAhead: 6)
    ]);
    final stored = await repo.refresh();
    expect(stored.transactions.where((t) => t.amount == 40), hasLength(3));
    expect(stored.transactions, hasLength(5));
    expect(stored.recurringTransactionRules.single.generatedMonthKeys.toSet(),
        hasLength(6));
    expect(stored.accounts.single.currentBalance, 500);

    final deletedRule = await stored.deleteRecurringTransactionRule(rule.id);
    final restored = await deletedRule
        .restoreSyncedSnapshot(await deletedRule.buildJsonSnapshotPayload());
    final recreated = await restored.addRecurringTransactionRule(
        name: 'Rent', transaction: changed);
    expect(recreated.recurringTransactionRules.single.id, rule.id);
    expect(recreated.transactions.map((t) => t.id).toSet(),
        stored.transactions.map((t) => t.id).toSet());
    expect(recreated.recurringTransactionRules.single.generatedMonthKeys,
        stored.recurringTransactionRules.single.generatedMonthKeys);
  });

  test(
      'moving a generated or promoted occurrence preserves its scheduled month',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await _testLedger(db);
    final rule = RecurringTransactionRule(
        id: 'fixed',
        name: 'January',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 10,
        currency: 'MYR',
        startDate: DateTime(2025, 1, 31));
    repo = await repo.saveRecurringTransactionRule(rule);
    repo = await repo.generateRecurringTransactions(rule.id,
        asOf: DateTime(2025, 1, 31), monthsAhead: 1);
    final feb = repo.transactions.single;
    repo = await repo.updateExistingTransaction(rule.toTransaction(
        id: feb.id,
        date: DateTime(2025, 3, 5),
        status: TransactionStatus.actual));
    repo = await repo.generateRecurringTransactions(rule.id,
        asOf: DateTime(2025, 1, 31), monthsAhead: 2);
    expect(
        repo.transactions.map((t) => t.transactionDate.day).toSet(), {5, 31});
    expect(
        repo.transactions
            .where((t) => t.status == TransactionStatus.actual)
            .single
            .id,
        feb.id);
    final today = DateTime.now();
    final seed = FinanceTransaction(
        id: 'arbitrary_seed',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 25,
        currency: 'MYR',
        status: TransactionStatus.planned,
        transactionDate: DateTime(today.year, today.month + 1, 15));
    repo = await repo.addTransaction(seed);
    repo =
        await repo.addRecurringTransactionRule(name: 'Seed', transaction: seed);
    final promoted =
        repo.recurringTransactionRules.singleWhere((r) => r.name == 'Seed');
    final moved = DateTime(today.year, today.month + 4, 2);
    repo = await repo.updateExistingTransaction(promoted.toTransaction(
        id: seed.id, date: moved, status: TransactionStatus.actual));
    repo =
        await repo.restoreSyncedSnapshot(await repo.buildJsonSnapshotPayload());
    repo =
        await repo.generateRecurringTransactions(promoted.id, monthsAhead: 4);
    final rows =
        repo.transactions.where((r) => r.recurringRuleId == promoted.id);
    expect(rows, hasLength(4));
    expect(
        rows
            .where((r) => r.transactionDate.month == moved.month)
            .map((r) => r.transactionDate.day)
            .toSet(),
        {2, 15});
  });

  test('another rule cannot take a retired name and duplicate its months',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await _testLedger(db);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month + 1, 12);
    final draft = FinanceTransaction(
        id: 'draft',
        type: TransactionType.expense,
        accountId: 'cash',
        currency: 'MYR',
        amount: 150,
        transactionDate: start);
    repo = await repo.addRecurringTransactionRule(
        name: 'Rent', transaction: draft);
    final oldId = repo.recurringTransactionRules.single.id;
    repo = await repo.deleteRecurringTransactionRule(oldId);
    final other = RecurringTransactionRule.fromTransaction(
        id: 'other', name: 'Travel', transaction: draft);
    repo = await repo.saveRecurringTransactionRule(other);
    final rename = RecurringTransactionRule.fromTransaction(
        id: other.id, name: 'Rent', transaction: draft);
    await expectLater(
        repo.saveRecurringTransactionRule(rename, generateMonthsAhead: 3),
        throwsA(isA<FormatException>()));
    final unchanged = await repo.refresh();
    expect(unchanged.recurringTransactionRules.single.name, 'Travel');
    expect(unchanged.transactions, hasLength(3));
    repo = await unchanged.addRecurringTransactionRule(
        name: 'Rent', transaction: draft);
    expect(
        repo.recurringTransactionRules.singleWhere((r) => r.name == 'Rent').id,
        oldId);
    expect(repo.transactions, hasLength(3));
  });

  test(
      'unmarked legacy instances prevent duplicate generation, including actuals',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await _testLedger(db);
    final rule = RecurringTransactionRule(
        id: 'rule',
        name: 'Rent',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 10,
        currency: 'MYR',
        startDate: DateTime(2025, 1, 31));
    repo = await repo.saveRecurringTransactionRule(rule);
    repo = await repo.addTransaction(rule.toTransaction(
        id: 'old_random_id',
        date: DateTime(2025, 2, 28),
        status: TransactionStatus.actual));
    repo = await repo.generateRecurringTransactions(rule.id,
        asOf: DateTime(2025, 1, 31), monthsAhead: 2);
    expect(repo.transactions, hasLength(2));
    expect(repo.transactions.singleWhere((t) => t.id == 'old_random_id').status,
        TransactionStatus.actual);
    expect(repo.recurringTransactionRules.single.generatedMonthKeys,
        ['2025-02', '2025-03']);
    expect(repo.accounts.single.currentBalance, 490);
  });

  test('failed marker write rolls back rows and seed link; retry is idempotent',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await _testLedger(db);
    final now = DateTime.now();
    final seed = FinanceTransaction(
        id: 'original',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 90,
        currency: 'MYR',
        status: TransactionStatus.planned,
        transactionDate: DateTime(now.year, now.month + 1, 1));
    repo = await repo.addTransaction(seed);
    await db.customStatement(
        "CREATE TEMP TRIGGER reject_rule BEFORE INSERT ON recurring_transaction_rules "
        "BEGIN SELECT RAISE(ABORT, 'test interrupted marker write'); END;");
    await expectLater(
        repo.addRecurringTransactionRule(name: 'Rent', transaction: seed),
        throwsA(predicate((Object e) =>
            e.toString().contains('test interrupted marker write'))));
    final rolledBack = await repo.refresh();
    expect(rolledBack.recurringTransactionRules, isEmpty);
    expect(rolledBack.transactions.single.recurringRuleId, isNull);
    expect(rolledBack.accounts.single.currentBalance, 500);
    await db.customStatement('DROP TRIGGER reject_rule');
    repo =
        await repo.addRecurringTransactionRule(name: 'Rent', transaction: seed);
    repo = await repo.generateRecurringTransactions(
        repo.recurringTransactionRules.single.id,
        monthsAhead: 3);
    expect(repo.transactions, hasLength(3));
    expect(repo.transactions.where((t) => t.id == seed.id), hasLength(1));
  });

  test('recurring rule creates planned transaction drafts with rule id', () {
    final base = FinanceTransaction(
      id: 'txn_salary',
      type: TransactionType.income,
      accountId: 'acc_bank',
      amount: 3000,
      currency: 'MYR',
      transactionDate: DateTime(2026, 4, 28),
      status: TransactionStatus.actual,
      description: 'Salary',
    );
    final rule = RecurringTransactionRule.fromTransaction(
      id: 'rule_salary',
      name: '工资',
      transaction: base,
    );
    final generated = rule.toTransaction(
      id: 'txn_salary_2026_05',
      date: DateTime(2026, 5, 28),
      status: TransactionStatus.planned,
    );

    expect(generated.recurringRuleId, 'rule_salary');
    expect(generated.status, TransactionStatus.planned);
    expect(generated.amount, 3000);
    expect(generated.description, 'Salary');
  });

  test('recurring rule preserves cross-currency transfer amounts', () {
    final base = FinanceTransaction(
      id: 'txn_transfer',
      type: TransactionType.transfer,
      accountId: 'acc_myr',
      toAccountId: 'acc_twd',
      amount: 150,
      currency: 'MYR',
      toAmount: 1000,
      toCurrency: 'TWD',
      transactionDate: DateTime(2026, 4, 28),
      status: TransactionStatus.actual,
    );
    final rule = RecurringTransactionRule.fromTransaction(
      id: 'rule_transfer',
      name: 'FX transfer',
      transaction: base,
    );

    final generated = rule.toTransaction(
      id: 'txn_transfer_2026_05',
      date: DateTime(2026, 5, 28),
      status: TransactionStatus.planned,
    );

    expect(generated.amount, 150);
    expect(generated.currency, 'MYR');
    expect(generated.toAmount, 1000);
    expect(generated.toCurrency, 'TWD');
    expect(generated.transferInAmount, 1000);
    expect(generated.transferInCurrency, 'TWD');
  });

  test('recurring rule created from a planned transaction stays planned', () {
    final base = FinanceTransaction(
      id: 'txn_plan',
      type: TransactionType.expense,
      accountId: 'acc_bank',
      amount: 88,
      currency: 'MYR',
      transactionDate: DateTime(2026, 7, 18),
      status: TransactionStatus.planned,
    );

    final rule = RecurringTransactionRule.fromTransaction(
      id: 'rule_plan',
      name: 'Planned rule',
      transaction: base,
    );

    expect(rule.status, TransactionStatus.planned);
  });

  test('saving a rule automatically creates three full months of plans',
      () async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month + 1, 15);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    var repository = await FinanceRepository.load(database);
    repository = await repository.addAccount(
      const Account(
        id: 'recurring_cash',
        name: 'Recurring cash',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        initialBalance: 1000,
        currentBalance: 1000,
      ),
    );
    repository = await repository.addRecurringTransactionRule(
      name: 'Actual installments',
      transaction: FinanceTransaction(
        id: 'actual_seed',
        type: TransactionType.expense,
        accountId: 'recurring_cash',
        amount: 100,
        currency: 'MYR',
        transactionDate: start,
        status: TransactionStatus.actual,
      ),
    );
    repository = await repository.addRecurringTransactionRule(
      name: 'Planned installments',
      transaction: FinanceTransaction(
        id: 'planned_seed',
        type: TransactionType.expense,
        accountId: 'recurring_cash',
        amount: 80,
        currency: 'MYR',
        transactionDate: start,
        status: TransactionStatus.planned,
      ),
    );

    final actualRule = repository.recurringTransactionRules
        .singleWhere((item) => item.name == 'Actual installments');
    final plannedRule = repository.recurringTransactionRules
        .singleWhere((item) => item.name == 'Planned installments');
    final actualRows = repository.transactions
        .where((item) => item.recurringRuleId == actualRule.id);
    final plannedRows = repository.transactions
        .where((item) => item.recurringRuleId == plannedRule.id);
    expect(actualRows, isNotEmpty);
    expect(actualRows, hasLength(3));
    expect(actualRows.map((item) => item.status),
        everyElement(TransactionStatus.planned));
    expect(plannedRows, hasLength(3));
    expect(plannedRows, isNotEmpty);
    expect(plannedRows.map((item) => item.status),
        everyElement(TransactionStatus.planned));

    await database.close();
  });

  test('non-positive intervalMonths is rejected and generation terminates',
      () async {
    expect(
      () => preset.RecurringTransactionRule.fromJson({
        'id': 'bad_zero',
        'type': 'expense',
        'account_id': 'cash',
        'amount': 50,
        'start_date': '2026-01-15T00:00:00.000',
        'interval_months': 0,
      }),
      throwsFormatException,
    );

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
    final seed = FinanceTransaction(
      id: 'seed',
      type: TransactionType.expense,
      accountId: 'cash',
      amount: 50,
      currency: 'MYR',
      transactionDate: DateTime(2026, 1, 15),
    );
    await expectLater(
      repository.addRecurringTransactionRule(
        name: 'Zero step',
        transaction: seed,
        intervalMonths: 0,
      ),
      throwsArgumentError,
    );

    await database.replaceRecurringTransactionRules([
      preset.RecurringTransactionRule(
        id: 'corrupt_rule',
        name: 'Corrupt',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 50,
        currency: 'MYR',
        startDate: DateTime(2020, 1, 1),
        intervalMonths: 0,
      ),
    ]);
    final loaded = await FinanceRepository.load(database);
    final afterGenerate = await loaded.generateRecurringTransactions(
      'corrupt_rule',
      monthsAhead: 3,
    );
    expect(afterGenerate.transactions, isEmpty);

    await expectLater(
      loaded.importJsonSnapshotBytes(
        utf8.encode(jsonEncode({
          'format_version': 3,
          'accounts': [
            {
              'id': 'cash',
              'name': 'Cash',
              'account_type': 'cash',
              'report_group': 'cash',
              'currency': 'MYR',
              'current_balance': 1000,
            }
          ],
          'transactions': const [],
          'recurring_transaction_rules': [
            {
              'id': 'bad_rule',
              'type': 'expense',
              'account_id': 'cash',
              'amount': 50,
              'start_date': '2026-01-15T00:00:00.000',
              'interval_months': 0,
            }
          ],
        })),
      ),
      throwsFormatException,
    );
  });
}
