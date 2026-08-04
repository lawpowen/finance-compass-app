[CmdletBinding()]
param(
  [string]$Flutter = 'flutter',
  [string]$Dart = 'dart',
  [string]$BaseHref = '/',
  [switch]$SkipPubGet
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$wasmLock = ConvertFrom-StringData (Get-Content -LiteralPath 'tool/sqlite3_wasm.lock' -Raw)
$pubspecLock = Get-Content -LiteralPath 'pubspec.lock' -Raw
$sqlite3Package = [regex]::Match(
  $pubspecLock,
  '(?ms)^  sqlite3:\s*\r?\n.*?^    version: "([^"]+)"'
).Groups[1].Value
if ($sqlite3Package -ne $wasmLock.SQLITE3_VERSION) {
  throw "pubspec.lock sqlite3 version '$sqlite3Package' does not match tool/sqlite3_wasm.lock '$($wasmLock.SQLITE3_VERSION)'. Update both as one reviewed change."
}
if (-not (Test-Path -LiteralPath 'web/sqlite3.wasm')) {
  throw 'web/sqlite3.wasm is missing. Restore the exact locked runtime asset before building.'
}
$wasmSize = (Get-Item -LiteralPath 'web/sqlite3.wasm').Length
$wasmHash = (Get-FileHash -LiteralPath 'web/sqlite3.wasm' -Algorithm SHA256).Hash
if ($wasmSize -ne [int64]$wasmLock.SIZE_BYTES -or $wasmHash -ne $wasmLock.SHA256) {
  throw "web/sqlite3.wasm does not match sqlite3 $($wasmLock.SQLITE3_VERSION). Expected $($wasmLock.SHA256) / $($wasmLock.SIZE_BYTES) bytes from $($wasmLock.SOURCE_URL)."
}

if (-not $SkipPubGet) {
  & $Flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
}

# Drift requires a separately compiled worker in addition to sqlite3.wasm.
& $Dart compile js -O4 -o web/drift_worker.js tool/drift_worker.dart
if ($LASTEXITCODE -ne 0) { throw 'Drift worker compilation failed.' }
Remove-Item -LiteralPath 'web/drift_worker.js.deps','web/drift_worker.js.map' -Force -ErrorAction SilentlyContinue

& $Flutter build web --release --no-web-resources-cdn --base-href $BaseHref
if ($LASTEXITCODE -ne 0) { throw 'Flutter Web release build failed.' }
Remove-Item -LiteralPath 'build/web/drift_worker.dart','build/web/drift_worker.js.deps','build/web/drift_worker.js.map' -Force -ErrorAction SilentlyContinue

foreach ($required in 'index.html', 'manifest.json', 'service-worker.js', 'flutter_service_worker.js', 'pwa_bootstrap.js', 'sqlite3.wasm', 'drift_worker.js', 'main.dart.js', 'flutter.js', 'assets/AssetManifest.bin', 'assets/FontManifest.json', 'assets/fonts/MaterialIcons-Regular.otf', 'canvaskit/canvaskit.js', 'canvaskit/canvaskit.wasm', 'canvaskit/skwasm.js', 'canvaskit/skwasm.wasm', 'canvaskit/skwasm_heavy.js', 'canvaskit/skwasm_heavy.wasm', 'canvaskit/wimp.js', 'canvaskit/wimp.wasm') {
  $path = Join-Path 'build/web' $required
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing web release asset: $required" }
}
$webJavaScript = Get-Content -LiteralPath 'build/web/flutter.js','build/web/flutter_bootstrap.js','build/web/main.dart.js' -Raw
if ($webJavaScript.Contains('gstatic.com')) {
  throw 'Web release still references gstatic.com; expected --no-web-resources-cdn output.'
}
foreach ($forbidden in 'drift_worker.dart', 'drift_worker.js.deps', 'drift_worker.js.map') {
  if (Test-Path -LiteralPath (Join-Path 'build/web' $forbidden)) {
    throw "Web release must not publish worker source or debug sidecar: $forbidden"
  }
}

Write-Host 'Web build complete: build/web'
