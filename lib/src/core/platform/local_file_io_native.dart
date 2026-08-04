import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> writeUtf8Text(String path, String contents) async {
  final file = File(path);
  await file.writeAsString(contents);
  return file.path;
}

Future<Uint8List> readFileBytes(String path) => File(path).readAsBytes();

Future<String> defaultExportPath() async {
  final directory = await getApplicationDocumentsDirectory();
  final timestamp = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
  return p.join(directory.path, 'finance_compass_export_$timestamp.json');
}

Future<String?> importRestorePointPath() async {
  final directory = await getApplicationDocumentsDirectory();
  return p.join(
    directory.path,
    'finance_compass_before_import_${DateTime.now().millisecondsSinceEpoch}.json',
  );
}
