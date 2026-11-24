import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/shared/compass_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final style in AppThemeStyle.selectableStyles) {
    testWidgets('${style.name} help is touch-sized and dismissible',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: buildFinanceTheme(style),
        home: const Scaffold(
          body: CompassHelpHeading(
            title: Text('现金流'),
            label: '现金流口径',
            message: '按现金账户的实际收付统计。',
          ),
        ),
      ));
      final trigger = find.byTooltip('查看现金流口径说明');
      expect(tester.getSize(trigger).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(trigger).height, greaterThanOrEqualTo(44));
      expect(find.text('按现金账户的实际收付统计。'), findsNothing);
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(find.text('按现金账户的实际收付统计。'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
