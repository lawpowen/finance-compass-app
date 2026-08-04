import 'package:flutter_test/flutter_test.dart';

import '../tool/visual_qa_capture_test.dart' as capture;

void main() {
  const enabled = bool.fromEnvironment('CAPTURE_VISUAL_QA');
  if (enabled) {
    capture.main();
    return;
  }
  test(
    'manual 390px visual QA capture',
    () {},
    skip: 'Run with --dart-define=CAPTURE_VISUAL_QA=true.',
  );
}
