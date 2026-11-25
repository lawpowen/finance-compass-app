import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/finance_repository.dart';
import '../../models/account.dart';
import '../repository_provider.dart';

/// Account CRUD operations.
///
/// Every method reads the current [FinanceRepository] from
/// [financeRepositoryProvider], calls the appropriate repository method, and
/// pushes the refreshed instance back so the UI re-renders.
class AccountMutations extends Notifier<void> {
  @override
  void build() {}

  FinanceRepositoryNotifier get _repoNotifier =>
      ref.read(financeRepositoryProvider.notifier);

  Future<FinanceRepository> get _repo =>
      ref.read(financeRepositoryProvider.future);

  /// Creates a new account.
  Future<void> addAccount(Account account) async {
    await _repoNotifier.mutate((repository) => repository.addAccount(account));
  }

  /// Updates an existing account.
  Future<void> updateAccount(Account account) async {
    await _repoNotifier.mutate((repository) =>
        repository.updateExistingAccount(account, preserveActivity: true));
  }

  Future<void> setActive(String accountId, bool active) async {
    await _repoNotifier
        .mutate((repository) => repository.setAccountActive(accountId, active));
  }

  /// Deletes an account only if it has no linked transactions or snapshots.
  ///
  /// Returns `true` if the account was deleted, `false` if it was kept
  /// because linked data exists.
  Future<bool> deleteAccount(String accountId) async {
    return await _repoNotifier.mutate(
            (repository) => repository.deleteAccountIfSafe(accountId)) !=
        null;
  }

  /// Checks whether an account can be safely deleted.
  Future<bool> canDelete(String accountId) async {
    return (await _repo).canDeleteAccount(accountId);
  }

  /// Creates a new asset goal.
  Future<void> addAssetGoal({
    required String name,
    required double amount,
    String? currency,
  }) async {
    await _repoNotifier.mutate((repository) => repository.addAssetGoal(
          name: name,
          amount: amount,
          currency: currency,
        ));
  }

  /// Updates an existing asset goal.
  Future<void> updateAssetGoal(AssetGoal goal) async {
    await _repoNotifier
        .mutate((repository) => repository.updateAssetGoal(goal));
  }

  /// Deletes an asset goal by id.
  Future<void> deleteAssetGoal(String goalId) async {
    await _repoNotifier
        .mutate((repository) => repository.deleteAssetGoal(goalId));
  }

  /// Sets the reconciled month for an account.
  Future<void> setAccountReconciledMonth(
    String accountId,
    String monthKey,
  ) async {
    await _repoNotifier
        .mutate((repository) => repository.setAccountReconciledMonth(
              accountId,
              monthKey,
            ));
  }

  /// Updates exchange rates and currency priority.
  Future<void> updateExchangeRates(
    Map<String, double> ratesToBase,
    List<String> currencyPriority,
  ) async {
    await _repoNotifier.mutate((repository) => repository.updateExchangeRates(
          ratesToBase,
          currencyPriority,
        ));
  }
}

/// Provider for account CRUD mutations.
final accountMutationsProvider = NotifierProvider<AccountMutations, void>(
    AccountMutations.new,
    dependencies: [financeRepositoryProvider]);
