import 'package:drift/wasm.dart';

/// Compiled into web/drift_worker.js by the web build scripts. Keeping the
/// source outside web/ prevents it and compiler source maps from being served.
void main() => WasmDatabase.workerMainForOpen();
