import '../database/app_database.dart';

Future<AppDatabase> openSyncDatabase() async =>
    throw UnsupportedError('网页同步仅支持浏览器。');

void protectPendingChanges(bool protect) {}

void Function() listenForPwaUpdates(void Function() onReady) => () {};

void Function() listenForNetworkReconnect(void Function() onReconnect) => () {};

void Function() listenForPwaRepaint(void Function() repaint,
        {required bool Function() hasOpenEditor}) =>
    () {};

Future<void> applyPwaUpdate() async => throw UnsupportedError('仅浏览器支持网页更新。');
