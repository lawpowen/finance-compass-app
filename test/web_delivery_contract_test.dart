import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current;

  test('web manifest describes an installable Finance Compass PWA', () async {
    final manifest = jsonDecode(
      await File('${root.path}/web/manifest.json').readAsString(),
    ) as Map<String, dynamic>;

    expect(manifest['name'], 'Finance Compass');
    expect(manifest['display'], 'standalone');
    expect(manifest['start_url'], './');
    expect(manifest['icons'], isNotEmpty);
  });

  test('self-hosted delivery includes real browser database and cache assets',
      () async {
    final required = [
      'web/sqlite3.wasm',
      'tool/drift_worker.dart',
      'tool/sqlite3_wasm.lock',
      'web/service-worker.js',
      'web/pwa_bootstrap.js',
      'deploy/selfhost/Dockerfile',
      'deploy/selfhost/Dockerfile.runtime',
      'deploy/selfhost/compose.yml',
      'deploy/selfhost/compose.runtime.yml',
      'deploy/selfhost/install.ps1',
      'deploy/selfhost/install.sh',
      'deploy/selfhost/install.command',
    ];
    for (final relative in required) {
      final file = File('${root.path}/$relative');
      expect(await file.exists(), isTrue, reason: '$relative must exist');
      expect(await file.length(), greaterThan(0), reason: '$relative is empty');
    }

    final wasmLock =
        await File('${root.path}/tool/sqlite3_wasm.lock').readAsString();
    expect(wasmLock, contains('SQLITE3_VERSION=2.9.4'));
    expect(
        wasmLock,
        contains(
            'SHA256=922A76B182B6AF69B030C8E2FDD3283ECC8E827248B20E4B1F3F3DB170B52117'));
    final wasm = File('${root.path}/web/sqlite3.wasm');
    expect(await wasm.length(), 730989);

    final caddy =
        await File('${root.path}/deploy/selfhost/Caddyfile').readAsString();
    expect(caddy, contains('application/wasm'));
    expect(caddy, contains('no-cache, no-store, must-revalidate'));
    expect(caddy, contains('/flutter_service_worker.js'));
    expect(caddy, contains("script-src 'self'"));
    expect(caddy, isNot(contains("script-src 'unsafe-inline'")));

    final worker =
        await File('${root.path}/web/service-worker.js').readAsString();
    for (final asset in [
      './main.dart.js',
      './sqlite3.wasm',
      './drift_worker.js',
      './canvaskit/canvaskit.wasm',
      './canvaskit/skwasm.wasm',
      './canvaskit/skwasm_heavy.wasm',
      './canvaskit/wimp.wasm',
      './assets/fonts/MaterialIcons-Regular.otf',
    ]) {
      expect(worker, contains(asset));
    }
    expect(worker, isNot(contains('http://')));
    expect(worker, isNot(contains('https://')));
  });

  test(
      'runtime package build copies a ready webroot, not a missing source tree',
      () async {
    final packager =
        await File('${root.path}/tool/package_selfhost.ps1').readAsString();
    expect(packager, contains("Copy-Item -LiteralPath 'build/web'"));
    expect(packager, contains("Dockerfile.runtime"));
    expect(packager, contains('FinanceCompass-SelfHost-Windows'));
    expect(packager, contains('FinanceCompass-SelfHost-macOS'));
    expect(packager, contains('FinanceCompass-SelfHost-Ubuntu'));
    expect(packager, contains('New-PortableZip'));
    expect(packager, contains("-replace '\\\\', '/'"));
    expect(packager, isNot(contains('Compress-Archive')));

    for (final dockerfile in [
      'deploy/selfhost/Dockerfile',
      'deploy/selfhost/Dockerfile.runtime',
    ]) {
      final contents = await File('${root.path}/$dockerfile').readAsString();
      expect(contents, contains('RUN setcap -r /usr/bin/caddy'));
    }

    for (final composeFile in [
      'deploy/selfhost/compose.yml',
      'deploy/selfhost/compose.runtime.yml',
    ]) {
      final contents = await File('${root.path}/$composeFile').readAsString();
      expect(contents, contains('/data/caddy'));
      expect(contents, contains('/config/caddy'));
      expect(contents, contains('cap_drop:'));
      expect(contents, contains('no-new-privileges:true'));
    }
  });

  test('import confirmation keeps native and browser recovery promises exact',
      () async {
    final settings = await File(
      '${root.path}/lib/src/features/settings/settings_reference_pages.dart',
    ).readAsString();
    expect(settings, contains('kIsWeb'));
    expect(settings, contains('Web 浏览器不会在服务器保留隐藏恢复点。'));
    expect(settings, contains('确认后会先建立恢复点，再用此文件替换当前资料。'));
  });
}
