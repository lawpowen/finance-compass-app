import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/finance_repository.dart';
import '../sync/ledger_sync.dart';
import 'database_provider.dart';

/// Opt-in hosted session. The ordinary app only opens its local database.
final ledgerSyncSessionProvider = Provider<LedgerSyncSession?>((ref) => null);

/// Loads the repository and routes ledger writes through a single boundary.
class FinanceRepositoryNotifier extends AsyncNotifier<FinanceRepository> {
  Object? _scope;
  Future<void> _localMutationTail = Future<void>.value();

  @override
  Future<FinanceRepository> build() {
    _captureScope();
    final db = ref.watch(appDatabaseProvider);
    return FinanceRepository.load(db);
  }

  Future<FinanceRepository?> mutate(
    Future<FinanceRepository?> Function(FinanceRepository) action,
  ) async {
    final scope = _captureScope();
    final sync = ref.read(ledgerSyncSessionProvider);
    final repository = await future;
    if (sync != null) {
      return sync.mutate(
        repository,
        action,
        onLocalCommit: (updated) => _publish(scope, updated),
      );
    }
    return _serializeLocal(() async {
      final current = state.valueOrNull ?? await future;
      final updated = await action(current);
      if (updated != null) _publish(scope, updated);
      return updated;
    });
  }

  Future<T> _serializeLocal<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final run = _localMutationTail.catchError((_) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _localMutationTail = run;
    return completer.future;
  }

  Future<void> pullRemote({
    bool retryPending = false,
    LedgerRevision? available,
    bool discardPending = false,
    bool Function()? canApply,
  }) async {
    final scope = _captureScope();
    final sync = ref.read(ledgerSyncSessionProvider);
    if (sync == null) return;
    final repository = await future;
    if (retryPending) {
      await sync.retry(repository);
      return;
    }
    await sync.refresh(
      repository,
      available: available,
      discardPending: discardPending,
      canApply: canApply,
      onLocalCommit: (updated) => _publish(scope, updated),
    );
  }

  Future<void> keepOversizedDraft() async {
    final scope = _captureScope();
    final sync = ref.read(ledgerSyncSessionProvider);
    if (sync == null) return;
    await sync.keepRejectedDraft(await future,
        onLocalCommit: (updated) => _publish(scope, updated));
  }

  Object _captureScope() {
    final current = _scope;
    if (current != null) return current;
    final scope = Object();
    _scope = scope;
    ref.onDispose(() {
      if (identical(_scope, scope)) _scope = null;
    });
    return scope;
  }

  void _publish(Object scope, FinanceRepository updated) {
    if (identical(_scope, scope)) {
      state = AsyncData(updated);
    }
  }
}

final financeRepositoryProvider =
    AsyncNotifierProvider<FinanceRepositoryNotifier, FinanceRepository>(
  FinanceRepositoryNotifier.new,
  dependencies: [appDatabaseProvider, ledgerSyncSessionProvider],
);
