Future<String> inspectPushBrowser(String accountId) async =>
    '{"supported":false,"permission":"denied"}';

Future<String> subscribePushBrowser(String accountId, String publicKey) async =>
    throw UnsupportedError('Web Push');

void confirmPushBrowser(String accountId, String endpoint, String timezone) {}

Future<String?> unsubscribePushBrowser(String accountId) async => null;

Future<void> reconcilePushBrowser(
    String accountId, bool verifiedTransition) async {}
