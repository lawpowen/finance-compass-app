import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/database/database_connection_native.dart';
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  for (final (name, badFields) in <(String, Map<String, Object>)>[
    ('duplicate ID', {'id': 'good'}),
    ('missing payer', {'account_id': 'gone'}),
    ('missing target', {'type': 'transfer', 'to_account_id': 'gone'}),
    ('missing category', {'category_id': 'gone'}),
  ]) {
    test(
        'legacy preset set with $name is quarantined before inserting any rows',
        () async {
      final dir = await Directory.systemTemp.createTemp('preset_quarantine_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'ledger.sqlite'));
      final old = AppDatabase.forTesting(NativeDatabase(file));
      await old.insertAccount(const Account(
          id: 'bank',
          name: 'Bank',
          accountType: AccountType.bankSaving,
          reportGroup: ReportGroup.cash,
          currency: 'MYR',
          initialBalance: 50,
          currentBalance: 50));
      // Simulate a v9 ledger whose old JSON has never been converted.
      await old.deleteMetaValue('local_profile_id');
      await old.deleteMetaValue(AppDatabase.presetTablesMarker);
      final good = {
        'id': 'good',
        'name': 'Lunch',
        'type': 'expense',
        'account_id': 'bank',
        'amount': 10
      };
      final bad = {...good, 'id': 'bad', ...badFields};
      final original = jsonEncode([good, bad]);
      await old.setMetaValue(AppDatabase.legacyTemplatesKey, original);
      await old.setMetaValue(
          AppDatabase.legacyRulesKey,
          jsonEncode([
            {...good, 'id': 'rule', 'start_date': '2026-01-01'}
          ]));
      await old.close();

      final db = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(db.close);
      final ledger = await FinanceRepository.load(db);
      expect(ledger.accounts.single.currentBalance, 50);
      expect(ledger.transactionTemplates, isEmpty);
      expect(ledger.recurringTransactionRules.single.id, 'rule');
      expect(
          ledger
              .metaValues['legacy_preset_recovery/transaction_templates_json'],
          original);
      expect(ledger.metaValues[AppDatabase.legacyTemplatesKey], isNull);
      expect(ledger.metaValues[AppDatabase.presetTablesMarker], 'true');
    });
  }

  test('empty preset tables survive reopen, restore and clearing the ledger',
      () async {
    final dir = await Directory.systemTemp.createTemp('ledger_preset_test_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'ledger.sqlite'));
    var db = AppDatabase.forTesting(NativeDatabase(file));
    var repo = await FinanceRepository.load(db);
    repo = await repo.addAccount(const Account(
        id: 'bank',
        name: 'Bank',
        accountType: AccountType.bankSaving,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 500));
    final tx = FinanceTransaction(
        id: 'draft',
        type: TransactionType.expense,
        accountId: 'bank',
        currency: 'MYR',
        amount: 10,
        transactionDate: DateTime(2000, 1));
    repo = await repo.addTransactionTemplate(
        name: 'old-template', transaction: tx);
    repo = await repo.addRecurringTransactionRule(
        name: 'old-rule', transaction: tx);
    final template = repo.transactionTemplates.single;
    final rule = repo.recurringTransactionRules.single;
    expect(await db.getMetaValue(AppDatabase.legacyTemplatesKey), isNull);
    expect(await db.getMetaValue(AppDatabase.legacyRulesKey), isNull);
    repo = await repo.deleteTransactionTemplate(template.id);
    repo = await repo.deleteRecurringTransactionRule(rule.id);
    final staleTemplate = jsonEncode([template.toJson()]);
    final staleRule = jsonEncode([rule.toJson()]);
    // Previous v7+ installation: new tables were intentionally emptied, but a
    // crash or old backup left its redundant JSON. Preserve the ambiguity for audit.
    await db.deleteMetaValue(AppDatabase.presetTablesMarker);
    await db.deleteMetaValue('account_report_groups_v1');
    await db.customStatement(
        "UPDATE accounts SET report_group = '' WHERE id = 'bank'");
    await db.setMetaValue(AppDatabase.legacyTemplatesKey, staleTemplate);
    await db.setMetaValue(AppDatabase.legacyRulesKey, staleRule);
    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(() => db.close());
    repo = await FinanceRepository.load(db);
    expect(repo.accounts.single.reportGroup, ReportGroup.cash);
    expect(repo.transactionTemplates, isEmpty);
    expect(repo.recurringTransactionRules, isEmpty);
    expect(
        await db
            .getMetaValue('legacy_preset_recovery/transaction_templates_json'),
        staleTemplate);
    expect(
        await db.getMetaValue(
            'legacy_preset_recovery/recurring_transaction_rules_json'),
        staleRule);
    final payload = await repo.buildJsonSnapshotPayload();
    final meta = payload['meta'] as Map<String, String>;
    // Even a foreign v3 snapshot with old meta must honor its explicit [].
    meta[AppDatabase.legacyTemplatesKey] = staleTemplate;
    meta[AppDatabase.legacyRulesKey] = staleRule;
    repo = await repo.restoreSyncedSnapshot(payload);
    expect(repo.transactionTemplates, isEmpty);
    expect(repo.recurringTransactionRules, isEmpty);
    expect(await db.getMetaValue(AppDatabase.legacyTemplatesKey), isNull);
    repo = await repo.addAssetGoal(name: 'previous-ledger', amount: 100);
    await db.setMetaValue('theme_style', 'monochrome');
    final profile = await db.getMetaValue('local_profile_id');
    repo = await repo.clearAllData();
    expect(repo.assetGoals, isEmpty);
    expect(repo.accounts, isEmpty);
    expect(repo.transactionTemplates, isEmpty);
    expect(
        repo.metaValues.keys
            .where((k) => k.startsWith('legacy_preset_recovery/')),
        isEmpty);
    expect(repo.metaValues['theme_style'], 'monochrome');
    expect(repo.metaValues['local_profile_id'], profile);
  });

  test('published SQLite and JSON backups use the same committed WAL snapshot',
      () async {
    final dir = await Directory.systemTemp.createTemp('ledger_wal_backup_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'active.sqlite'));
    final writer = sqlite.sqlite3.open(file.path);
    addTearDown(writer.dispose);
    writer.execute('PRAGMA journal_mode=WAL');
    writer.execute('PRAGMA wal_autocheckpoint=0');
    writer.execute(
        'CREATE TABLE accounts (id TEXT PRIMARY KEY, current_balance REAL)');
    writer.execute(
        'CREATE TABLE transactions (id TEXT PRIMARY KEY, amount REAL)');
    writer.execute('PRAGMA user_version=6');
    writer.execute("INSERT INTO accounts VALUES ('cash', 100)");
    writer.execute("INSERT INTO transactions VALUES ('opening', 100)");
    writer.execute('BEGIN IMMEDIATE');
    writer.execute("UPDATE accounts SET current_balance=80 WHERE id='cash'");
    writer.execute("INSERT INTO transactions VALUES ('later', -20)");

    final dirs = await Future.wait([
      createPreSchemaMigrationBackup(file, dir),
      createPreSchemaMigrationBackup(file, dir),
    ]);
    writer.execute('COMMIT');
    expect(dirs[0]!.path, isNot(dirs[1]!.path));
    for (final point in dirs.nonNulls) {
      final image = sqlite.sqlite3.open(
          p.join(point.path, 'finance_app.sqlite'),
          mode: sqlite.OpenMode.readOnly);
      try {
        expect(image.userVersion, 6);
        expect(
            image
                .select('SELECT current_balance FROM accounts')
                .single
                .values
                .single,
            100);
        expect(
            image
                .select('SELECT SUM(amount) FROM transactions')
                .single
                .values
                .single,
            100);
        final data = jsonDecode(
            await File(p.join(point.path, 'snapshot.json')).readAsString());
        expect(data['source_schema_version'], 6);
        expect(data['tables']['accounts'].single['current_balance'], 100);
        expect(data['tables']['transactions'], [
          {'id': 'opening', 'amount': 100}
        ]);
      } finally {
        image.dispose();
      }
      expect(await File(p.join(point.path, 'finance_app.sqlite-wal')).exists(),
          isFalse);
    }
    expect(
        writer
            .select('SELECT current_balance FROM accounts')
            .single
            .values
            .single,
        80);
    writer.execute('PRAGMA user_version=9');
    expect(await createPreSchemaMigrationBackup(file, dir), isNull);
  });

  test('invalid recovery images never appear as finished restore points',
      () async {
    final dir = await Directory.systemTemp.createTemp('ledger_invalid_backup_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'broken.sqlite'));
    final source = sqlite.sqlite3.open(file.path);
    addTearDown(source.dispose);
    source.execute('PRAGMA foreign_keys=OFF');
    source.execute('CREATE TABLE accounts (id TEXT PRIMARY KEY)');
    source.execute(
        'CREATE TABLE transactions (account_id TEXT REFERENCES accounts(id))');
    source.execute("INSERT INTO transactions VALUES ('unknown')");
    source.execute('PRAGMA user_version=6');
    await expectLater(
        createPreSchemaMigrationBackup(file, dir), throwsStateError);
    expect(source.userVersion, 6);
    expect(
        await Directory(p.join(dir.path, 'finance_compass_backups'))
            .list()
            .toList(),
        isEmpty);
  });
}
