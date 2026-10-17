import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/transaction.dart';
import '../../core/notifications/notification_bridge.dart';
import '../../core/providers/repository_provider.dart';
import '../transactions/transaction_form_dialog.dart';

class NotificationBookkeepingPage extends ConsumerStatefulWidget {
  const NotificationBookkeepingPage({super.key});
  @override
  ConsumerState<NotificationBookkeepingPage> createState() =>
      _NotificationBookkeepingPageState();
}

class _NotificationBookkeepingPageState
    extends ConsumerState<NotificationBookkeepingPage> {
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => _run(() => ref.read(notificationBridgeProvider).refresh()));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working || !mounted) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = '操作未完成：$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(notificationBridgeProvider);
    final pending = bridge.items.where((i) => i['state'] == 'pending').toList();
    final history = bridge.items.where((i) => i['state'] != 'pending').toList();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('通知记账'),
          actions: [
            IconButton(
              tooltip: '刷新并重试',
              onPressed:
                  _working || bridge.busy ? null : () => _run(bridge.drain),
              icon: const Icon(Icons.refresh),
            )
          ],
          bottom: TabBar(isScrollable: true, tabs: [
            const Tab(text: '来源设置'),
            Tab(text: '待确认 ${pending.length}'),
            const Tab(text: '已处理'),
          ]),
        ),
        body: SafeArea(
            child: Column(children: [
          if (bridge.busy) const LinearProgressIndicator(),
          if (bridge.captureFailed)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('曾有通知无法保存，请与银行账单核对缺失交易。')),
          if (_error != null || bridge.error != null)
            Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error ?? bridge.error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          Expanded(
              child: TabBarView(children: [
            _settings(bridge),
            _records(bridge, pending),
            _records(bridge, history),
          ])),
        ])),
      ),
    );
  }

  Widget _settings(NotificationBridge bridge) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('明确交易自动入账，其余由你确认',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              '只处理你选择的应用。通知正文在本机识别，不发送给 AI；完整 JSON 备份会包含通知记录。请先绑定账户，再授权并开启。'),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('自动接收与记账'),
            subtitle: Text(bridge.permission ? '系统通知读取权限已开启' : '尚未获得系统通知读取权限'),
            value: bridge.enabled,
            onChanged: _working ||
                    !NotificationBridge.supported ||
                    (!bridge.enabled &&
                        (!bridge.permission || bridge.bindings.isEmpty))
                ? null
                : (value) => _run(() => bridge.configure(active: value)),
          ),
          OutlinedButton.icon(
            onPressed: _working || !NotificationBridge.supported
                ? null
                : () => _run(bridge.openPermission),
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('打开系统通知读取授权'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _working || !NotificationBridge.supported
                ? null
                : () => _run(() => _addBinding(bridge)),
            icon: const Icon(Icons.add),
            label: const Text('绑定通知来源与账户'),
          ),
          for (var index = 0; index < bridge.bindings.length; index++)
            Card(
                child: ListTile(
              title: Text('${bridge.bindings[index]['label']}'),
              subtitle: Text(
                  '${bridge.bindings[index]['accountName']}\n包含：${bridge.bindings[index]['marker']}'),
              trailing: IconButton(
                  tooltip: '移除来源绑定',
                  icon: const Icon(Icons.link_off),
                  onPressed: _working
                      ? null
                      : () => _run(() async {
                            final updated = [...bridge.bindings]
                              ..removeAt(index);
                            await bridge.configure(
                                sources: updated,
                                active: updated.isEmpty ? false : null);
                          })),
            )),
          const SizedBox(height: 16),
          const Text('自动入账条件', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text(
              '成功通知格式匹配、单一金额与币种、唯一账户标识、交易编号明确且无疑似重复。未知格式、退款、转账、还款等进入待确认。验证码不保存。'),
          const SizedBox(height: 12),
          const Text(
              '账户标识应填写通知中独有的完整片段，例如 Card: **1234，避免只填常见数字。一个应用可绑定多个账户，但匹配多条时不会自动记账。'),
          const SizedBox(height: 12),
          const Text(
              '限制：不补读授权前通知；系统强制停止、隐藏通知内容或收回权限可能漏记。交易时间默认使用通知送达时间，请定期与账单核对。'),
        ],
      );

  Widget _records(NotificationBridge bridge, List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('暂无记录。开启通知记账后，新通知会显示在这里。')));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final state = item['state'];
        final label = const {
              'pending': '待确认',
              'posted': '自动入账',
              'confirmed': '已确认入账',
              'ignored': '已忽略',
              'undone': '已撤销'
            }[state] ??
            '$state';
        final date =
            DateTime.fromMillisecondsSinceEpoch(item['postedAt'] as int)
                .toLocal();
        return Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '$label · ${item['currency'] ?? '币种待确认'} ${item['amount'] ?? ''}',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                        '${item['package']} · ${date.toString().substring(0, 16)}'),
                    if (state == 'pending')
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text('${item['reason']}')),
                    ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('查看原始通知'),
                        children: [
                          SelectableText('${item['title']}\n${item['text']}')
                        ]),
                    if (state == 'pending')
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        FilledButton(
                            onPressed: _working
                                ? null
                                : () => _run(() => _confirm(bridge, item)),
                            child: const Text('核对并记账')),
                        TextButton(
                            onPressed: _working
                                ? null
                                : () => _run(() => bridge.mutate(() => bridge
                                    .bookkeeper
                                    .ignore(item['id'] as String))),
                            child: const Text('忽略')),
                      ]),
                    if (state == 'posted' || state == 'confirmed')
                      OutlinedButton(
                          onPressed: _working
                              ? null
                              : () => _run(() => _undo(bridge, item)),
                          child: const Text('撤销这笔记账')),
                  ],
                )));
      },
    );
  }

  Future<void> _addBinding(NotificationBridge bridge) async {
    final apps = await bridge.apps();
    final repository = await ref.read(financeRepositoryProvider.future);
    final accounts = repository.accounts.where((a) => a.isActive).toList();
    if (accounts.isEmpty) throw StateError('请先创建一个账户');
    if (!mounted) return;
    var marker = '';
    String? package;
    String? accountId;
    final form = GlobalKey<FormState>();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('绑定通知来源'),
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
                child: Form(
                    key: form,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                            isExpanded: true,
                            decoration:
                                const InputDecoration(labelText: '通知来自哪个应用'),
                            items: apps
                                .map((a) => DropdownMenuItem(
                                    value: a['package'] as String,
                                    child: Text('${a['label']}',
                                        overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: (value) => package = value,
                            validator: (v) => v == null ? '请选择来源应用' : null),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                            isExpanded: true,
                            decoration:
                                const InputDecoration(labelText: '记入哪个账户'),
                            items: accounts
                                .map((a) => DropdownMenuItem(
                                    value: a.id,
                                    child: Text('${a.name} · ${a.currency}',
                                        overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: (value) => accountId = value,
                            validator: (v) => v == null ? '请选择账户' : null),
                        const SizedBox(height: 16),
                        TextFormField(
                            onChanged: (value) => marker = value,
                            decoration: const InputDecoration(
                                labelText: '通知中的账户识别片段',
                                hintText: '例如 Card: **1234',
                                helperText: '区分同一应用中的多个账户；按原文匹配'),
                            validator: (value) =>
                                (value ?? '').trim().length < 4
                                    ? '请输入至少 4 个字符的独有片段'
                                    : null),
                      ],
                    )))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                Navigator.pop(context, <String, dynamic>{
                  'package': package,
                  'label':
                      apps.firstWhere((a) => a['package'] == package)['label'],
                  'accountId': accountId,
                  'accountName':
                      accounts.firstWhere((a) => a.id == accountId).name,
                  'marker': marker.trim()
                });
              },
              child: const Text('保存绑定')),
        ],
      ),
    );
    if (result != null) {
      await bridge.configure(sources: [...bridge.bindings, result]);
    }
  }

  Future<void> _confirm(
      NotificationBridge bridge, Map<String, dynamic> item) async {
    final repository = await ref.read(financeRepositoryProvider.future);
    final accounts = repository.accounts.where((a) => a.isActive).toList();
    if (accounts.isEmpty) throw StateError('请先创建账户');
    final account =
        accounts.where((a) => a.id == item['accountId']).firstOrNull ??
            accounts.first;
    final date = DateTime.fromMillisecondsSinceEpoch(item['postedAt'] as int);
    if (!mounted) return;
    final result = await showDialog<TransactionFormResult>(
        context: context,
        builder: (_) => TransactionFormDialog(
              repository: repository,
              notificationDraft: true,
              draftTransaction: FinanceTransaction(
                id: 'notification_${item['id']}',
                type: item['type'] == 'income'
                    ? TransactionType.income
                    : TransactionType.expense,
                accountId: account.id,
                amount: (item['amount'] as num?)?.toDouble() ?? 0,
                currency: account.currency,
                transactionDate: date,
                recordDate: date,
                merchant: item['merchant'] as String?,
                description: '通知确认 · ${item['package']}',
              ),
            ));
    if (result == null) return;
    if (result.transactions.length != 1) throw StateError('每条通知只能确认一笔交易');
    await bridge.mutate(() => bridge.bookkeeper
        .confirm(item['id'] as String, result.transactions.single));
  }

  Future<void> _undo(
      NotificationBridge bridge, Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('撤销通知记账？'),
              content: const Text(
                  '将删除对应交易并恢复余额。通知记录会保留，避免重复入账。如果交易曾被手动修改，将撤销修改后的交易。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('确认撤销'))
              ],
            ));
    if (confirmed == true) {
      await bridge.mutate(() => bridge.bookkeeper.undo(item['id'] as String));
    }
  }
}
