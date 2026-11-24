import 'dart:async';
import 'dart:js_interop';

import 'package:drift/wasm.dart';
import 'package:sqlite3/wasm.dart';

import '../database/app_database.dart';

Future<AppDatabase> openSyncDatabase() async {
  final sqlite =
      await WasmSqlite3.loadFromUrl(Uri.base.resolve('/sqlite3.wasm'));
  sqlite.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
  return AppDatabase.withExecutor(WasmDatabase.inMemory(sqlite));
}

@JS('window.addEventListener')
external void _addEventListener(JSString type, JSFunction callback);

@JS('window.removeEventListener')
external void _removeEventListener(JSString type, JSFunction callback);

extension type _BeforeUnloadEvent(JSObject _) implements JSObject {
  external void preventDefault();
  external set returnValue(JSString value);
}

final _beforeUnload = ((_BeforeUnloadEvent event) {
  event.preventDefault();
  event.returnValue = ''.toJS;
}).toJS;

bool _protected = false;

void protectPendingChanges(bool protect) {
  if (protect == _protected) return;
  _protected = protect;
  if (protect) {
    _addEventListener('beforeunload'.toJS, _beforeUnload);
  } else {
    _removeEventListener('beforeunload'.toJS, _beforeUnload);
  }
}

@JS('window.financeCompassUpdateReady')
external JSBoolean? get _updateReady;

@JS('window.financeCompassApplyUpdate')
external JSPromise<JSAny?> _applyUpdate();

void Function() listenForPwaUpdates(void Function() onReady) {
  const type = 'finance-compass-update-ready';
  final listener = onReady.toJS;
  _addEventListener(type.toJS, listener);
  if (_updateReady?.toDart == true) scheduleMicrotask(onReady);
  return () => _removeEventListener(type.toJS, listener);
}

void Function() listenForNetworkReconnect(void Function() onReconnect) {
  final listener = onReconnect.toJS;
  _addEventListener('online'.toJS, listener);
  return () => _removeEventListener('online'.toJS, listener);
}

Future<void> applyPwaUpdate() async {
  await _applyUpdate().toDart;
}
