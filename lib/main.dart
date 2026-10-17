import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/core/settings/app_settings_controller.dart';
import 'src/core/notifications/notification_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settingsController = AppSettingsController();
  await settingsController.load();
  final container = ProviderContainer();
  if (NotificationBridge.supported) {
    await container.read(notificationBridgeProvider).start();
  }
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: FinanceApp(settingsController: settingsController),
    ),
  );
}
