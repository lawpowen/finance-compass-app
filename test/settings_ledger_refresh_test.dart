import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/database_provider.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/settings/app_settings_controller.dart';
import 'package:finance_app/src/core/sync/ledger_outbox.dart';
import 'package:finance_app/src/core/sync/ledger_sync.dart';
import 'package:finance_app/src/features/settings/settings_reference_pages.dart';
import 'package:finance_app/src/features/settings/settings_screen.dart';
import 'package:finance_app/src/features/shared/compass_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
      'saving the gateway queues a ledger write which reopens on another client',
      (tester) async {
    final upload = Completer<void>();
    Map<String, dynamic>? remote;
    final client = MockClient((request) async {
      expect(request.headers['X-Finance-Account'], '1');
      if (request.method == 'PUT') {
        await upload.future;
        remote = (jsonDecode(request.body) as Map)['snapshot']
            as Map<String, dynamic>;
        return http.Response('{"revision":1}', 200);
      }
      return http.Response.bytes(
          utf8.encode(jsonEncode({
            'accountId': '1',
            'username': 'one',
            'revision': 1,
            'snapshot': remote,
          })),
          200);
    });
    addTearDown(client.close);
    final api = LedgerSyncApi(client, Uri.https('ledger.test'));
    final outbox = MemoryLedgerOutboxStore();
    const firstRevision =
        (accountId: '1', username: 'one', revision: 0, snapshot: null);
    final sync = LedgerSyncSession(api, firstRevision, outboxStore: outbox);
    addTearDown(sync.dispose);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final outerDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(outerDb.close);
    final outer = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(outerDb)]);
    addTearDown(outer.dispose);
    await outer.read(financeRepositoryProvider.future);
    final scope = ProviderContainer(parent: outer, overrides: [
      appDatabaseProvider.overrideWithValue(db),
      ledgerSyncSessionProvider.overrideWithValue(sync),
    ]);
    addTearDown(scope.dispose);
    final repo = await scope.read(financeRepositoryProvider.future);
    final settings = AppSettingsController(database: db);
    addTearDown(settings.dispose);
    await _mount(tester, scope,
        SettingsScreen(repository: repo, settingsController: settings));
    final gateway = find.widgetWithText(TextField, '网关地址');
    await tester.scrollUntilVisible(gateway, 480,
        scrollable: find.byType(Scrollable).first);
    const url = 'https://analysis.example.test';
    await tester.enterText(gateway, url);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    final save = find.widgetWithText(FilledButton, '保存');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final queued = await outbox.read('1', 'one');
    expect(queued!.head.snapshot['meta']['ai_gateway_url'], url);
    expect(
        (await scope.read(financeRepositoryProvider.future)).aiGatewayUrl, url);
    expect(await outerDb.getMetaValue('ai_gateway_url'), isNull);
    upload.complete();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(await outbox.read('1', 'one'), isNull);
    final reopened = LedgerSyncSession(api, firstRevision);
    addTearDown(reopened.dispose);
    final secondDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(secondDb.close);
    final second =
        await reopened.refresh(await FinanceRepository.load(secondDb));
    expect(second.aiGatewayUrl, url);
  });

  testWidgets(
      'currency settings observe child edits and preserve unrelated drafts',
      (tester) async {
    final (scope, repo) = await _local();
    final settings = AppSettingsController(database: repo.database);
    addTearDown(settings.dispose);
    await _mount(tester, scope,
        CurrencyDisplayPage(repository: repo, settingsController: settings));
    await tester.tap(find.text('主币种'));
    await tester.pumpAndSettle();
    final usd = find.byKey(const ValueKey('exchange-rate-USD'));
    final scroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(usd, 200, scrollable: scroll);
    await tester.enterText(usd, '5.25');
    await scope.read(financeRepositoryProvider.notifier).mutate((repo) => repo
        .updateExchangeRates(
            {...repo.exchangeRatesToBase, 'CNY': .7}, repo.currencyPriority));
    await tester.pump();
    expect(tester.widget<TextField>(usd).controller!.text, '5.25');
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('exchange-rate-CNY')))
            .controller!
            .text,
        '0.7');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, '保存汇率和优先级');
    await tester.scrollUntilVisible(save, 180, scrollable: scroll);
    await tester.pumpAndSettle();
    expect(save.hitTestable(), findsOneWidget);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final saved = await scope.read(financeRepositoryProvider.future);
    expect(saved.exchangeRatesToBase['USD'], 5.25);
    expect(saved.exchangeRatesToBase['CNY'], .7);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('1 USD = MYR 5.2500'), findsOneWidget);
  });

  testWidgets('rules and local account counts follow the published ledger',
      (tester) async {
    final (scope, repo) = await _local();
    await _mount(tester, scope, FinanceRulesCenterPage(repository: repo));
    await tester.tap(find.text('类别管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_rounded).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Utilities');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.tap(find.text('保存').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CompassBackButton).first);
    await tester.pumpAndSettle();
    expect(find.text('1 个'), findsOneWidget);

    await _mount(tester, scope, AccountSyncPage(repository: repo));
    await scope.read(financeRepositoryProvider.notifier).mutate((repo) async {
      final withAccount = await repo.addAccount(const Account(
          id: 'wallet',
          name: 'Cash',
          accountType: AccountType.cash,
          reportGroup: ReportGroup.cash,
          currency: 'MYR',
          currentBalance: 0));
      return withAccount.addTransaction(FinanceTransaction(
          id: 'salary',
          accountId: 'wallet',
          type: TransactionType.income,
          currency: 'MYR',
          amount: 12,
          transactionDate: DateTime(2026, 11, 1)));
    });
    await tester.pump();
    expect(find.text('1 条交易仅保存在此设备'), findsOneWidget);
  });
}

Future<(ProviderContainer, FinanceRepository)> _local() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final scope =
      ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
  addTearDown(scope.dispose);
  return (scope, await scope.read(financeRepositoryProvider.future));
}

Future<void> _mount(
    WidgetTester tester, ProviderContainer scope, Widget page) async {
  tester.view.physicalSize = const Size(520, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: scope, child: MaterialApp(home: Scaffold(body: page))));
  await tester.pumpAndSettle();
}
