import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/asset_snapshot.dart';
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
  Future<void> updateSnapshot(AssetSnapshot snapshot) async {
    await _repoNotifier.mutate(
        (repository) => repository.updateExistingAssetSnapshot(snapshot));
  }

  /// Deletes an asset snapshot by its id.
  Future<void> deleteSnapshot(String snapshotId) async {
    await _repoNotifier.mutate(
        (repository) => repository.deleteExistingAssetSnapshot(snapshotId));
  }
}

/// Provider for asset snapshot CRUD mutations.
final assetMutationsProvider =
    NotifierProvider<AssetMutations, void>(AssetMutations.new);
