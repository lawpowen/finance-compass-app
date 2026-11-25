import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/data_migration.dart';
import '../models/account.dart' as model;
import '../models/account_valuation.dart'
    show accountTransactionDelta, compareAssetSnapshots;
import '../models/asset_snapshot.dart' as model;
import '../models/budget.dart' as model;
import '../models/category.dart' as model;
import '../models/category_hierarchy.dart';
import '../models/transaction.dart' as model;
import '../models/transaction_preset.dart' as model;
import '../utils/anchored_month.dart';
import '../utils/id_generator.dart';
import 'enum_codec.dart';
import 'database_connection.dart';
import 'tables/accounts_table.dart';
import 'tables/asset_snapshots_table.dart';
import 'tables/app_meta_table.dart';
import 'tables/budgets_table.dart';
import 'tables/categories_table.dart';
import 'tables/transactions_table.dart';
import 'tables/transaction_templates_table.dart';
import 'tables/recurring_transaction_rules_table.dart';

part 'app_database.g.dart';
part 'investment_snapshot_upgrade.dart';
part 'loan_installment_storage.dart';

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
  AppDatabase() : super(openDatabaseConnection());

  AppDatabase.withExecutor(super.executor);

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) => super.transaction(() async {
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
          if (from < 8) {
            await m.addColumn(accounts, accounts.loanPrincipal);
            await m.addColumn(accounts, accounts.loanAnnualInterestRate);
            await m.addColumn(accounts, accounts.loanTermMonths);
            await m.addColumn(accounts, accounts.loanStartDate);
            await m.addColumn(accounts, accounts.loanPaymentDay);
            await m.addColumn(accounts, accounts.loanRepaymentMethod);
            await m.addColumn(accounts, accounts.loanQuotedMonthlyPayment);
          }
          if (from < 9) {
            await m.addColumn(accounts, accounts.loanTrackingStartDate);
          }
          // Drift normally sets user_version after beforeOpen. Commit it with
          // the DDL and data fixes so interrupted upgrades can safely reopen.
          await _prepareLedger(OpeningDetails(from, to));
          await customStatement('PRAGMA user_version = $to');
        }),
        beforeOpen: (details) async {
          if (!details.hadUpgrade) {
            await super.transaction(() => _prepareLedger(details));
          }
        },
      );

  Future<void> _prepareLedger(OpeningDetails details) async {
    await repairLegacyAccountReportGroups(this);
    await _migrateLegacyPresetMetadata(details);
    await _migrateCreditCardTransactionDates();
    await _ensureLocalProfileId();
    await _applyV2VisualDefault();
    final oldLoanFormat = await getMetaValue(_loanSemanticsKey) == null;
    await _migrateLegacyLoanLinks();
    if (oldLoanFormat) {
      final phaseTwo = await getMetaValue(_investmentSemanticsKey) ==
          _immutableInvestmentSemantics;
      await _repairLegacyZeroSameCurrencyTransfers(
          alreadyPosted: phaseTwo, forceScan: phaseTwo);
    }
    await _prepareInvestmentSnapshotSemantics();
    await _validateDatabaseIntegrity();
  }

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
            loanPrincipal: row.loanPrincipal,
            loanAnnualInterestRate: row.loanAnnualInterestRate,
            loanTermMonths: row.loanTermMonths,
            loanStartDate: row.loanStartDate,
            loanTrackingStartDate: row.loanTrackingStartDate,
            loanPaymentDay: row.loanPaymentDay,
            loanRepaymentMethod: row.loanRepaymentMethod == null
                ? null
                : enumByName(
                    model.LoanRepaymentMethod.values,
                    row.loanRepaymentMethod!,
                  ),
            loanQuotedMonthlyPayment: row.loanQuotedMonthlyPayment,
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
    final links = await _readLoanLinks(_loanTransactions);
    return (await select(transactions).get())
        .map((row) => _transactionModel(row, links[row.id]))
        .toList();
  }

  model.FinanceTransaction _transactionModel(Transaction row,
      [Map<String, dynamic>? link]) {
    return model.FinanceTransaction(
      id: row.id,
      loanInstallmentNumber: link?['loan_installment_number'] as int?,
      loanPaymentAmount: (link?['loan_payment_amount'] as num?)?.toDouble(),
      legacyLoanId: link?['legacy_loan_id'] as String?,
      legacyLoanPartNumber: link?['legacy_loan_part_number'] as int?,
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
      status: enumByName(model.TransactionStatus.values,
          row.status ?? model.TransactionStatus.actual.name),
      recurringRuleId: row.recurringRuleId,
      description: row.description,
      merchant: row.merchant,
    );
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
    final links = await _readLoanLinks(_loanTemplates);
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
            loanInstallmentNumber:
                links[row.id]?['loan_installment_number'] as int?,
            loanPaymentAmount:
                (links[row.id]?['loan_payment_amount'] as num?)?.toDouble(),
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
    final links = await _readLoanLinks(_loanRules);
    final rows = await (select(recurringTransactionRules)
          ..orderBy([(row) => OrderingTerm.asc(row.name)]))
        .get();
    return rows
        .map(
          (row) => model.RecurringTransactionRule(
            id: row.id,
            name: row.name,
            loanInstallmentNumber:
                links[row.id]?['loan_installment_number'] as int?,
            loanPaymentAmount:
                (links[row.id]?['loan_payment_amount'] as num?)?.toDouble(),
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
  ) =>
      _replaceTransactionTemplates(items, restoringLegacy: false);

  Future<void> _replaceTransactionTemplates(
      List<model.TransactionTemplate> items,
      {required bool restoringLegacy}) async {
    await super.transaction(() async {
      if (!restoringLegacy) {
        final previous = {
          for (final row in await select(transactionTemplates).get())
            row.id: row
        };
        await _requireActiveAccounts(items.expand((item) =>
            _newAccountReferences(item,
                originalSource: previous[item.id]?.accountId,
                originalTarget: previous[item.id]?.toAccountId)));
        for (final item in items) {
          final old = previous[item.id];
          await _validateCategoryChoice(
              item.categoryId, allowedCategoryTypes(item.type),
              originalCategoryId:
                  old?.type == item.type.name ? old?.categoryId : null);
        }
      }
      await _replaceLoanLinks(_loanTemplates, items);
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

  Future<void> linkTransactionToRecurringRule(
      String transactionId, String ruleId) async {
    final count = await (update(transactions)
          ..where((t) => t.id.equals(transactionId)))
        .write(TransactionsCompanion(recurringRuleId: Value(ruleId)));
    if (count != 1) throw StateError('找不到要关联的原交易。');
  }

  Future<void> replaceRecurringTransactionRules(
    List<model.RecurringTransactionRule> items,
  ) =>
      _replaceRecurringTransactionRules(items, restoringLegacy: false);

  Future<void> _replaceRecurringTransactionRules(
      List<model.RecurringTransactionRule> items,
      {required bool restoringLegacy}) async {
    await super.transaction(() async {
      if (!restoringLegacy) {
        final previous = {
          for (final row in await select(recurringTransactionRules).get())
            row.id: row
        };
        await _requireActiveAccounts(items.expand((item) =>
            _newAccountReferences(item,
                originalSource: previous[item.id]?.accountId,
                originalTarget: previous[item.id]?.toAccountId)));
        for (final item in items) {
          final old = previous[item.id];
          await _validateCategoryChoice(
              item.categoryId, allowedCategoryTypes(item.type),
              originalCategoryId:
                  old?.type == item.type.name ? old?.categoryId : null);
        }
      }
      await _replaceLoanLinks(_loanRules, items);
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

  static const presetTablesMarker = 'preset_tables_authoritative_v1';
  static const legacyTemplatesKey = 'transaction_templates_json';
  static const legacyRulesKey = 'recurring_transaction_rules_json';

  Future<void> _migrateLegacyPresetMetadata(OpeningDetails details) async {
    if (await getMetaValue(presetTablesMarker) == 'true') return;
    // Earlier releases created local_profile_id after their preset migration.
    // In a previously opened v7+ ledger an empty table may be an intentional
    // deletion. Keep ambiguous old bytes available for recovery, never replay them.
    final profile = await getMetaValue('local_profile_id');
    final firstMigration = (details.versionBefore ?? 0) < 7 ||
        profile == null ||
        profile.trim().isEmpty;
    Future<void> migrate(String key, bool empty,
        Future<void> Function(List<dynamic>) insert) async {
      final raw = await getMetaValue(key);
      if (raw == null) return;
      if (empty && raw.trim().isNotEmpty && raw.trim() != '[]') {
        if (firstMigration) {
          // A malformed legacy preference must not prevent access to the
          // rest of the ledger. Keep its original bytes for manual recovery.
          try {
            final decoded = jsonDecode(raw);
            if (decoded is! List) throw FormatException('旧预设数据格式无效：$key');
            final ids = <String>{};
            final accountIds = (await (selectOnly(accounts)
                  ..addColumns([accounts.id]))
                .map((row) => row.read(accounts.id)!)
                .get()).toSet();
            final categoryIds = (await (selectOnly(categories)
                  ..addColumns([categories.id]))
                .map((row) => row.read(categories.id)!)
                .get()).toSet();
            for (final row in decoded) {
              if (row is! Map) throw FormatException('旧预设条目无效：$key');
              final id = row['id'];
              if (id is! String || id.trim().isEmpty || !ids.add(id) ||
                  !accountIds.contains(row['account_id']) ||
                  (row['to_account_id'] != null && !accountIds.contains(row['to_account_id'])) ||
                  (row['category_id'] != null && !categoryIds.contains(row['category_id']))) {
                throw FormatException('旧预设 ID 或关联账户、类别无效：$key');
              }
            }
            await insert(decoded);
          } on FormatException {
            await setMetaValue('legacy_preset_recovery/$key', raw);
          } on TypeError {
            await setMetaValue('legacy_preset_recovery/$key', raw);
          } on ArgumentError {
            await setMetaValue('legacy_preset_recovery/$key', raw);
          }
        } else {
          await setMetaValue('legacy_preset_recovery/$key', raw);
        }
      }
      await deleteMetaValue(key);
    }

    await migrate(
        legacyTemplatesKey,
        (await (select(transactionTemplates)..limit(1)).get()).isEmpty,
        (rows) => _replaceTransactionTemplates(
            rows
                .map((row) => model.TransactionTemplate.fromJson(
                    Map<String, dynamic>.from(row as Map)))
                .toList(),
            restoringLegacy: true));
    await migrate(
        legacyRulesKey,
        (await (select(recurringTransactionRules)..limit(1)).get()).isEmpty,
        (rows) => _replaceRecurringTransactionRules(
            rows
                .map((row) => model.RecurringTransactionRule.fromJson(
                    Map<String, dynamic>.from(row as Map)))
                .toList(),
            restoringLegacy: true));
    await setMetaValue(presetTablesMarker, 'true');
  }

  Future<void> _ensureLocalProfileId() async {
    final existing = await getMetaValue('local_profile_id');
    if (existing != null && existing.trim().isNotEmpty) return;
    await setMetaValue(
      'local_profile_id',
      buildId('local'),
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
  }) =>
      transaction(() async {
        if (categoryItems.isNotEmpty) {
          CategoryHierarchy([...await fetchCategories(), ...categoryItems])
              .validate();
        }
        await _seedRows(
            accountItems: accountItems,
            categoryItems: categoryItems,
            budgetItems: budgetItems,
            transactionItems: transactionItems,
            snapshotItems: snapshotItems);
        await _saveSeedLoanLinks(transactionItems);
        await _rebuildInvestmentCaches(accountItems, snapshotItems);
      });

  Future<void> _seedRows({
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
                loanPrincipal: Value(item.loanPrincipal),
                loanAnnualInterestRate: Value(item.loanAnnualInterestRate),
                loanTermMonths: Value(item.loanTermMonths),
                loanStartDate: Value(item.loanStartDate),
                loanTrackingStartDate: Value(item.loanTrackingStartDate),
                loanPaymentDay: Value(item.loanPaymentDay),
                loanRepaymentMethod: Value(item.loanRepaymentMethod?.name),
                loanQuotedMonthlyPayment: Value(item.loanQuotedMonthlyPayment),
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
    CategoryHierarchy(categoryItems).validate();
    await super.transaction(() async {
      await delete(recurringTransactionRules).go();
      await delete(transactionTemplates).go();
      await delete(assetSnapshots).go();
      await delete(transactions).go();
      await delete(budgets).go();
      await delete(categories).go();
      await delete(accounts).go();
      await delete(appMeta).go();

      await _seedRows(
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
      // Preset sections, including explicit empty arrays, were resolved by the importer.
      await setMetaValue(presetTablesMarker, 'true');
      await deleteMetaValue(legacyTemplatesKey);
      await deleteMetaValue(legacyRulesKey);
      // Import parsing has already applied the source format's date semantics.
      // Mark the resulting snapshot so a later reopen does not reinterpret a
      // v3 user-edited occurrence date as a legacy settlement date.
      await setMetaValue('credit_card_account_billing_dates_v1', 'true');
      // Sample data is created using current semantics. Imported backups
      // supply a metadata map, even if their legacy format had no metadata.
      if (metaValues == null) {
        await setMetaValue(
            _investmentSemanticsKey, _immutableInvestmentSemantics);
      }
      await _replaceLoanLinks(_loanTransactions, transactionItems);
      await _replaceLoanLinks(_loanTemplates, templateItems);
      await _replaceLoanLinks(_loanRules, recurringRuleItems);
      if (metaValues == null) {
        await setMetaValue(_loanSemanticsKey, _explicitLoanSemantics);
      } else {
        await _migrateLegacyLoanLinks();
      }
      if (metaValues != null && metaValues[_loanSemanticsKey] == null) {
        await _repairLegacyZeroSameCurrencyTransfers(
            forceScan: true,
            alreadyPosted: metaValues[_investmentSemanticsKey] ==
                _immutableInvestmentSemantics);
      } else {
        await setMetaValue(_zeroSameCurrencyTransferRepairKey, 'true');
      }
      if (!await _prepareInvestmentSnapshotSemantics()) {
        await _rebuildInvestmentCaches(accountItems, snapshotItems);
      }
      await _validateDatabaseIntegrity();
    });
  }

  static const _zeroSameCurrencyTransferRepairKey =
      'zero_same_currency_transfer_amounts_v1';

  Future<void> _repairLegacyZeroSameCurrencyTransfers({
    bool forceScan = false,
    bool alreadyPosted = false,
  }) async {
    if (!forceScan &&
        await getMetaValue(_zeroSameCurrencyTransferRepairKey) == 'true') {
      return;
    }

    final loanLinks = await _readLoanLinks(_loanTransactions);
    final rows = await (select(transactions)
          ..where((tbl) =>
              tbl.type.equals(model.TransactionType.transfer.name) &
              tbl.toAccountId.isNotNull() &
              tbl.toAmount.equals(0)))
        .get();

    final evidence =
        alreadyPosted ? null : await _legacyZeroEvidence(rows, loanLinks);
    final loanIds = {
      for (final account in await fetchAccounts())
        if (account.accountType == model.AccountType.loan) account.id
    };
    for (final row in rows) {
      if (row.amount == 0) {
        continue;
      }
      final sourceCurrency = row.currency.trim().toUpperCase();
      final targetCurrency =
          (row.toCurrency ?? row.currency).trim().toUpperCase();
      if (sourceCurrency != targetCurrency) {
        continue;
      }
      if (loanLinks.containsKey(row.id)) continue;
      // Phase 2 left only the old loan-payment shape at zero; other ordinary
      // same-currency receipts already used the source amount in its cache.
      if (loanIds.contains(row.toAccountId) &&
          (!alreadyPosted ||
              RegExp(r'^贷款月供 #\d+$').hasMatch(row.description ?? ''))) {
        continue;
      }
      final actual = (row.status ?? 'actual') != 'planned';
      if (row.toAccountId == row.accountId && !alreadyPosted) continue;
      if (actual &&
          evidence != null &&
          !evidence.missing.contains(row.id) &&
          !evidence.credited.contains(row.id)) {
        continue;
      }

      await (update(transactions)..where((tbl) => tbl.id.equals(row.id))).write(
        TransactionsCompanion(
          toAmount: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
      final status = enumByName(
        model.TransactionStatus.values,
        row.status ?? model.TransactionStatus.actual.name,
      );
      if (status != model.TransactionStatus.planned &&
          !alreadyPosted &&
          evidence!.missing.contains(row.id)) {
        await _updateBalanceCaches({row.toAccountId!: row.amount});
      }
    }

    await setMetaValue(_zeroSameCurrencyTransferRepairKey, 'true');
  }

  /// An old zero receipt alone does not prove that the cached credit is missing.
  /// Require the expected opening-to-closing reconciliation on both accounts.
  Future<({Set<String> missing, Set<String> credited})> _legacyZeroEvidence(
      List<Transaction> candidates, _LoanLinks links) async {
    if (candidates.isEmpty) return (missing: <String>{}, credited: <String>{});
    final ledgerAccounts = {for (final a in await fetchAccounts()) a.id: a};
    final expected = {
      for (final a in ledgerAccounts.values) a.id: a.initialBalance
    };
    for (final tx in await fetchTransactions()) {
      for (final id in {
        tx.accountId,
        if (tx.toAccountId != null) tx.toAccountId!
      }) {
        final a = ledgerAccounts[id];
        if (a != null) {
          expected[id] = expected[id]! + accountTransactionDelta(id, tx);
        }
      }
    }
    final missing = <String, double>{};
    final sources = <String, Set<String>>{};
    final candidateIds = <String, Set<String>>{};
    final observed =
        (await fetchAssetSnapshots()).map((row) => row.accountId).toSet();
    for (final row in candidates) {
      final target = row.toAccountId!;
      final currency = row.currency.trim().toUpperCase();
      if (links.containsKey(row.id) ||
          row.status == 'planned' ||
          row.accountId == target ||
          row.amount == 0 ||
          ledgerAccounts[target]?.accountType == model.AccountType.loan ||
          ledgerAccounts[target]?.currency.trim().toUpperCase() != currency ||
          ledgerAccounts[row.accountId]?.currency.trim().toUpperCase() !=
              currency ||
          currency != (row.toCurrency ?? row.currency).trim().toUpperCase()) {
        continue;
      }
      expected[target] = expected[target]! + row.amount;
      missing[target] = (missing[target] ?? 0) + row.amount;
      (sources[target] ??= {}).add(row.accountId);
      (candidateIds[target] ??= {}).add(row.id);
    }
    bool reconciles(String id, double residual) =>
        !observed.contains(id) &&
        expected[id] != null &&
        _sameBalance(
            expected[id]! - residual, ledgerAccounts[id]!.currentBalance);
    final supported = {
      for (final target in missing.keys)
        if (sources[target]!.every(
            (id) => reconciles(id, 0) || reconciles(id, missing[id] ?? 0)))
          target
    };
    return (
      missing: {
        for (final id in supported)
          if (missing[id] != 0 && reconciles(id, missing[id]!))
            ...candidateIds[id]!
      },
      credited: {
        for (final id in supported)
          if (reconciles(id, 0)) ...candidateIds[id]!
      }
    );
  }

  bool _investmentGroup(String group) =>
      group == model.ReportGroup.investment.name ||
      group == model.ReportGroup.retirement.name;

  void _checkAccountGroup(model.Account account) {
    if (!model
        .allowedReportGroups(account.accountType)
        .contains(account.reportGroup)) {
      throw ArgumentError('账户类型与报表分组不匹配。');
    }
  }

  Future<void> insertAccount(model.Account account) {
    _checkAccountGroup(account);
    // A new investment's only value is its opening balance. Legacy API callers
    // sometimes pass this value as currentBalance with the default initial zero.
    final investment = _investmentGroup(account.reportGroup.name);
    final opening = investment && account.initialBalance == 0
        ? account.currentBalance
        : account.initialBalance;
    return into(accounts).insert(
      AccountsCompanion.insert(
        id: account.id,
        name: account.name,
        accountType: account.accountType.name,
        reportGroup: account.reportGroup.name,
        currency: account.currency,
        currentBalance: investment ? opening : account.currentBalance,
        initialBalance: Value(opening),
        institution: Value(account.institution),
        note: Value(account.note),
        isActive: Value(account.isActive),
        creditLimit: Value(account.creditLimit),
        statementDay: Value(account.statementDay),
        paymentDueDay: Value(account.paymentDueDay),
        loanPrincipal: Value(account.loanPrincipal),
        loanAnnualInterestRate: Value(account.loanAnnualInterestRate),
        loanTermMonths: Value(account.loanTermMonths),
        loanStartDate: Value(account.loanStartDate),
        loanTrackingStartDate: Value(account.loanTrackingStartDate),
        loanPaymentDay: Value(account.loanPaymentDay),
        loanRepaymentMethod: Value(account.loanRepaymentMethod?.name),
        loanQuotedMonthlyPayment: Value(account.loanQuotedMonthlyPayment),
      ),
    );
  }

  Future<void> setAccountActive(String accountId, bool active) async {
    final count = await (update(accounts)..where((a) => a.id.equals(accountId)))
        .write(AccountsCompanion(isActive: Value(active)));
    if (count != 1) throw const FormatException('账户已移除，请返回账户列表。');
  }

  Future<void> updateAccount(model.Account account,
          {bool preserveActivity = false}) =>
      super.transaction(() async {
        _checkAccountGroup(account);
        final existing = await (select(accounts)
              ..where((row) => row.id.equals(account.id)))
            .getSingle();
        final linked = await _hasEconomicRecords(account.id);
        if (linked && existing.currency != account.currency) {
          throw StateError('已有流水或快照的账户不能更改币种。');
        }
        if (linked && existing.accountType != account.accountType.name) {
          throw StateError('已有流水或快照的账户不能更改账户类型。');
        }
        if (linked && _effectiveGroup(existing) != account.reportGroup) {
          throw StateError('已有流水或快照的账户不能更改报表分组。');
        }
        final openingChange = account.initialBalance - existing.initialBalance;
        final loan = existing.accountType == model.AccountType.loan.name;
        if (linked && !loan && openingChange != 0) {
          throw StateError('已有流水或快照的账户请通过调整交易更正余额。');
        }
        // A loan opening correction preserves the principal already repaid.
        final expectedBalance =
            existing.currentBalance + (loan ? openingChange : 0);
        if (linked &&
            (!account.currentBalance.isFinite ||
                (account.currentBalance - expectedBalance).abs() > 0.0000001)) {
          throw StateError('账户余额已由流水或快照确定，请重新加载或记录调整交易。');
        }
        final newBalance = linked
            ? expectedBalance
            : _investmentGroup(account.reportGroup.name)
                ? account.initialBalance
                : account.currentBalance;
        await (update(accounts)..where((tbl) => tbl.id.equals(account.id)))
            .write(
          AccountsCompanion(
            name: Value(account.name),
            accountType: Value(account.accountType.name),
            reportGroup: Value(account.reportGroup.name),
            currency: Value(account.currency),
            initialBalance: Value(account.initialBalance),
            currentBalance: Value(newBalance),
            institution: Value(account.institution),
            note: Value(account.note),
            isActive: preserveActivity
                ? const Value.absent()
                : Value(account.isActive),
            creditLimit: Value(account.creditLimit),
            statementDay: Value(account.statementDay),
            paymentDueDay: Value(account.paymentDueDay),
            loanPrincipal: Value(account.loanPrincipal),
            loanAnnualInterestRate: Value(account.loanAnnualInterestRate),
            loanTermMonths: Value(account.loanTermMonths),
            loanStartDate: Value(account.loanStartDate),
            loanTrackingStartDate: Value(account.loanTrackingStartDate),
            loanPaymentDay: Value(account.loanPaymentDay),
            loanRepaymentMethod: Value(account.loanRepaymentMethod?.name),
            loanQuotedMonthlyPayment: Value(account.loanQuotedMonthlyPayment),
          ),
        );
      });

  Future<bool> _hasEconomicRecords(String accountId) async {
    final entry = await (select(transactions)
          ..where((tbl) =>
              tbl.accountId.equals(accountId) |
              tbl.toAccountId.equals(accountId))
          ..limit(1))
        .getSingleOrNull();
    return entry != null || await _latestBalanceAnchor(accountId) != null;
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
    return super.transaction(() async {
      await _validateCategoryParent(category);
      await into(categories).insert(
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
    });
  }

  Future<void> updateCategory(model.Category category) {
    return super.transaction(() async {
      final existing = await (select(categories)
            ..where((c) => c.id.equals(category.id)))
          .getSingleOrNull();
      if (existing == null) throw ArgumentError('此类别已删除，请刷新后重试。');
      if (existing.type != category.type.name &&
          await categoryHasLinkedData(category.id)) {
        throw ArgumentError('此类别已有关联记录或子类别，不能更改类型。');
      }
      await _validateCategoryParent(category);
      await (update(categories)..where((tbl) => tbl.id.equals(category.id)))
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
    });
  }

  Future<void> _validateCategoryParent(model.Category category) async {
    final parentId = category.parentId;
    if (parentId == null) return;
    final rows = await (selectOnly(categories)
          ..addColumns([categories.id, categories.parentId, categories.type]))
        .get();
    final parents = {
      for (final row in rows)
        row.read(categories.id)!: row.read(categories.parentId),
    };
    if (!rows.any((row) =>
        row.read(categories.id) == parentId &&
        row.read(categories.type) == category.type.name)) {
      throw ArgumentError('父类别不存在或与当前类别类型不同。');
    }
    if (categoryParentWouldCycle(category.id, parentId, parents)) {
      throw ArgumentError('不能将自身或后代设为父类别。');
    }
  }

  Iterable<String> _newAccountReferences(model.LoanInstallmentFields entry,
      {String? originalSource, String? originalTarget}) sync* {
    if (entry.accountId != originalSource) yield entry.accountId;
    final target = entry.toAccountId;
    if (entry.type == model.TransactionType.transfer &&
        target != null &&
        target != originalTarget) {
      yield target;
    }
  }

  Future<void> _requireActiveAccounts(Iterable<String> changed) async {
    final ids = changed.toSet();
    if (ids.isEmpty) return;
    final enabled = await (selectOnly(accounts)
          ..addColumns([accounts.id])
          ..where(accounts.id.isIn(ids) & accounts.isActive.equals(true)))
        .get();
    if (enabled.length != ids.length) {
      throw const FormatException('所选账户已停用或移除，请选择启用的账户。');
    }
  }

  Future<void> _validateCategoryChoice(
      String? id, Set<model.CategoryType> allowedTypes,
      {String? originalCategoryId}) async {
    if (id == null || id == originalCategoryId) return;
    final row = await (select(categories)..where((c) => c.id.equals(id)))
        .getSingleOrNull();
    if (row == null ||
        row.isArchived ||
        !allowedTypes.any((t) => t.name == row.type)) {
      throw ArgumentError('请选择当前类型下未归档的有效类别。');
    }
  }

  Future<bool> categoryHasLinkedData(String categoryId) async {
    final child = await (select(categories)
          ..where((tbl) => tbl.parentId.equals(categoryId))
          ..limit(1))
        .getSingleOrNull();
    if (child != null) return true;

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

  Future<bool> deleteCategoryIfSafe(String categoryId) {
    return super.transaction(() async {
      if (await categoryHasLinkedData(categoryId)) return false;
      await (delete(categories)..where((tbl) => tbl.id.equals(categoryId)))
          .go();
      return true;
    });
  }

  Future<void> upsertBudget(model.Budget budget) async {
    await super.transaction(() async {
      final existing = await (select(budgets)
            ..where((tbl) => tbl.id.equals(budget.id)))
          .getSingleOrNull();

      await _validateCategoryChoice(
          budget.categoryId, const {model.CategoryType.expense},
          originalCategoryId: existing?.monthKey == budget.monthKey
              ? existing?.categoryId
              : null);
      if (existing == null) {
        final sameMonthRules = await (select(budgets)
              ..where((tbl) =>
                  tbl.categoryId.equals(budget.categoryId) &
                  tbl.monthKey.equals(budget.monthKey)))
            .get();

        if (sameMonthRules.isNotEmpty) {
          final target = sameMonthRules.first;
          await (update(budgets)..where((tbl) => tbl.id.equals(target.id)))
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
          if (sameMonthRules.length > 1) {
            final extraIds =
                sameMonthRules.skip(1).map((row) => row.id).toList();
            await (delete(budgets)..where((tbl) => tbl.id.isIn(extraIds))).go();
          }
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
    });
  }

  Future<void> deleteBudget(String budgetId) {
    return (delete(budgets)..where((tbl) => tbl.id.equals(budgetId))).go();
  }

  Future<void> insertTransaction(model.FinanceTransaction entry) =>
      insertTransactions([entry]);

  Future<void> insertTransactions(List<model.FinanceTransaction> entries) =>
      replaceTransactions(deleteIds: const [], insertItems: entries);

  TransactionsCompanion _transactionCompanion(model.FinanceTransaction entry) {
    return TransactionsCompanion.insert(
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
    );
  }

  Future<model.FinanceTransaction> _liveTransaction(
      model.FinanceTransaction entry,
      {model.FinanceTransaction? previous}) async {
    await _validateCategoryChoice(
        entry.categoryId, allowedCategoryTypes(entry.type),
        originalCategoryId:
            previous?.type == entry.type ? previous?.categoryId : null);
    if (previous?.loanInstallmentNumber != null &&
        entry.loanInstallmentNumber == null &&
        entry.type == model.TransactionType.transfer &&
        entry.toAccountId == previous!.toAccountId) {
      throw const FormatException('编辑已关联的月供须保留贷款期号。');
    }
    if (entry.type != model.TransactionType.transfer ||
        entry.toAmount != 0 ||
        entry.amount == 0 ||
        entry.toAccountId == null ||
        entry.loanFields.isNotEmpty ||
        entry.currency.trim().toUpperCase() !=
            entry.transferInCurrency.trim().toUpperCase() ||
        (previous?.toAmount == 0 &&
            previous?.toAccountId == entry.toAccountId)) {
      return entry;
    }
    final target = await (select(accounts)
          ..where((a) => a.id.equals(entry.toAccountId!)))
        .getSingle();
    return target.accountType == 'loan'
        ? entry
        : entry.canonicalOrdinaryTransfer();
  }

  Future<void> _rememberRecurringMonth(Transaction row) async {
    final ruleId = row.recurringRuleId;
    if (ruleId == null) return;
    final key = occurrenceKey(ruleId, row.id);
    if (await getMetaValue(key) == null) {
      await setMetaValue(key,
          nominalOccurrenceMonth(ruleId, row.id, row.transactionDate, null));
    }
  }

  Future<void> updateTransaction(model.FinanceTransaction entry) =>
      super.transaction(() async {
        final row = await (select(transactions)
              ..where((t) => t.id.equals(entry.id)))
            .getSingle();
        await _rememberRecurringMonth(row);
        final changes = <String, double>{};
        final links = await _readLoanLinks(_loanTransactions);
        final previous = _transactionModel(row, links[row.id]);
        await _requireActiveAccounts(_newAccountReferences(entry,
            originalSource: previous.accountId,
            originalTarget: previous.toAccountId));
        entry = await _liveTransaction(entry, previous: previous);
        _collectBalanceChanges(changes, previous, reversing: true);
        await (update(transactions)..where((t) => t.id.equals(entry.id)))
            .write(_transactionCompanion(entry));
        _collectBalanceChanges(changes, entry);
        await _patchLoanLinks(_loanTransactions, links, [entry], [entry.id]);
        await _updateBalanceCaches(changes);
      });

  Future<void> deleteTransaction(String transactionId) =>
      deleteTransactionsByIds([transactionId]);

  Future<void> deleteTransactionsByIds(Iterable<String> transactionIds) =>
      replaceTransactions(deleteIds: transactionIds, insertItems: const []);

  /// The selected rows, both sides of their transfers and all replacements
  /// become visible together. Refresh each affected account only once.
  Future<void> replaceTransactions({
    required Iterable<String> deleteIds,
    required List<model.FinanceTransaction> insertItems,
  }) async {
    final ids = deleteIds.toSet();
    if (ids.isEmpty && insertItems.isEmpty) return;
    await super.transaction(() async {
      final changes = <String, double>{};
      final previousById = <String, model.FinanceTransaction>{};
      final links = await _readLoanLinks(_loanTransactions);
      if (ids.isNotEmpty) {
        final existing =
            await (select(transactions)..where((t) => t.id.isIn(ids))).get();
        if (existing.length != ids.length) {
          throw StateError(
              'One or more selected transactions no longer exist.');
        }
        for (final row in existing) {
          await _rememberRecurringMonth(row);
          final previous = _transactionModel(row, links[row.id]);
          previousById[row.id] = previous;
          _collectBalanceChanges(changes, previous, reversing: true);
        }
        await (delete(transactions)..where((t) => t.id.isIn(ids))).go();
      }
      await _requireActiveAccounts(insertItems.expand((item) =>
          _newAccountReferences(item,
              originalSource: previousById[item.id]?.accountId,
              originalTarget: previousById[item.id]?.toAccountId)));
      for (final item in insertItems) {
        final entry =
            await _liveTransaction(item, previous: previousById[item.id]);
        await into(transactions).insert(_transactionCompanion(entry));
        _collectBalanceChanges(changes, entry);
      }
      await _patchLoanLinks(_loanTransactions, links, insertItems, ids);
      await _updateBalanceCaches(changes);
    });
  }

  void _collectBalanceChanges(
      Map<String, double> changes, model.FinanceTransaction entry,
      {bool reversing = false}) {
    if (!entry.affectsBalance) return;
    final affected = {
      entry.accountId,
      if (entry.type == model.TransactionType.transfer &&
          entry.toAccountId != null)
        entry.toAccountId!,
    };
    for (final id in affected) {
      final delta = accountTransactionDelta(id, entry);
      changes[id] = (changes[id] ?? 0) + (reversing ? -delta : delta);
    }
  }

  AssetSnapshotsCompanion _snapshotCompanion(model.AssetSnapshot snapshot) {
    return AssetSnapshotsCompanion.insert(
      id: snapshot.id,
      accountId: snapshot.accountId,
      snapshotDate: snapshot.snapshotDate,
      marketValue: snapshot.marketValue,
      costBasis: Value(snapshot.costBasis),
      cashBalance: Value(snapshot.cashBalance),
      unrealizedPnl: Value(snapshot.unrealizedPnl),
    );
  }

  Future<void> insertAssetSnapshot(model.AssetSnapshot snapshot) =>
      super.transaction(() async {
        await into(assetSnapshots).insert(_snapshotCompanion(snapshot));
        await _rebuildSnapshotAccount(snapshot.accountId);
      });

  Future<void> updateAssetSnapshot(model.AssetSnapshot snapshot) =>
      super.transaction(() async {
        final row = await (select(assetSnapshots)
              ..where((t) => t.id.equals(snapshot.id)))
            .getSingleOrNull();
        if (row == null) return;
        if (row.accountId != snapshot.accountId) {
          throw ArgumentError.value(snapshot.accountId, 'snapshot.accountId',
              '资产快照不能改换账户，请删除后在目标账户重新录入。');
        }
        await (update(assetSnapshots)..where((t) => t.id.equals(snapshot.id)))
            .write(_snapshotCompanion(snapshot));
        await _rebuildSnapshotAccount(row.accountId);
      });

  Future<void> deleteAssetSnapshot(String snapshotId) =>
      super.transaction(() async {
        final row = await (select(assetSnapshots)
              ..where((t) => t.id.equals(snapshotId)))
            .getSingleOrNull();
        if (row == null) return;
        await (delete(assetSnapshots)..where((t) => t.id.equals(snapshotId)))
            .go();
        await _rebuildSnapshotAccount(row.accountId);
      });

  Future<AssetSnapshot?> _latestBalanceAnchor(String accountId) =>
      (select(assetSnapshots)
            ..where((t) => t.accountId.equals(accountId))
            ..orderBy([
              (t) => OrderingTerm.desc(t.snapshotDate),
              (t) => OrderingTerm.desc(t.id)
            ])
            ..limit(1))
          .getSingleOrNull();

  model.ReportGroup _effectiveGroup(Account account) =>
      model.effectiveReportGroupFor(
          enumByName(model.AccountType.values, account.accountType),
          enumByName(model.ReportGroup.values, account.reportGroup));

  Future<void> _updateBalanceCaches(Map<String, double> changes) async {
    for (final change in changes.entries) {
      final account = await (select(accounts)
            ..where((t) => t.id.equals(change.key)))
          .getSingle();
      final anchor = await _latestBalanceAnchor(account.id);
      if (anchor != null || _investmentGroup(_effectiveGroup(account).name)) {
        await _replayBalance(account, anchor);
      } else {
        // Ordinary legacy accounts may have a reconciled balance offset.
        // Preserve it while applying the net movement of this operation.
        await _writeCurrentBalance(
            account.id, account.currentBalance + change.value);
      }
    }
  }

  Future<void> _rebuildSnapshotAccount(String id) async {
    final account =
        await (select(accounts)..where((t) => t.id.equals(id))).getSingle();
    await _replayBalance(account, await _latestBalanceAnchor(id));
  }

  Future<void> _replayBalance(Account account, AssetSnapshot? anchor) async {
    final query = select(transactions)
      ..where((t) =>
          t.accountId.equals(account.id) | t.toAccountId.equals(account.id))
      ..orderBy([
        (t) => OrderingTerm.asc(t.transactionDate),
        (t) => OrderingTerm.asc(t.id)
      ]);
    if (anchor != null) {
      query.where(
          (t) => t.transactionDate.isBiggerThanValue(anchor.snapshotDate));
    }
    final links = await _readLoanLinks(_loanTransactions);
    var balance = anchor?.marketValue ?? account.initialBalance;
    for (final row in await query.get()) {
      balance += accountTransactionDelta(
          account.id, _transactionModel(row, links[row.id]));
    }
    await _writeCurrentBalance(account.id, balance);
  }

  Future<void> _writeCurrentBalance(String accountId, double balance) {
    return (update(accounts)..where((tbl) => tbl.id.equals(accountId))).write(
      AccountsCompanion(currentBalance: Value(balance)),
    );
  }

  Future<void> clearAllUserData() async {
    await super.transaction(() async {
      // Account-specific reconciliation, goals, FX, notifications and preset
      // ownership belong to the cleared ledger; the device appearance and local
      // profile still apply. Keep completed representation markers for new rows.
      await (delete(appMeta)
            ..where((m) => m.key.isNotIn(const [
                  'local_profile_id',
                  'theme_style',
                  'ui_redesign_v2_applied',
                  'account_report_groups_v1',
                  presetTablesMarker,
                  _loanSemanticsKey,
                  _investmentSemanticsKey,
                  _zeroSameCurrencyTransferRepairKey,
                  'credit_card_account_billing_dates_v1',
                ])))
          .go();
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
}
