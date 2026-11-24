import 'dart:io';
import 'dart:ui' as ui;

import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/shared/finance_amount_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pressAmountKeys(WidgetTester tester, List<String> keys) async {
  for (final key in keys) {
    final finder = find.byKey(ValueKey('amount-key-$key'));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }
}

void main() {
  final screenshots =
      Platform.environment['AMOUNT_KEYBOARD_SCREENSHOTS'] == '1';
  setUpAll(() async {
    if (screenshots) {
      final icons =
          await File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf')
              .readAsBytes();
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.sublistView(icons))))
          .load();
      final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
      await (FontLoader('QaFont')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  });
  Future<TextEditingController> open(
    WidgetTester tester, {
    String initial = '',
    ValueChanged<String>? onChanged,
    bool readOnly = false,
    bool enabled = true,
    AppThemeStyle theme = AppThemeStyle.abyss,
    double scale = 1,
  }) async {
    final controller = TextEditingController(text: initial);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: screenshots
            ? buildFinanceTheme(theme).copyWith(
                textTheme: buildFinanceTheme(theme)
                    .textTheme
                    .apply(fontFamily: 'QaFont'))
            : buildFinanceTheme(theme),
        builder: (context, child) => RepaintBoundary(
          key: const Key('keypad-capture'),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: FinanceAmountField(
              controller: controller,
              onChanged: onChanged,
              readOnly: readOnly,
              enabled: enabled,
              decoration:
                  const InputDecoration(labelText: '金额', prefixText: 'MYR '),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(FinanceAmountField));
    await tester.pumpAndSettle();
    return controller;
  }

  String display(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('amount-display'))).data!;

  testWidgets('tap opens keypad without IME; cents commit once on Done',
      (tester) async {
    final changes = <String>[];
    final controller = await open(tester, onChanged: changes.add);
    expect(tester.testTextInput.isVisible, isFalse);
    await pressAmountKeys(tester, ['1', '1', '3', '4']);
    expect(display(tester), '11.34');
    expect(controller.text, isEmpty);
    await pressAmountKeys(tester, ['完成']);
    expect(controller.text, '11.34');
    expect(changes, ['11.34']);
    expect(find.byKey(const Key('amount-keyboard')), findsNothing);
    await tester.tap(find.byType(FinanceAmountField));
    await tester.pumpAndSettle();
    expect(display(tester), '11.34');
    await pressAmountKeys(tester, ['1', '5', '0', '完成']);
    expect(controller.text, '1.50');
  });

  testWidgets(
      'Done evaluates pending arithmetic and preserves controller listeners',
      (tester) async {
    final controller = await open(tester, initial: '11.34');
    var notifications = 0;
    controller.addListener(() => notifications++);
    await pressAmountKeys(tester, ['+', '1', '5', '0', '完成']);
    expect(controller.text, '12.84');
    expect(notifications, 1);
  });

  testWidgets(
      'division by zero blocks commit, preserves input and permits correction',
      (tester) async {
    final controller = await open(tester, initial: '10.00');
    await pressAmountKeys(tester, ['÷', '0', '完成']);
    expect(find.text('不能除以 0'), findsOneWidget);
    expect(controller.text, '10.00');
    await pressAmountKeys(tester, ['⌫', '2', '00', '完成']);
    expect(controller.text, '5.00');
  });

  testWidgets('clear allows optional amount to be removed', (tester) async {
    final controller = await open(tester, initial: '50');
    await pressAmountKeys(tester, ['C', '完成']);
    expect(controller.text, isEmpty);
  });

  testWidgets(
      'untouched high precision value is not rounded by opening and closing',
      (tester) async {
    final controller = await open(tester, initial: '1.2345');
    await pressAmountKeys(tester, ['完成']);
    expect(controller.text, '1.2345');
  });

  testWidgets(
      'back and close protect unsaved draft; cancel keeps original amount',
      (tester) async {
    final controller = await open(tester, initial: '10');
    await pressAmountKeys(tester, ['1', '5', '0']);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放弃本次金额输入？'), findsOneWidget);
    await tester.tap(find.text('继续输入'));
    await tester.pumpAndSettle();
    expect(display(tester), '1.50');
    await tester.tap(find.byTooltip('关闭金额键盘'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃输入'));
    await tester.pumpAndSettle();
    expect(controller.text, '10');
    expect(find.byKey(const Key('amount-keyboard')), findsNothing);
  });

  testWidgets('hardware digits and Enter follow the same cents input',
      (tester) async {
    final controller = await open(tester);
    for (final key in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit0
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.text, '1.50');
  });

  testWidgets('read-only and disabled amounts do not open a keypad',
      (tester) async {
    await open(tester, readOnly: true);
    expect(find.byKey(const Key('amount-keyboard')), findsNothing);
    await open(tester, enabled: false);
    expect(find.byKey(const Key('amount-keyboard')), findsNothing);
  });

  for (final theme in [AppThemeStyle.abyss, AppThemeStyle.sky]) {
    for (final size in [
      const Size(375, 812),
      const Size(812, 375),
      const Size(1024, 768)
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('keypad layout ${theme.name} $size scale $scale',
            (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await open(tester, theme: theme, scale: scale);
          await pressAmountKeys(tester, ['1', '1', '3', '4']);
          for (final button in find.byType(FilledButton).evaluate()) {
            final box = button.renderObject! as RenderBox;
            expect(box.size.width, greaterThanOrEqualTo(48));
            expect(box.size.height, greaterThanOrEqualTo(48));
          }
          final done = tester.widget<FilledButton>(
              find.byKey(const ValueKey('amount-key-完成')));
          final foreground =
              done.style!.foregroundColor!.resolve({})!.computeLuminance();
          final background =
              done.style!.backgroundColor!.resolve({})!.computeLuminance();
          final light = foreground > background ? foreground : background;
          final dark = foreground < background ? foreground : background;
          expect((light + 0.05) / (dark + 0.05), greaterThanOrEqualTo(4.5));
          expect(tester.takeException(), isNull);
          if (Platform.environment['AMOUNT_KEYBOARD_SCREENSHOTS'] == '1' &&
              size.width == 375 &&
              scale == 1) {
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const Key('keypad-capture')),
              );
              final image = await boundary.toImage();
              final data =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              final file = File(
                  'artifacts/qa/amount-keyboard-2026-11-23/${theme.name}.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          await pressAmountKeys(tester, ['完成']);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
