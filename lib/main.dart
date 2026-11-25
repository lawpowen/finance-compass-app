import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/core/settings/app_settings_controller.dart';
import 'src/features/sync/finance_sync_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['MiSans', 'MiSans TC'],
      '本应用嵌入 MiSans 和 MiSans TC，由小米科技有限责任公司授权使用。\n\n'
      'https://hyperos.mi.com/font/en/download/',
    );
  });
  final settingsController = AppSettingsController();
  runApp(
    kIsWeb
        ? FinanceSyncGate(
            settingsController: settingsController,
            localOnly: !const bool.fromEnvironment('FINANCE_SYNC_WEB'),
          )
        : ProviderScope(
            child: FinanceApp(settingsController: settingsController)),
  );
  // Launch even if device storage is locked. The controller retains the
  // default on timeout/error and publishes a successfully restored theme.
  unawaited(settingsController.load());
}
