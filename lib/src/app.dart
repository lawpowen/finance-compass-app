import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/settings/app_settings_controller.dart';
import 'core/theme/finance_theme.dart';
import 'features/home/home_screen.dart';

class FinanceApp extends ConsumerWidget {
  const FinanceApp({
    super.key,
    required this.settingsController,
    this.navigatorKey,
    this.builder,
    this.syncSettings,
    this.workspaceNavigation,
  });

  final AppSettingsController settingsController;
  final GlobalKey<NavigatorState>? navigatorKey;
  final TransitionBuilder? builder;
  final Widget? syncSettings;
  final FinanceWorkspaceNavigation? workspaceNavigation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnimatedBuilder(
      animation: settingsController,
      builder: (context, _) {
        return MaterialApp(
          title: 'Finance Compass',
          navigatorKey: navigatorKey,
          builder: builder,
          debugShowCheckedModeBanner: false,
          theme: buildFinanceTheme(settingsController.themeStyle),
          home: HomeScreen(
            settingsController: settingsController,
            syncSettings: syncSettings,
            workspaceNavigation: workspaceNavigation,
          ),
        );
      },
    );
  }
}
