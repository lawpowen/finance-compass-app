import 'dart:js_interop';

@JS('FinanceCompassLedgerOutbox.read')
external JSPromise<_StoredOutbox> _read(JSString accountId, JSString username);

@JS('FinanceCompassLedgerOutbox.replace')
external JSPromise<JSBoolean> _replace(
  JSString accountId,
  JSString username,
  JSString? expectedIdentity,
  JSString? nextIdentity,
  JSString? payload,
);

extension type _StoredOutbox(JSObject _) implements JSObject {
  external JSBoolean get conflict;
  external JSString? get payload;
  external JSString? get identity;
}

Future<({bool conflict, String? payload, String? identity})> readOutbox(
  String accountId,
  String username,
) async {
  final result = await _read(accountId.toJS, username.toJS).toDart;
  return (
    conflict: result.conflict.toDart,
    payload: result.payload?.toDart,
    identity: result.identity?.toDart,
  );
}

Future<bool> replaceOutbox(
  String accountId,
  String username,
  String? expectedIdentity,
  String? nextIdentity,
  String? payload,
) async {
  final replaced = await _replace(
    accountId.toJS,
    username.toJS,
    expectedIdentity?.toJS,
    nextIdentity?.toJS,
    payload?.toJS,
  ).toDart;
  return replaced.toDart;
}
