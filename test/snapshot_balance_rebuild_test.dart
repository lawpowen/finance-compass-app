import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase, SnapshotBalanceAmbiguityException;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/asset_snapshot.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/services/account_service.dart';
import 'package:finance_app/src/core/services/asset_service.dart';
import 'package:finance_app/src/core/services/currency_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _investmentId = 'investment';
final _farFuture = DateTime(2100);

Future<(AppDatabase, FinanceRepository)> _openRepository({
  double initialBalance = 1000,
}) async {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  var repository = await FinanceRepository.load(database);
  repository = await repository.addAccount(Account(
    id: _investmentId,
    name: '投资',
    accountType: AccountType.trading,
    reportGroup: ReportGroup.investment,
    currency: 'MYR',
    initialBalance: initialBalance,
    currentBalance: initialBalance,
  ));
  repository = await repository.addAccount(const Account(
    id: 'cash',
    name: '现金',
    accountType: AccountType.cash,
    reportGroup: ReportGroup.cash,
    currency: 'MYR',
    currentBalance: 0,
  ));
  return (database, repository);
}

AssetSnapshot _snapshot(
  String id,
  DateTime date,
  double marketValue, {
  double costBasis = 0,
  String accountId = _investmentId,
}) {
  return AssetSnapshot(
    id: id,
    accountId: accountId,
    snapshotDate: date,
    marketValue: marketValue,
    costBasis: costBasis,
  );
}

FinanceTransaction _income(
  String id,
  DateTime date,
  double amount, {
  TransactionStatus status = TransactionStatus.actual,
}) {
  return FinanceTransaction(
    id: id,
    type: TransactionType.income,
    accountId: _investmentId,
    amount: amount,
    currency: 'MYR',
    transactionDate: date,
    status: status,
  );
}

FinanceTransaction _transferIn(
  String id,
  DateTime date,
  double amount, {
  TransactionStatus status = TransactionStatus.actual,
}) {
  return FinanceTransaction(
    id: id,
    type: TransactionType.transfer,
    accountId: 'cash',
    toAccountId: _investmentId,
    amount: amount,
    currency: 'MYR',
    transactionDate: date,
    status: status,
  );
}

double _currentBalance(FinanceRepository repository) {
  return repository.accounts
      .firstWhere((item) => item.id == _investmentId)
      .currentBalance;
}

/// Reloads from the database so assertions read persisted values.
Future<FinanceRepository> _reload(AppDatabase database) {
  return FinanceRepository.load(database);
}

Future<double> _persistedBalance(AppDatabase database) async {
  return _currentBalance(await _reload(database));
}

/// The displayed balance after every recorded transaction must equal the
/// materialized `current_balance`.
void _expectReadMatchesMaterialized(FinanceRepository repository) {
  expect(
    repository.accountBalanceAt(_investmentId, _farFuture),
    closeTo(_currentBalance(repository), 0.001),
  );
}

void main() {
  group('deleteAssetSnapshot', () {
    test('deleting the only snapshot restores the ledger balance, not 0',
        () async {
      final (database, initialRepository) = await _openRepository();
      var repository = await initialRepository.addAssetSnapshot(
        _snapshot('only', DateTime(2026, 2, 1), 1200),
      );
      expect(_currentBalance(repository), 1200);

      repository = await repository.deleteExistingAssetSnapshot('only');

      expect(_currentBalance(repository), 1000);
      expect(await _persistedBalance(database), 1000);
    });

    test('deleting the only snapshot replays actual transactions only',
        () async {
      final (database, initialRepository) = await _openRepository();
      var repository = await initialRepository.addAssetSnapshot(
        _snapshot('only', DateTime(2026, 1, 10), 1200),
      );
      repository = await repository
          .addTransaction(_transferIn('in', DateTime(2026, 1, 20), 300));
      repository = await repository
          .addTransaction(_income('dividend', DateTime(2026, 1, 25), 100));
      repository = await repository.addTransaction(_income(
        'planned',
        DateTime(2026, 1, 26),
        999,
        status: TransactionStatus.planned,
      ));
      expect(_currentBalance(repository), 1600);

      repository = await repository.deleteExistingAssetSnapshot('only');

      // initial 1000 + transfer 300 + income 100; planned is excluded.
      expect(_currentBalance(repository), 1400);
      expect(await _persistedBalance(database), 1400);
    });

    test('without transfers, deleting latest or historical snapshot rebuilds',
        () async {
      Future<(AppDatabase, FinanceRepository)> seed() async {
        final (database, initialRepository) = await _openRepository();
        var repository = await initialRepository.addAssetSnapshot(
          _snapshot('jan', DateTime(2026, 1, 10), 1200),
        );
        repository = await repository
            .addTransaction(_income('feb', DateTime(2026, 2, 1), 50));
        repository = await repository.addAssetSnapshot(
          _snapshot('mar', DateTime(2026, 3, 1), 1500),
        );
        repository = await repository
            .addTransaction(_income('mar-income', DateTime(2026, 3, 10), 70));
        repository = await repository.addTransaction(_transferIn(
          'planned-in',
          DateTime(2026, 3, 15),
          999,
          status: TransactionStatus.planned,
        ));
        expect(_currentBalance(repository), 1570);
        return (database, repository);
      }

      final (latestDb, latestRepo) = await seed();
      final afterLatest = await latestRepo.deleteExistingAssetSnapshot('mar');
      // Jan snapshot 1200 + income after it (50 + 70); planned excluded.
      expect(_currentBalance(afterLatest), 1320);
      expect(await _persistedBalance(latestDb), 1320);
      _expectReadMatchesMaterialized(await _reload(latestDb));

      final (historyDb, historyRepo) = await seed();
      final afterHistory = await historyRepo.deleteExistingAssetSnapshot('jan');
      expect(_currentBalance(afterHistory), 1570);
      expect(await _persistedBalance(historyDb), 1570);
      _expectReadMatchesMaterialized(await _reload(historyDb));
    });

    test(
        'deleting latest snapshot after a backfilled transfer is refused '
        'and leaves the database unchanged', () async {
      final (database, initialRepository) = await _openRepository();
      var repository = await initialRepository.addAssetSnapshot(
        _snapshot('jan', DateTime(2026, 1, 10), 1000),
      );
      repository = await repository.addAssetSnapshot(
        _snapshot('mar', DateTime(2026, 3, 1), 1200),
      );
      // Backfilled Feb transfer is folded into the then-latest Mar snapshot
      // only; nothing records that Jan does not contain it.
      repository = await repository
          .addTransaction(_transferIn('feb-in', DateTime(2026, 2, 1), 100));
      expect(_currentBalance(repository), 1300);

      await expectLater(
        repository.deleteExistingAssetSnapshot('mar'),
        throwsA(isA<SnapshotBalanceAmbiguityException>()),
      );

      final reloaded = await _reload(database);
      expect(reloaded.snapshotsForAccount(_investmentId).map((s) => s.id),
          ['jan', 'mar']);
      expect(
          reloaded.latestSnapshotForAccount(_investmentId)!.marketValue, 1300);
      expect(_currentBalance(reloaded), 1300);
      _expectReadMatchesMaterialized(reloaded);

      // Deleting the non-latest snapshot is still lossless.
      final afterHistory = await reloaded.deleteExistingAssetSnapshot('jan');
      expect(_currentBalance(afterHistory), 1300);
    });

    test('planned transfers do not block deleting the latest snapshot',
        () async {
      final (database, initialRepository) = await _openRepository();
      var repository = await initialRepository.addAssetSnapshot(
        _snapshot('jan', DateTime(2026, 1, 10), 1000),
      );
      repository = await repository.addAssetSnapshot(
        _snapshot('mar', DateTime(2026, 3, 1), 1200),
      );
      repository = await repository.addTransaction(_transferIn(
        'planned-in',
        DateTime(2026, 2, 1),
        100,
        status: TransactionStatus.planned,
      ));

      repository = await repository.deleteExistingAssetSnapshot('mar');

      expect(_currentBalance(repository), 1000);
      expect(await _persistedBalance(database), 1000);
    });
  });

  group('updateAssetSnapshot', () {
    test('editing market value keeps later actual transactions', () async {
      final (database, initialRepository) = await _openRepository();
      var repository = await initialRepository.addAssetSnapshot(
        _snapshot('snap', DateTime(2026, 1, 10), 1000),
      );
      repository = await repository
          .addTransaction(_income('dividend', DateTime(2026, 1, 20), 100));
      repository = await repository.addTransaction(_income(
        'planned',
        DateTime(2026, 1, 21),
        999,
        status: TransactionStatus.planned,
      ));
      expect(_currentBalance(repository), 1100);

      repository = await repository.updateExistingAssetSnapshot(
        _snapshot('snap', DateTime(2026, 1, 10), 1050),
      );

      expect(_currentBalance(repository), 1150);
      expect(await _persistedBalance(database), 1150);
      _expectReadMatchesMaterialized(await _reload(database));
    });

    test('editing the latest snapshot in place works with transfers', () async {
      final (database, initialRepository) = await _openRepository();
      var repository = await initialRepository.addAssetSnapshot(
        _snapshot('snap', DateTime(2026, 1, 10), 1000),
      );
      repository = await repository
          .addTransaction(_transferIn('in', DateTime(2026, 2, 1), 100));
      repository = await repository
          .addTransaction(_income('dividend', DateTime(2026, 2, 20), 50));
      expect(_currentBalance(repository), 1150);
      expect(repository.latestSnapshotForAccount(_investmentId)!.marketValue,
          1100);

      repository = await repository.updateExistingAssetSnapshot(
        _snapshot('snap', DateTime(2026, 1, 10), 1120),
      );

      expect(_currentBalance(repository), 1170);
      expect(await _persistedBalance(database), 1170);
      _expectReadMatchesMaterialized(await _reload(database));
    });

    test('moving the latest snapshot after a transaction stops counting it',
        () async {
      final (database, initialRepository) = await _openRepository();
      var repository = await initialRepository.addAssetSnapshot(
        _snapshot('snap', DateTime(2026, 1, 10), 1000),
      );
      repository = await repository
          .addTransaction(_income('dividend', DateTime(2026, 1, 20), 100));

      repository = await repository.updateExistingAssetSnapshot(
        _snapshot('snap', DateTime(2026, 1, 25), 1050),
      );

      expect(_currentBalance(repository), 1050);
      expect(await _persistedBalance(database), 1050);
      _expectReadMatchesMaterialized(await _reload(database));
    });

    test('changing which snapshot is latest is refused when transfers exist',
        () async {
      final (database, initialRepository) = await _openRepository();
      var repository = await initialRepository.addAssetSnapshot(
        _snapshot('jan', DateTime(2026, 1, 10), 1000),
      );
      repository = await repository.addAssetSnapshot(
        _snapshot('mar', DateTime(2026, 3, 1), 1200),
      );
      repository = await repository
          .addTransaction(_transferIn('feb-in', DateTime(2026, 2, 1), 100));

      await expectLater(
        repository.updateExistingAssetSnapshot(
          _snapshot('mar', DateTime(2026, 1, 1), 1300),
        ),
        throwsA(isA<SnapshotBalanceAmbiguityException>()),
      );

      final reloaded = await _reload(database);
      final mar = reloaded
          .snapshotsForAccount(_investmentId)
          .firstWhere((s) => s.id == 'mar');
      expect(mar.snapshotDate, DateTime(2026, 3, 1));
      expect(mar.marketValue, 1300);
      expect(_currentBalance(reloaded), 1300);
    });

    test('moving a snapshot to another account is rejected', () async {
      final (_, initialRepository) = await _openRepository();
      final repository = await initialRepository.addAssetSnapshot(
        _snapshot('snap', DateTime(2026, 1, 10), 1000),
      );

      await expectLater(
        repository.updateExistingAssetSnapshot(
          _snapshot('snap', DateTime(2026, 1, 10), 1000, accountId: 'cash'),
        ),
        throwsArgumentError,
      );
    });
  });

  group('insertAssetSnapshot', () {
    test('backdated snapshot does not replace the latest anchor', () async {
      final (database, initialRepository) = await _openRepository();
      var repository = await initialRepository.addAssetSnapshot(
        _snapshot('mar', DateTime(2026, 3, 1), 1500),
      );
      repository = await repository
          .addTransaction(_income('mar-income', DateTime(2026, 3, 10), 70));
      expect(_currentBalance(repository), 1570);

      repository = await repository.addAssetSnapshot(
        _snapshot('jan', DateTime(2026, 1, 10), 1200),
      );

      expect(_currentBalance(repository), 1570);
      expect(await _persistedBalance(database), 1570);
    });

    test(
        'new latest snapshot dated before an existing transfer folds it in '
        'and keeps later income', () async {
      final (database, initialRepository) = await _openRepository();
      var repository = await initialRepository.addAssetSnapshot(
        _snapshot('jan', DateTime(2026, 1, 10), 1000),
      );
      repository = await repository
          .addTransaction(_transferIn('mar-in', DateTime(2026, 3, 1), 100));
      repository = await repository
          .addTransaction(_income('mar-income', DateTime(2026, 3, 20), 30));
      repository = await repository.addTransaction(_transferIn(
        'planned-in',
        DateTime(2026, 4, 1),
        500,
        status: TransactionStatus.planned,
      ));
      expect(_currentBalance(repository), 1130);

      repository = await repository.addAssetSnapshot(
        _snapshot('feb', DateTime(2026, 2, 15), 1050),
      );

      final reloaded = await _reload(database);
      final feb = reloaded.latestSnapshotForAccount(_investmentId)!;
      expect(feb.id, 'feb');
      // Observed 1050 + Mar transfer 100; the planned transfer is excluded.
      expect(feb.marketValue, 1150);
      expect(_currentBalance(repository), 1180);
      expect(_currentBalance(reloaded), 1180);
      expect(reloaded.accountBalanceAt(_investmentId, DateTime(2026, 2, 28)),
          1050);
      expect(reloaded.accountBalanceAt(_investmentId, DateTime(2026, 3, 31)),
          1180);
      _expectReadMatchesMaterialized(reloaded);
    });
  });

  group('accountBalanceAt after a snapshot', () {
    Future<(AppDatabase, FinanceRepository)> seed() async {
      final (database, initialRepository) = await _openRepository();
      var repository = await initialRepository.addAssetSnapshot(
        _snapshot('jan', DateTime(2026, 1, 10), 1000),
      );
      repository = await repository
          .addTransaction(_income('jan-income', DateTime(2026, 1, 20), 100));
      repository = await repository
          .addTransaction(_transferIn('jan-in', DateTime(2026, 1, 25), 200));
      repository = await repository
          .addTransaction(_income('feb-income', DateTime(2026, 2, 10), 50));
      repository = await repository.addTransaction(_income(
        'planned',
        DateTime(2026, 1, 22),
        999,
        status: TransactionStatus.planned,
      ));
      return (database, repository);
    }

    test('adds income after the snapshot and ignores future income', () async {
      final (database, _) = await seed();
      final repository = await _reload(database);

      expect(repository.accountBalanceAt(_investmentId, DateTime(2026, 1, 15)),
          1000);
      expect(repository.accountBalanceAt(_investmentId, DateTime(2026, 1, 21)),
          1100);
      expect(
          repository.accountBalanceAt(
              _investmentId, DateTime(2026, 1, 31, 23, 59, 59)),
          1300);
      expect(repository.accountBalanceAt(_investmentId, DateTime(2026, 2, 28)),
          1350);
      expect(_currentBalance(repository), 1350);
      _expectReadMatchesMaterialized(repository);

      for (final day in [15, 21, 31]) {
        final cutoff = DateTime(2026, 1, day, 23, 59, 59);
        expect(
          repository.accountBalanceTrace(_investmentId, cutoff).endingBalance,
          repository.accountBalanceAt(_investmentId, cutoff),
        );
      }
    });

    test('single-snapshot income example from review', () async {
      final (database, initialRepository) = await _openRepository();
      var repository = await initialRepository.addAssetSnapshot(
        _snapshot('jan', DateTime(2026, 1, 10), 1000),
      );
      repository = await repository
          .addTransaction(_income('jan-income', DateTime(2026, 1, 20), 100));
      repository = await repository
          .addTransaction(_income('feb-income', DateTime(2026, 2, 5), 50));
      repository = await _reload(database);

      expect(
          repository.accountBalanceAt(
              _investmentId, DateTime(2026, 1, 31, 23, 59, 59)),
          1100);
      expect(repository.accountBalanceAt(_investmentId, DateTime(2026, 1, 15)),
          1000);
    });

    test('mirror services agree with the repository', () async {
      final (database, _) = await seed();
      final repository = await _reload(database);
      final accountService = AccountService(
        accounts: repository.accounts,
        transactions: repository.transactions,
        snapshots: repository.snapshots,
        currencyService:
            CurrencyService(database: database, metaValues: const {}),
        database: database,
      );
      for (final date in [
        DateTime(2026, 1, 15),
        DateTime(2026, 1, 21),
        DateTime(2026, 2, 28),
      ]) {
        expect(accountService.accountBalanceAt(_investmentId, date),
            repository.accountBalanceAt(_investmentId, date));
        expect(
            accountService
                .accountBalanceTrace(_investmentId, date)
                .endingBalance,
            repository.accountBalanceAt(_investmentId, date));
      }
    });
  });

  group('history before the first snapshot', () {
    Future<(AppDatabase, FinanceRepository)> seed() async {
      final (database, initialRepository) = await _openRepository();
      var repository = await initialRepository
          .addTransaction(_income('jan-income', DateTime(2026, 1, 20), 50));
      repository = await repository.addTransaction(_transferIn(
        'planned-in',
        DateTime(2026, 1, 22),
        5000,
        status: TransactionStatus.planned,
      ));
      repository = await repository.addAssetSnapshot(
        _snapshot('feb', DateTime(2026, 2, 15), 1200, costBasis: 900),
      );
      return (database, repository);
    }

    test('balance and cost do not leak the future snapshot', () async {
      final (database, _) = await seed();
      final repository = await _reload(database);
      final janEnd = DateTime(2026, 1, 31, 23, 59, 59);

      expect(_currentBalance(repository), 1200);
      expect(repository.accountBalanceAt(_investmentId, DateTime(2026, 1, 10)),
          1000);
      expect(repository.accountBalanceAt(_investmentId, janEnd), 1050);
      expect(
          repository.costBasisForAccount(_investmentId, upToDate: janEnd), 0);
      expect(
          repository.remainingCostBasisForAccount(_investmentId,
              upToDate: janEnd),
          0);
      expect(
          repository.accountBalanceTrace(_investmentId, janEnd).endingBalance,
          1050);

      final febEnd = DateTime(2026, 2, 28, 23, 59, 59);
      expect(repository.accountBalanceAt(_investmentId, febEnd), 1200);
      expect(
          repository.costBasisForAccount(_investmentId, upToDate: febEnd), 900);
    });

    test('mirror services agree with the repository', () async {
      final (database, _) = await seed();
      final repository = await _reload(database);
      final janEnd = DateTime(2026, 1, 31, 23, 59, 59);
      final currencyService =
          CurrencyService(database: database, metaValues: const {});
      final assetService = AssetService(
        accounts: repository.accounts,
        transactions: repository.transactions,
        snapshots: repository.snapshots,
        metaValues: const {},
        currencyService: currencyService,
        database: database,
      );
      final accountService = AccountService(
        accounts: repository.accounts,
        transactions: repository.transactions,
        snapshots: repository.snapshots,
        currencyService: currencyService,
        database: database,
      );

      expect(
          assetService.costBasisForAccount(_investmentId, upToDate: janEnd), 0);
      expect(accountService.accountBalanceAt(_investmentId, janEnd), 1050);
      expect(
          accountService
              .accountBalanceTrace(_investmentId, janEnd)
              .endingBalance,
          1050);
    });
  });
}
