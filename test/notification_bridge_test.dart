import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/notifications/notification_bookkeeper.dart';
import 'package:finance_app/src/core/notifications/notification_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late NotificationBridge bridge;
  late List<String> queue;
  var permission = true;
  var failReady = false;
  var failReload = false;
  var readyCalls = 0;
  var reloadCalls = 0;
  var accountId = 'bank';
  var configVersion = 1;
  var disposed = false;
  Future<void> Function(String)? onAck;
  Future<void> Function()? onCaptureStatus;
  Future<void> Function()? onConfig;
  Future<void> Function()? onPermission;

  String event(String id, double amount) => jsonEncode({
        'id': id,
        'key': id,
        'package': 'example.bank',
        'title': 'Payment',
        'text':
            'Payment of MYR ${amount.toStringAsFixed(2)} to SHOP was successful. Ref: REF123$id Card: **1234',
        'postedAt': DateTime.now().millisecondsSinceEpoch,
        'configVersion': 1,
      });

  setUp(() async {
    queue = [];
    permission = true;
    failReady = false;
    failReload = false;
    readyCalls = 0;
    reloadCalls = 0;
    accountId = 'bank';
    configVersion = 1;
    disposed = false;
    onAck = null;
    onCaptureStatus = null;
    onConfig = null;
    onPermission = null;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.insertAccount(const Account(
      id: 'bank',
      name: 'Bank',
      accountType: AccountType.bankSaving,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      initialBalance: 100,
      currentBalance: 100,
    ));
    bridge = NotificationBridge(NotificationBookkeeper(db), () async {
      reloadCalls++;
      if (failReload) throw StateError('Repository unavailable');
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NotificationBridge.channel, (call) async {
      switch (call.method) {
        case 'ready':
          readyCalls++;
          if (failReady) throw PlatformException(code: 'not_ready');
          return null;
        case 'config':
          await onConfig?.call();
          return jsonEncode({
            'enabled': true,
            'version': configVersion,
            'bindings': [
              {
                'package': 'example.bank',
                'accountId': accountId,
                'marker': 'Card: **1234'
              }
            ],
          });
        case 'permission':
          await onPermission?.call();
          return permission;
        case 'captureFailed':
          await onCaptureStatus?.call();
          return false;
        case 'pending':
          return [...queue];
        case 'ack':
          final id = call.arguments as String;
          queue.removeWhere((s) => (jsonDecode(s) as Map)['id'] == id);
          await onAck?.call(id);
          return null;
      }
      return null;
    });
  });

  tearDown(() async {
    if (!disposed) bridge.dispose();
    await db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NotificationBridge.channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  androidTest('failed startup retries the native ready handshake', () async {
    failReady = true;
    await bridge.start();
    expect(bridge.error, isNotNull);
    expect(readyCalls, 1);
    failReady = false;
    await bridge.drain();
    expect(readyCalls, 2);
    expect(bridge.error, isNull);
    expect(bridge.busy, isFalse);
  });

  androidTest(
      'permission revoked between events sends the remaining event to review',
      () async {
    queue.addAll([event('one', 10), event('two', 20)]);
    onAck = (id) async {
      if (id == 'one') permission = false;
    };
    await bridge.start();
    expect((await bridge.bookkeeper.record('one'))!['state'], 'posted');
    expect((await bridge.bookkeeper.record('two'))!['state'], 'pending');
    expect((await db.fetchTransactions()).length, 1);
    expect((await db.fetchAccounts()).single.currentBalance, 90);
    expect(bridge.permission, isFalse);
    expect(queue, isEmpty);
  });

  androidTest(
      'repository refresh failure remains retryable after the queue is acknowledged',
      () async {
    queue.add(event('one', 10));
    failReload = true;
    await bridge.drain();
    expect(queue, isEmpty);
    expect(bridge.error, isNotNull);
    expect(bridge.busy, isFalse);
    expect(bridge.items.single['state'], 'posted');
    failReload = false;
    await bridge.drain();
    expect(reloadCalls, 2);
    expect(bridge.error, isNull);
    expect((await db.fetchTransactions()).length, 1);
    expect((await db.fetchAccounts()).single.currentBalance, 90);
  });

  androidTest('wake during final refresh drains the newly arrived event',
      () async {
    queue.add(event('one', 10));
    var injectArrival = false;
    var injected = false;
    onAck = (id) async {
      if (id == 'one') injectArrival = true;
    };
    onCaptureStatus = () async {
      if (injectArrival && !injected) {
        injected = true;
        queue.add(event('two', 20));
        unawaited(bridge.drain());
      }
    };
    await bridge.drain();
    expect(injected, isTrue);
    expect(queue, isEmpty);
    expect((await db.fetchTransactions()).length, 2);
    expect((await db.fetchAccounts()).single.currentBalance, 70);
    expect(bridge.busy, isFalse);
  });

  androidTest(
      'concurrent settings refresh cannot swap the account of an in-flight event',
      () async {
    await db.insertAccount(const Account(
      id: 'other',
      name: 'Other',
      accountType: AccountType.bankSaving,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      initialBalance: 100,
      currentBalance: 100,
    ));
    queue.add(event('one', 10));
    var permissionCalls = 0;
    onPermission = () async {
      permissionCalls++;
      if (permissionCalls == 2) {
        accountId = 'other';
        configVersion = 2;
        await bridge.refresh();
      }
    };
    await bridge.drain();
    expect((await db.fetchTransactions()).single.accountId, 'bank');
    final accounts = await db.fetchAccounts();
    expect(accounts.singleWhere((a) => a.id == 'bank').currentBalance, 90);
    expect(accounts.singleWhere((a) => a.id == 'other').currentBalance, 100);
  });

  testWidgets('startup reconnects automatically after the 30 second backoff',
      (tester) async {
    failReady = true;
    await bridge.start();
    failReady = false;
    await tester.pump(const Duration(seconds: 29));
    expect(readyCalls, 1);
    await tester.pump(const Duration(seconds: 1));
    await bridge.drain();
    expect(readyCalls, 2);
    expect(bridge.error, isNull);
    expect(bridge.busy, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  androidTest(
      'disposing during a native call leaves the queue intact without notifying listeners',
      () async {
    queue.add(event('one', 10));
    final entered = Completer<void>();
    final release = Completer<void>();
    onConfig = () async {
      entered.complete();
      await release.future;
    };
    var notificationsAfterDispose = 0;
    bridge.addListener(() {
      if (disposed) notificationsAfterDispose++;
    });
    final draining = bridge.drain();
    await entered.future;
    bridge.dispose();
    disposed = true;
    release.complete();
    await draining;
    expect(notificationsAfterDispose, 0);
    expect(queue.length, 1);
    expect(await db.fetchTransactions(), isEmpty);
    expect(bridge.busy, isFalse);
  });
}

void androidTest(String description, Future<void> Function() body) {
  test(description, () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await body();
  });
}
