import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/finance_repository.dart';
import '../../models/transaction.dart';
import '../repository_provider.dart';

/// Transaction CRUD operations.
///
/// All methods read the current [FinanceRepository], mutate via the
/// repository, and push the refreshed instance back into
/// [financeRepositoryProvider] so consumers rebuild.
class TransactionMutations extends Notifier<void> {
  @override
  void build() {}

  FinanceRepositoryNotifier get _repoNotifier =>
      ref.read(financeRepositoryProvider.notifier);

  Future<FinanceRepository> get _repo =>
      ref.read(financeRepositoryProvider.future);

  /// Creates a single transaction.
  Future<void> addTransaction(FinanceTransaction transaction) async {
    final updated = await (await _repo).addTransaction(transaction);
    _repoNotifier.setRepository(updated);
  }

  /// Creates multiple transactions in a single batch.
  Future<void> addTransactions(List<FinanceTransaction> transactions) async {
    final updated = await (await _repo).addTransactions(transactions);
    _repoNotifier.setRepository(updated);
  }

  /// Updates an existing transaction (reverses old balance effects, applies new).
  Future<void> updateTransaction(FinanceTransaction transaction) async {
    final updated = await (await _repo).updateExistingTransaction(transaction);
    _repoNotifier.setRepository(updated);
  }

  /// Deletes a transaction and reverses its balance effects.
  Future<void> deleteTransaction(String transactionId) async {
    final repository = await _repo;
    final ids = _expandLoanInstallmentDeletionIds(
      repository,
      [transactionId],
    );
    final updated = await repository.deleteExistingTransactions(ids);
    _repoNotifier.setRepository(updated);
  }

  /// Deletes multiple transactions atomically and reverses every balance effect.
  Future<void> deleteTransactions(Iterable<String> transactionIds) async {
    final repository = await _repo;
    final ids = _expandLoanInstallmentDeletionIds(
      repository,
      transactionIds,
    );
    final updated = await repository.deleteExistingTransactions(ids);
    _repoNotifier.setRepository(updated);
  }

  Set<String> _expandLoanInstallmentDeletionIds(
    FinanceRepository repository,
    Iterable<String> requestedIds,
  ) {
    final result = requestedIds.toSet();
    final byId = {
      for (final transaction in repository.transactions)
        transaction.id: transaction,
    };
    final installmentPattern = RegExp(r'^贷款(月供|本金|利息) #(\d+)$');
    for (final id in result.toList()) {
      final selected = byId[id];
      if (selected == null) continue;
      final match = installmentPattern.firstMatch(selected.description ?? '');
      if (match == null || match.group(1) == '月供') continue;
      final number = match.group(2)!;
      final candidates = repository.transactions.where((item) {
        if (item.id == selected.id ||
            item.accountId != selected.accountId ||
            item.status != selected.status ||
            !_sameDay(item.transactionDate, selected.transactionDate)) {
          return false;
        }
        final candidate = installmentPattern.firstMatch(item.description ?? '');
        return candidate != null &&
            candidate.group(2) == number &&
            candidate.group(1) != '月供';
      }).toList();
      final selectedPart = match.group(1)!;
      final complementary = candidates.where((item) {
        final part =
            installmentPattern.firstMatch(item.description ?? '')!.group(1)!;
        return part != selectedPart;
      }).toList();
      if (complementary.length == 1) {
        result.add(complementary.single.id);
      }
    }
    return result;
  }

  bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  /// Saves a transaction as a reusable template.
  Future<void> addTransactionTemplate({
    required String name,
    required FinanceTransaction transaction,
  }) async {
    final updated = await (await _repo).addTransactionTemplate(
      name: name,
      transaction: transaction,
    );
    _repoNotifier.setRepository(updated);
  }

  /// Deletes a transaction template by id.
  Future<void> deleteTransactionTemplate(String templateId) async {
    final updated = await (await _repo).deleteTransactionTemplate(templateId);
    _repoNotifier.setRepository(updated);
  }

  /// Replaces an existing template while preserving its identifier.
  Future<void> saveTransactionTemplate(TransactionTemplate template) async {
    final updated = await (await _repo).saveTransactionTemplate(template);
    _repoNotifier.setRepository(updated);
  }

  /// Persists the complete quick-template order in one atomic replacement.
  Future<void> reorderTransactionTemplates(
      List<String> orderedTemplateIds) async {
    final updated =
        await (await _repo).reorderTransactionTemplates(orderedTemplateIds);
    _repoNotifier.setRepository(updated);
  }

  /// Creates a recurring transaction rule.
  Future<void> addRecurringTransactionRule({
    required String name,
    required FinanceTransaction transaction,
    required int intervalMonths,
  }) async {
    final updated = await (await _repo).addRecurringTransactionRule(
      name: name,
      transaction: transaction,
      intervalMonths: intervalMonths,
    );
    _repoNotifier.setRepository(updated);
  }

  /// Deletes a recurring transaction rule.
  Future<void> deleteRecurringTransactionRule(String ruleId) async {
    final updated = await (await _repo).deleteRecurringTransactionRule(ruleId);
    _repoNotifier.setRepository(updated);
  }

  /// Replaces an existing recurring rule while preserving generated history.
  Future<void> saveRecurringTransactionRule(
    RecurringTransactionRule rule,
  ) async {
    final updated = await (await _repo).saveRecurringTransactionRule(rule);
    _repoNotifier.setRepository(updated);
  }

  /// Generates future transactions from a recurring rule.
  Future<void> generateRecurringTransactions(
    String ruleId, {
    required int monthsAhead,
  }) async {
    final updated = await (await _repo)
        .generateRecurringTransactions(ruleId, monthsAhead: monthsAhead);
    _repoNotifier.setRepository(updated);
  }
}

/// Provider for transaction CRUD mutations.
final transactionMutationsProvider =
    NotifierProvider<TransactionMutations, void>(TransactionMutations.new);
