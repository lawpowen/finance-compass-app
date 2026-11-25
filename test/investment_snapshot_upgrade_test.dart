import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

const semanticsKey = 'investment_snapshot_semantics';
const auditKey = 'investment_snapshot_upgrade_v1_json';

Map<String, dynamic> _oldBackup({double cache = 140}) => {
      'format_version': 3,
      'schema_version': 9,
      'meta': <String, dynamic>{},
      'accounts': [
        {
          'id': 'portfolio',
          'name': 'Portfolio',
          'account_type': 'trading',
          'report_group': 'investment',
          'currency': 'MYR',
          'initial_balance': 90,
          'current_balance': cache
        },
      ],
      'categories': [],
      'budgets': [],
      'transactions': [
        {
          'id': 'deposit',
          'type': 'adjustment',
          'account_id': 'portfolio',
          'amount': 30,
          'transaction_date': '2026-03-01',
          'status': 'settled'
        },
        {
          'id': 'interest',
          'type': 'income',
          'account_id': 'portfolio',
          'amount': 10,
          'transaction_date': '2026-03-02'
        },
        {
          'id': 'plan',
          'type': 'adjustment',
          'account_id': 'portfolio',
          'amount': 600,
          'transaction_date': '2026-03-10',
          'status': 'planned'
        },
      ],
      'asset_snapshots': [
        {
          'id': 'jan',
          'account_id': 'portfolio',
          'snapshot_date': '2026-01-01',
          'market_value': 90,
          'cost_basis': 90
        },
        {
          'id': 'feb',
          'account_id': 'portfolio',
          'snapshot_date': '2026-02-01',
          'market_value': 130,
          'cash_balance': 50,
          'cost_basis': 90,
          'unrealized_pnl': 40
        },
      ],
      'transaction_templates': [],
      'recurring_transaction_rules': [],
    };

void main() {
  test('a lone legacy portfolio value becomes explicit opening capital once',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final legacy = _oldBackup(cache: 850)
      ..['asset_snapshots'] = []
      ..['transactions'] = [];
    legacy['accounts'][0]['initial_balance'] = 0;
    var repo =
        await (await FinanceRepository.load(db)).restoreSyncedSnapshot(legacy);
    for (var pass = 0; pass < 2; pass++) {
      expect(repo.accounts.single.initialBalance, 850);
      expect(repo.accounts.single.currentBalance, 850);
      expect(repo.costBasisForAccount('portfolio'), 850);
      expect(repo.accountBalanceAt('portfolio', DateTime(2026, 3, 1)), 850);
      expect(repo.snapshots, isEmpty);
      expect(repo.transactions, isEmpty);
      final audit = jsonDecode(repo.metaValues[auditKey]!)['portfolio'];
      expect(audit['original_initial_balance'], 0);
      expect(audit['original_current_balance'], 850);
      expect(audit['reason'], 'sole_recorded_balance_used_as_opening');
      repo = await repo
          .restoreSyncedSnapshot(await repo.buildJsonSnapshotPayload());
    }
  });

  test(
      'recording and restoring a zero-principal installment never reduces the loan',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await FinanceRepository.load(db);
    repo = await repo.addAccount(const Account(
        id: 'cash',
        name: 'Cash',
        reportGroup: ReportGroup.cash,
        accountType: AccountType.cash,
        currency: 'MYR',
        initialBalance: 10,
        currentBalance: 10));
    repo = await repo.addAccount(const Account(
        id: 'loan',
        name: 'Loan',
        reportGroup: ReportGroup.credit,
        accountType: AccountType.loan,
        currency: 'MYR',
        initialBalance: -1,
        currentBalance: -1));
    repo = await repo.addTransaction(FinanceTransaction(
        id: 'payment',
        accountId: 'cash',
        toAccountId: 'loan',
        type: TransactionType.transfer,
        amount: .01,
        toAmount: 0,
        currency: 'MYR',
        toCurrency: 'MYR',
        loanInstallmentNumber: 1,
        description: '银行扣账',
        transactionDate: DateTime(2026, 3, 1)));
    for (var pass = 0; pass < 3; pass++) {
      expect(
          repo.accounts.singleWhere((a) => a.id == 'loan').currentBalance, -1);
      expect(repo.accountBalanceAt('loan', DateTime(2026, 2)), -1);
      expect(repo.accounts.singleWhere((a) => a.id == 'cash').currentBalance,
          closeTo(9.99, 1e-9));
      expect(repo.transactions.single.toAmount, 0);
      expect(repo.transferIncomingAmountInBase(repo.transactions.single), 0);
      final copy = await repo.buildJsonSnapshotPayload();
      if (pass == 1) copy['meta'].remove(semanticsKey);
      repo = await repo.restoreSyncedSnapshot(copy);
    }
    repo = await repo.deleteExistingTransactions(['payment']);
    expect(repo.accounts.singleWhere((a) => a.id == 'loan').currentBalance, -1);
    expect(repo.accounts.singleWhere((a) => a.id == 'cash').currentBalance, 10);
  });

  test('old sync ledger unfolds only the evidenced latest observation once',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = await FinanceRepository.load(db);
    final converted = await repo.restoreSyncedSnapshot(_oldBackup());
    expect(converted.accounts.single.currentBalance, 140);
    expect(converted.accountBalanceAt('portfolio', DateTime(2026, 1, 31)), 90);
    expect(converted.accountBalanceAt('portfolio', DateTime(2026, 2, 28)), 100);
    final feb = converted.snapshots.singleWhere((s) => s.id == 'feb');
    expect(feb.cashBalance, 20);
    expect(feb.costBasis, 90);
    final audit = jsonDecode(converted.metaValues[auditKey]!) as Map;
    expect(audit['portfolio']['original_market_value'], 130);
    final backup = await converted.buildJsonSnapshotPayload();
    expect(backup['meta'][semanticsKey], 'immutable_v1');
    final restored = await converted.restoreSyncedSnapshot(backup);
    final secondBackup = await restored.buildJsonSnapshotPayload();
    for (final key in ['accounts', 'transactions', 'asset_snapshots', 'meta']) {
      expect(secondBackup[key], backup[key], reason: key);
    }
  });

  test(
      'ambiguous legacy values remain as supplied and keep the old cache for reconciliation',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final original = await FinanceRepository.load(db);
    final repo = await original.restoreSyncedSnapshot(_oldBackup(cache: 145));
    expect(repo.latestSnapshotForAccount('portfolio')!.marketValue, 130);
    expect(repo.accounts.single.currentBalance, 170);
    final audit = jsonDecode(repo.metaValues[auditKey]!) as Map;
    expect(audit['portfolio']['original_current_balance'], 145);
    expect(
        audit['portfolio']['reasons'], contains('cache_matches_neither_model'));
  });

  test('conversion retains unverifiable cash and tied observations for review',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final legacy = _oldBackup(cache: 80);
    legacy['transactions'][0]['amount'] = -30;
    legacy['asset_snapshots'][1]['market_value'] = 70;
    legacy['asset_snapshots'][1]['cash_balance'] = 0;
    final repo =
        await (await FinanceRepository.load(db)).restoreSyncedSnapshot(legacy);
    final feb = repo.latestSnapshotForAccount('portfolio')!;
    expect(feb.marketValue, 100);
    expect(feb.cashBalance, 0);
    expect(jsonDecode(repo.metaValues[auditKey]!)['portfolio']['reasons'],
        contains('legacy_cash_clamp_unknown'));

    legacy['asset_snapshots'][0]['snapshot_date'] = '2026-02-01';
    final tied = await repo.restoreSyncedSnapshot(legacy);
    expect(tied.snapshots.singleWhere((s) => s.id == 'feb').marketValue, 70);
    expect(tied.snapshots.singleWhere((s) => s.id == 'jan').marketValue, 90);
    expect(jsonDecode(tied.metaValues[auditKey]!)['portfolio']['reasons'],
        contains('latest_timestamp_tie'));
  });

  test(
      'v9 native open converts old observations once without changing the schema',
      () async {
    final dir = await Directory.systemTemp.createTemp('investment_v9_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/ledger.sqlite');
    final old = AppDatabase.forTesting(NativeDatabase(file));
    await old.customStatement(
        "INSERT INTO accounts (id,name,account_type,report_group,currency,initial_balance,current_balance) "
        "VALUES ('portfolio','Portfolio','trading','investment','MYR',90,130)");
    await old.customStatement(
        "INSERT INTO asset_snapshots (id,account_id,snapshot_date,market_value,cost_basis,cash_balance,unrealized_pnl) "
        "VALUES ('old','portfolio',10000,130,90,45,40)");
    await old.customStatement(
        "INSERT INTO transactions (id,type,account_id,amount,currency,transaction_date,status) "
        "VALUES ('deposit','adjustment','portfolio',30,'MYR',20000,'actual')");
    await old.deleteMetaValue(semanticsKey);
    await old.close();
    for (var pass = 0; pass < 2; pass++) {
      final db = AppDatabase.forTesting(NativeDatabase(file));
      try {
        final repo = await FinanceRepository.load(db);
        expect(db.schemaVersion, 9);
        expect(repo.snapshots.single.marketValue, 100);
        expect(repo.snapshots.single.cashBalance, 15);
        expect(repo.accounts.single.currentBalance, 130);
        expect(repo.metaValues[semanticsKey], 'immutable_v1');
      } finally {
        await db.close();
      }
    }
  });
}
