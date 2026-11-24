import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:finance_app/src/app.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/category.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/settings/app_settings_controller.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/dashboard/dashboard_v2_screen.dart';
import 'package:finance_app/src/features/home/home_screen.dart';
import 'package:finance_app/src/features/shared/compass_ui.dart';
import 'package:finance_app/src/features/transactions/transactions_v2_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestRepositoryNotifier extends FinanceRepositoryNotifier {
  _TestRepositoryNotifier(this._repository);

  final FinanceRepository _repository;

  @override
  Future<FinanceRepository> build() async => _repository;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets(
      'dock BackdropFilter is disabled on Android CPU software web and enabled otherwise',
      (tester) async {
    addTearDown(() => debugOverrideCompassCpuSoftwareWeb = null);

    final settingsController = AppSettingsController();
    addTearDown(settingsController.dispose);
    final repo = FinanceRepository.preview();

    Widget buildHarness() => ProviderScope(
          overrides: [
            financeRepositoryProvider
                .overrideWith(() => _TestRepositoryNotifier(repo)),
          ],
          child: MaterialApp(
            theme: buildFinanceTheme(AppThemeStyle.liquidGlass),
            home: HomeScreen(settingsController: settingsController),
          ),
        );

    debugOverrideCompassCpuSoftwareWeb = true;
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();
    final dock = find.byType(NavigationBar);
    final cpuFilter = tester.widget<BackdropFilter>(
      find.ancestor(of: dock, matching: find.byType(BackdropFilter)),
    );
    expect(cpuFilter.enabled, isFalse);

    debugOverrideCompassCpuSoftwareWeb = false;
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();
    final gpuFilter = tester.widget<BackdropFilter>(
      find.ancestor(of: dock, matching: find.byType(BackdropFilter)),
    );
    expect(gpuFilter.enabled, isTrue);
  });

  testWidgets(
      'CompassCard enables BackdropFilter blur on liquidGlass GPU mode and skips on CPU fallback',
      (tester) async {
    addTearDown(() => debugOverrideCompassCpuSoftwareWeb = null);

    Widget buildCardHarness() => MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.liquidGlass),
          home: const Scaffold(
            body: CompassBackdropLayer(
              child: Center(
                child: CompassCard(
                  child: Text('液态玻璃测试卡片'),
                ),
              ),
            ),
          ),
        );

    debugOverrideCompassCpuSoftwareWeb = false;
    await tester.pumpWidget(buildCardHarness());
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: find.text('液态玻璃测试卡片'),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );

    debugOverrideCompassCpuSoftwareWeb = true;
    await tester.pumpWidget(buildCardHarness());
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: find.text('液态玻璃测试卡片'),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'HomeScreen caches tab root widgets across tab switches and invalidates on repo update',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repo = await FinanceRepository.load(database);
    final settingsController = AppSettingsController(database: database);
    addTearDown(settingsController.dispose);
    await settingsController.load();

    final container = ProviderContainer(
      overrides: [
        financeRepositoryProvider
            .overrideWith(() => _TestRepositoryNotifier(repo)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: FinanceApp(settingsController: settingsController),
      ),
    );
    await tester.pumpAndSettle();

    final initialDashboard = tester.widget<DashboardV2Screen>(
      find.byType(DashboardV2Screen),
    );

    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is NavigationDestination && widget.label == '交易',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is NavigationDestination && widget.label == '总览',
      ),
    );
    await tester.pumpAndSettle();

    final afterSwitchDashboard = tester.widget<DashboardV2Screen>(
      find.byType(DashboardV2Screen),
    );
    expect(identical(initialDashboard, afterSwitchDashboard), isTrue);

    await container.read(financeRepositoryProvider.notifier).mutate(
          (current) => current.addAccount(
            const Account(
              id: 'cache-test-cash',
              name: '测试现金',
              accountType: AccountType.cash,
              reportGroup: ReportGroup.cash,
              currency: 'MYR',
              currentBalance: 500,
              initialBalance: 500,
            ),
          ),
        );
    await tester.pumpAndSettle();

    final afterMutationDashboard = tester.widget<DashboardV2Screen>(
      find.byType(DashboardV2Screen),
    );
    expect(identical(afterSwitchDashboard, afterMutationDashboard), isFalse);
    expect(afterMutationDashboard.repository.accounts.length, 1);
  });

  testWidgets(
      'TransactionsV2Screen lazily virtualizes long monthly lists on mobile',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repo = await FinanceRepository.load(database);
    repo = await repo.addAccount(
      const Account(
        id: 'wallet',
        name: '现金钱包',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 20000,
        initialBalance: 20000,
      ),
    );
    repo = await repo.addCategory(
      const Category(id: 'food', name: '餐饮', type: CategoryType.expense),
    );
    final now = DateTime.now();
    final transactions = <FinanceTransaction>[
      for (var i = 1; i <= 120; i++)
        FinanceTransaction(
          id: 'perf-tx-$i',
          type: TransactionType.expense,
          accountId: 'wallet',
          categoryId: 'food',
          amount: 10.0 + (i % 7),
          currency: 'MYR',
          transactionDate: DateTime(
            now.year,
            now.month,
            ((i - 1) % 28) + 1,
            12,
            i % 60,
          ),
          merchant: '虚拟化商户 ${i.toString().padLeft(3, '0')}',
        ),
    ];
    repo = await repo.addTransactions(transactions);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeRepositoryProvider
              .overrideWith(() => _TestRepositoryNotifier(repo)),
        ],
        child: MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.liquidGlass),
          home: Scaffold(body: TransactionsV2Screen(repository: repo)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Newest day (day 28) renders near the top; early-month items are not built yet.
    expect(find.textContaining('28日'), findsWidgets);
    expect(find.text('虚拟化商户 001'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('虚拟化商户 001'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('虚拟化商户 001'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('实际现金'),
      -500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('实际现金'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('monthly-funding-need-note')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
