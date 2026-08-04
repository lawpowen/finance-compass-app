import 'dart:io';
import 'dart:ui' as ui;

import 'package:finance_app/src/core/settings/app_settings_controller.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/settings/settings_reference_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'theme carousel drags through previews and changes preview content',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppSettingsController();
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.abyss).copyWith(
          splashFactory: NoSplash.splashFactory,
        ),
        home: RepaintBoundary(
          key: boundaryKey,
          child: AppearancePage(settingsController: controller),
        ),
      ),
    );
    await tester.pump();

    if (const bool.fromEnvironment('CAPTURE_VISUAL_QA')) {
      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File('artifacts/design-qa/appearance-carousel-390.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(data!.buffer.asUint8List(), flush: true);
      });
    }

    expect(find.byType(PageView), findsOneWidget);
    expect(find.textContaining('墨绿 · 当前使用'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-260, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('左右拖动预览'), findsOneWidget);
    expect(find.textContaining('石墨'), findsWidgets);

    await tester.drag(find.byType(ListView).first, const Offset(0, -520));
    await tester.pump();
    await tester.drag(find.byType(ListView).first, const Offset(0, -320));
    await tester.pump();
    await tester.tap(find.text('交易').last);
    await tester.pump();
    expect(find.text('薪资收入'), findsWidgets);
  });
}
