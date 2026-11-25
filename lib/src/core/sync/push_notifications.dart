import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ledger_sync.dart';
import 'push_browser_stub.dart'
    if (dart.library.js_interop) 'push_browser_web.dart' as browser;

class BrowserPushStatus {
  const BrowserPushStatus._({
    required this.supported,
    required this.permission,
    required this.endpoint,
    required this.enabled,
    this.publicKey,
    this.error,
  });

  final bool supported;
  final String permission;
  final String? endpoint;
  final bool enabled;
  final String? publicKey;
  final String? error;
}

class DevicePushNotifications {
  const DevicePushNotifications(this.session);

  final LedgerSyncSession session;

  Future<BrowserPushStatus> inspect() async {
    final raw = jsonDecode(await browser.inspectPushBrowser(session.accountId))
        as Map<String, dynamic>;
    final supported = raw['supported'] == true;
    final permission = raw['permission'] as String;
    final endpoint = raw['endpoint'] as String?;
    final enabled = raw['enabled'] == true;
    String? publicKey;
    String? error;
    if (supported && permission != 'denied' && !enabled) {
      try {
        final config = await _request('GET', 'config', expected: 200);
        publicKey = (jsonDecode(config.body)
            as Map<String, dynamic>)['publicKey'] as String;
      } on SyncException catch (failure) {
        error = failure.message;
      }
    }
    return BrowserPushStatus._(
      supported: supported,
      permission: permission,
      endpoint: endpoint,
      enabled: enabled,
      publicKey: publicKey,
      error: error,
    );
  }

  Future<void> enable(String publicKey) async {
    // Keep the browser subscription call before any await so permission can
    // be requested during the button's direct user gesture, including Safari.
    final started = browser.subscribePushBrowser(session.accountId, publicKey);
    final payload = jsonDecode(await started) as Map<String, dynamic>;
    final subscription = payload['subscription'] as Map<String, dynamic>;
    final endpoint = subscription['endpoint'] as String;
    try {
      await _request('PUT', 'subscription', body: payload);
      browser.confirmPushBrowser(
          session.accountId, endpoint, payload['timezone'] as String);
    } catch (_) {
      // A timed-out write may have committed. Disable delivery locally before
      // attempting to remove that account's entry.
      await _discardFailedEnable();
      rethrow;
    }
  }

  Future<void> _discardFailedEnable() async {
    try {
      await disable();
    } catch (_) {
      // Preserve the original registration error and allow a new attempt.
    }
  }

  Future<void> disable() async {
    await browser.unsubscribePushBrowser(session.accountId);
  }

  Future<void> sendTest(String endpoint) =>
      _request('POST', 'test', body: {'endpoint': endpoint});

  Future<http.Response> _request(
    String method,
    String operation, {
    Map<String, dynamic>? body,
    int expected = 204,
  }) async {
    final request = http.Request(
      method,
      session.api.origin.resolve('/api/sync/v1/push/$operation'),
    )..headers['X-Finance-Account'] = session.accountId;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.bodyBytes = utf8.encode(jsonEncode(body));
    }
    final http.Response response;
    try {
      response = await session.api.client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw const SyncException('连接通知服务超时，请稍后重试。');
    } on http.ClientException {
      throw const SyncException('无法连接通知服务，请检查网络。');
    }
    if (response.statusCode == expected) return response;
    String? code;
    try {
      final payload = jsonDecode(response.body);
      if (payload is Map && payload['error'] is String) {
        code = payload['error'] as String;
      }
    } on FormatException {
      // A reverse proxy can return a non-JSON page.
    }
    final status = response.statusCode;
    final message = switch (code) {
      'account_changed' => '当前登录账号已改变，请重新进入通知设置。',
      'push_subscription_in_use' => '此浏览器的推送属于其他账号。请停用旧订阅后重试。',
      'push_subscription_limit' => '已达到账号可订阅的设备上限。',
      'invalid_timezone' => '无法识别本设备的时区，请检查系统设置。',
      _ => switch (status) {
          401 => '登录已失效，请重新登录后设置推送。',
          404 || 410 when operation == 'test' => '此设备的推送订阅已失效，请停用后重新启用。',
          429 => '发送过于频繁，请稍后再试。',
          503 => '系统推送服务暂不可用。',
          _ => '通知操作未完成，请稍后重试。',
        },
    };
    throw SyncException(message, status: status, code: code);
  }
}

Future<void> disableBrowserPush(LedgerSyncSession session) =>
    DevicePushNotifications(session).disable();

Future<void> reconcileBrowserPush(String accountId,
    {bool verifiedTransition = false}) async {
  try {
    await browser.reconcilePushBrowser(accountId, verifiedTransition);
  } catch (_) {
    // A browser permission failure must not close an authenticated ledger.
  }
}
