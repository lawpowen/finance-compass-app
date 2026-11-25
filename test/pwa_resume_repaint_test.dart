import 'dart:async';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/providers/database_provider.dart';
import 'package:finance_app/src/core/settings/app_settings_controller.dart';
import 'package:finance_app/src/features/sync/finance_sync_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('resume repaints an idle app surface and retains the open route',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = AppSettingsController(database: db);
    addTearDown(settings.dispose);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: FinanceSyncGate(settingsController: settings, localOnly: true),
    ));
    await tester.pumpAndSettle();

    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    final route = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Open ledger detail')),
    );
    unawaited(navigator.push(route));
    await tester.pumpAndSettle();
    var paints = 0;
    void onPaint(PaintingContext context, Offset offset, RenderView view) {
      paints++;
    }

    RenderView.debugAddPaintCallback(onPaint);
    addTearDown(() => RenderView.debugRemovePaintCallback(onPaint));
    void returnToApp() {
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    returnToApp();
    returnToApp();
    await tester.pump();
    expect(paints, 1);
    expect(route.isCurrent, isTrue);
    expect(find.text('Open ledger detail'), findsOneWidget);
    await tester.pump();
    expect(paints, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final afterDisposal = paints;
    returnToApp();
    await tester.pump();
    expect(paints, afterDisposal);
  });
}
