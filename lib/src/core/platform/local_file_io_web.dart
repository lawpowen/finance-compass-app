import 'dart:typed_data';

Never _unsupported() =>
    throw UnsupportedError('浏览器不允许按本机路径读取或写入文件；请使用页面提供的文件选择和下载操作。');

Future<String> writeUtf8Text(String path, String contents) async =>
    _unsupported();
Future<Uint8List> readFileBytes(String path) async => _unsupported();
Future<String> defaultExportPath() async => _unsupported();
Future<String?> importRestorePointPath() async => null;
