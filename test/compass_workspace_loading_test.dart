import 'dart:async';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/settings/app_settings_controller.dart';
import 'package:finance_app/src/features/home/home_screen.dart';
import 'package:finance_app/src/features/shared/compass_loading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('first ledger open reveals real data as soon as it arrives',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = await FinanceRepository.load(database);
    final notifier = _DeferredRepository();
    await _mountHome(tester, notifier);

    expect(find.byType(CompassWorkspaceLoading), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 110));
    notifier.initial.complete(repository);
    await tester.idle();
    await tester.pump();
    expect(find.byType(CompassWorkspaceLoading), findsNothing);
    expect(find.text('财务罗盘'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(_workspaceOpacity(tester), lessThan(1));

    await tester.pump(const Duration(milliseconds: 240));
    expect(_workspaceOpacity(tester), 1);
    notifier.publish(await repository.refresh());
    await tester.pump();
    expect(find.byType(CompassWorkspaceLoading), findsNothing);
    expect(_workspaceOpacity(tester), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion displays the placeholder and ledger statically',
      (tester) async {
    final repository = FinanceRepository.preview();
    addTearDown(repository.database.close);
    final notifier = _DeferredRepository();
    await _mountHome(tester, notifier, disableAnimations: true);
    final skeleton = find.descendant(
      of: find.byType(CompassWorkspaceLoading),
      matching: find.byType(Opacity),
    );
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.widget<Opacity>(skeleton).opacity, 1);

    notifier.initial.complete(repository);
    await tester.idle();
    await tester.pump();
    expect(find.byType(CompassWorkspaceLoading), findsNothing);
    expect(_workspaceOpacity(tester), 1);
  });
}

Future<void> _mountHome(
  WidgetTester tester,
  _DeferredRepository notifier, {
  bool disableAnimations = false,
}) async {
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [financeRepositoryProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
        home: HomeScreen(settingsController: settings),
      ),
    ),
  );
}

double _workspaceOpacity(WidgetTester tester) {
  final workspace = find.byWidgetPredicate((widget) {
    if (widget is! Opacity) return false;
    final transform = widget.child;
    return transform is Transform && transform.child is IndexedStack;
  });
  return tester.widget<Opacity>(workspace).opacity;
}

class _DeferredRepository extends FinanceRepositoryNotifier {
  final initial = Completer<FinanceRepository>();

  @override
  Future<FinanceRepository> build() => initial.future;

  void publish(FinanceRepository repository) => state = AsyncData(repository);
}
