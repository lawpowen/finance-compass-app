import 'dart:convert';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/notifications/notification_bookkeeper.dart';
import 'package:finance_app/src/core/notifications/notification_bridge.dart';
import 'package:finance_app/src/core/notifications/notification_sources.dart';
import 'package:finance_app/src/core/providers/database_provider.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/settings/notification_bookkeeping_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late ProviderContainer container;
  late Map<String, dynamic> config;
  late List<String> queue;
  late List<Map<String, String>> installedApps;
  var failAck = false;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.insertAccount(const Account(
        id: 'bank',
        name: '测试银行',
        accountType: AccountType.bankSaving,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        initialBalance: 100,
        currentBalance: 100));
    container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)]);
    config = {
      'enabled': true,
      'bindings': [
        {
          'package': 'example.bank',
          'label': '银行应用',
          'accountName': '测试银行',
          'accountId': 'bank',
          'marker': 'Card: **1234'
        }
      ]
    };
    queue = [];
    installedApps = [
      {'package': 'other.bank', 'label': '另一个银行'},
      {'package': tngEwalletPackage, 'label': 'TNG eWallet'},
    ];
    failAck = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NotificationBridge.channel, (call) async {
      switch (call.method) {
        case 'config':
          return jsonEncode(config);
        case 'configure':
          config = Map<String, dynamic>.from(
              jsonDecode(call.arguments as String) as Map);
          return null;
        case 'permission':
          return true;
        case 'captureFailed':
          return false;
        case 'pending':
          return [...queue];
        case 'ack':
          if (failAck) throw PlatformException(code: 'test_failure');
          queue.removeWhere(
              (s) => (jsonDecode(s) as Map)['id'] == call.arguments);
          return null;
        case 'apps':
          return installedApps;
        case 'ready':
          return null;
      }
      return null;
    });
  });
  tearDown(() async {
    container.dispose();
    await db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NotificationBridge.channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  Map<String, dynamic> sample(String text) => {
        'id': 'one',
        'key': 'key',
        'package': 'example.bank',
        'title': 'Payment',
        'text': text,
        'postedAt': DateTime.now().millisecondsSinceEpoch
      };

  Future<void> open(WidgetTester tester,
      {Size size = const Size(375, 812),
      double scale = 1,
      AppThemeStyle theme = AppThemeStyle.abyss}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await container.read(financeRepositoryProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: buildFinanceTheme(theme),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true),
                child: child!),
            home: const NotificationBookkeepingPage())));
    await tester.pumpAndSettle();
  }

  androidTestWidgets('pause persists and pending review can be ignored',
      (tester) async {
    await NotificationBookkeeper(db).ingest(
        sample('Unknown MYR 12.34 Card: **1234'),
        (config['bindings'] as List).cast<Map<String, dynamic>>(),
        enabled: true);
    await open(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(config['enabled'], isFalse);
    await tester.tap(find.text('待确认 1'));
    await tester.pumpAndSettle();
    expect(find.text('核对并记账'), findsOneWidget);
    await tester.tap(find.text('忽略'));
    await tester.pumpAndSettle();
    expect(
        (await NotificationBookkeeper(db).record('one'))!['state'], 'ignored');
    expect((await db.fetchAccounts()).single.currentBalance, 100);
    expect(tester.takeException(), isNull);
  });

  androidTestWidgets('manual review saves exactly one actual entry',
      (tester) async {
    await NotificationBookkeeper(db).ingest(
        sample('Unknown MYR 12.34 Card: **1234'),
        (config['bindings'] as List).cast<Map<String, dynamic>>(),
        enabled: true);
    await open(tester);
    await tester.tap(find.text('待确认 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('核对并记账'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    final save = find.widgetWithText(FilledButton, '保存');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect((await db.fetchTransactions()).length, 1);
    expect((await db.fetchAccounts()).single.currentBalance,
        closeTo(87.66, 0.001));
    expect(tester.takeException(), isNull);
  });

  androidTestWidgets('source binding persists selected app account and marker',
      (tester) async {
    await open(tester);
    await tester.ensureVisible(find.text('绑定通知来源与账户'));
    await tester.tap(find.text('绑定通知来源与账户'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('另一个银行').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试银行 · MYR').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Account: **5678');
    await tester.tap(find.text('保存绑定'));
    await tester.pumpAndSettle();
    final sources = config['bindings'] as List;
    expect(sources.length, 2);
    expect(sources.last['package'], 'other.bank');
    expect(sources.last['accountId'], 'bank');
    expect(sources.last['marker'], 'Account: **5678');
    expect(sources.last['reviewOnly'], isFalse);
    expect(tester.takeException(), isNull);
  });

  androidTestWidgets(
      'source without a sample must opt into review before saving',
      (tester) async {
    await open(tester);
    await tester.ensureVisible(find.text('绑定通知来源与账户'));
    await tester.tap(find.text('绑定通知来源与账户'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('另一个银行').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试银行 · MYR').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存绑定'));
    await tester.pumpAndSettle();
    expect(find.text('请输入至少 4 个字符的独有片段'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(SwitchListTile, '仅收集到待确认'));
    await tester.tap(find.widgetWithText(SwitchListTile, '仅收集到待确认'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存绑定'));
    await tester.pumpAndSettle();
    final binding = (config['bindings'] as List).last as Map;
    expect(binding['package'], 'other.bank');
    expect(binding['marker'], isEmpty);
    expect(binding['reviewOnly'], isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final source in malaysiaBankNotificationSources) {
    androidTestWidgets(
        '${source.appName} binds without a sample with review locked',
        (tester) async {
      // Only installed apps may appear; localized labels resolve by package.
      installedApps = [
        {'package': source.packageName, 'label': '本机银行应用名称'},
      ];
      await open(tester);
      await tester.ensureVisible(find.text('绑定通知来源与账户'));
      await tester.tap(find.text('绑定通知来源与账户'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      expect(find.text('TNG eWallet'), findsNothing);
      await tester.tap(find.text(source.appName).last);
      await tester.pumpAndSettle();
      expect(find.text('通知中的账户识别片段（可选）'), findsOneWidget);
      final toggle = tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, '仅收集到待确认'));
      expect(toggle.value, isTrue);
      expect(toggle.onChanged, isNull);
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('测试银行 · MYR').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存绑定'));
      await tester.pumpAndSettle();
      final binding = (config['bindings'] as List).last as Map;
      expect(binding['package'], source.packageName);
      expect(binding['label'], source.appName);
      expect(binding['accountId'], 'bank');
      expect(binding['marker'], isEmpty);
      expect(binding['reviewOnly'], isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  androidTestWidgets('old bank bindings display effective review policy',
      (tester) async {
    final source = malaysiaBankNotificationSources.first;
    config['bindings'] = [
      ...config['bindings'] as List,
      {
        'package': source.packageName,
        'label': '旧显示名称',
        'accountId': 'bank',
        'accountName': '测试银行',
        'marker': 'Card: **1234',
        'reviewOnly': false,
      }
    ];
    await open(tester);
    await tester.scrollUntilVisible(find.text(source.appName), 200,
        scrollable: find
            .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable))
            .first);
    final tile = find.ancestor(
        of: find.text(source.appName), matching: find.byType(ListTile));
    expect(find.descendant(of: tile, matching: find.textContaining('仅收集到待确认')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final theme in [AppThemeStyle.abyss, AppThemeStyle.sky]) {
    for (final size in [
      const Size(375, 812),
      const Size(812, 375),
      const Size(1024, 768)
    ]) {
      androidTestWidgets(
          'settings fits $size in $theme with large text and reduced motion',
          (tester) async {
        final source = malaysiaBankNotificationSources
            .firstWhere((s) => s.institution == 'Hong Leong Bank');
        installedApps = [
          {'package': source.packageName, 'label': source.appName}
        ];
        await open(tester, size: size, scale: 2, theme: theme);
        expect(find.text('通知记账'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('绑定通知来源与账户'), 200,
            scrollable: find
                .descendant(
                    of: find.byType(ListView).first,
                    matching: find.byType(Scrollable))
                .first);
        await tester.ensureVisible(find.text('绑定通知来源与账户'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('绑定通知来源与账户'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(source.appName).last);
        await tester.pumpAndSettle();
        expect(find.text('通知中的账户识别片段（可选）'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
      });
    }
  }

  androidTestWidgets('source catalog expands without offering uninstalled apps',
      (tester) async {
    installedApps = [];
    await open(tester);
    await tester.scrollUntilVisible(find.text('银行与钱包接入范围'), 200,
        scrollable: find
            .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('银行与钱包接入范围'));
    await tester.pumpAndSettle();
    for (final source in reviewOnlyNotificationSources) {
      expect(find.text(source.institution), findsOneWidget);
    }
    await tester.ensureVisible(find.text('绑定通知来源与账户'));
    await tester.tap(find.text('绑定通知来源与账户'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('未找到可绑定的应用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  androidTestWidgets(
      'TNG can be bound without a sample and always requires review',
      (tester) async {
    await open(tester);
    await tester.ensureVisible(find.text('绑定通知来源与账户'));
    await tester.tap(find.text('绑定通知来源与账户'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('TNG eWallet').last);
    await tester.pumpAndSettle();
    final review = tester
        .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '仅收集到待确认'));
    expect(review.value, isTrue);
    expect(review.onChanged, isNull);
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试银行 · MYR').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存绑定'));
    await tester.pumpAndSettle();
    final binding = (config['bindings'] as List).last as Map;
    expect(binding['package'], tngEwalletPackage);
    expect(binding['marker'], isEmpty);
    expect(binding['reviewOnly'], isTrue);
    expect(tester.takeException(), isNull);
  });

  test('ack failure retries without a second debit and refreshes repository',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    queue.add(jsonEncode(sample(
        'Payment of MYR 12.34 to SHOP was successful. Ref: ABC12345 Card: **1234')));
    final bridge = container.read(notificationBridgeProvider);
    failAck = true;
    await bridge.drain();
    expect(bridge.error, isNotNull);
    expect(queue.length, 1);
    expect((await db.fetchTransactions()).length, 1);
    failAck = false;
    await bridge.drain();
    expect(queue, isEmpty);
    expect(bridge.error, isNull);
    expect((await db.fetchTransactions()).length, 1);
    expect(
        (await container.read(financeRepositoryProvider.future))
            .accounts
            .single
            .currentBalance,
        closeTo(87.66, 0.001));
  });
}

void androidTestWidgets(
    String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, body,
      variant: TargetPlatformVariant.only(TargetPlatform.android));
}
