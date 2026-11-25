import 'dart:io';

// Scan the authored CanvasKit bootstrap, before Flutter expands its templates.
// Keep strings as individual tokens so documentation and comments cannot be
// mistaken for property reads, and quoted JS property names still work.
final _lexemes = RegExp(
  r'''//[^\r\n]*|/\*[\s\S]*?\*/|'(?:\\[\s\S]|[^'\\])*'|"(?:\\[\s\S]|[^"\\])*"|`(?:\\[\s\S]|[^`\\])*`|[\w$]+|\S''',
);
final _displayMode = RegExp(r'\(\s*display-mode\s*:', caseSensitive: false);
const _platformProperties = {
  'userAgent',
  'userAgentData',
  'platform',
  'standalone',
  'maxTouchPoints',
};

List<String> lintWebRenderer(String source, String path) {
  final tokens = _lexemes.allMatches(source).where((match) {
    final token = match[0]!;
    return !token.startsWith('//') && !token.startsWith('/*');
  }).toList();
  String at(int i) => i >= 0 && i < tokens.length ? tokens[i][0]! : '';
  String unquote(String s) => s.length >= 2 &&
          (s.startsWith("'") || s.startsWith('"') || s.startsWith('`')) &&
          s.endsWith(s[0])
      ? s.substring(1, s.length - 1)
      : s;
  final diagnostics = <String>[];
  void report(int i, String rule, String message) {
    final offset = tokens[i].start;
    final line = '\n'.allMatches(source.substring(0, offset)).length + 1;
    final column = offset - source.lastIndexOf('\n', offset);
    diagnostics.add('$path:$line:$column [$rule] $message');
  }

  bool endsValue(int i) {
    final next = at(i + 1);
    if (const {'', ';', ',', '}'}.contains(next)) return true;
    // JavaScript also terminates a declaration before a new statement.
    return RegExp(r'^[a-zA-Z_$]').hasMatch(next) &&
        next != 'in' &&
        next != 'instanceof' &&
        source.substring(tokens[i].end, tokens[i + 1].start).contains('\n');
  }

  // Follow simple aliases, including a local name for window.navigator.
  final constants = <String, String>{};
  for (var i = 0; i < tokens.length; i++) {
    if (at(i) == 'const' && at(i + 2) == '=') {
      var value = i + 3;
      if (at(value) == 'window' &&
          at(value + 1) == '.' &&
          at(value + 2) == 'navigator') {
        value += 2;
      }
      if (endsValue(value)) constants[at(i + 1)] = at(value);
    }
  }
  String resolve(String value) {
    final seen = <String>{};
    while (constants.containsKey(value) && seen.add(value)) {
      value = constants[value]!;
    }
    return value;
  }

  for (var i = 0; i < tokens.length; i++) {
    final token = at(i);
    final name = unquote(token);
    final bracket = at(i - 1) == '[' && at(i + 1) == ']';
    final next = bracket ? i + 2 : i + 1;
    var receiver = i - 2;
    if (bracket && at(receiver) == '.') receiver--;
    if (at(receiver) == '?') receiver--;
    if (at(receiver) == ']') receiver--; // window['navigator']
    final navigatorRead = (at(i - 1) == '.' || bracket) &&
        resolve(unquote(at(receiver))) == 'navigator' &&
        _platformProperties.contains(name);
    var unpacked = false;
    if (_platformProperties.contains(name) &&
        (at(i - 1) == '{' || at(i - 1) == ',')) {
      // const { userAgent: ua, platform } = navigator;
      var end = i + 1;
      while (end < tokens.length && !const {'{', '}', ';'}.contains(at(end))) {
        end++;
      }
      if (at(end) == '}' && at(end + 1) == '=') {
        final rhs = at(end + 2) == 'window' && at(end + 3) == '.'
            ? at(end + 4)
            : at(end + 2);
        unpacked = resolve(rhs) == 'navigator';
      }
    }
    var call = next;
    if (at(call) == '?' && at(call + 1) == '.') call += 2;
    final displayModeQuery = name == 'matchMedia' &&
        at(call) == '(' &&
        _displayMode.hasMatch(unquote(resolve(at(call + 1))));
    if (navigatorRead || unpacked || displayModeQuery) {
      report(
          i,
          'web-renderer/platform-default',
          'Keep device and display-mode detection out of the renderer bootstrap. '
              'Default to WebGL; use explicit CPU or temporary session fallback.');
    }
    if (name == 'canvasKitForceCpuOnly' &&
        (at(next) == ':' || at(next) == '=') &&
        resolve(at(next + 1)) == 'true' &&
        endsValue(next + 1)) {
      report(i, 'web-renderer/always-cpu',
          'CanvasKit software rendering must be conditional.');
    }
  }
  return diagnostics;
}

Future<void> main(List<String> args) async {
  if (args.length > 1) {
    stderr.writeln('Usage: dart tool/lint_web_renderer.dart [bootstrap.js]');
    exitCode = 64;
    return;
  }
  final file = File(args.isEmpty ? 'web/flutter_bootstrap.js' : args.single);
  final diagnostics = lintWebRenderer(await file.readAsString(), file.path);
  if (diagnostics.isEmpty) return;
  diagnostics.forEach(stderr.writeln);
  exitCode = 1;
}
