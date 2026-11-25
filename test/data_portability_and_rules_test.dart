import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/category.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('explicit loan identity survives presets and repeated v3 restores',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await FinanceRepository.load(db);
    repo = await repo.addAccount(const Account(
        id: 'usd',
        name: 'USD bank',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'USD',
        initialBalance: 100,
        currentBalance: 100));
    repo = await repo.addAccount(const Account(
        id: 'loan',
        name: 'MYR loan',
        accountType: AccountType.loan,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        initialBalance: -500,
        currentBalance: -500));
    final payment = FinanceTransaction(
        id: 'paid',
        type: TransactionType.transfer,
        accountId: 'usd',
        toAccountId: 'loan',
        currency: 'USD',
        toCurrency: 'MYR',
        amount: 25,
        toAmount: 80,
        loanPaymentAmount: 100,
        loanInstallmentNumber: 3,
        transactionDate: DateTime(2025),
        merchant: 'Bank',
        description: 'manual note');
    repo = await repo.addTransaction(payment);
    repo = await repo.addTransactionTemplate(
        name: 'repayment', transaction: payment);
    final rule = RecurringTransactionRule.fromTransaction(
        id: 'r', name: 'rule', transaction: payment);
    repo = await repo.saveRecurringTransactionRule(rule);
    for (var i = 0; i < 3; i++) {
      final backup = await repo.buildJsonSnapshotPayload();
      expect((backup['transactions'] as List).single['loan_installment_number'],
          3);
      expect(
          (backup['meta'] as Map)
              .keys
              .where((key) => key.toString().startsWith('loan_installment/')),
          isEmpty);
      repo = await repo.restoreSyncedSnapshot(backup);
      expect(
          repo.accounts.singleWhere((a) => a.id == 'usd').currentBalance, 75);
      expect(repo.accounts.singleWhere((a) => a.id == 'loan').currentBalance,
          -420);
      for (final record in [
        repo.transactions.single,
        repo.transactionTemplates.single
            .toTransaction(id: 'draft', date: DateTime(2025)),
        repo.recurringTransactionRules.single.toTransaction(
            id: 'rule', date: DateTime(2025), status: TransactionStatus.planned)
      ]) {
        expect(record.loanInstallmentNumber, 3);
        expect(record.loanPaymentAmount, 100);
        expect(record.toAmount, 80);
        expect(record.description, 'manual note');
      }
    }
    for (final malformed in <Map<String, Object?>>[
      {'amount': 0},
      {'to_amount': -80},
      {'to_amount': 110},
      {'amount': 0.004},
      {'loan_payment_amount': 100.005},
      {'to_amount': 79.999},
      {'amount': 1e307},
      {'loan_installment_number': 0},
      {'loan_payment_amount': null},
      {'loan_installment_number': null},
      {'to_account_id': 'usd'},
    ]) {
      final invalid = await repo.buildJsonSnapshotPayload();
      (invalid['transactions'] as List).single.addAll(malformed);
      await expectLater(
          repo.restoreSyncedSnapshot(invalid), throwsA(isA<FormatException>()));
      repo = await FinanceRepository.load(db);
      expect(repo.transactions.single.loanInstallmentNumber, 3);
      expect(
          repo.accounts.singleWhere((a) => a.id == 'usd').currentBalance, 75);
    }
    // Failed replacements roll back deletion of both the old row and its sidecar.
    await expectLater(
        db.replaceTransactions(deleteIds: [
          'paid'
        ], insertItems: [
          FinanceTransaction(
              id: 'bad',
              type: TransactionType.transfer,
              accountId: 'usd',
              toAccountId: 'loan',
              currency: 'USD',
              toCurrency: 'MYR',
              amount: 0,
              toAmount: 80,
              loanInstallmentNumber: 3,
              loanPaymentAmount: 100,
              transactionDate: DateTime(2025)),
        ]),
        throwsA(isA<FormatException>()));
    expect((await db.fetchTransactions()).single.loanInstallmentNumber, 3);
    final reversal = FinanceTransaction(
        id: 'reverse',
        type: TransactionType.transfer,
        accountId: 'usd',
        toAccountId: 'loan',
        currency: 'USD',
        toCurrency: 'MYR',
        amount: -25,
        toAmount: -80,
        loanInstallmentNumber: 3,
        loanPaymentAmount: -100,
        transactionDate: DateTime(2025, 2));
    repo = await repo.addTransaction(reversal);
    expect(repo.accounts.singleWhere((a) => a.id == 'usd').currentBalance, 100);
    expect(
        repo.accounts.singleWhere((a) => a.id == 'loan').currentBalance, -500);
  });

  test('only legacy imports infer a monthly identity from matching loan data',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repo = await FinanceRepository.load(database);
    repo = await repo.addAccount(const Account(
        id: 'source',
        name: 'Cash',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        initialBalance: 1000,
        currentBalance: 1000));
    repo = await repo.addAccount(const Account(
        id: 'loan',
        name: 'Loan',
        accountType: AccountType.loan,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        initialBalance: -800,
        currentBalance: -800));
    repo = await repo.addTransaction(FinanceTransaction(
        id: 'old',
        type: TransactionType.transfer,
        accountId: 'source',
        toAccountId: 'loan',
        amount: 1,
        toAmount: 0,
        currency: 'MYR',
        description: '贷款月供 #8',
        transactionDate: DateTime(2025)));
    final current = await repo.buildJsonSnapshotPayload();
    repo = await repo.restoreSyncedSnapshot(current);
    expect(repo.transactions.single.loanInstallmentNumber, isNull);
    final old = await repo.buildJsonSnapshotPayload();
    (old['meta'] as Map).remove('loan_installment_semantics');
    repo = await repo.restoreSyncedSnapshot(old);
    expect(repo.transactions.single.loanInstallmentNumber, 8);
    expect(repo.transactions.single.transferInAmount, 0);
    expect(
        repo.accounts.singleWhere((a) => a.id == 'loan').currentBalance, -800);
    expect(
        (await repo.buildJsonSnapshotPayload())['meta']
            ['loan_installment_semantics'],
        'explicit_v1');
    await repo.deleteExistingTransactions(['old']);
    expect(
        (await database.fetchAccounts())
            .singleWhere((a) => a.id == 'source')
            .currentBalance,
        1000);
  });

  test(
      'old zero receipt requires evidence and preserves ambiguous observations',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await FinanceRepository.load(db);
    final empty = await repo.buildJsonSnapshotPayload();
    for (final observed in [false, true]) {
      final backup = {
        ...empty,
        'meta': <String, String>{},
        'accounts': [
          {
            'id': 'cash',
            'name': 'Cash',
            'account_type': 'cash',
            'report_group': 'cash',
            'currency': 'MYR',
            'initial_balance': 1000,
            'current_balance': 500
          },
          {
            'id': 'inv',
            'name': 'Fund',
            'account_type': 'stock',
            'report_group': 'investment',
            'currency': 'MYR',
            'initial_balance': 100,
            'current_balance': 100
          }
        ],
        'transactions': [
          {
            'id': 'tx',
            'type': 'transfer',
            'account_id': 'cash',
            'to_account_id': 'inv',
            'currency': 'MYR',
            'amount': 500,
            'to_amount': 0,
            'transaction_date': '2025-02-01'
          }
        ],
        'asset_snapshots': [
          if (observed)
            {
              'id': 'snap',
              'account_id': 'inv',
              'snapshot_date': '2025-01-01',
              'market_value': 100,
              'cash_balance': 100
            }
        ]
      };
      repo = await repo.restoreSyncedSnapshot(backup);
      // A cached value plus a mutable observation does not prove which flows
      // were already absorbed. With an opening and no observation we can reconcile.
      expect(repo.accounts.singleWhere((a) => a.id == 'inv').currentBalance,
          observed ? 100 : 600);
      expect(repo.transactions.single.transferInAmount, observed ? 0 : 500);
      final again = await repo
          .restoreSyncedSnapshot(await repo.buildJsonSnapshotPayload());
      expect(again.accounts.singleWhere((a) => a.id == 'inv').currentBalance,
          observed ? 100 : 600);
    }
  });

  test('full export preview includes real data, templates, and recurring rules',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    var repository = await FinanceRepository.load(database);

    repository = await repository.addAccount(
      const Account(
        id: 'cash',
        name: 'Cash',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 1000,
        initialBalance: 1000,
      ),
    );
    repository = await repository.addCategory(
      const Category(
        id: 'food',
        name: 'Food',
        type: CategoryType.expense,
      ),
    );
    final now = DateTime.now();
    final transaction = FinanceTransaction(
      id: 'txn_lunch',
      type: TransactionType.expense,
      accountId: 'cash',
      categoryId: 'food',
      amount: 18,
      currency: 'MYR',
      transactionDate: DateTime(now.year, now.month, now.day),
      merchant: 'Lunch',
    );
    repository = await repository.addTransaction(transaction);
    repository = await repository.addTransactionTemplate(
      name: 'Lunch template',
      transaction: transaction,
    );
    repository = await repository.addRecurringTransactionRule(
      name: 'Monthly lunch',
      transaction: transaction,
      intervalMonths: 1,
    );

    final template = repository.transactionTemplates.single;
    repository = await repository.saveTransactionTemplate(
      TransactionTemplate(
        id: template.id,
        name: template.name,
        type: template.type,
        accountId: template.accountId,
        amount: template.amount,
        currency: template.currency,
        categoryId: template.categoryId,
        merchant: template.merchant,
        sortOrder: 4,
      ),
    );
    final rule = repository.recurringTransactionRules.single;
    repository = await repository.saveRecurringTransactionRule(
      rule.copyWith(isActive: false),
    );

    final bytes = await repository.exportJsonSnapshotBytes();
    final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(payload['format_version'], 3);
    expect(payload['transaction_date_semantics'], 'occurrence_date');
    expect((payload['accounts'] as List), hasLength(1));
    expect((payload['categories'] as List), hasLength(1));
    expect((payload['transactions'] as List), hasLength(4));
    expect(
      (payload['transaction_templates'] as List).single['sort_order'],
      4,
    );
    expect(
      (payload['recurring_transaction_rules'] as List).single['is_active'],
      isFalse,
    );

    final directory = await Directory.systemTemp.createTemp('finance_export');
    final file = File('${directory.path}/snapshot.json');
    await file.writeAsBytes(bytes);
    final preview = await repository.previewImportJson(file.path);
    expect(preview.accounts, 1);
    expect(preview.categories, 1);
    expect(preview.transactions, 4);

    const pathProviderChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return directory.path;
      }
      return null;
    });
    await database.close();

    final importedDatabase = AppDatabase.forTesting(NativeDatabase.memory());
    var importedRepository = await FinanceRepository.load(importedDatabase);
    importedRepository = await importedRepository.importJsonSnapshot(file.path);
    expect(importedRepository.accounts.single.id, 'cash');
    expect(importedRepository.categories.single.id, 'food');
    expect(
      importedRepository.transactions
          .singleWhere((item) => item.id == transaction.id)
          .merchant,
      'Lunch',
    );
    expect(
      importedRepository.transactions
          .where((item) => item.status == TransactionStatus.planned),
      hasLength(3),
    );
    expect(importedRepository.transactionTemplates.single.sortOrder, 4);
    expect(
        importedRepository.recurringTransactionRules.single.isActive, isFalse);

    await importedDatabase.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    await directory.delete(recursive: true);
  });

  test('legacy credit-card import discards per-transaction settlement date',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('finance_card_import');
    const pathProviderChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return directory.path;
      }
      return null;
    });

    final file = File('${directory.path}/legacy-card.json');
    await file.writeAsString(jsonEncode({
      'meta': {
        'transaction_templates_json': jsonEncode([
          {
            'id': 'legacy-tpl',
            'name': 'Groceries',
            'type': 'expense',
            'account_id': 'card',
            'amount': 12
          }
        ]),
        'recurring_transaction_rules_json': jsonEncode([
          {
            'id': 'legacy-rule',
            'name': 'Monthly',
            'type': 'expense',
            'account_id': 'card',
            'amount': 8,
            'start_date': '2026-01-01'
          }
        ]),
      },
      'accounts': [
        {
          'id': 'card',
          'name': 'Legacy Card',
          'account_type': 'creditCard',
          'report_group': '',
          'currency': 'MYR',
          'current_balance': -88,
        }
      ],
      'transactions': [
        {
          'id': 'purchase',
          'type': 'expense',
          'account_id': 'card',
          'amount': 88,
          'currency': 'MYR',
          'record_date': '2026-06-20T00:00:00.000',
          'transaction_date': '2026-07-12T00:00:00.000',
          'status': 'actual',
        }
      ],
    }));

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    var repository = await FinanceRepository.load(database);
    repository = await repository.importJsonSnapshot(file.path);

    expect(repository.accounts.single.reportGroup, ReportGroup.credit);
    expect(repository.transactionTemplates.single.id, 'legacy-tpl');
    expect(repository.recurringTransactionRules.single.id, 'legacy-rule');
    expect(await database.getMetaValue(AppDatabase.legacyTemplatesKey), isNull);
    expect(await database.getMetaValue(AppDatabase.legacyRulesKey), isNull);
    expect(repository.transactions.single.recordDate, DateTime(2026, 6, 20));
    expect(
        repository.transactions.single.transactionDate, DateTime(2026, 6, 20));

    await file.writeAsString(jsonEncode({
      'format_version': 3,
      'transaction_date_semantics': 'occurrence_date',
      'accounts': [
        {
          'id': 'card',
          'name': 'Current Card',
          'account_type': 'creditCard',
          'report_group': 'credit',
          'currency': 'MYR',
          'current_balance': -88,
        }
      ],
      'transactions': [
        {
          'id': 'edited_purchase',
          'type': 'expense',
          'account_id': 'card',
          'amount': 88,
          'currency': 'MYR',
          'record_date': '2026-06-20T00:00:00.000',
          'transaction_date': '2026-06-25T00:00:00.000',
          'status': 'actual',
        }
      ],
    }));
    repository = await repository.importJsonSnapshot(file.path);
    expect(repository.transactions.single.recordDate, DateTime(2026, 6, 20));
    expect(
        repository.transactions.single.transactionDate, DateTime(2026, 6, 25));

    await database.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    await directory.delete(recursive: true);
  });

  test('empty export file is rejected without changing current data', () async {
    final directory =
        await Directory.systemTemp.createTemp('finance_empty_import');
    final file = File('${directory.path}/empty.json');
    await file.writeAsBytes(const []);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    var repository = await FinanceRepository.load(database);
    repository = await repository.addAccount(
      const Account(
        id: 'safe_cash',
        name: 'Safe cash',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 88,
      ),
    );

    await expectLater(
      repository.importJsonSnapshot(file.path),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('0 KB'),
        ),
      ),
    );
    final reloaded = await FinanceRepository.load(database);
    expect(reloaded.accounts.single.id, 'safe_cash');
    expect(reloaded.accounts.single.currentBalance, 88);

    await database.close();
    await directory.delete(recursive: true);
  });

  test('broken account references roll back instead of replacing live data',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('finance_invalid_import');
    const pathProviderChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return directory.path;
      }
      return null;
    });
    final file = File('${directory.path}/invalid.json');
    await file.writeAsString(jsonEncode({
      'format_version': 3,
      'accounts': [
        {
          'id': 'imported_cash',
          'name': 'Imported cash',
          'account_type': 'cash',
          'report_group': 'cash',
          'currency': 'MYR',
          'current_balance': 10,
        }
      ],
      'transactions': [
        {
          'id': 'broken_transfer',
          'type': 'transfer',
          'account_id': 'imported_cash',
          'to_account_id': 'missing_target',
          'amount': 10,
          'currency': 'MYR',
          'record_date': '2026-07-20T00:00:00.000',
          'transaction_date': '2026-07-20T00:00:00.000',
          'status': 'actual',
        }
      ],
    }));

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    var repository = await FinanceRepository.load(database);
    repository = await repository.addAccount(
      const Account(
        id: 'original_cash',
        name: 'Original cash',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 99,
      ),
    );

    await expectLater(
      repository.importJsonSnapshot(file.path),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('missing_target'),
        ),
      ),
    );
    final reloaded = await FinanceRepository.load(database);
    expect(reloaded.accounts.single.id, 'original_cash');
    expect(reloaded.accounts.single.currentBalance, 99);

    await database.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    await directory.delete(recursive: true);
  });

  test('import repairs legacy zero same-currency transfer destination balance',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('finance_transfer_repair');
    const pathProviderChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return directory.path;
      }
      return null;
    });
    final file = File('${directory.path}/legacy-zero-transfer.json');
    await file.writeAsString(jsonEncode({
      'format_version': 3,
      'accounts': [
        {
          'id': 'grab',
          'name': 'Grab',
          'initial_balance': 1000,
          'account_type': 'cash',
          'report_group': 'cash',
          'currency': 'MYR',
          'current_balance': 500,
        },
        {
          'id': 'uob_one',
          'name': 'UOB One',
          'initial_balance': 100,
          'account_type': 'cash',
          'report_group': 'cash',
          'currency': 'MYR',
          'current_balance': 100,
        }
      ],
      'transactions': [
        {
          'id': 'grab-to-uob-one',
          'type': 'transfer',
          'account_id': 'grab',
          'to_account_id': 'uob_one',
          'amount': 500,
          'currency': 'MYR',
          'to_amount': 0,
          'to_currency': 'MYR',
          'record_date': '2026-07-19T00:00:00.000',
          'transaction_date': '2026-07-19T00:00:00.000',
          'status': 'actual',
        }
      ],
    }));

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    var repository = await FinanceRepository.load(database);
    repository = await repository.importJsonSnapshot(file.path);

    expect(
      repository.accounts
          .firstWhere((account) => account.id == 'uob_one')
          .currentBalance,
      600,
    );
    expect(repository.transactions.single.toAmount, isNull);
    expect(repository.transactions.single.transferInAmount, 500);

    await database.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    await directory.delete(recursive: true);
  });
}
