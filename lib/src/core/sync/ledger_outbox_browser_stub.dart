Future<({bool conflict, String? payload, String? identity})> readOutbox(
  String accountId,
  String username,
) async =>
    throw UnsupportedError('待同步储存仅支持浏览器。');

Future<bool> replaceOutbox(
  String accountId,
  String username,
  String? expectedIdentity,
  String? nextIdentity,
  String? payload,
) async =>
    throw UnsupportedError('待同步储存仅支持浏览器。');
