import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/shared/compass_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selectableStyles and normalize expose only the 3 active themes', () {
    expect(
      AppThemeStyle.selectableStyles,
      [
        AppThemeStyle.monochrome,
        AppThemeStyle.dopamine,
        AppThemeStyle.liquidGlass,
      ],
    );
    expect(AppThemeStyle.normalize('dopamine'), AppThemeStyle.dopamine);
    expect(AppThemeStyle.normalize('liquidGlass'), AppThemeStyle.liquidGlass);
    expect(AppThemeStyle.normalize('monochrome'), AppThemeStyle.monochrome);
    expect(AppThemeStyle.normalize('abyss'), AppThemeStyle.monochrome);
    expect(AppThemeStyle.normalize('darkWood'), AppThemeStyle.monochrome);
    expect(AppThemeStyle.normalize(null), AppThemeStyle.monochrome);
    expect(AppThemeStyle.normalize('not_real'), AppThemeStyle.monochrome);
  });

  test(
      'liquidGlass and dopamine palettes satisfy gradient and extension contracts',
      () {
    final dopamine = paletteForStyle(AppThemeStyle.dopamine);
    final glass = paletteForStyle(AppThemeStyle.liquidGlass);

    expect(dopamine.backgroundGradientColors.length, 3);
    expect(dopamine.donutColors, hasLength(5));
    expect(dopamine.selectedSurface, isNotNull);

    expect(glass.backgroundMiddle, isNotNull);
    expect(glass.glassHighlightColor, isNotNull);
    expect(glass.cardBlurSigma, greaterThan(0));
    expect(glass.dockBlurSigma, greaterThanOrEqualTo(18));
    expect(glass.dockSurfaceAlpha, lessThan(0.75));
    expect(glass.backgroundGradientColors, [
      glass.backgroundTop,
      glass.backgroundMiddle,
      glass.backgroundBottom,
    ]);
    expect(
        glass
            .copyWith(selectedSurface: const Color(0xFF000000))
            .selectedSurface,
        const Color(0xFF000000));
    expect(dopamine.lerp(glass, 0.2), same(dopamine));
    expect(dopamine.lerp(glass, 0.8), same(glass));
  });

  testWidgets(
      'CompassCard and CompassBackground render cleanly under liquidGlass and dopamine',
      (tester) async {
    for (final style in [AppThemeStyle.dopamine, AppThemeStyle.liquidGlass]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildFinanceTheme(style),
          home: const Scaffold(
            body: CompassBackground(
              child: Center(
                child: CompassCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Theme Smoke Check'),
                      SizedBox(height: 8),
                      CompassPrimaryButton(
                        label: '操作',
                        onPressed: null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Theme Smoke Check'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
