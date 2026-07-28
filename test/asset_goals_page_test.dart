import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/accounts/accounts_v2_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('asset goals use total assets without deducting credit liabilities',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    for (final account in const [
      Account(
        id: 'goal-cash',
        name: 'Cash',
        accountType: AccountType.bankSaving,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 1000,
      ),
      Account(
        id: 'goal-investment',
        name: 'Investment',
        accountType: AccountType.fund,
        reportGroup: ReportGroup.investment,
        currency: 'MYR',
        currentBalance: 500,
      ),
      Account(
        id: 'goal-credit',
        name: 'Credit',
        accountType: AccountType.creditCard,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        currentBalance: -800,
      ),
    ]) {
      repository = await repository.addAccount(account);
    }
    repository = await repository.addAssetGoal(
      name: 'MYR 1,200',
      amount: 1200,
    );

    final summary = repository.assetGoalSummaries().single;
    expect(repository.totalAssets(), 700);
    expect(repository.totalTargetAssets(), 1500);
    expect(summary.currentAssets, 1500);
    expect(summary.isReached, isTrue);
    expect(summary.history.last.totalAssets, 1500);
  });

  testWidgets('accounts entry opens functional asset-goal management',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    repository = await repository.addAccount(
      const Account(
        id: 'cash',
        name: '储蓄账户',
        accountType: AccountType.bankSaving,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 1000,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        financeRepositoryProvider.overrideWith(
          () => _TestRepositoryNotifier(repository),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.abyss),
          home: Scaffold(body: AccountsV2Screen(repository: repository)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('asset-goals-card')), findsOneWidget);
    await tester.tap(find.byKey(const Key('asset-goals-card')));
    await tester.pumpAndSettle();
    expect(find.text('资产目标'), findsWidgets);
    expect(find.byKey(const Key('asset-goal-empty-add')), findsOneWidget);

    await tester.tap(find.byKey(const Key('asset-goal-empty-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('asset-goal-name')),
      '首个十万',
    );
    await tester.enterText(
      find.byKey(const Key('asset-goal-amount')),
      '100000',
    );
    await tester.tap(find.byKey(const Key('asset-goal-save')));
    await tester.pumpAndSettle();

    expect(find.text('首个十万'), findsOneWidget);
    final updated = await container.read(financeRepositoryProvider.future);
    expect(updated.assetGoals.single.name, '首个十万');
    expect(updated.assetGoals.single.targetAmount, 100000);
    expect(tester.takeException(), isNull);
  });
}

class _TestRepositoryNotifier extends FinanceRepositoryNotifier {
  _TestRepositoryNotifier(this.repository);

  final FinanceRepository repository;

  @override
  Future<FinanceRepository> build() async => repository;
}
