import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/finance_repository.dart';
import '../../models/category.dart';
import '../repository_provider.dart';

/// Category CRUD operations.
///
/// Wraps [FinanceRepository] category methods and refreshes the global
/// repository state after every write.
class CategoryMutations extends Notifier<void> {
  @override
  void build() {}

  FinanceRepositoryNotifier get _repoNotifier =>
      ref.read(financeRepositoryProvider.notifier);

  Future<FinanceRepository> get _repo =>
      ref.read(financeRepositoryProvider.future);

  /// Creates a new category.
  Future<void> addCategory(Category category) async {
    await _repoNotifier
        .mutate((repository) => repository.addCategory(category));
  }

  /// Updates an existing category.
  Future<void> updateCategory(Category category) async {
    await _repoNotifier
        .mutate((repository) => repository.updateExistingCategory(category));
  }

  /// Deletes a category only if it has no linked transactions or budgets.
  ///
  /// Returns `true` if deleted, `false` if linked data exists.
  Future<bool> deleteCategory(String categoryId) async {
    return await _repoNotifier.mutate(
            (repository) => repository.deleteCategoryIfSafe(categoryId)) !=
        null;
  }

  /// Checks whether a category can be safely deleted.
  Future<bool> canDelete(String categoryId) async {
    return (await _repo).canDeleteCategory(categoryId);
  }
}

/// Provider for category CRUD mutations.
final categoryMutationsProvider =
    NotifierProvider<CategoryMutations, void>(CategoryMutations.new);
