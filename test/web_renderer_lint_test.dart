import 'package:flutter_test/flutter_test.dart';

import '../tool/lint_web_renderer.dart';

void main() {
  List<String> check(String js) => lintWebRenderer(js, 'bootstrap.js');

  test('rejects the Web 24 Android standalone renderer decision', () {
    final issues = check('''
const installedAndroid =
  (navigator.userAgentData?.platform === 'Android' || /Android/i.test(navigator.userAgent)) &&
  window.matchMedia?.('(display-mode: standalone)').matches;
const forceCpuOnly = renderParams.has('cpu') || installedAndroid;
_flutter.loader.load({config: {canvasKitForceCpuOnly: forceCpuOnly}});
''');
    expect(
        issues,
        contains(
            startsWith('bootstrap.js:2:14 [web-renderer/platform-default]')));
    expect(
        issues,
        contains(
            startsWith('bootstrap.js:3:10 [web-renderer/platform-default]')));
  });

  test(
      'checks installation queries and device reads through common JS spellings',
      () {
    for (final js in [
      'navigator?.["standalone"]',
      'window.navigator /* compatibility */ .platform',
      'const browser = window.navigator; browser?.userAgentData',
      'const {userAgent: ua, platform} = navigator;',
      "const query = '(display-mode: standalone)'; window['matchMedia'](query);",
      "matchMedia('screen and ( display-mode : fullscreen )')",
    ]) {
      expect(check(js), contains(contains('[web-renderer/platform-default]')),
          reason: js);
    }
  });

  test(
      'rejects an unconditional CanvasKit software option including const aliases',
      () {
    for (final js in [
      "load({config: {'canvasKitForceCpuOnly': true}});",
      "config['canvasKitForceCpuOnly'] = true;",
      'const software = true; const cpu = software; load({canvasKitForceCpuOnly: cpu});',
      'const cpu = true\nwindow.config.canvasKitForceCpuOnly = cpu',
    ]) {
      expect(check(js), contains(contains('[web-renderer/always-cpu]')),
          reason: js);
    }
  });

  test(
      'accepts explicit and session fallbacks, other media queries, comments and text',
      () {
    expect(check('''
// Web 24 used navigator.userAgent and matchMedia('(display-mode: standalone)').
/* canvasKitForceCpuOnly: true */
const note = "Previously used navigator['standalone'] or (display-mode: standalone).";
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const label = metadata.platform;
const cpu = renderParams.has('cpu') || (!gpuRequested && temporaryFallbackActive(window.sessionStorage));
_flutter.loader.load({config: {canvasKitForceCpuOnly: cpu}});
'''), isEmpty);
  });
}
