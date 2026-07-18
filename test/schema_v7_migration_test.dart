import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test('v6 data upgrades in place and migrates preset metadata', () async {
    final directory = await Directory.systemTemp.createTemp('finance_v7_test');
    final file = File('${directory.path}/finance.sqlite');
    final legacy = sqlite.sqlite3.open(file.path);
    legacy.execute('''
      CREATE TABLE accounts (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        account_type TEXT NOT NULL,
        report_group TEXT NOT NULL,
        currency TEXT NOT NULL,
        initial_balance REAL NOT NULL DEFAULT 0,
        current_balance REAL NOT NULL,
        institution TEXT,
        note TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      );
      CREATE TABLE categories (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        parent_id TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      );
      CREATE TABLE budgets (
        id TEXT NOT NULL PRIMARY KEY,
        category_id TEXT NOT NULL,
        month_key TEXT NOT NULL,
        amount REAL NOT NULL,
        currency TEXT NOT NULL DEFAULT 'MYR',
        alert_threshold REAL NOT NULL DEFAULT 0.8,
        rollover_enabled INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      );
      CREATE TABLE transactions (
        id TEXT NOT NULL PRIMARY KEY,
        type TEXT NOT NULL,
        account_id TEXT NOT NULL,
        to_account_id TEXT,
        category_id TEXT,
        amount REAL NOT NULL,
        currency TEXT NOT NULL,
        to_amount REAL,
        to_currency TEXT,
        record_date INTEGER,
        transaction_date INTEGER NOT NULL,
        status TEXT,
        recurring_rule_id TEXT,
        description TEXT,
        merchant TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      );
      CREATE TABLE asset_snapshots (
        id TEXT NOT NULL PRIMARY KEY,
        account_id TEXT NOT NULL,
        snapshot_date INTEGER NOT NULL,
        market_value REAL NOT NULL,
        cost_basis REAL NOT NULL DEFAULT 0,
        cash_balance REAL NOT NULL DEFAULT 0,
        unrealized_pnl REAL NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      );
      CREATE TABLE app_meta (
        key TEXT NOT NULL PRIMARY KEY,
        value TEXT NOT NULL
      );
      PRAGMA user_version = 6;
    ''');
    legacy.execute(
      "INSERT INTO accounts (id,name,account_type,report_group,currency,current_balance) VALUES ('card','Legacy Card','creditCard','credit','MYR',-321.45)",
    );
    legacy.execute(
      "INSERT INTO accounts (id,name,account_type,report_group,currency,current_balance) VALUES ('cash','Cash','cash','cash','MYR',1000)",
    );
    final purchaseDate = DateTime(2026, 6, 20);
    final legacySettlementDate = DateTime(2026, 7, 12);
    legacy.execute(
      'INSERT INTO transactions '
      '(id,type,account_id,amount,currency,record_date,transaction_date,status) '
      'VALUES (?,?,?,?,?,?,?,?)',
      [
        'card_purchase',
        'expense',
        'card',
        88.0,
        'MYR',
        purchaseDate.millisecondsSinceEpoch ~/ 1000,
        legacySettlementDate.millisecondsSinceEpoch ~/ 1000,
        'actual',
      ],
    );
    legacy.execute(
      'INSERT INTO transactions '
      '(id,type,account_id,amount,currency,record_date,transaction_date,status) '
      'VALUES (?,?,?,?,?,?,?,?)',
      [
        'cash_purchase',
        'expense',
        'cash',
        12.0,
        'MYR',
        purchaseDate.millisecondsSinceEpoch ~/ 1000,
        legacySettlementDate.millisecondsSinceEpoch ~/ 1000,
        'actual',
      ],
    );
    legacy.execute(
      'INSERT INTO app_meta (key,value) VALUES (?,?)',
      [
        'transaction_templates_json',
        jsonEncode([
          {
            'id': 'tpl_legacy',
            'name': 'Coffee',
            'type': 'expense',
            'account_id': 'card',
            'amount': 12.5,
            'currency': 'MYR',
            'status': 'actual',
          }
        ]),
      ],
    );
    legacy.dispose();

    final database = AppDatabase.forTesting(NativeDatabase(file));
    final accounts = await database.fetchAccounts();
    final transactions = await database.fetchTransactions();
    final templates = await database.fetchTransactionTemplates();

    expect(database.schemaVersion, 7);
    final card = accounts.singleWhere((item) => item.id == 'card');
    expect(card.currentBalance, -321.45);
    expect(card.creditLimit, isNull);
    expect(card.statementDay, isNull);
    expect(
      transactions
          .singleWhere((item) => item.id == 'card_purchase')
          .transactionDate,
      purchaseDate,
    );
    expect(
      transactions
          .singleWhere((item) => item.id == 'cash_purchase')
          .transactionDate,
      legacySettlementDate,
    );
    expect(templates.single.id, 'tpl_legacy');
    expect(templates.single.amount, 12.5);
    expect(
        await database.getMetaValue('transaction_templates_json'), isNotNull);
    expect(
        await database.getMetaValue('local_profile_id'), startsWith('local_'));

    await database.close();
    await directory.delete(recursive: true);
  });
}
