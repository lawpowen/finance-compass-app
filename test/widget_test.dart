import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/settings/app_settings_controller.dart';
import 'package:finance_app/src/features/accounts/accounts_v2_screen.dart';
import 'package:finance_app/src/features/home/home_screen.dart';
import 'package:finance_app/src/features/transactions/transactions_v2_screen.dart';

void main() {
  testWidgets('app renders dashboard title', (WidgetTester tester) async {
    await tester.pumpWidget(
      const FinanceAppTestHarness(),
    );
    await tester.pumpAndSettle();

    expect(find.text('财务罗盘'), findsOneWidget);
    expect(_destination('总览'), findsOneWidget);
  });

  testWidgets('bottom dock preserves the active page on resize',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const FinanceAppTestHarness());
    await tester.pumpAndSettle();

    final dock = find.byType(NavigationBar);
    final workspace = find.byType(IndexedStack).first;
    final transactions = find.byType(TransactionsV2Screen);
    expect(dock, findsOneWidget);
    expect(transactions, findsNothing);
    expect(tester.getRect(dock), const Rect.fromLTWH(300, 696, 424, 62));
    expect(tester.getSize(workspace).width, 1024);
    expect(tester.getRect(workspace).bottom, 768);
    final frost =
        find.ancestor(of: dock, matching: find.byType(BackdropFilter));
    expect(frost, findsOneWidget);
    expect(tester.getRect(frost), tester.getRect(dock));
    expect(find.ancestor(of: frost, matching: find.byType(ClipRRect)),
        findsOneWidget);
    expect(tester.widget<NavigationBar>(dock).labelBehavior,
        NavigationDestinationLabelBehavior.alwaysHide);

    await tester.tap(_destination('交易'));
    await tester.pumpAndSettle();
    final transactionsState = tester.state(transactions);
    expect(tester.widget<NavigationBar>(dock).selectedIndex, 2);
    final ledgerList = find
        .descendant(of: transactions, matching: find.byType(ListView))
        .first;
    expect(tester.getRect(ledgerList).bottom, 768);
    expect(tester.widget<ListView>(ledgerList).padding!.vertical,
        greaterThan(tester.getSize(dock).height));

    tester.view.physicalSize = const Size(320, 844);
    tester.view.padding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPadding);
    await tester.pumpAndSettle();
    expect(tester.getRect(dock), const Rect.fromLTWH(10, 752, 300, 58));
    expect(tester.getSize(_destination('设置')).width, greaterThanOrEqualTo(48));
    expect(tester.widget<NavigationBar>(dock).selectedIndex, 2);
    expect(tester.state(transactions), same(transactionsState));

    tester.view.physicalSize = const Size(1920, 1080);
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(dock).selectedIndex, 2);
    expect(tester.state(transactions), same(transactionsState));
    expect(tester.getSize(workspace).width, 1240);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard deep links and detail routes keep the workspace dock',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final navigation = FinanceWorkspaceNavigation();
    await tester.pumpWidget(
      FinanceAppTestHarness(workspaceNavigation: navigation),
    );
    await tester.pumpAndSettle();

    final dock = find.byType(NavigationBar);
    final assetAccounts = find.byKey(const Key('dashboard-asset-accounts'));
    await tester.ensureVisible(assetAccounts);
    await tester.tap(assetAccounts);
    await tester.pumpAndSettle();
    expect(find.byType(AccountsV2Screen), findsOneWidget);
    expect(tester.widget<NavigationBar>(dock).selectedIndex, 1);
    expect(navigation.hasOpenPage, isFalse);

    await tester.tap(_destination('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('版本信息'));
    await tester.pumpAndSettle();
    final about = find.text('关于 Finance Compass');
    expect(about, findsOneWidget);
    expect(dock, findsOneWidget);
    expect(navigation.hasOpenPage, isTrue);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(about, findsOneWidget);
    await tester.tap(_destination('账户'));
    await tester.pumpAndSettle();
    expect(about, findsNothing);
    expect(navigation.hasOpenPage, isTrue);
    await tester.tap(_destination('设置'));
    await tester.pumpAndSettle();
    expect(about, findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(about, findsNothing);
    expect(find.text('版本信息'), findsOneWidget);
    expect(dock, findsOneWidget);
    expect(navigation.hasOpenPage, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'dock hides persistent labels and animates icon lift with floating hover text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const FinanceAppTestHarness());
    await tester.pumpAndSettle();

    final hoverLabel = find.byKey(const Key('compass-dock-hover-label'));
    expect(hoverLabel, findsNothing);

    final dock = find.byType(NavigationBar);
    final dockRect = tester.getRect(dock);
    final iconFinder = find.byKey(const Key('compass-dock-icon-2'));
    final neighbor = find.byKey(const Key('compass-dock-icon-1'));
    final distant = find.byKey(const Key('compass-dock-icon-4'));
    final idleIconRect = tester.getRect(iconFinder);
    final idleNeighborRect = tester.getRect(neighbor);
    final idleDistantRect = tester.getRect(distant);
    final destinations = tester
        .widget<NavigationBar>(dock)
        .destinations
        .cast<NavigationDestination>();
    final transaction = _destination(destinations[2].label);
    final transactionCenter = tester.getCenter(transaction);
    final slotWidth = dockRect.width / destinations.length;
    for (var i = 0; i < destinations.length; i++) {
      final slot = tester.getRect(_destination(destinations[i].label));
      expect(slot.width, closeTo(slotWidth, .001));
      expect(
        slot.center.dx,
        closeTo(dockRect.left + (i + .5) * slotWidth, .001),
      );
    }
    expect(
      tester.widget<NavigationBar>(dock).labelBehavior,
      NavigationDestinationLabelBehavior.alwaysHide,
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(transactionCenter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getRect(iconFinder).top, greaterThan(dockRect.top));
    await tester.pumpAndSettle();

    expect(hoverLabel, findsOneWidget);
    expect(
      find.descendant(
        of: hoverLabel,
        matching: find.text(destinations[2].label),
      ),
      findsOneWidget,
    );
    expect(tester.getRect(hoverLabel).bottom, lessThan(dockRect.top));

    final hoveredIconRect = tester.getRect(iconFinder);
    expect(hoveredIconRect.width, greaterThan(idleIconRect.width));
    expect(hoveredIconRect.center.dy, lessThan(idleIconRect.center.dy));
    expect(tester.getRect(neighbor).width, greaterThan(idleNeighborRect.width));
    expect(
      tester.getRect(neighbor).center.dy,
      lessThan(idleNeighborRect.center.dy),
    );
    expect(tester.getRect(distant), idleDistantRect);

    await gesture.down(transactionCenter);
    await gesture.up();
    await tester.pump();
    expect(tester.widget<NavigationBar>(dock).selectedIndex, 2);
    expect(iconFinder, findsOneWidget);
    expect(
      tester.getRect(iconFinder).center.dy,
      closeTo(hoveredIconRect.center.dy, .001),
    );
    await tester.pumpAndSettle();
    expect(hoverLabel, findsOneWidget);
    expect(tester.getRect(distant), idleDistantRect);

    for (final index in [3, 4, 2]) {
      final destination = _destination(destinations[index].label);
      await gesture.moveTo(tester.getCenter(destination));
      await tester.pump(const Duration(milliseconds: 16));
      expect(hoverLabel, findsOneWidget);
      expect(
        find.descendant(
          of: hoverLabel,
          matching: find.text(destinations[index].label),
        ),
        findsOneWidget,
      );
    }

    await gesture.moveTo(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(hoverLabel, findsNothing);
    expect(tester.getRect(neighbor), idleNeighborRect);
    expect(tester.getRect(distant), idleDistantRect);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile dock applies reduced motion and keeps touch icon-only',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 820);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(size: Size(320, 820), disableAnimations: true),
      child: FinanceAppTestHarness(),
    ));
    await tester.pumpAndSettle();

    final dock = find.byType(NavigationBar);
    final dockRect = tester.getRect(dock);
    final destinations = tester
        .widget<NavigationBar>(dock)
        .destinations
        .cast<NavigationDestination>();
    final first = _destination(destinations.first.label);
    final last = _destination(destinations.last.label);
    final lastIcon = find.byKey(const Key('compass-dock-icon-5'));
    final idleIconRect = tester.getRect(lastIcon);
    final hoverLabel = find.byKey(const Key('compass-dock-hover-label'));
    expect(MediaQuery.disableAnimationsOf(tester.element(dock)), isTrue);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    for (final destination in [first, last]) {
      await mouse.moveTo(tester.getCenter(destination));
      await tester.pump();
      expect(hoverLabel, findsOneWidget);
      final labelRect = tester.getRect(hoverLabel);
      expect(labelRect.left, greaterThanOrEqualTo(dockRect.left));
      expect(labelRect.right, lessThanOrEqualTo(dockRect.right));
      expect(labelRect.bottom, lessThan(dockRect.top));
    }
    final hoveredIconRect = tester.getRect(lastIcon);
    expect(hoveredIconRect.width, greaterThan(idleIconRect.width));
    expect(hoveredIconRect.center.dy, lessThan(idleIconRect.center.dy));
    expect(hoveredIconRect.top, greaterThan(dockRect.top));

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(hoverLabel, findsNothing);
    expect(tester.getRect(lastIcon), idleIconRect);

    final touched = tester.getCenter(_destination(destinations[2].label));
    await tester.tapAt(touched, kind: PointerDeviceKind.touch);
    await tester.pump();
    expect(tester.widget<NavigationBar>(dock).selectedIndex, 2);
    expect(hoverLabel, findsNothing);
    await mouse.moveTo(touched);
    await tester.pump();
    expect(hoverLabel, findsNothing,
        reason: 'a compatibility hover at the tapped location stays hidden');
    await mouse.moveTo(tester.getCenter(last));
    await tester.pump();
    expect(hoverLabel, findsOneWidget,
        reason: 'a distinct mouse position can still reveal its label');
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(hoverLabel, findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Finder _destination(String label) => find.byWidgetPredicate(
      (widget) => widget is NavigationDestination && widget.label == label,
    );

class FinanceAppTestHarness extends StatelessWidget {
  const FinanceAppTestHarness({super.key, this.workspaceNavigation});

  final FinanceWorkspaceNavigation? workspaceNavigation;

  @override
  Widget build(BuildContext context) {
    final settingsController = AppSettingsController();
    final repository = FinanceRepository.preview();
    return ProviderScope(
      overrides: [
        financeRepositoryProvider.overrideWith(() {
          final notifier = _TestFinanceRepositoryNotifier(repository);
          return notifier;
        }),
      ],
      child: MaterialApp(
        home: HomeScreen(
          settingsController: settingsController,
          workspaceNavigation: workspaceNavigation,
        ),
      ),
    );
  }
}

class _TestFinanceRepositoryNotifier extends FinanceRepositoryNotifier {
  final FinanceRepository _repository;

  _TestFinanceRepositoryNotifier(this._repository);

  @override
  Future<FinanceRepository> build() async => _repository;
}
