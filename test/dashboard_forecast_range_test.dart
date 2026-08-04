import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/dashboard/dashboard_v2_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dashboard forecast range can change from 30 to 60 days', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = await FinanceRepository.load(database);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildFinanceTheme(
            AppThemeStyle.abyss,
          ).copyWith(splashFactory: NoSplash.splashFactory),
          home: Scaffold(body: DashboardV2Screen(repository: repository)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('未来 30 天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('未来 60 天').last);
    await tester.pumpAndSettle();

    expect(find.text('未来 60 天'), findsOneWidget);
  });
}
