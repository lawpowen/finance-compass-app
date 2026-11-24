import 'dart:js_interop';

@JS('FinanceCompassPush')
external JSObject? get _bridge;

@JS('FinanceCompassPush.inspect')
external JSPromise<JSString> _inspect(JSString accountId);

@JS('FinanceCompassPush.subscribe')
external JSPromise<JSString> _subscribe(JSString accountId, JSString publicKey);

@JS('FinanceCompassPush.confirm')
external void _confirm(JSString accountId, JSString endpoint);

@JS('FinanceCompassPush.unsubscribe')
external JSPromise<JSString> _unsubscribe(JSString accountId);

@JS('FinanceCompassPush.reconcile')
external JSPromise<JSAny?> _reconcile(JSString accountId);

Future<String> inspectPushBrowser(String accountId) async {
  if (_bridge == null) return '{"supported":false,"permission":"denied"}';
  final status =
      await _inspect(accountId.toJS).toDart.timeout(const Duration(seconds: 8));
  return status.toDart;
}

Future<String> subscribePushBrowser(String accountId, String publicKey) =>
    _subscribe(accountId.toJS, publicKey.toJS)
        .toDart
        .then((value) => value.toDart);

void confirmPushBrowser(String accountId, String endpoint) =>
    _confirm(accountId.toJS, endpoint.toJS);

Future<String?> unsubscribePushBrowser(String accountId) async {
  if (_bridge == null) return null;
  final endpoint = (await _unsubscribe(accountId.toJS).toDart).toDart;
  return endpoint.isEmpty ? null : endpoint;
}

Future<void> reconcilePushBrowser(String accountId) async {
  if (_bridge == null) return;
  await _reconcile(accountId.toJS).toDart;
}
