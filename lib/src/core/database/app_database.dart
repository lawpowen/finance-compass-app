import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../models/account.dart' as model;
import '../models/asset_snapshot.dart' as model;
import '../models/budget.dart' as model;
import '../models/category.dart' as model;
import '../models/transaction.dart' as model;
import '../models/transaction_preset.dart' as model;
import 'enum_codec.dart';
import 'tables/accounts_table.dart';
import 'tables/asset_snapshots_table.dart';
import 'tables/app_meta_table.dart';
import 'tables/budgets_table.dart';
import 'tables/categories_table.dart';
import 'tables/transactions_table.dart';
import 'tables/transaction_templates_table.dart';
import 'tables/recurring_transaction_rules_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Accounts,
    Categories,
    Budgets,
    Transactions,
    AssetSnapshots,
    AppMeta,
    TransactionTemplates,
    RecurringTransactionRules,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(appMeta);
          }
          if (from < 3) {
            await m.addColumn(transactions, transactions.recordDate);
          }
          if (from < 4) {
            await m.addColumn(transactions, transactions.status);
            await m.addColumn(transactions, transactions.recurringRuleId);
          }
          if (from < 5) {
            await m.addColumn(transactions, transactions.toAmount);
            await m.addColumn(transactions, transactions.toCurrency);
          }
          if (from < 6) {
            await m.addColumn(budgets, budgets.currency);
          }
          if (from < 7) {
            await m.addColumn(accounts, accounts.creditLimit);
            await m.addColumn(accounts, accounts.statementDay);
            await m.addColumn(accounts, accounts.paymentDueDay);
            await m.addColumn(categories, categories.iconKey);
            await m.addColumn(categories, categories.colorValue);
            await m.addColumn(categories, categories.sortOrder);
            await m.addColumn(categories, categories.isArchived);
            await m.createTable(transactionTemplates);
            await m.createTable(recurringTransactionRules);
          }
        },
        beforeOpen: (_) async {
          await _migrateLegacyPresetMetadata();
          await _migrateCreditCardTransactionDates();
          await _ensureLocalProfileId();
          await _applyV2VisualDefault();
          await _validateDatabaseIntegrity();
        },
      );

  Future<List<model.Account>> fetchAccounts() async {
    final rows = await select(accounts).get();
    return rows
        .map(
          (row) => model.Account(
            id: row.id,
            name: row.name,
            accountType: enumByName(model.AccountType.values, row.accountType),
            reportGroup: enumByName(model.ReportGroup.values, row.reportGroup),
            currency: row.currency,
            initialBalance: row.initialBalance,
            currentBalance: row.currentBalance,
            institution: row.institution,
            note: row.note,
            isActive: row.isActive,
            creditLimit: row.creditLimit,
            statementDay: row.statementDay,
            paymentDueDay: row.paymentDueDay,
          ),
        )
        .toList();
  }

  Future<List<model.Category>> fetchCategories() async {
    final rows = await select(categories).get();
    return rows
        .map(
          (row) => model.Category(
            id: row.id,
            name: row.name,
            type: enumByName(model.CategoryType.values, row.type),
            parentId: row.parentId,
            iconKey: row.iconKey,
            colorValue: row.colorValue,
            sortOrder: row.sortOrder,
            isArchived: row.isArchived,
          ),
        )
        .toList();
  }

  Future<List<model.Budget>> fetchBudgets() async {
    final rows = await select(budgets).get();
    return rows
        .map(
          (row) => model.Budget(
            id: row.id,
            categoryId: row.categoryId,
            monthKey: row.monthKey,
            amount: row.amount,
            currency: row.currency,
            alertThreshold: row.alertThreshold,
            rolloverEnabled: row.rolloverEnabled,
          ),
        )
        .toList();
  }

  Future<List<model.FinanceTransaction>> fetchTransactions() async {
    final rows = await select(transactions).get();
    return rows
        .map(
          (row) => model.FinanceTransaction(
            id: row.id,
            type: enumByName(model.TransactionType.values, row.type),
            accountId: row.accountId,
            toAccountId: row.toAccountId,
            categoryId: row.categoryId,
            amount: row.amount,
            currency: row.currency,
            toAmount: row.toAmount,
            toCurrency: row.toCurrency,
            recordDate: row.recordDate ?? row.transactionDate,
            transactionDate: row.transactionDate,
            status: row.status == null
                ? model.TransactionStatus.actual
                : enumByName(model.TransactionStatus.values, row.status!),
            recurringRuleId: row.recurringRuleId,
            description: row.description,
            merchant: row.merchant,
          ),
        )
        .toList();
  }

  Future<List<model.AssetSnapshot>> fetchAssetSnapshots() async {
    final rows = await select(assetSnapshots).get();
    return rows
        .map(
          (row) => model.AssetSnapshot(
            id: row.id,
            accountId: row.accountId,
            snapshotDate: row.snapshotDate,
            marketValue: row.marketValue,
            costBasis: row.costBasis,
            cashBalance: row.cashBalance,
            unrealizedPnl: row.unrealizedPnl,
          ),
        )
        .toList();
  }

  Future<List<model.TransactionTemplate>> fetchTransactionTemplates() async {
    final rows = await (select(transactionTemplates)
          ..orderBy([
            (row) => OrderingTerm.asc(row.sortOrder),
            (row) => OrderingTerm.asc(row.name),
          ]))
        .get();
    return rows
        .map(
          (row) => model.TransactionTemplate(
            id: row.id,
            name: row.name,
            type: enumByName(model.TransactionType.values, row.type),
            accountId: row.accountId,
            toAccountId: row.toAccountId,
            categoryId: row.categoryId,
            amount: row.amount,
            currency: row.currency,
            toAmount: row.toAmount,
            toCurrency: row.toCurrency,
            status: enumByName(model.TransactionStatus.values, row.status),
            description: row.description,
            merchant: row.merchant,
            sortOrder: row.sortOrder,
          ),
        )
        .toList();
  }

  Future<List<model.RecurringTransactionRule>>
      fetchRecurringTransactionRules() async {
    final rows = await (select(recurringTransactionRules)
          ..orderBy([(row) => OrderingTerm.asc(row.name)]))
        .get();
    return rows
        .map(
          (row) => model.RecurringTransactionRule(
            id: row.id,
            name: row.name,
            type: enumByName(model.TransactionType.values, row.type),
            accountId: row.accountId,
            toAccountId: row.toAccountId,
            categoryId: row.categoryId,
            amount: row.amount,
            currency: row.currency,
            toAmount: row.toAmount,
            toCurrency: row.toCurrency,
            startDate: row.startDate,
            intervalMonths: row.intervalMonths,
            status: enumByName(model.TransactionStatus.values, row.status),
            description: row.description,
            merchant: row.merchant,
            endDate: row.endDate,
            generatedMonthKeys:
                (jsonDecode(row.generatedMonthKeysJson) as List<dynamic>)
                    .map((item) => '$item')
                    .toList(),
            isActive: row.isActive,
          ),
        )
        .toList();
  }

  Future<void> replaceTransactionTemplates(
    List<model.TransactionTemplate> items,
  ) async {
    await super.transaction(() async {
      await delete(transactionTemplates).go();
      if (items.isEmpty) return;
      await batch((batch) {
        batch.insertAll(
          transactionTemplates,
          items.map(_transactionTemplateCompanion).toList(),
        );
      });
    });
  }

  Future<void> replaceRecurringTransactionRules(
    List<model.RecurringTransactionRule> items,
  ) async {
    await super.transaction(() async {
      await delete(recurringTransactionRules).go();
      if (items.isEmpty) return;
      await batch((batch) {
        batch.insertAll(
          recurringTransactionRules,
          items.map(_recurringRuleCompanion).toList(),
        );
      });
    });
  }

  TransactionTemplatesCompanion _transactionTemplateCompanion(
    model.TransactionTemplate item,
  ) {
    return TransactionTemplatesCompanion.insert(
      id: item.id,
      name: item.name,
      type: item.type.name,
      accountId: item.accountId,
      toAccountId: Value(item.toAccountId),
      categoryId: Value(item.categoryId),
      amount: item.amount,
      currency: item.currency,
      toAmount: Value(item.toAmount),
      toCurrency: Value(item.toCurrency),
      status: Value(item.status.name),
      description: Value(item.description),
      merchant: Value(item.merchant),
      sortOrder: Value(item.sortOrder),
    );
  }

  RecurringTransactionRulesCompanion _recurringRuleCompanion(
    model.RecurringTransactionRule item,
  ) {
    return RecurringTransactionRulesCompanion.insert(
      id: item.id,
      name: item.name,
      type: item.type.name,
      accountId: item.accountId,
      toAccountId: Value(item.toAccountId),
      categoryId: Value(item.categoryId),
      amount: item.amount,
      currency: item.currency,
      toAmount: Value(item.toAmount),
      toCurrency: Value(item.toCurrency),
      startDate: item.startDate,
      intervalMonths: Value(item.intervalMonths),
      status: Value(item.status.name),
      description: Value(item.description),
      merchant: Value(item.merchant),
      endDate: Value(item.endDate),
      generatedMonthKeysJson: Value(jsonEncode(item.generatedMonthKeys)),
      isActive: Value(item.isActive),
    );
  }

  Future<void> _migrateLegacyPresetMetadata() async {
    final templateCount = await (selectOnly(transactionTemplates)
          ..addColumns([transactionTemplates.id.count()]))
        .map((row) => row.read(transactionTemplates.id.count()) ?? 0)
        .getSingle();
    if (templateCount == 0) {
      final raw = await getMetaValue('transaction_templates_json');
      if (raw != null && raw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(raw) as List<dynamic>;
          final items = decoded
              .whereType<Map>()
              .map((item) => model.TransactionTemplate.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList();
          await replaceTransactionTemplates(items);
        } catch (_) {
          // Keep the legacy JSON untouched so the recovery path remains valid.
        }
      }
    }

    final ruleCount = await (selectOnly(recurringTransactionRules)
          ..addColumns([recurringTransactionRules.id.count()]))
        .map((row) => row.read(recurringTransactionRules.id.count()) ?? 0)
        .getSingle();
    if (ruleCount == 0) {
      final raw = await getMetaValue('recurring_transaction_rules_json');
      if (raw != null && raw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(raw) as List<dynamic>;
          final items = decoded
              .whereType<Map>()
              .map((item) => model.RecurringTransactionRule.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList();
          await replaceRecurringTransactionRules(items);
        } catch (_) {
          // Keep the legacy JSON untouched so the recovery path remains valid.
        }
      }
    }
  }

  Future<void> _ensureLocalProfileId() async {
    final existing = await getMetaValue('local_profile_id');
    if (existing != null && existing.trim().isNotEmpty) return;
    await setMetaValue(
      'local_profile_id',
      'local_${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  /// Converts the legacy per-transaction settlement-date model to the
  /// account-level credit-card billing-cycle model.
  ///
  /// Older builds stored the user-entered occurrence date in `record_date`
  /// and a separate card settlement date in `transaction_date`. Credit-card
  /// statements are now derived from the occurrence date plus the account's
  /// statement day, so carrying the legacy settlement date forward would put
  /// purchases in the wrong cycle. The marker makes this destructive field
  /// normalization run once while leaving amounts and non-card transactions
  /// untouched.
  Future<void> _migrateCreditCardTransactionDates() async {
    const marker = 'credit_card_account_billing_dates_v1';
    if (await getMetaValue(marker) == 'true') return;

    await customUpdate('''
      UPDATE transactions
      SET transaction_date = record_date
      WHERE record_date IS NOT NULL
        AND transaction_date != record_date
        AND (
          account_id IN (
            SELECT id FROM accounts WHERE account_type = 'creditCard'
          )
          OR to_account_id IN (
            SELECT id FROM accounts WHERE account_type = 'creditCard'
          )
        )
    ''');
    await setMetaValue(marker, 'true');
  }

  Future<void> _applyV2VisualDefault() async {
    final applied = await getMetaValue('ui_redesign_v2_applied');
    if (applied == 'true') return;
    await setMetaValue('theme_style', 'abyss');
    await setMetaValue('ui_redesign_v2_applied', 'true');
  }

  Future<void> _validateDatabaseIntegrity() async {
    final quickCheck = await customSelect('PRAGMA quick_check').get();
    final isOk = quickCheck.length == 1 &&
        quickCheck.first.data.values.first.toString() == 'ok';
    if (!isOk) {
      throw StateError('SQLite quick_check failed after schema migration.');
    }
    final foreignKeyFailures =
        await customSelect('PRAGMA foreign_key_check').get();
    if (foreignKeyFailures.isNotEmpty) {
      throw StateError('Foreign-key validation failed after schema migration.');
    }
  }

  Future<int> accountCount() async {
    final query = selectOnly(accounts)..addColumns([accounts.id.count()]);
    final row = await query.getSingle();
    return row.read(accounts.id.count()) ?? 0;
  }

  Future<bool> hasCompletedSeed() async {
    final row = await (select(appMeta)
          ..where((tbl) => tbl.key.equals('seed_completed')))
        .getSingleOrNull();
    return row?.value == 'true';
  }

  Future<void> markSeedCompleted() {
    return into(appMeta).insertOnConflictUpdate(
      const AppMetaCompanion(
        key: Value('seed_completed'),
        value: Value('true'),
      ),
    );
  }

  Future<String?> getMetaValue(String keyValue) async {
    final row = await (select(appMeta)
          ..where((tbl) => tbl.key.equals(keyValue)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<Map<String, String>> fetchAllMetaValues() async {
    final rows = await select(appMeta).get();
    return {
      for (final row in rows) row.key: row.value,
    };
  }

  Future<void> setMetaValue(String keyValue, String valueText) {
    return into(appMeta).insertOnConflictUpdate(
      AppMetaCompanion(
        key: Value(keyValue),
        value: Value(valueText),
      ),
    );
  }

  Future<void> deleteMetaValue(String keyValue) {
    return (delete(appMeta)..where((tbl) => tbl.key.equals(keyValue))).go();
  }

  Future<void> seedAll({
    required List<model.Account> accountItems,
    required List<model.Category> categoryItems,
    required List<model.Budget> budgetItems,
    required List<model.FinanceTransaction> transactionItems,
    required List<model.AssetSnapshot> snapshotItems,
  }) async {
    await batch((batch) {
      batch.insertAll(
        accounts,
        accountItems
            .map(
              (item) => AccountsCompanion.insert(
                id: item.id,
                name: item.name,
                accountType: item.accountType.name,
                reportGroup: item.reportGroup.name,
                currency: item.currency,
                currentBalance: item.currentBalance,
                initialBalance: Value(item.initialBalance),
                institution: Value(item.institution),
                note: Value(item.note),
                isActive: Value(item.isActive),
                creditLimit: Value(item.creditLimit),
                statementDay: Value(item.statementDay),
                paymentDueDay: Value(item.paymentDueDay),
              ),
            )
            .toList(),
      );
      batch.insertAll(
        categories,
        categoryItems
            .map(
              (item) => CategoriesCompanion.insert(
                id: item.id,
                name: item.name,
                type: item.type.name,
                parentId: Value(item.parentId),
                iconKey: Value(item.iconKey),
                colorValue: Value(item.colorValue),
                sortOrder: Value(item.sortOrder),
                isArchived: Value(item.isArchived),
              ),
            )
            .toList(),
      );
      batch.insertAll(
        budgets,
        budgetItems
            .map(
              (item) => BudgetsCompanion.insert(
                id: item.id,
                categoryId: item.categoryId,
                monthKey: item.monthKey,
                amount: item.amount,
                currency: Value(item.currency),
                alertThreshold: Value(item.alertThreshold),
                rolloverEnabled: Value(item.rolloverEnabled),
              ),
            )
            .toList(),
      );
      batch.insertAll(
        transactions,
        transactionItems
            .map(
              (item) => TransactionsCompanion.insert(
                id: item.id,
                type: item.type.name,
                accountId: item.accountId,
                amount: item.amount,
                currency: item.currency,
                toAmount: Value(item.toAmount),
                toCurrency: Value(item.toCurrency),
                recordDate: Value(item.recordDate),
                transactionDate: item.transactionDate,
                status: Value(item.status.name),
                recurringRuleId: Value(item.recurringRuleId),
                toAccountId: Value(item.toAccountId),
                categoryId: Value(item.categoryId),
                description: Value(item.description),
                merchant: Value(item.merchant),
              ),
            )
            .toList(),
      );
      batch.insertAll(
        assetSnapshots,
        snapshotItems
            .map(
              (item) => AssetSnapshotsCompanion.insert(
                id: item.id,
                accountId: item.accountId,
                snapshotDate: item.snapshotDate,
                marketValue: item.marketValue,
                costBasis: Value(item.costBasis),
                cashBalance: Value(item.cashBalance),
                unrealizedPnl: Value(item.unrealizedPnl),
              ),
            )
            .toList(),
      );
    });
  }

  Future<void> replaceAllWithSeedData({
    required List<model.Account> accountItems,
    required List<model.Category> categoryItems,
    required List<model.Budget> budgetItems,
    required List<model.FinanceTransaction> transactionItems,
    required List<model.AssetSnapshot> snapshotItems,
    List<model.TransactionTemplate> templateItems = const [],
    List<model.RecurringTransactionRule> recurringRuleItems = const [],
    Map<String, String>? metaValues,
  }) async {
    await super.transaction(() async {
      await delete(recurringTransactionRules).go();
      await delete(transactionTemplates).go();
      await delete(assetSnapshots).go();
      await delete(transactions).go();
      await delete(budgets).go();
      await delete(categories).go();
      await delete(accounts).go();
      await delete(appMeta).go();

      await seedAll(
        accountItems: accountItems,
        categoryItems: categoryItems,
        budgetItems: budgetItems,
        transactionItems: transactionItems,
        snapshotItems: snapshotItems,
      );

      if (templateItems.isNotEmpty || recurringRuleItems.isNotEmpty) {
        await batch((batch) {
          if (templateItems.isNotEmpty) {
            batch.insertAll(
              transactionTemplates,
              templateItems.map(_transactionTemplateCompanion).toList(),
            );
          }
          if (recurringRuleItems.isNotEmpty) {
            batch.insertAll(
              recurringTransactionRules,
              recurringRuleItems.map(_recurringRuleCompanion).toList(),
            );
          }
        });
      }

      if (metaValues != null && metaValues.isNotEmpty) {
        await batch((batch) {
          batch.insertAll(
            appMeta,
            metaValues.entries
                .map(
                  (entry) => AppMetaCompanion.insert(
                    key: entry.key,
                    value: entry.value,
                  ),
                )
                .toList(),
          );
        });
      }

      await into(appMeta).insertOnConflictUpdate(
        const AppMetaCompanion(
          key: Value('seed_completed'),
          value: Value('true'),
        ),
      );
      await _ensureLocalProfileId();
      // Import parsing has already applied the source format's date semantics.
      // Mark the resulting snapshot so a later reopen does not reinterpret a
      // v3 user-edited occurrence date as a legacy settlement date.
      await setMetaValue('credit_card_account_billing_dates_v1', 'true');
    });
  }

  Future<void> insertAccount(model.Account account) {
    return into(accounts).insert(
      AccountsCompanion.insert(
        id: account.id,
        name: account.name,
        accountType: account.accountType.name,
        reportGroup: account.reportGroup.name,
        currency: account.currency,
        currentBalance: account.currentBalance,
        initialBalance: Value(account.initialBalance),
        institution: Value(account.institution),
        note: Value(account.note),
        isActive: Value(account.isActive),
        creditLimit: Value(account.creditLimit),
        statementDay: Value(account.statementDay),
        paymentDueDay: Value(account.paymentDueDay),
      ),
    );
  }

  Future<void> updateAccount(model.Account account) {
    return (update(accounts)..where((tbl) => tbl.id.equals(account.id))).write(
      AccountsCompanion(
        name: Value(account.name),
        accountType: Value(account.accountType.name),
        reportGroup: Value(account.reportGroup.name),
        currency: Value(account.currency),
        initialBalance: Value(account.initialBalance),
        currentBalance: Value(account.currentBalance),
        institution: Value(account.institution),
        note: Value(account.note),
        isActive: Value(account.isActive),
        creditLimit: Value(account.creditLimit),
        statementDay: Value(account.statementDay),
        paymentDueDay: Value(account.paymentDueDay),
      ),
    );
  }

  Future<bool> accountHasLinkedData(String accountId) async {
    final ownedTransactions = await ((select(transactions)
          ..where((tbl) =>
              tbl.accountId.equals(accountId) |
              tbl.toAccountId.equals(accountId))
          ..limit(1)))
        .getSingleOrNull();
    if (ownedTransactions != null) {
      return true;
    }

    final linkedTemplate = await ((select(transactionTemplates)
          ..where((tbl) =>
              tbl.accountId.equals(accountId) |
              tbl.toAccountId.equals(accountId))
          ..limit(1)))
        .getSingleOrNull();
    if (linkedTemplate != null) return true;

    final linkedRule = await ((select(recurringTransactionRules)
          ..where((tbl) =>
              tbl.accountId.equals(accountId) |
              tbl.toAccountId.equals(accountId))
          ..limit(1)))
        .getSingleOrNull();
    if (linkedRule != null) return true;

    final snapshot = await ((select(assetSnapshots)
          ..where((tbl) => tbl.accountId.equals(accountId))
          ..limit(1)))
        .getSingleOrNull();
    return snapshot != null;
  }

  Future<bool> deleteAccountIfSafe(String accountId) async {
    if (await accountHasLinkedData(accountId)) {
      return false;
    }

    await (delete(accounts)..where((tbl) => tbl.id.equals(accountId))).go();
    return true;
  }

  Future<void> insertCategory(model.Category category) {
    return into(categories).insert(
      CategoriesCompanion.insert(
        id: category.id,
        name: category.name,
        type: category.type.name,
        parentId: Value(category.parentId),
        iconKey: Value(category.iconKey),
        colorValue: Value(category.colorValue),
        sortOrder: Value(category.sortOrder),
        isArchived: Value(category.isArchived),
      ),
    );
  }

  Future<void> updateCategory(model.Category category) {
    return (update(categories)..where((tbl) => tbl.id.equals(category.id)))
        .write(
      CategoriesCompanion(
        name: Value(category.name),
        type: Value(category.type.name),
        parentId: Value(category.parentId),
        iconKey: Value(category.iconKey),
        colorValue: Value(category.colorValue),
        sortOrder: Value(category.sortOrder),
        isArchived: Value(category.isArchived),
      ),
    );
  }

  Future<bool> categoryHasLinkedData(String categoryId) async {
    final linkedTransaction = await ((select(transactions)
          ..where((tbl) => tbl.categoryId.equals(categoryId))
          ..limit(1)))
        .getSingleOrNull();
    if (linkedTransaction != null) {
      return true;
    }
    final linkedBudget = await ((select(budgets)
          ..where((tbl) => tbl.categoryId.equals(categoryId))
          ..limit(1)))
        .getSingleOrNull();
    if (linkedBudget != null) return true;
    final linkedTemplate = await ((select(transactionTemplates)
          ..where((tbl) => tbl.categoryId.equals(categoryId))
          ..limit(1)))
        .getSingleOrNull();
    if (linkedTemplate != null) return true;
    final linkedRule = await ((select(recurringTransactionRules)
          ..where((tbl) => tbl.categoryId.equals(categoryId))
          ..limit(1)))
        .getSingleOrNull();
    return linkedRule != null;
  }

  Future<bool> deleteCategoryIfSafe(String categoryId) async {
    if (await categoryHasLinkedData(categoryId)) {
      return false;
    }
    await (delete(categories)..where((tbl) => tbl.id.equals(categoryId))).go();
    return true;
  }

  Future<void> upsertBudget(model.Budget budget) async {
    final existing = await (select(budgets)
          ..where((tbl) => tbl.id.equals(budget.id)))
        .getSingleOrNull();

    if (existing == null) {
      final sameMonthRule = await (select(budgets)
            ..where((tbl) =>
                tbl.categoryId.equals(budget.categoryId) &
                tbl.monthKey.equals(budget.monthKey)))
          .getSingleOrNull();

      if (sameMonthRule != null) {
        await (update(budgets)..where((tbl) => tbl.id.equals(sameMonthRule.id)))
            .write(
          BudgetsCompanion(
            categoryId: Value(budget.categoryId),
            monthKey: Value(budget.monthKey),
            amount: Value(budget.amount),
            currency: Value(budget.currency),
            alertThreshold: Value(budget.alertThreshold),
            rolloverEnabled: Value(budget.rolloverEnabled),
          ),
        );
        return;
      }
    }

    if (existing == null) {
      await into(budgets).insert(
        BudgetsCompanion.insert(
          id: budget.id,
          categoryId: budget.categoryId,
          monthKey: budget.monthKey,
          amount: budget.amount,
          currency: Value(budget.currency),
          alertThreshold: Value(budget.alertThreshold),
          rolloverEnabled: Value(budget.rolloverEnabled),
        ),
      );
      return;
    }

    await (update(budgets)..where((tbl) => tbl.id.equals(existing.id))).write(
      BudgetsCompanion(
        categoryId: Value(budget.categoryId),
        monthKey: Value(budget.monthKey),
        amount: Value(budget.amount),
        currency: Value(budget.currency),
        alertThreshold: Value(budget.alertThreshold),
        rolloverEnabled: Value(budget.rolloverEnabled),
      ),
    );
  }

  Future<void> deleteBudget(String budgetId) {
    return (delete(budgets)..where((tbl) => tbl.id.equals(budgetId))).go();
  }

  Future<void> insertTransaction(model.FinanceTransaction entry) async {
    await super.transaction(() async {
      await into(transactions).insert(
        TransactionsCompanion.insert(
          id: entry.id,
          type: entry.type.name,
          accountId: entry.accountId,
          amount: entry.amount,
          currency: entry.currency,
          toAmount: Value(entry.toAmount),
          toCurrency: Value(entry.toCurrency),
          recordDate: Value(entry.recordDate),
          transactionDate: entry.transactionDate,
          status: Value(entry.status.name),
          recurringRuleId: Value(entry.recurringRuleId),
          toAccountId: Value(entry.toAccountId),
          categoryId: Value(entry.categoryId),
          description: Value(entry.description),
          merchant: Value(entry.merchant),
        ),
      );

      await _applyTransactionToBalances(entry);
    });
  }

  Future<void> insertTransactions(
      List<model.FinanceTransaction> entries) async {
    await super.transaction(() async {
      for (final entry in entries) {
        await into(transactions).insert(
          TransactionsCompanion.insert(
            id: entry.id,
            type: entry.type.name,
            accountId: entry.accountId,
            amount: entry.amount,
            currency: entry.currency,
            toAmount: Value(entry.toAmount),
            toCurrency: Value(entry.toCurrency),
            recordDate: Value(entry.recordDate),
            transactionDate: entry.transactionDate,
            status: Value(entry.status.name),
            recurringRuleId: Value(entry.recurringRuleId),
            toAccountId: Value(entry.toAccountId),
            categoryId: Value(entry.categoryId),
            description: Value(entry.description),
            merchant: Value(entry.merchant),
          ),
        );
        await _applyTransactionToBalances(entry);
      }
    });
  }

  Future<void> updateTransaction(model.FinanceTransaction entry) async {
    await super.transaction(() async {
      final existing = await (select(transactions)
            ..where((tbl) => tbl.id.equals(entry.id)))
          .getSingle();
      final previous = model.FinanceTransaction(
        id: existing.id,
        type: enumByName(model.TransactionType.values, existing.type),
        accountId: existing.accountId,
        toAccountId: existing.toAccountId,
        categoryId: existing.categoryId,
        amount: existing.amount,
        currency: existing.currency,
        toAmount: existing.toAmount,
        toCurrency: existing.toCurrency,
        recordDate: existing.recordDate ?? existing.transactionDate,
        transactionDate: existing.transactionDate,
        status: existing.status == null
            ? model.TransactionStatus.actual
            : enumByName(model.TransactionStatus.values, existing.status!),
        recurringRuleId: existing.recurringRuleId,
        description: existing.description,
        merchant: existing.merchant,
      );

      await _reverseTransactionFromBalances(previous);
      await (update(transactions)..where((tbl) => tbl.id.equals(entry.id)))
          .write(
        TransactionsCompanion(
          type: Value(entry.type.name),
          accountId: Value(entry.accountId),
          amount: Value(entry.amount),
          currency: Value(entry.currency),
          toAmount: Value(entry.toAmount),
          toCurrency: Value(entry.toCurrency),
          recordDate: Value(entry.recordDate),
          transactionDate: Value(entry.transactionDate),
          status: Value(entry.status.name),
          recurringRuleId: Value(entry.recurringRuleId),
          toAccountId: Value(entry.toAccountId),
          categoryId: Value(entry.categoryId),
          description: Value(entry.description),
          merchant: Value(entry.merchant),
        ),
      );
      await _applyTransactionToBalances(entry);
    });
  }

  Future<void> deleteTransaction(String transactionId) =>
      deleteTransactionsByIds([transactionId]);

  Future<void> deleteTransactionsByIds(Iterable<String> transactionIds) async {
    final ids = transactionIds.toSet().toList(growable: false);
    if (ids.isEmpty) return;
    await super.transaction(() async {
      final existing =
          await (select(transactions)..where((tbl) => tbl.id.isIn(ids))).get();
      if (existing.length != ids.length) {
        throw StateError('One or more selected transactions no longer exist.');
      }
      for (final row in existing) {
        final previous = model.FinanceTransaction(
          id: row.id,
          type: enumByName(model.TransactionType.values, row.type),
          accountId: row.accountId,
          toAccountId: row.toAccountId,
          categoryId: row.categoryId,
          amount: row.amount,
          currency: row.currency,
          toAmount: row.toAmount,
          toCurrency: row.toCurrency,
          recordDate: row.recordDate ?? row.transactionDate,
          transactionDate: row.transactionDate,
          status: row.status == null
              ? model.TransactionStatus.actual
              : enumByName(model.TransactionStatus.values, row.status!),
          recurringRuleId: row.recurringRuleId,
          description: row.description,
          merchant: row.merchant,
        );
        await _reverseTransactionFromBalances(previous);
      }
      await (delete(transactions)..where((tbl) => tbl.id.isIn(ids))).go();
    });
  }

  Future<void> insertAssetSnapshot(model.AssetSnapshot snapshot) async {
    await super.transaction(() async {
      await into(assetSnapshots).insert(
        AssetSnapshotsCompanion.insert(
          id: snapshot.id,
          accountId: snapshot.accountId,
          snapshotDate: snapshot.snapshotDate,
          marketValue: snapshot.marketValue,
          costBasis: Value(snapshot.costBasis),
          cashBalance: Value(snapshot.cashBalance),
          unrealizedPnl: Value(snapshot.unrealizedPnl),
        ),
      );

      await (update(accounts)
            ..where((tbl) => tbl.id.equals(snapshot.accountId)))
          .write(
        AccountsCompanion(
          currentBalance: Value(snapshot.marketValue),
        ),
      );
    });
  }

  Future<void> updateAssetSnapshot(model.AssetSnapshot snapshot) async {
    await super.transaction(() async {
      await (update(assetSnapshots)..where((tbl) => tbl.id.equals(snapshot.id)))
          .write(
        AssetSnapshotsCompanion(
          accountId: Value(snapshot.accountId),
          snapshotDate: Value(snapshot.snapshotDate),
          marketValue: Value(snapshot.marketValue),
          costBasis: Value(snapshot.costBasis),
          cashBalance: Value(snapshot.cashBalance),
          unrealizedPnl: Value(snapshot.unrealizedPnl),
        ),
      );

      final latest = await (select(assetSnapshots)
            ..where((tbl) => tbl.accountId.equals(snapshot.accountId))
            ..orderBy([(tbl) => OrderingTerm.desc(tbl.snapshotDate)])
            ..limit(1))
          .getSingleOrNull();
      if (latest != null) {
        await (update(accounts)
              ..where((tbl) => tbl.id.equals(snapshot.accountId)))
            .write(
          AccountsCompanion(
            currentBalance: Value(latest.marketValue),
          ),
        );
      }
    });
  }

  Future<void> deleteAssetSnapshot(String snapshotId) async {
    await super.transaction(() async {
      final existing = await (select(assetSnapshots)
            ..where((tbl) => tbl.id.equals(snapshotId)))
          .getSingleOrNull();
      if (existing == null) {
        return;
      }
      final accountId = existing.accountId;
      await (delete(assetSnapshots)..where((tbl) => tbl.id.equals(snapshotId)))
          .go();

      final latest = await (select(assetSnapshots)
            ..where((tbl) => tbl.accountId.equals(accountId))
            ..orderBy([(tbl) => OrderingTerm.desc(tbl.snapshotDate)])
            ..limit(1))
          .getSingleOrNull();
      await (update(accounts)..where((tbl) => tbl.id.equals(accountId))).write(
        AccountsCompanion(
          currentBalance: Value(latest?.marketValue ?? 0),
        ),
      );
    });
  }

  Future<void> clearAllUserData() async {
    await super.transaction(() async {
      await delete(recurringTransactionRules).go();
      await delete(transactionTemplates).go();
      await delete(assetSnapshots).go();
      await delete(transactions).go();
      await delete(budgets).go();
      await delete(categories).go();
      await delete(accounts).go();
      await into(appMeta).insertOnConflictUpdate(
        const AppMetaCompanion(
          key: Value('seed_completed'),
          value: Value('true'),
        ),
      );
    });
  }

  Future<void> _applyTransactionToBalances(
      model.FinanceTransaction transaction) async {
    if (!transaction.affectsBalance) {
      return;
    }
    switch (transaction.type) {
      case model.TransactionType.income:
        await _incrementAccountBalance(
            transaction.accountId, transaction.amount);
        return;
      case model.TransactionType.adjustment:
        await _incrementAccountBalance(
            transaction.accountId, transaction.amount);
        await _syncInvestmentFlowIntoSnapshot(
          accountId: transaction.accountId,
          delta: transaction.amount,
          transactionDate: transaction.transactionDate,
        );
        return;
      case model.TransactionType.expense:
        await _incrementAccountBalance(
            transaction.accountId, -transaction.amount);
        return;
      case model.TransactionType.transfer:
        await _incrementAccountBalance(
            transaction.accountId, -transaction.amount);
        await _syncInvestmentFlowIntoSnapshot(
          accountId: transaction.accountId,
          delta: -transaction.amount,
          transactionDate: transaction.transactionDate,
        );
        if (transaction.toAccountId != null) {
          final incomingAmount = transaction.transferInAmount;
          await _incrementAccountBalance(
              transaction.toAccountId!, incomingAmount);
          await _syncInvestmentFlowIntoSnapshot(
            accountId: transaction.toAccountId!,
            delta: incomingAmount,
            transactionDate: transaction.transactionDate,
          );
        }
        return;
    }
  }

  Future<void> _reverseTransactionFromBalances(
      model.FinanceTransaction transaction) async {
    if (!transaction.affectsBalance) {
      return;
    }
    switch (transaction.type) {
      case model.TransactionType.income:
        await _incrementAccountBalance(
            transaction.accountId, -transaction.amount);
        return;
      case model.TransactionType.adjustment:
        await _incrementAccountBalance(
            transaction.accountId, -transaction.amount);
        await _syncInvestmentFlowIntoSnapshot(
          accountId: transaction.accountId,
          delta: -transaction.amount,
          transactionDate: transaction.transactionDate,
        );
        return;
      case model.TransactionType.expense:
        await _incrementAccountBalance(
            transaction.accountId, transaction.amount);
        return;
      case model.TransactionType.transfer:
        await _incrementAccountBalance(
            transaction.accountId, transaction.amount);
        await _syncInvestmentFlowIntoSnapshot(
          accountId: transaction.accountId,
          delta: transaction.amount,
          transactionDate: transaction.transactionDate,
        );
        if (transaction.toAccountId != null) {
          final incomingAmount = transaction.transferInAmount;
          await _incrementAccountBalance(
              transaction.toAccountId!, -incomingAmount);
          await _syncInvestmentFlowIntoSnapshot(
            accountId: transaction.toAccountId!,
            delta: -incomingAmount,
            transactionDate: transaction.transactionDate,
          );
        }
        return;
    }
  }

  Future<void> _incrementAccountBalance(String accountId, double delta) async {
    final row = await (select(accounts)
          ..where((tbl) => tbl.id.equals(accountId)))
        .getSingle();
    await (update(accounts)..where((tbl) => tbl.id.equals(accountId))).write(
      AccountsCompanion(
        currentBalance: Value(row.currentBalance + delta),
      ),
    );
  }

  Future<void> _syncInvestmentFlowIntoSnapshot({
    required String accountId,
    required double delta,
    required DateTime transactionDate,
  }) async {
    if (delta == 0) {
      return;
    }
    final account = await (select(accounts)
          ..where((tbl) => tbl.id.equals(accountId)))
        .getSingle();
    final reportGroup =
        enumByName(model.ReportGroup.values, account.reportGroup);
    if (reportGroup != model.ReportGroup.investment &&
        reportGroup != model.ReportGroup.retirement) {
      return;
    }

    final latest = await (select(assetSnapshots)
          ..where((tbl) => tbl.accountId.equals(accountId))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.snapshotDate)])
          ..limit(1))
        .getSingleOrNull();
    final first = await (select(assetSnapshots)
          ..where((tbl) => tbl.accountId.equals(accountId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.snapshotDate)])
          ..limit(1))
        .getSingleOrNull();

    if (latest == null) {
      final seededCost = delta.clamp(0, double.infinity).toDouble();
      final seededMarketValue = account.currentBalance;
      final seededCashBalance =
          account.currentBalance.clamp(0, double.infinity).toDouble();
      await into(assetSnapshots).insert(
        AssetSnapshotsCompanion.insert(
          id: 'snap_${DateTime.now().microsecondsSinceEpoch}',
          accountId: accountId,
          snapshotDate: transactionDate,
          marketValue: seededMarketValue,
          costBasis: Value(seededCost),
          cashBalance: Value(seededCashBalance),
          unrealizedPnl: Value(seededMarketValue - seededCost),
        ),
      );
      return;
    }

    final nextMarketValue = latest.marketValue + delta;
    final nextCashBalance =
        (latest.cashBalance + delta).clamp(0, double.infinity).toDouble();
    final shouldAdjustBaselineCost =
        first != null && !transactionDate.isAfter(first.snapshotDate);
    final nextLatestCostBasis =
        shouldAdjustBaselineCost && first.id == latest.id
            ? (latest.costBasis + delta).clamp(0, double.infinity).toDouble()
            : latest.costBasis;
    await (update(assetSnapshots)..where((tbl) => tbl.id.equals(latest.id)))
        .write(
      AssetSnapshotsCompanion(
        marketValue: Value(nextMarketValue),
        costBasis: Value(nextLatestCostBasis),
        cashBalance: Value(nextCashBalance),
        unrealizedPnl: Value(nextMarketValue - nextLatestCostBasis),
      ),
    );

    if (shouldAdjustBaselineCost && first.id != latest.id) {
      final nextFirstCostBasis =
          (first.costBasis + delta).clamp(0, double.infinity).toDouble();
      await (update(assetSnapshots)..where((tbl) => tbl.id.equals(first.id)))
          .write(
        AssetSnapshotsCompanion(
          costBasis: Value(nextFirstCostBasis),
          unrealizedPnl: Value(first.marketValue - nextFirstCostBasis),
        ),
      );
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'finance_app.sqlite'));
    await _createPreV7MigrationBackup(file, directory);
    return NativeDatabase.createInBackground(file);
  });
}

Future<void> _createPreV7MigrationBackup(
  File databaseFile,
  Directory documentsDirectory,
) async {
  if (!await databaseFile.exists()) return;

  sqlite.Database? source;
  try {
    source = sqlite.sqlite3.open(
      databaseFile.path,
      mode: sqlite.OpenMode.readOnly,
    );
    final version = source.userVersion;
    if (version <= 0 || version >= 7) return;

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final backupDirectory = Directory(
      p.join(
        documentsDirectory.path,
        'finance_compass_backups',
        'pre_v7_$timestamp',
      ),
    );
    await backupDirectory.create(recursive: true);

    const tableNames = [
      'accounts',
      'categories',
      'budgets',
      'transactions',
      'asset_snapshots',
      'app_meta',
    ];
    final tables = <String, List<Map<String, Object?>>>{};
    for (final tableName in tableNames) {
      final exists = source.select(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        [tableName],
      );
      if (exists.isEmpty) continue;
      tables[tableName] = source
          .select('SELECT * FROM $tableName')
          .map((row) => Map<String, Object?>.from(row))
          .toList();
    }
    final jsonBackup = File(p.join(backupDirectory.path, 'snapshot.json'));
    await jsonBackup.writeAsString(
      const JsonEncoder.withIndent(' ').convert({
        'backup_type': 'pre_schema_migration',
        'source_schema_version': version,
        'target_schema_version': 7,
        'exported_at': DateTime.now().toIso8601String(),
        'tables': tables,
      }),
      flush: true,
    );
    source.dispose();
    source = null;

    await databaseFile.copy(p.join(backupDirectory.path, 'finance_app.sqlite'));
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('${databaseFile.path}$suffix');
      if (await sidecar.exists()) {
        await sidecar.copy(
          p.join(backupDirectory.path, 'finance_app.sqlite$suffix'),
        );
      }
    }
  } catch (_) {
    // Never upgrade an existing v1-v6 database without a verified restore
    // point. Surfacing the error keeps the original file untouched.
    rethrow;
  } finally {
    source?.dispose();
  }
}
