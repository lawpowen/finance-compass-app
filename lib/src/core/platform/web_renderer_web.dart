import 'dart:js_interop';

@JS('window.financeCompassCpuRendering')
external bool? get _cpuRendering;

// The bootstrap selects the CanvasKit renderer before loading the Dart entrypoint.
final isSoftwareRenderer =
    _cpuRendering ?? Uri.base.queryParameters.containsKey('cpu');
