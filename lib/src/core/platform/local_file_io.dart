import 'dart:typed_data';

import 'local_file_io_native.dart'
    if (dart.library.js_interop) 'local_file_io_web.dart' as platform;

Future<String> writeUtf8Text(String path, String contents) =>
    platform.writeUtf8Text(path, contents);

Future<Uint8List> readFileBytes(String path) => platform.readFileBytes(path);

Future<String> defaultExportPath() => platform.defaultExportPath();

/// Native targets create a recoverable JSON restore point before replacement.
/// Web does not claim to write hidden files; callers must offer an explicit
/// download before replacing browser-local data.
Future<String?> importRestorePointPath() => platform.importRestorePointPath();
