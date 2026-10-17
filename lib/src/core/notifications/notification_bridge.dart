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
  bool _ready = false;
  bool _disposed = false;
  bool _drainRequested = false;
  bool _reloadNeeded = false;
  Future<void>? _draining;
  Timer? _retry;

  Future<void> start() async {
    if (!supported || _disposed) return;
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addObserver(this);
      channel.setMethodCallHandler((call) async {
        if (call.method == 'available') await drain();
      });
    }
    await drain();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(drain());
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (supported) {
      final config = await _readConfiguration();
      if (_disposed) return;
      enabled = config.enabled;
      bindings = config.bindings;
      permission = config.permission;
      captureFailed =
          await channel.invokeMethod<bool>('captureFailed') ?? false;
    }
    if (_disposed) return;
    items = await bookkeeper.records();
    _notify();
  }

  Future<
      ({
        bool enabled,
        bool permission,
        List<Map<String, dynamic>> bindings,
        Object? version
      })> _readConfiguration() async {
    final raw = await channel.invokeMethod<String>('config');
    final config = jsonDecode(raw ?? '{}') as Map;
    final authorized = await channel.invokeMethod<bool>('permission') ?? false;
    return (
      enabled: config['enabled'] == true,
      permission: authorized,
      bindings: (config['bindings'] as List? ?? [])
          .map((b) => Map<String, dynamic>.from(b as Map))
          .toList(),
      version: config['version'],
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
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

  Future<void> drain() {
    if (!supported || _disposed) return Future.value();
    // A wake while publishing the last batch must trigger another queue read.
    _drainRequested = true;
    return _draining ??= Future<void>.microtask(_drain).whenComplete(() {
      _draining = null;
      _notify();
    });
  }

  Future<void> _drain() async {
    busy = true;
    _notify();
    _retry?.cancel();
    var failed = false;
    try {
      do {
        _drainRequested = false;
        try {
          // Ready belongs to the retryable connection, not just startup.
          if (_started && !_ready && !_disposed) {
            await channel.invokeMethod<void>('ready');
            _ready = true;
          }
          await refresh();
          await _consumeQueue();
        } catch (_) {
          failed = true;
        }

        // ACK and UI publication have independent failure paths. Retain the
        // dirty flag even when the native queue has already been emptied.
        try {
          if (_reloadNeeded && !_disposed) {
            await onChanged();
            _reloadNeeded = false;
          }
        } catch (_) {
          failed = true;
        }
        try {
          await refresh();
        } catch (_) {
          failed = true;
        }
      } while (_drainRequested && !failed && !_disposed);
      error = failed ? '通知同步暂未完成，已保存的记录会保留；30 秒后自动重试，也可点击重试' : null;
      if (failed && !_disposed) {
        _retry = Timer(const Duration(seconds: 30), () => unawaited(drain()));
      }
    } finally {
      busy = false;
    }
  }

  Future<void> _consumeQueue() async {
    while (!_disposed) {
      final pending =
          await channel.invokeMethod<List<dynamic>>('pending') ?? [];
      if (pending.isEmpty) return;
      for (final raw in pending) {
        if (_disposed) return;
        // Re-read both settings and system authorization before every event.
        final config = await _readConfiguration();
        if (_disposed) return;
        final event =
            Map<String, dynamic>.from(jsonDecode(raw as String) as Map);
        event['configurationChanged'] =
            event['configVersion'] != config.version;
        // Keep this event's settings together: a concurrent screen refresh
        // must not replace its account bindings with another configuration.
        await bookkeeper.ingest(event, config.bindings,
            enabled: config.enabled && config.permission);
        _reloadNeeded = true;
        if (_disposed) return;
        await channel.invokeMethod<void>('ack', event['id']);
      }
    }
  }

  Future<void> mutate(Future<void> Function() action) async {
    await action();
    await onChanged();
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      channel.setMethodCallHandler(null);
    }
    super.dispose();
  }
}
