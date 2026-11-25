import 'dart:io';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/app_version.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/utils/id_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('full backup reports the app release declared by pubspec', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    final declared = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(pubspec)!
        .group(1);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = await FinanceRepository.load(db);
    expect(appVersion, declared);
    final worker = await File('web/service-worker.js').readAsString();
    final shellRelease = RegExp(
            r"const CACHE_NAME = 'finance-compass-shell-consent-v([^']+)-sync(\d+)';")
        .firstMatch(worker)!;
    expect(shellRelease.group(1), appVersion.split('+').first);
    expect(webReleaseLabel, 'Web ${shellRelease.group(2)}');
    expect((await repo.buildJsonSnapshotPayload())['app_version'], declared);
    expect(repo.accountName('missing'), '已删除账户');
    expect(repo.categoryName('missing'), '已删除类别');
  });

  test('snapshot IDs remain distinct within a burst of local writes', () {
    final ids = {for (var i = 0; i < 20000; i++) buildId('snap')};
    expect(ids.length, 20000);
    expect(ids.every((id) => id.startsWith('snap_')), isTrue);
  });
}
