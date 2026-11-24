import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/asset_snapshot.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/features/accounts/account_detail_screen.dart';
import 'package:finance_app/src/features/accounts/asset_snapshot_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'snapshot preview uses investment currency, not the ledger currency',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    const account = Account(
      id: 'usd-fund',
      name: '美元基金',
      accountType: AccountType.fund,
      reportGroup: ReportGroup.investment,
      currency: 'USD',
      currentBalance: 0,
    );
    repository = await repository.addAccount(account);
    final snapshot = AssetSnapshot(
      id: 'usd-fund-snapshot',
      accountId: account.id,
      snapshotDate: DateTime.now(),
      marketValue: 150,
      costBasis: 120,
    );
    repository = await repository.addAssetSnapshot(snapshot);

    await tester.pumpWidget(MaterialApp(
      home: AssetSnapshotFormDialog(
        repository: repository,
        initialSnapshot: snapshot,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('美元基金 · USD'), findsOneWidget);
    expect(find.text(r'累计成本: US$ 120.00'), findsOneWidget);
    expect(find.text(r'未实现盈亏: US$ 30.00'), findsOneWidget);
  });

  testWidgets('investment detail exposes a locked market value update entry',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = FinanceRepository.preview();
    final account = repository.investmentAccounts().first;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeRepositoryProvider.overrideWith(
            () => _TestRepositoryNotifier(repository),
          ),
        ],
        child: MaterialApp(
          home: AccountDetailScreen(
            account: account,
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final entry = find.text(
      repository.snapshotsForAccount(account.id).isEmpty ? '录入当前市值' : '更新当前市值',
    );
    expect(entry, findsOneWidget);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.text('更新市值'), findsOneWidget);
    expect(find.text('${account.name} · ${account.currency}'), findsOneWidget);
    final accountDropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(accountDropdown.onChanged, isNull);
  });

  testWidgets('historical investment detail hides write actions',
      (tester) async {
    final repository = FinanceRepository.preview();
    final account = repository.investmentAccounts().first;
    final now = DateTime.now();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeRepositoryProvider.overrideWith(
            () => _TestRepositoryNotifier(repository),
          ),
        ],
        child: MaterialApp(
          home: AccountDetailScreen(
            account: account,
            repository: repository,
            cutoffDate: DateTime(now.year, now.month, 0, 23, 59, 59),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('account-detail-historical-banner')),
      findsOneWidget,
    );
    expect(find.text('录入当前市值'), findsNothing);
    expect(find.text('更新当前市值'), findsNothing);

    await tester.tap(find.byKey(const Key('account-detail-return-current')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('account-detail-historical-banner')),
      findsNothing,
    );
    expect(
      find.text(
        repository.snapshotsForAccount(account.id).isEmpty
            ? '录入当前市值'
            : '更新当前市值',
      ),
      findsOneWidget,
    );
  });
}

class _TestRepositoryNotifier extends FinanceRepositoryNotifier {
  _TestRepositoryNotifier(this.repository);

  final FinanceRepository repository;

  @override
  Future<FinanceRepository> build() async => repository;
}
