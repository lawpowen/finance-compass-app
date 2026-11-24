import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/budget.dart';
import '../repository_provider.dart';

/// Budget CRUD operations.
///
/// Wraps [FinanceRepository] budget methods and refreshes the global
/// repository state after every write.
class BudgetMutations extends Notifier<void> {
  @override
  void build() {}

  FinanceRepositoryNotifier get _repoNotifier =>
      ref.read(financeRepositoryProvider.notifier);

  /// Creates or updates a budget (upsert by id, or by category+monthKey).
  Future<void> addBudget(Budget budget) async {
    await _repoNotifier.mutate((repository) => repository.addBudget(budget));
  }

  /// Deletes a budget by its id.
  Future<void> deleteBudget(String budgetId) async {
    await _repoNotifier
        .mutate((repository) => repository.deleteExistingBudget(budgetId));
  }
}

/// Provider for budget CRUD mutations.
final budgetMutationsProvider =
    NotifierProvider<BudgetMutations, void>(BudgetMutations.new);
