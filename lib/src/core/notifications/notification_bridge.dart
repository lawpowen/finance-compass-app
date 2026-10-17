import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/database_provider.dart';
import '../providers/repository_provider.dart';
import 'notification_bookkeeper.dart';

final notificationBridgeProvider =
    ChangeNotifierProvider<NotificationBridge>((ref) {
  final bridge = NotificationBridge(
    NotificationBookkeeper(ref.read(appDatabaseProvider)),
    () => ref.read(financeRepositoryProvider.notifier).reload(),
  );
  return bridge;
});

class NotificationBridge extends ChangeNotifier with WidgetsBindingObserver {
  NotificationBridge(this.bookkeeper, this.onChanged);
  static const channel =
      MethodChannel('finance_compass/notification_bookkeeping');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  final NotificationBookkeeper bookkeeper;
  final Future<void> Function() onChanged;
  bool enabled = false;
  bool permission = false;
  bool busy = false;
  bool captureFailed = false;
  String? error;
  List<Map<String, dynamic>> bindings = [];
  List<Map<String, dynamic>> items = [];
  bool _started = false;
  Future<void>? _draining;
  Timer? _retry;

  Future<void> start() async {
    if (!supported || _started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    channel.setMethodCallHandler((call) async {
      if (call.method == 'available') await drain();
    });
    try {
      await refresh();
      await channel.invokeMethod<void>('ready');
      await drain();
    } catch (_) {
      error = '通知服务连接失败，请重新打开应用';
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(drain());
  }

  Future<void> refresh() async {
    if (supported) {
      final raw = await channel.invokeMethod<String>('config');
      final config = jsonDecode(raw ?? '{}') as Map;
      enabled = config['enabled'] == true;
      bindings = (config['bindings'] as List? ?? [])
          .map((b) => Map<String, dynamic>.from(b as Map))
          .toList();
      permission = await channel.invokeMethod<bool>('permission') ?? false;
      captureFailed =
          await channel.invokeMethod<bool>('captureFailed') ?? false;
    }
    items = await bookkeeper.records();
    notifyListeners();
  }

  Future<void> configure(
      {bool? active, List<Map<String, dynamic>>? sources}) async {
    await channel.invokeMethod<void>(
        'configure',
        jsonEncode({
          'enabled': active ?? enabled,
          'bindings': sources ?? bindings,
        }));
    await refresh();
  }

  Future<void> openPermission() => channel.invokeMethod<void>('openPermission');

  Future<List<Map<String, dynamic>>> apps() async {
    final result = await channel.invokeMethod<List<dynamic>>('apps') ?? [];
    return result.map((a) => Map<String, dynamic>.from(a as Map)).toList();
  }

  Future<void> drain() =>
      _draining ??= _drain().whenComplete(() => _draining = null);

  Future<void> _drain() async {
    if (!supported) return;
    busy = true;
    notifyListeners();
    var changed = false;
    try {
      await refresh();
      while (true) {
        final pending =
            await channel.invokeMethod<List<dynamic>>('pending') ?? [];
        if (pending.isEmpty) break;
        for (final raw in pending) {
          // Re-read device settings before each event: pause/rebinding must
          // apply even while a backlog is being drained.
          final config =
              jsonDecode(await channel.invokeMethod<String>('config') ?? '{}')
                  as Map;
          enabled = config['enabled'] == true;
          bindings = (config['bindings'] as List? ?? [])
              .map((b) => Map<String, dynamic>.from(b as Map))
              .toList();
          final event =
              Map<String, dynamic>.from(jsonDecode(raw as String) as Map);
          event['configurationChanged'] =
              event['configVersion'] != config['version'];
          await bookkeeper.ingest(event, bindings,
              enabled: enabled && permission);
          changed = true;
          await channel.invokeMethod<void>('ack', event['id']);
        }
      }
      error = null;
      _retry?.cancel();
    } catch (_) {
      error = '通知处理失败，原通知队列已保留；可点击重试';
      _retry?.cancel();
      _retry = Timer(const Duration(seconds: 30), () => unawaited(drain()));
    } finally {
      if (changed) await onChanged();
      try {
        await refresh();
      } catch (_) {
        error ??= '读取通知记录失败，请重试';
      }
      busy = false;
      notifyListeners();
    }
  }

  Future<void> mutate(Future<void> Function() action) async {
    await action();
    await onChanged();
    await refresh();
  }

  @override
  void dispose() {
    _retry?.cancel();
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      channel.setMethodCallHandler(null);
    }
    super.dispose();
  }
}
