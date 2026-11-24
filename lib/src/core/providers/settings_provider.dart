import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_settings_controller.dart';

/// Loads and exposes [AppSettingsController] to the widget tree.
///
/// The controller normalizes legacy appearance settings on first load.
class AppSettingsNotifier extends AsyncNotifier<AppSettingsController> {
  @override
  Future<AppSettingsController> build() async {
    final controller = AppSettingsController();
    await controller.load();
    return controller;
  }
}

/// The app-wide settings provider.
///
/// Widgets should watch this as `ref.watch(appSettingsProvider)` and
/// access `.value?.themeStyle` for the current theme.
final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettingsController>(
  AppSettingsNotifier.new,
);
