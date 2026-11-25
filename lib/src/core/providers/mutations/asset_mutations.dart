import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/asset_snapshot.dart';
import '../../data/finance_repository.dart';
import '../repository_provider.dart';

/// Asset snapshot CRUD operations.
///
/// Wraps [FinanceRepository] asset-snapshot methods and refreshes the
/// global repository state after every write.
class AssetMutations extends Notifier<void> {
  @override
  void build() {}

  FinanceRepositoryNotifier get _repoNotifier =>
      ref.read(financeRepositoryProvider.notifier);

  /// Creates a new asset snapshot for an account.
  Future<void> addSnapshot(AssetSnapshot snapshot) async {
    await _repoNotifier
        .mutate((repository) => repository.addAssetSnapshot(snapshot));
  }

  /// Updates an existing asset snapshot.
  Future<void> updateSnapshot(AssetSnapshot snapshot,
      {AssetSnapshot? expected}) async {
    await _repoNotifier.mutate((repository) {
      _checkObservation(repository, expected);
      return repository.updateExistingAssetSnapshot(snapshot);
    });
  }

  Future<void> deleteSnapshot(String snapshotId,
      {AssetSnapshot? expected}) async {
    await _repoNotifier.mutate((repository) {
      _checkObservation(repository, expected);
      return repository.deleteExistingAssetSnapshot(snapshotId);
    });
  }

  void _checkObservation(
      FinanceRepository repository, AssetSnapshot? expected) {
    if (expected == null) return;
    final current = repository
        .snapshotsForAccount(expected.accountId)
        .where((item) => item.id == expected.id)
        .firstOrNull;
    if (!expected.matchesObservation(current)) {
      throw StateError('快照已修改或删除，请重新核对。');
    }
  }
}

/// Provider for asset snapshot CRUD mutations.
final assetMutationsProvider = NotifierProvider<AssetMutations, void>(
    AssetMutations.new,
    dependencies: [financeRepositoryProvider]);
