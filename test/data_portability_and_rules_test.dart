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
    final transaction = FinanceTransaction(
      id: 'txn_lunch',
      type: TransactionType.expense,
      accountId: 'cash',
      categoryId: 'food',
      amount: 18,
      currency: 'MYR',
      transactionDate: DateTime(2026, 7, 17),
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
    expect((payload['transactions'] as List), hasLength(1));
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
    expect(preview.transactions, 1);

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
    expect(importedRepository.transactions.single.merchant, 'Lunch');
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
      'accounts': [
        {
          'id': 'card',
          'name': 'Legacy Card',
          'account_type': 'creditCard',
          'report_group': 'credit',
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
}
