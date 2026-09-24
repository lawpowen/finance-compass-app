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

  test('service worker precaches only files the web build ships', () async {
    final worker =
        await File('${root.path}/web/service-worker.js').readAsString();
    final core = RegExp(r'const CORE = \[(.*?)\];', dotAll: true)
        .firstMatch(worker)!
        .group(1)!;
    // Flutter 3.44's flutter_service_worker.js only unregisters itself.
    expect(core, isNot(contains('flutter_service_worker.js')));
    // flutter.js loads this CanvasKit variant on Chrome and Edge.
    expect(core, contains("'./canvaskit/chromium/canvaskit.wasm'"));
    expect(core, contains("'./fonts/SHA256SUMS'"));
    expect(worker, contains("const FONT_INDEX = './fonts/SHA256SUMS'"));

    // Entries that come from web/ must exist in the source tree; Flutter
    // generated entries are checked against build/web by tool/build_web.*.
    for (final entry in [
      'manifest.json',
      'favicon.png',
      'icons/Icon-192.png',
      'icons/Icon-512.png',
      'icons/Icon-maskable-192.png',
      'icons/Icon-maskable-512.png',
      'pwa_bootstrap.js',
      'service-worker.js',
      'sqlite3.wasm',
      'fonts/SHA256SUMS',
    ]) {
      expect(core, contains("'./$entry'"));
      expect(File('${root.path}/web/$entry').existsSync(), isTrue,
          reason: 'web/$entry is precached but missing');
    }
  });

  test('Flutter bootstrap keeps the app worker and same-origin fonts',
      () async {
    final bootstrap =
        await File('${root.path}/web/flutter_bootstrap.js').readAsString();
    expect(bootstrap, contains('{{flutter_js}}'));
    expect(bootstrap, contains('{{flutter_build_config}}'));
    expect(bootstrap, contains("fontFallbackBaseUrl: 'fonts/'"));
    expect(bootstrap, isNot(contains('serviceWorkerSettings:')));
    expect(bootstrap, isNot(contains('flutter_service_worker_version')));
  });

  test('fallback fonts are vendored with a complete checksum list', () async {
    final fontsDir = Directory('${root.path}/web/fonts');
    final lines = (await File('${fontsDir.path}/SHA256SUMS').readAsLines())
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final listed = <String>{};
    for (final line in lines) {
      final match = RegExp(r'^([0-9a-f]{64})\s+(\S+)$').firstMatch(line);
      expect(match, isNotNull, reason: 'Malformed SHA256SUMS line: $line');
      final path = match!.group(2)!;
      listed.add(path);
      final file = File('${fontsDir.path}/$path');
      expect(file.existsSync(), isTrue, reason: 'fonts/$path is missing');
      expect(file.lengthSync(), greaterThan(0));
    }
    expect(listed.where((p) => p.startsWith('roboto/')), isNotEmpty);
    expect(listed.where((p) => p.startsWith('notosanssc/')).length, 101);

    final vendored = fontsDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.woff2') || f.path.endsWith('.ttf'))
        .map((f) => f.path
            .substring(fontsDir.path.length + 1)
            .replaceAll(Platform.pathSeparator, '/'))
        .toSet();
    expect(vendored, listed);
    for (final family in ['roboto', 'notosanssc']) {
      expect(File('${fontsDir.path}/$family/OFL.txt').existsSync(), isTrue);
    }
  });

  test('every web build path runs the shared release contract', () async {
    final ps1 = await File('${root.path}/tool/build_web.ps1').readAsString();
    final sh = await File('${root.path}/tool/build_web.sh').readAsString();
    final dockerfile =
        await File('${root.path}/deploy/selfhost/Dockerfile').readAsString();

    // Flutter deletes "stale" outputs by path string: build from the physical
    // path into an empty directory so it cannot delete fresh outputs.
    expect(ps1, contains('Resolve-PhysicalPath'));
    expect(ps1, contains("Remove-Item -LiteralPath \$webOut -Recurse -Force"));
    expect(sh, contains('pwd -P'));
    expect(sh, contains('rm -rf build/web'));
    // A failed build must not leave a partial webroot for packaging.
    expect(ps1, contains('trap {'));
    expect(sh, contains("trap 'status=\$?"));
    for (final script in [ps1, sh]) {
      expect(script, contains('const CORE'));
      expect(script, contains('SHA256SUMS'));
      expect(script, contains('useLocalCanvasKit'));
      expect(script, contains('.last_build_id'));
      expect(script, contains('*.symbols'));
      expect(script, isNot(contains('flutter_service_worker.js')));
    }
    expect(dockerfile, contains('sh tool/build_web.sh'));
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
