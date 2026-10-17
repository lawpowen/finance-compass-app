import 'dart:convert';

import '../database/app_database.dart' show AppDatabase;
import '../models/account.dart';
import '../models/transaction.dart';
import 'notification_parser.dart';

const notificationRecordPrefix = 'notification_record_v1_';

class NotificationBookkeeper {
  NotificationBookkeeper(this.db);
  final AppDatabase db;

  Future<List<Map<String, dynamic>>> records() async {
    final meta = await db.fetchAllMetaValues();
    final result = <Map<String, dynamic>>[];
    for (final entry in meta.entries) {
      if (entry.key.startsWith(notificationRecordPrefix)) {
        result.add(Map<String, dynamic>.from(jsonDecode(entry.value) as Map));
      }
    }
    result
        .sort((a, b) => (b['postedAt'] as int).compareTo(a['postedAt'] as int));
    return result;
  }

  Future<Map<String, dynamic>?> record(String id) async {
    final value = await db.getMetaValue('$notificationRecordPrefix$id');
    return value == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(value) as Map);
  }

  Future<void> _save(Map<String, dynamic> item) => db.setMetaValue(
      '$notificationRecordPrefix${item['id']}', jsonEncode(item));

  /// Event receipt, ledger entry and balance mutation commit together. The
  /// Android queue is acknowledged only after this transaction succeeds.
  Future<void> ingest(
      Map<String, dynamic> event, List<Map<String, dynamic>> bindings,
      {required bool enabled}) async {
    await db.transaction(() async {
      final id = event['id'] as String;
      if (await record(id) != null) return;
      final text = event['text'] as String;
      final parsed = parsePaymentNotification(text,
          sourcePackage: event['package'] as String);
      final accounts = await db.fetchAccounts();
      final candidates = bindings.where((b) {
        if (b['package'] != event['package']) return false;
        final marker = (b['marker'] as String? ?? '').trim();
        // A source-only binding can preselect the review form's account, but
        // must never authorize automatic ledger writes.
        if (marker.isEmpty) return b['reviewOnly'] == true;
        return text.contains(marker);
      }).toList();
      final matchingAccounts = candidates.length == 1
          ? accounts
              .where(
                  (a) => a.id == candidates.single['accountId'] && a.isActive)
              .toList()
          : <Account>[];
      final account =
          matchingAccounts.length == 1 ? matchingAccounts.single : null;
      var reason = parsed.reason;
      if (reason.isEmpty &&
          candidates.length == 1 &&
          candidates.single['reviewOnly'] == true) {
        reason = '此来源仅收集到待确认，请核对后记账';
      }
      if (RegExp(
              r'\b(failed|declined|pending|refund|reversed|request|otp|tac)\b|失败|退款|验证码',
              caseSensitive: false)
          .hasMatch(event['title'] as String? ?? '')) {
        reason = '通知标题含失败、待处理或特殊状态';
      }
      if (account == null) reason = '账户标识缺失、存在多条绑定或账户已停用';
      if (account != null && parsed.currency != account.currency) {
        reason = '通知币种与绑定账户不一致';
      }
      if (account != null &&
          !const [
            AccountType.bankSaving,
            AccountType.eWallet,
            AccountType.creditCard,
            AccountType.cash
          ].contains(account.accountType)) {
        reason = '该账户类型需要人工确认';
      }
      if (!enabled) reason = '通知自动记账已暂停';
      if (event['configurationChanged'] == true) reason = '接收通知后设置已更改，请重新核对账户';
      final postedAt =
          DateTime.fromMillisecondsSinceEpoch(event['postedAt'] as int);
      if (DateTime.now().difference(postedAt).abs() > const Duration(days: 1)) {
        reason = '延迟送达的通知，请核对真实交易日期';
      }
      final history = await records();
      // A same-key update may change amount/status; never silently rewrite an
      // existing financial transaction or drop a potentially different one.
      if (history.any((r) =>
          r['key'] == event['key'] && r['package'] == event['package'])) {
        reason = '同一通知发生更新，请核对是否已记账';
      }
      if (parsed.reference != null &&
          history.any((r) =>
              r['reference'] == parsed.reference &&
              r['package'] == event['package'])) {
        reason = '相同来源与交易编号已有记录，请核对重复或状态变化';
      }
      final transactions = await db.fetchTransactions();
      if (transactions.any((t) => t.id == 'notification_$id')) {
        reason = '已有同一通知的交易但处理凭据缺失，请核对后忽略';
      }
      if (parsed.amount != null &&
          transactions.any((t) =>
              t.affectsBalance &&
              t.amount == parsed.amount &&
              t.currency == parsed.currency &&
              t.transactionDate.difference(postedAt).inMinutes.abs() <= 10)) {
        reason = '附近已有同金额交易，可能来自手动记账或其他通知';
      }
      final item = <String, dynamic>{
        ...event,
        'state': reason.isEmpty ? 'posted' : 'pending',
        'reason': reason,
        'amount': parsed.amount,
        'currency': parsed.currency,
        'type': parsed.type?.name,
        'reference': parsed.reference,
        'merchant': parsed.merchant,
        'accountId': account?.id,
        'transactionId': reason.isEmpty ? 'notification_$id' : null,
      };
      if (reason.isEmpty) {
        await db.insertTransaction(FinanceTransaction(
          id: 'notification_$id',
          type: parsed.type!,
          accountId: account!.id,
          amount: parsed.amount!,
          currency: parsed.currency!,
          transactionDate: postedAt,
          recordDate: DateTime.now(),
          merchant: parsed.merchant,
          description: '通知记账 · ${event['package']} · ${parsed.reference}',
        ));
      }
      await _save(item);
    });
  }

  Future<void> confirm(String id, FinanceTransaction draft) async {
    await db.transaction(() async {
      final item = await record(id);
      if (item == null || item['state'] != 'pending') {
        throw StateError('该通知已处理，请刷新列表');
      }
      final accounts = await db.fetchAccounts();
      final source =
          accounts.where((a) => a.id == draft.accountId && a.isActive);
      if (source.length != 1 ||
          source.single.currency != draft.currency ||
          !draft.amount.isFinite ||
          draft.amount == 0 ||
          !draft.affectsBalance) {
        throw StateError('请选择有效账户、币种和非零金额，并设为已发生');
      }
      if (draft.type == TransactionType.transfer) {
        final target =
            accounts.where((a) => a.id == draft.toAccountId && a.isActive);
        if (target.length != 1 ||
            target.single.id == draft.accountId ||
            target.single.currency != draft.transferInCurrency ||
            !draft.transferInAmount.isFinite ||
            draft.transferInAmount == 0) {
          throw StateError('请核对转入账户、币种及金额');
        }
      }
      final transactionId = 'notification_$id';
      await db.insertTransaction(FinanceTransaction(
        id: transactionId,
        type: draft.type,
        accountId: draft.accountId,
        toAccountId: draft.toAccountId,
        categoryId: draft.categoryId,
        amount: draft.amount,
        currency: draft.currency,
        toAmount: draft.toAmount,
        toCurrency: draft.toCurrency,
        transactionDate: draft.transactionDate,
        recordDate: DateTime.now(),
        merchant: draft.merchant,
        description: draft.description,
      ));
      await _save(
          {...item, 'state': 'confirmed', 'transactionId': transactionId});
    });
  }

  Future<void> ignore(String id) async {
    await db.transaction(() async {
      final item = await record(id);
      if (item == null || item['state'] != 'pending') {
        throw StateError('该通知已处理');
      }
      await _save({...item, 'state': 'ignored'});
    });
  }

  Future<void> undo(String id) async {
    await db.transaction(() async {
      final item = await record(id);
      if (item == null || !['posted', 'confirmed'].contains(item['state'])) {
        throw StateError('该通知没有可撤销的交易');
      }
      final transactionId = item['transactionId'] as String;
      if ((await db.fetchTransactions()).any((t) => t.id == transactionId)) {
        await db.deleteTransactionsByIds([transactionId]);
      }
      // Tombstone survives deletion so replay cannot recreate the charge.
      await _save({...item, 'state': 'undone'});
    });
  }
}
