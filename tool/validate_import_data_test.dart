import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/utils/month_key.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('imports and validates a supplied Finance Compass JSON snapshot',
      () async {
    const inputPath = String.fromEnvironment('INPUT_JSON');
    const outputPath = String.fromEnvironment('OUTPUT_JSON');
    if (inputPath.isEmpty) {
      markTestSkipped('Pass --dart-define=INPUT_JSON=<snapshot.json>.');
      return;
    }

    final input = File(inputPath);
    expect(await input.exists(), isTrue, reason: 'Input JSON does not exist.');
    final raw = jsonDecode(await input.readAsString()) as Map<String, dynamic>;
    final rawTransactions =
        (raw['transactions'] as List? ?? const []).cast<Map<String, dynamic>>();
    final repairIds = rawTransactions
        .where((item) {
          final sourceCurrency =
              (item['currency'] as String? ?? '').trim().toUpperCase();
          final targetCurrency = (item['to_currency'] as String? ??
                  item['currency'] as String? ??
                  '')
              .trim()
              .toUpperCase();
          return item['type'] == 'transfer' &&
              item['to_account_id'] != null &&
              (item['amount'] as num? ?? 0) != 0 &&
              (item['to_amount'] as num?) == 0 &&
              sourceCurrency == targetCurrency;
        })
        .map((item) => item['id'] as String)
        .toSet();

    final tempDirectory =
        await Directory.systemTemp.createTemp('finance_import_validation');
    const pathProviderChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDirectory.path;
      }
      return null;
    });

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    try {
      var repository = await FinanceRepository.load(database);
      repository = await repository.importJsonSnapshot(input.path);

      expect(repository.accounts, isNotEmpty);
      expect(repository.transactions, isNotEmpty);
      for (final transaction in repository.transactions
          .where((transaction) => repairIds.contains(transaction.id))) {
        expect(transaction.toAmount, isNull);
        expect(transaction.transferInAmount, transaction.amount);
      }

      final now = DateTime.now();
      final currentMonth = monthKeyFromDate(now);
      final nextMonth = monthKeyFromDate(DateTime(now.year, now.month + 1));
      final currentCash =
          repository.actualCashFlowSummaryForMonth(currentMonth);
      final nextCash = repository.actualCashFlowSummaryForMonth(
        nextMonth,
        includePlanned: true,
      );
      final nextFunding = repository.monthlyFundingNeedForMonth(
        nextMonth,
        includePlanned: true,
      );
      final activeNextBudgets = repository.activeBudgetsForMonth(nextMonth);
      expect(
        activeNextBudgets.map((budget) => budget.categoryId).toSet().length,
        activeNextBudgets.length,
        reason: 'Only the latest effective budget may be active per category.',
      );
      expect(repository.assetGoalSummaries(),
          hasLength(repository.assetGoals.length));

      if (outputPath.isNotEmpty) {
        final output = File(outputPath).absolute;
        await output.parent.create(recursive: true);
        await output.writeAsBytes(
          await repository.exportJsonSnapshotBytes(),
          flush: true,
        );
        expect(await output.length(), greaterThan(0));
      }

      // ignore: avoid_print
      print(
        'Validated ${repository.accounts.length} accounts, '
        '${repository.categories.length} categories, '
        '${repository.budgets.length} budgets, '
        '${repository.transactions.length} transactions; '
        '${repository.assetGoals.length} asset goals; '
        '$currentMonth cash in/out '
        '${currentCash.inflow.toStringAsFixed(2)}/'
        '${currentCash.outflow.toStringAsFixed(2)}; '
        '$nextMonth planned cash in/out '
        '${nextCash.inflow.toStringAsFixed(2)}/'
        '${nextCash.outflow.toStringAsFixed(2)}; '
        'funding need ${nextFunding.totalCashRequired.toStringAsFixed(2)} '
        '(credit ${nextFunding.creditDue.toStringAsFixed(2)}, '
        'loan ${nextFunding.loanDue.toStringAsFixed(2)}, '
        'uncovered ${nextFunding.uncoveredDebtDue.toStringAsFixed(2)}); '
        'repaired ${repairIds.length} legacy same-currency transfers'
        '${outputPath.isEmpty ? '.' : '; wrote $outputPath.'}',
      );
    } finally {
      await database.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
      await tempDirectory.delete(recursive: true);
    }
  });
}
