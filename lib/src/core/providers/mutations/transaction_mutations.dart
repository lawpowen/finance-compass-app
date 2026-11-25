import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/finance_repository.dart';
import '../../models/account.dart';
import '../../models/credit_card_billing.dart' show creditCardSourceBillingDate;
import '../../models/loan_amortization.dart';
import '../../models/loan_settlement.dart';
import '../../models/transaction.dart';
import '../../utils/id_generator.dart';
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

  /// Creates a single transaction.
  Future<void> addTransaction(FinanceTransaction transaction) async {
    await _repoNotifier
        .mutate((repository) => repository.addTransaction(transaction));
  }

  /// Creates multiple transactions in a single batch.
  Future<void> addTransactions(List<FinanceTransaction> transactions) async {
    await _repoNotifier
        .mutate((repository) => repository.addTransactions(transactions));
  }

  /// Updates an existing transaction (reverses old balance effects, applies new).
  Future<void> updateTransaction(FinanceTransaction transaction) async {
    await _repoNotifier.mutate(
        (repository) => repository.updateExistingTransaction(transaction));
  }

  /// Deletes a transaction and reverses its balance effects.
  Future<void> deleteTransaction(String transactionId) async {
    await _repoNotifier.mutate((repository) {
      final ids =
          _expandLoanInstallmentDeletionIds(repository, [transactionId]);
      return repository.deleteExistingTransactions(ids);
    });
  }

  /// Deletes multiple transactions atomically and reverses every balance effect.
  Future<void> deleteTransactions(Iterable<String> transactionIds) async {
    await _repoNotifier.mutate((repository) {
      final ids = _expandLoanInstallmentDeletionIds(repository, transactionIds);
      return repository.deleteExistingTransactions(ids);
    });
  }

  /// Atomically replaces [deleteIds] with [insertItems] in one transaction.
  Future<void> replaceTransactions({
    required Iterable<String> deleteIds,
    required List<FinanceTransaction> insertItems,
  }) async {
    await _repoNotifier.mutate(
      (repository) => repository.replaceExistingTransactions(
        deleteIds: deleteIds,
        insertItems: insertItems,
      ),
    );
  }

  /// Recheck the amount displayed in the confirmation inside the write transaction.
  Future<bool> recordLoanInstallment({
    required String loanId,
    required String payerId,
    required LoanInstallment confirmed,
  }) async {
    final result = await _repoNotifier
        .mutate((current) => current.database.transaction(() async {
              final ledger = await current.refresh();
              final loan =
                  ledger.accounts.where((a) => a.id == loanId).firstOrNull;
              final payer = ledger
                  .repaymentSources(loanId)
                  .where((a) => a.id == payerId)
                  .firstOrNull;
              if (loan == null || payer == null) return null;
              final schedule = tryCalculateLoanScheduleForAccount(loan);
              final due = schedule?.installments
                  .where((i) => i.number == confirmed.number)
                  .firstOrNull;
              if (due == null || due.dueDate != confirmed.dueDate) return null;
              final now = DateTime.now();
              final cutoff =
                  DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
              final occurred = LoanSettlement.forLoan(
                  loanId: loanId,
                  currency: loan.currency,
                  transactions: ledger.transactions,
                  cutoff: cutoff);
              final booked = LoanSettlement.forLoan(
                  loanId: loanId,
                  currency: loan.currency,
                  transactions: ledger.transactions);
              final remaining =
                  installmentAvailableToRecord(due, occurred, booked);
              if (remaining.payment == 0 ||
                  remaining.principal != confirmed.principal ||
                  remaining.interest != confirmed.interest) {
                return null;
              }
              final planIds = ledger.transactions
                  .where((tx) =>
                      tx.status == TransactionStatus.planned &&
                      ((tx.toAccountId == loanId &&
                              tx.loanInstallmentNumber == due.number) ||
                          (tx.legacyLoanId == loanId &&
                              tx.legacyLoanPartNumber == due.number)))
                  .map((tx) => tx.id);
              return ledger.replaceExistingTransactions(
                deleteIds: planIds,
                insertItems: [
                  _loanPayment(loan, payer, remaining,
                      date: now, status: TransactionStatus.actual)
                ],
              );
            }));
    return result != null;
  }

  Future<int> generateLoanInstallmentPlans({
    required String loanId,
    required String payerId,
    required List<LoanInstallment> confirmed,
  }) async {
    var count = 0;
    await _repoNotifier.mutate((current) =>
        current.database.transaction(() async {
          final ledger = await current.refresh();
          final loan = ledger.accounts.where((a) => a.id == loanId).firstOrNull;
          final payer = ledger
              .repaymentSources(loanId)
              .where((a) => a.id == payerId)
              .firstOrNull;
          if (loan == null || payer == null) return null;
          final schedule = tryCalculateLoanScheduleForAccount(loan);
          if (schedule == null) return null;
          final pending = unplannedLoanInstallments(
              loanId: loan.id,
              currency: loan.currency,
              transactions: ledger.transactions,
              schedule: schedule);
          final accepted = {for (final entry in confirmed) entry.number: entry};
          final rows = <FinanceTransaction>[];
          for (final item in pending) {
            final quote = accepted[item.number];
            if (quote == null ||
                quote.dueDate != item.dueDate ||
                quote.principal != item.principal ||
                quote.interest != item.interest) {
              continue;
            }
            rows.add(_loanPayment(loan, payer, item,
                date: item.dueDate, status: TransactionStatus.planned));
          }
          if (rows.isEmpty) return null;
          count = rows.length;
          return ledger.addTransactions(rows);
        }));
    return count;
  }

  Future<void> consolidateLegacyLoanPlans(String loanId) async {
    await _repoNotifier.mutate((current) =>
        current.database.transaction(() async {
          final ledger = await current.refresh();
          final parts = ledger.transactions
              .where((tx) =>
                  tx.legacyLoanId == loanId &&
                  tx.legacyLoanPartNumber != null &&
                  tx.status == TransactionStatus.planned)
              .toList();
          final insertItems = <FinanceTransaction>[];
          final deleteIds = <String>[];
          for (final principal
              in parts.where((tx) => tx.type == TransactionType.transfer)) {
            final companions = parts
                .where((tx) =>
                    tx.accountId == principal.accountId &&
                    tx.legacyLoanPartNumber == principal.legacyLoanPartNumber &&
                    tx.currency == principal.currency &&
                    _sameDay(tx.transactionDate, principal.transactionDate))
                .toList();
            if (companions.length != 2) continue;
            final interest = companions
                .where((tx) => tx.type == TransactionType.expense)
                .firstOrNull;
            if (interest == null) continue;
            // A merged entry can represent only one source-card statement day.
            if (creditCardSourceBillingDate(principal, principal.accountId) !=
                creditCardSourceBillingDate(interest, interest.accountId)) {
              continue;
            }
            final number = principal.legacyLoanPartNumber!;
            final paidPrincipal = principal.toAmount ?? principal.amount;
            final payment = ((principal.amount * 100).round() +
                    (interest.amount * 100).round()) /
                100;
            if (payment <= 0 || paidPrincipal < 0 || paidPrincipal > payment) {
              continue;
            }
            deleteIds.addAll([principal.id, interest.id]);
            insertItems.add(FinanceTransaction(
              id: principal.id,
              type: TransactionType.transfer,
              accountId: principal.accountId,
              toAccountId: loanId,
              amount: payment,
              toAmount: paidPrincipal,
              currency: principal.currency,
              toCurrency: principal.transferInCurrency,
              transactionDate: principal.transactionDate,
              cardPostingDate: principal.cardPostingDate ?? interest.cardPostingDate,
              recordDate: principal.recordDate,
              status: TransactionStatus.planned,
              loanInstallmentNumber: number,
              description: '贷款月供 #$number',
            ));
          }
          if (deleteIds.isEmpty) return null;
          return ledger.replaceExistingTransactions(
              deleteIds: deleteIds, insertItems: insertItems);
        }));
  }

  FinanceTransaction _loanPayment(
          Account loan, Account payer, LoanInstallment payment,
          {required DateTime date, required TransactionStatus status}) =>
      FinanceTransaction(
        id: '${buildId('txn_loan_payment')}_${payment.number}',
        type: TransactionType.transfer,
        accountId: payer.id,
        toAccountId: loan.id,
        loanInstallmentNumber: payment.number,
        amount: payment.payment,
        toAmount: payment.principal,
        currency: payer.currency,
        toCurrency: loan.currency,
        transactionDate: date,
        status: status,
        description: '贷款月供 #${payment.number}',
      );

  Set<String> _expandLoanInstallmentDeletionIds(
    FinanceRepository repository,
    Iterable<String> requestedIds,
  ) {
    final result = requestedIds.toSet();
    final byId = {for (final tx in repository.transactions) tx.id: tx};
    for (final id in requestedIds.toSet()) {
      final selected = byId[id];
      if (selected == null ||
          selected.legacyLoanPartNumber == null ||
          selected.legacyLoanId == null) {
        continue;
      }
      final parts = repository.transactions
          .where((tx) =>
              tx.legacyLoanId == selected.legacyLoanId &&
              tx.legacyLoanPartNumber == selected.legacyLoanPartNumber &&
              tx.accountId == selected.accountId &&
              tx.status == selected.status &&
              tx.currency == selected.currency &&
              _sameDay(tx.transactionDate, selected.transactionDate))
          .toList();
      if (parts.length == 2 &&
          parts.where((t) => t.type == TransactionType.transfer).length == 1 &&
          parts.where((t) => t.type == TransactionType.expense).length == 1) {
        result.addAll(parts.map((tx) => tx.id));
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
    PresetCategoryChoice? categoryChoice,
    bool fromStoredTransaction = false,
  }) async {
    await _repoNotifier
        .mutate((repository) => repository.addTransactionTemplate(
              name: name,
              transaction: transaction,
              categoryChoice: categoryChoice,
              fromStoredTransaction: fromStoredTransaction,
            ));
  }

  /// Deletes a transaction template by id.
  Future<void> deleteTransactionTemplate(String templateId) async {
    await _repoNotifier.mutate(
        (repository) => repository.deleteTransactionTemplate(templateId));
  }

  /// Replaces an existing template while preserving its identifier.
  Future<void> saveTransactionTemplate(TransactionTemplate template) async {
    await _repoNotifier
        .mutate((repository) => repository.saveTransactionTemplate(template));
  }

  /// Persists the complete quick-template order in one atomic replacement.
  Future<void> reorderTransactionTemplates(
      List<String> orderedTemplateIds) async {
    await _repoNotifier.mutate((repository) =>
        repository.reorderTransactionTemplates(orderedTemplateIds));
  }

  /// Creates a recurring transaction rule.
  Future<void> addRecurringTransactionRule({
    required String name,
    required FinanceTransaction transaction,
    PresetCategoryChoice? categoryChoice,
    bool fromStoredTransaction = false,
    required int intervalMonths,
  }) async {
    await _repoNotifier
        .mutate((repository) => repository.addRecurringTransactionRule(
              name: name,
              transaction: transaction,
              categoryChoice: categoryChoice,
              fromStoredTransaction: fromStoredTransaction,
              intervalMonths: intervalMonths,
            ));
  }

  /// Deletes a recurring transaction rule.
  Future<void> deleteRecurringTransactionRule(String ruleId) async {
    await _repoNotifier.mutate(
        (repository) => repository.deleteRecurringTransactionRule(ruleId));
  }

  /// Replaces an existing recurring rule while preserving generated history.
  Future<void> saveRecurringTransactionRule(RecurringTransactionRule rule,
      {int? generateMonthsAhead}) async {
    await _repoNotifier.mutate((repository) =>
        repository.saveRecurringTransactionRule(rule,
            generateMonthsAhead: generateMonthsAhead, requireExisting: true));
  }

  /// Generates future transactions from a recurring rule.
  Future<void> generateRecurringTransactions(
    String ruleId, {
    required int monthsAhead,
  }) async {
    await _repoNotifier.mutate((repository) => repository
        .generateRecurringTransactions(ruleId, monthsAhead: monthsAhead));
  }
}

/// Provider for transaction CRUD mutations.
final transactionMutationsProvider =
    NotifierProvider<TransactionMutations, void>(TransactionMutations.new,
        dependencies: [financeRepositoryProvider]);
