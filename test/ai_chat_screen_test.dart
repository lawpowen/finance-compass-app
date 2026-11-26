import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/providers/ai_chat_provider.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/ai/ai_chat_screen.dart';
import 'package:finance_app/src/features/dashboard/dashboard_v2_screen.dart';
import 'package:finance_app/src/features/reports/reports_v2_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubChat extends AiChatController {
  _StubChat(
      [this.initial =
          const AiChatState(availability: AiChatAvailability.ready)]);
  final AiChatState initial;
  final sent = <String>[];
  int stops = 0;

  @override
  AiChatState build() => initial;

  @override
  Future<void> send(String text) async {
    sent.add(text);
    state = AiChatState(
      availability: AiChatAvailability.ready,
      generating: true,
      hasPending: state.hasPending,
      messages: [
        ...state.messages,
        AiChatMessage(role: AiChatRole.user, text: text)
      ],
      statusText: '正在查询信用卡账单…',
    );
  }

  void reply(String text, {String? refusalReason}) {
    final messages = [...state.messages];
    if (messages.last.role == AiChatRole.assistant) messages.removeLast();
    state = AiChatState(
      availability: AiChatAvailability.ready,
      generating: true,
      hasPending: state.hasPending,
      messages: [
        ...messages,
        AiChatMessage(
            role: AiChatRole.assistant,
            text: text,
            refusalReason: refusalReason)
      ],
      statusText: '正在回答…',
    );
  }

  @override
  void stop() {
    stops++;
    state = AiChatState(
      availability: AiChatAvailability.ready,
      hasPending: state.hasPending,
      messages: state.messages,
    );
  }

  @override
  void clear() => state = initial;
}

void _viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _mount(
  WidgetTester tester,
  _StubChat stub, {
  AppThemeStyle theme = AppThemeStyle.monochrome,
  Widget child = const AiChatScreen(),
}) async {
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: buildFinanceTheme(theme),
      // The actual Navigator may live above the signed-in ledger scope.
      home: ProviderScope(
        overrides: [aiChatProvider.overrideWith(() => stub)],
        child: child,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final screen in ['总览', '报表']) {
    testWidgets('$screen入口沿用当前账本对话', (tester) async {
      _viewport(tester, const Size(390, 844));
      final repository = FinanceRepository.preview();
      addTearDown(repository.database.close);
      final stub = _StubChat();
      await _mount(tester, stub,
          child: Scaffold(
              body: screen == '总览'
                  ? DashboardV2Screen(repository: repository)
                  : ReportsV2Screen(repository: repository)));
      await tester.tap(find.byTooltip('AI 理财助手'));
      await tester.pumpAndSettle();
      expect(find.byType(AiChatScreen), findsOneWidget);
      await tester.tap(find.text('本月消费与预算'));
      expect(stub.sent.single, contains('预算'));
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.byType(AiChatScreen), findsNothing);
      await tester.tap(find.byTooltip('AI 理财助手'));
      await tester.pumpAndSettle();
      expect(find.text(stub.sent.single), findsOneWidget);
    });
  }

  testWidgets('快捷提问、增量回复、停止与确认清空', (tester) async {
    _viewport(tester, const Size(360, 740));
    final stub = _StubChat(const AiChatState(
        availability: AiChatAvailability.ready, hasPending: true));
    await _mount(tester, stub, theme: AppThemeStyle.liquidGlass);
    expect(find.byType(ActionChip), findsNWidgets(4));
    final pending = find.text('基于已同步账本，当前有待上传记录');
    expect(pending, findsOneWidget);
    await tester.tap(find.text('未来 30 天还款压力'));
    await tester.pump();
    expect(find.text('正在查询信用卡账单…'), findsOneWidget);
    expect(pending, findsOneWidget);
    stub.reply('本期');
    await tester.pump();
    expect(find.text('本期'), findsOneWidget);
    stub.reply('本期账单为 80。');
    await tester.pump();
    expect(
        find.byWidgetPredicate(
            (w) => w is SelectableText && w.data == '本期账单为 80。'),
        findsOneWidget);
    expect(find.byTooltip('复制回复'), findsOneWidget);
    await tester.tap(find.text('停止生成'));
    await tester.pump();
    expect(stub.stops, 1);
    expect(find.text('停止生成'), findsNothing);
    expect(find.text('本期账单为 80。'), findsOneWidget);
    await tester.tap(find.byTooltip('清空对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(find.text('本期账单为 80。'), findsNothing);
    expect(find.byType(ActionChip), findsNWidgets(4));
  });

  testWidgets('拒答与包含链接的回复按纯文本显示和复制', (tester) async {
    const reply = '只能回答账本问题。<b>示例</b> https://example.invalid/';
    final stub = _StubChat(const AiChatState(
      availability: AiChatAvailability.ready,
      messages: [
        AiChatMessage(
            role: AiChatRole.assistant,
            text: reply,
            refusalReason: 'off_topic'),
      ],
    ));
    String? copied;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = call.arguments['text'] as String;
      }
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await _mount(tester, stub);
    expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(text.data, reply);
    await tester.tap(find.byTooltip('复制回复'));
    await tester.pump();
    expect(copied, reply);
    expect(find.text('已复制回复'), findsOneWidget);
  });

  testWidgets('输入法组合期间确认候选不发送，完成后回车只发送一次', (tester) async {
    final stub = _StubChat();
    await _mount(tester, stub);
    final input = find.byType(TextField);
    await tester.showKeyboard(input);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: 'yusuan',
      selection: TextSelection.collapsed(offset: 6),
      composing: TextRange(start: 0, end: 6),
    ));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(stub.sent, isEmpty);
    await tester.enterText(input, '本月预算');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(stub.sent, ['本月预算']);
  });

  testWidgets('阅读历史时流式输出保留滚动位置，跳至最新恢复跟随', (tester) async {
    _viewport(tester, const Size(390, 720));
    final stub = _StubChat();
    await _mount(tester, stub);
    await tester.tap(find.text('支出超标分类'));
    final lines = List.generate(70, (i) => '账本查询结果第 ${i + 1} 行。').join('\n');
    stub.reply(lines);
    await tester.pumpAndSettle();
    final list = find.byKey(const Key('ai-chat-messages'));
    final position = tester.widget<ListView>(list).controller!.position;
    expect(position.extentAfter, 0);
    await tester.dragFrom(tester.getCenter(list), const Offset(0, 190));
    await tester.pumpAndSettle();
    final offset = position.pixels;
    expect(find.text('跳至最新'), findsOneWidget);
    stub.reply('$lines\n后续数据');
    await tester.pumpAndSettle();
    expect(position.pixels, offset);
    await tester.tap(find.text('跳至最新'));
    await tester.pumpAndSettle();
    expect(position.extentAfter, 0);
  });

  for (final (availability, notice) in [
    (AiChatAvailability.offline, '本地账本模式'),
    (AiChatAvailability.disabled, '服务器尚未启用'),
  ]) {
    testWidgets('$availability显示原因并隐藏提问入口', (tester) async {
      _viewport(tester, const Size(1100, 800));
      await _mount(tester, _StubChat(AiChatState(availability: availability)),
          theme: AppThemeStyle.dopamine);
      expect(find.textContaining(notice), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(ActionChip), findsNothing);
      expect(find.textContaining('不构成投资/税务/法律建议'), findsOneWidget);
      await tester.tap(find.byTooltip('查看账本分析口径说明'));
      await tester.pumpAndSettle();
      expect(find.text('账本分析口径'), findsOneWidget);
    });
  }
}
