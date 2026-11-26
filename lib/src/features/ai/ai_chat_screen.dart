import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/ai_chat_provider.dart';
import '../../core/providers/repository_provider.dart';
import '../../core/theme/finance_theme.dart';
import '../shared/compass_ui.dart';

const _disclaimer = '仅讨论个人理财与消费，基于已同步账本供参考，不构成投资/税务/法律建议';
const _suggestions = [
  ('本月消费与预算', '我这个月花了多少？各项预算还剩多少？'),
  ('未来 30 天还款压力', '未来 30 天有哪些还款到期？现金够用吗？'),
  ('支出超标分类', '哪些分类的支出超过预算？可以怎样调整？'),
  ('净资产与目标进度', '我的净资产是多少？储蓄目标进度如何？'),
];

class AiChatEntryButton extends StatelessWidget {
  const AiChatEntryButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'AI 理财助手',
        icon: const Icon(Icons.chat_bubble_outline_rounded),
        onPressed: () {
          final container = ProviderScope.containerOf(context, listen: false);
          Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => UncontrolledProviderScope(
              container: container,
              child: const AiChatScreen(),
            ),
          ));
        },
      );
}

class AiChatScreen extends ConsumerWidget {
  const AiChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Conversation(
        key: ObjectKey(ref.watch(ledgerSyncSessionProvider)),
      );
}

class _Conversation extends ConsumerStatefulWidget {
  const _Conversation({super.key});

  @override
  ConsumerState<_Conversation> createState() => _ConversationState();
}

class _ConversationState extends ConsumerState<_Conversation> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _following = true;
  bool _scrollScheduled = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _followAfterLayout() {
    if (!_following || _scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_following || !_scroll.hasClients) return;
      if (_scroll.position.extentAfter > 0) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _setFollowing(bool value) {
    if (value != _following) setState(() => _following = value);
  }

  bool _observeScroll(ScrollNotification event) {
    if (!_scroll.hasClients || event.depth != 0) return false;
    if (event is UserScrollNotification &&
        event.direction == ScrollDirection.forward) {
      _setFollowing(false);
    } else if (_scroll.position.userScrollDirection ==
            ScrollDirection.reverse &&
        event.metrics.extentAfter <= 8) {
      _setFollowing(true);
    }
    return false;
  }

  bool get _composing {
    final range = _input.value.composing;
    return range.isValid && !range.isCollapsed;
  }

  void _send([String? suggestion]) {
    final chat = ref.read(aiChatProvider);
    if (chat.availability != AiChatAvailability.ready ||
        chat.generating ||
        (suggestion == null && _composing)) {
      return;
    }
    final question = (suggestion ?? _input.text).trim();
    if (question.isEmpty) return;
    _setFollowing(true);
    // IME grapheme clusters can contain multiple code points. Keep the draft
    // when the server's code-point limit rejects a visually shorter string.
    if (suggestion == null && question.runes.length <= 1000) _input.clear();
    ref.read(aiChatProvider.notifier).send(question);
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空这段对话？'),
        content: const Text('清空后无法找回对话记录。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清空')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      ref.read(aiChatProvider.notifier).clear();
      _setFollowing(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(aiChatProvider);
    if (chat.messages.isNotEmpty) _followAfterLayout();
    final palette = financePaletteOf(context);
    final ready = chat.availability == AiChatAvailability.ready;
    final subtitle = switch (chat.availability) {
      AiChatAvailability.offline => '本地账本',
      AiChatAvailability.checking => '正在连接同步服务…',
      _ when chat.hasPending => '基于已同步账本，当前有待上传记录',
      _ => '基于已同步账本',
    };
    return Scaffold(
      body: CompassBackdropLayer(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 832),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: CompassPageHeader(
                        title: 'AI 理财助手',
                        leading: const Tooltip(
                            message: '返回', child: CompassBackButton()),
                        subtitle: subtitle,
                        actions: [
                          IconButton(
                            tooltip: '清空对话',
                            icon: const Icon(Icons.delete_sweep_outlined),
                            onPressed: chat.messages.isEmpty ? null : _clear,
                          ),
                          const CompassHelpButton(
                            title: '账本分析口径',
                            message:
                                '回答使用服务器上最近一次同步的账本。助手可查询账本及解释计算口径，不能更改账目。本页仅在当前登录会话中保留对话。\n\n$_disclaimer',
                          ),
                        ],
                      ),
                    ),
                    compassHairline,
                    Expanded(
                      child: chat.messages.isEmpty
                          ? _emptyState(chat)
                          : Stack(children: [
                              NotificationListener<ScrollMetricsNotification>(
                                onNotification: (_) {
                                  _followAfterLayout();
                                  return false;
                                },
                                child: NotificationListener<ScrollNotification>(
                                  onNotification: _observeScroll,
                                  child: ListView.builder(
                                    key: const Key('ai-chat-messages'),
                                    controller: _scroll,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    itemCount: chat.messages.length,
                                    itemBuilder: (_, index) => _MessageBubble(
                                      message: chat.messages[index],
                                    ),
                                  ),
                                ),
                              ),
                              if (!_following)
                                Positioned(
                                  bottom: 8,
                                  right: 0,
                                  child: FilledButton.tonalIcon(
                                    onPressed: () {
                                      _setFollowing(true);
                                      _followAfterLayout();
                                    },
                                    icon: const Icon(Icons.arrow_downward,
                                        size: 16),
                                    label: const Text('跳至最新'),
                                  ),
                                ),
                            ]),
                    ),
                    if (chat.errorText case final error?
                        when chat.availability !=
                                AiChatAvailability.unavailable ||
                            chat.messages.isNotEmpty)
                      Text(error, style: TextStyle(color: palette.expense)),
                    if (chat.generating)
                      Semantics(
                          liveRegion: true,
                          child: Text(
                            chat.statusText ?? '正在回答…',
                            style: TextStyle(color: palette.textMuted),
                          )),
                    if (ready) _composer(chat.generating),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(_disclaimer,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: palette.textMuted)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(AiChatState chat) {
    final availability = chat.availability;
    final session = ref.read(ledgerSyncSessionProvider);
    final needsLogin = session?.authenticationExpired == true ||
        session?.accountMismatch == true;
    final message = switch (availability) {
      AiChatAvailability.offline => '本地账本模式无法使用 AI 理财助手。登录同步账本后可查看服务状态。',
      AiChatAvailability.checking => '正在检查 AI 服务…',
      AiChatAvailability.disabled => '服务器尚未启用 AI 理财助手。请联系管理员配置 AI 服务。',
      AiChatAvailability.unavailable => chat.errorText ?? '暂时无法连接 AI 服务。',
      AiChatAvailability.ready => '可以问我账本里的消费、预算、到期还款和储蓄目标。',
    };
    return Center(
        child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.chat_bubble_outline_rounded,
            size: 32, color: financePaletteOf(context).accent),
        const SizedBox(height: 12),
        Text(message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
        if (availability == AiChatAvailability.ready) ...[
          const SizedBox(height: 16),
          Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, prompt) in _suggestions)
                  ActionChip(
                      label: Text(label), onPressed: () => _send(prompt)),
              ]),
        ],
        if (availability == AiChatAvailability.unavailable && !needsLogin ||
            availability == AiChatAvailability.disabled)
          TextButton(
              onPressed: ref.read(aiChatProvider.notifier).retryStatus,
              child: const Text('重新检查')),
      ]),
    ));
  }

  Widget _composer(bool generating) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Focus(
              onKeyEvent: (_, event) {
                final enter = event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter;
                if (!enter ||
                    HardwareKeyboard.instance.isShiftPressed ||
                    _composing ||
                    event is! KeyDownEvent) {
                  return KeyEventResult.ignored;
                }
                _send();
                return KeyEventResult.handled;
              },
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 3,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                maxLength: 1000,
                decoration:
                    const InputDecoration(hintText: '问问我的账本…', counterText: ''),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (generating)
            FilledButton.tonalIcon(
              onPressed: ref.read(aiChatProvider.notifier).stop,
              icon: const Icon(Icons.stop_rounded),
              label: const Text('停止生成'),
            )
          else
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _input,
              builder: (_, value, child) => IconButton.filled(
                tooltip: '发送',
                onPressed: value.text.trim().isEmpty || _composing
                    ? null
                    : () => _send(),
                icon: child!,
              ),
              child: const Icon(Icons.arrow_upward_rounded),
            ),
        ]),
      );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final AiChatMessage message;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final assistant = message.role == AiChatRole.assistant;
    if (message.text.isEmpty) return const SizedBox.shrink();
    final refused = message.refusalReason != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: assistant ? Alignment.centerLeft : Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 700),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: assistant ? palette.surface : palette.surfaceAlt,
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (refused)
                  Icon(Icons.info_outline_rounded,
                      size: 18, color: palette.textMuted),
                SelectableText(message.text,
                    style: TextStyle(
                        color:
                            refused ? palette.textMuted : palette.textPrimary)),
                if (assistant)
                  IconButton(
                    tooltip: '复制回复',
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await Clipboard.setData(
                            ClipboardData(text: message.text));
                        if (context.mounted) {
                          messenger.showSnackBar(
                              const SnackBar(content: Text('已复制回复')));
                        }
                      } on Exception {
                        if (context.mounted) {
                          messenger.showSnackBar(const SnackBar(
                              content: Text('无法访问剪贴板，请选择文字复制。')));
                        }
                      }
                    },
                  ),
              ]),
        ),
      ),
    );
  }
}
