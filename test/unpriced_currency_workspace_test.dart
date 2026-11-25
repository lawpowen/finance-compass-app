import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/settings/app_settings_controller.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/home/home_screen.dart';
import 'package:finance_app/src/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Ledger extends FinanceRepositoryNotifier {
  _Ledger(this.initial);
  final FinanceRepository initial;

  @override
  Future<FinanceRepository> build() async => initial;
}

void main() {
  testWidgets(
      'a missing historical quote is visible and can be supplied from the workspace',
      (tester) async {
    tester.view.physicalSize = const Size(320, 840);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await FinanceRepository.load(db);
    for (final (code, amount) in [('MYR', 100.0), ('EUR', 25.0)]) {
      repo = await repo.addAccount(Account(
        id: code,
        name: '$code cash',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: code,
        initialBalance: amount,
        currentBalance: amount,
      ));
    }
    repo = await repo.addAssetGoal(name: 'Target', amount: 180);
    final container = ProviderContainer(overrides: [
      financeRepositoryProvider.overrideWith(() => _Ledger(repo)),
    ]);
    addTearDown(container.dispose);
    final settings = AppSettingsController(database: db);
    addTearDown(settings.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.abyss),
          home: HomeScreen(settingsController: settings)),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('EUR 未估值'), findsOneWidget);
    expect(repo.assetGoalSummaries().single.valuationAvailable, isFalse);
    await tester.tap(find.text('设置汇率'));
    await tester.pumpAndSettle();
    final scroll = find
        .descendant(
            of: find.byType(SettingsScreen), matching: find.byType(Scrollable))
        .first;
    final quote = find.byKey(const ValueKey('exchange-rate-EUR'));
    await tester.scrollUntilVisible(quote, 150, scrollable: scroll);
    await tester.enterText(quote, '4');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final save = find.text('保存汇率和优先级');
    await tester.scrollUntilVisible(save, 120, scrollable: scroll);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final updated = await container.read(financeRepositoryProvider.future);
    expect(updated.unpricedCurrencies, isEmpty);
    expect(updated.totalAssets(), 200);
    expect(updated.assetGoalSummaries().single.isReached, isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('missing-exchange-rates')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
