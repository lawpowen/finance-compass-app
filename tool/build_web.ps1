[CmdletBinding()]
param(
  [string]$Flutter = 'flutter',
  [string]$Dart = 'dart',
  [string]$BaseHref = '/',
  [switch]$SkipPubGet
)

$ErrorActionPreference = 'Stop'

# Resolve junctions and symbolic links in every path component. Flutter's
# build system tracks outputs by path string and deletes "stale" outputs whose
# string no longer matches; when the checkout is reached through a junction it
# records a mix of linked and physical paths and deletes files it has just
# written (main.dart.js, assets/, canvaskit/, copied web/ files).
function Resolve-PhysicalPath([string]$Path) {
  $current = [System.IO.Path]::GetFullPath($Path)
  for ($guard = 0; $guard -lt 32; $guard++) {
    $probe = $current
    $suffix = ''
    $changed = $false
    while ($probe) {
      $item = Get-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
      if ($item -and $item.LinkType -in 'Junction', 'SymbolicLink') {
        $target = @($item.Target)[0]
        if (-not [System.IO.Path]::IsPathRooted($target)) {
          $target = Join-Path (Split-Path -Parent $probe) $target
        }
        $current = [System.IO.Path]::GetFullPath((Join-Path $target $suffix))
        $changed = $true
        break
      }
      $leaf = Split-Path -Leaf $probe
      $parent = Split-Path -Parent $probe
      if (-not $parent -or $parent -eq $probe) { break }
      $suffix = if ($suffix) { Join-Path $leaf $suffix } else { $leaf }
      $probe = $parent
    }
    if (-not $changed) { return $current.TrimEnd('\', '/') }
  }
  throw "Could not resolve links in path: $Path"
}

$root = Resolve-PhysicalPath (Split-Path -Parent $PSScriptRoot)
Set-Location -LiteralPath $root
$wasmLock = ConvertFrom-StringData (Get-Content -LiteralPath 'tool/sqlite3_wasm.lock' -Raw)
$pubspecLock = Get-Content -LiteralPath 'pubspec.lock' -Raw
$sqlite3Package = [regex]::Match(
  $pubspecLock,
  '(?ms)^  sqlite3:\s*\r?\n.*?^    version: "([^"]+)"'
).Groups[1].Value
if ($sqlite3Package -ne $wasmLock.SQLITE3_VERSION) {
  throw "pubspec.lock sqlite3 version '$sqlite3Package' does not match tool/sqlite3_wasm.lock '$($wasmLock.SQLITE3_VERSION)'. Update both as one reviewed change."
}
function Assert-LockedWasm([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "$Path is missing. Restore the exact locked runtime asset before building."
  }
  $size = (Get-Item -LiteralPath $Path).Length
  $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
  if ($size -ne [int64]$wasmLock.SIZE_BYTES -or $hash -ne $wasmLock.SHA256) {
    throw "$Path does not match sqlite3 $($wasmLock.SQLITE3_VERSION). Expected $($wasmLock.SHA256) / $($wasmLock.SIZE_BYTES) bytes from $($wasmLock.SOURCE_URL)."
  }
}
Assert-LockedWasm 'web/sqlite3.wasm'

if (-not $SkipPubGet) {
  & $Flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
}

# Drift requires a separately compiled worker in addition to sqlite3.wasm.
& $Dart compile js -O4 -o web/drift_worker.js tool/drift_worker.dart
if ($LASTEXITCODE -ne 0) { throw 'Drift worker compilation failed.' }
Remove-Item -LiteralPath 'web/drift_worker.js.deps','web/drift_worker.js.map' -Force -ErrorAction SilentlyContinue

# Always start from an empty output directory. Flutter records the previous
# build configuration in build/web/.last_build_id and, after a build with a
# different configuration, deletes every file listed in that configuration's
# outputs.json. The configuration hash includes the project path, so building
# the same checkout through another path (for example a junction such as
# C:\Users\<user>\Documents\Codex -> D:\Codex\Projects) makes Flutter delete the
# files it has just written (main.dart.js, flutter_bootstrap.js, assets/, and
# every copied web/ file). A clean directory also keeps stale files from older
# builds out of the release.
$webOut = Join-Path $root 'build/web'
if (Test-Path -LiteralPath $webOut) { Remove-Item -LiteralPath $webOut -Recurse -Force }
# A failed build or check must not leave a partial webroot that
# package_selfhost.ps1 -SkipWebBuild would package; rethrow afterwards.
trap {
  if ($webOut -and (Test-Path -LiteralPath $webOut)) { Remove-Item -LiteralPath $webOut -Recurse -Force -ErrorAction SilentlyContinue }
  break
}

& $Flutter build web --release --no-web-resources-cdn --base-href $BaseHref
if ($LASTEXITCODE -ne 0) { throw 'Flutter Web release build failed.' }
# Debug-only sidecars and Flutter's build bookkeeping are not loaded at runtime
# and are not published.
Remove-Item -LiteralPath 'build/web/.last_build_id','build/web/drift_worker.dart','build/web/drift_worker.js.deps','build/web/drift_worker.js.map' -Force -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath 'build/web' -Recurse -File -Include '*.symbols','*.map' | Remove-Item -Force

foreach ($required in 'index.html', 'flutter_bootstrap.js', 'manifest.json', 'service-worker.js', 'pwa_bootstrap.js', 'sqlite3.wasm', 'drift_worker.js', 'main.dart.js', 'flutter.js', 'version.json', 'favicon.png', 'assets/AssetManifest.bin', 'assets/FontManifest.json', 'assets/fonts/MaterialIcons-Regular.otf', 'canvaskit/canvaskit.js', 'canvaskit/canvaskit.wasm', 'canvaskit/chromium/canvaskit.js', 'canvaskit/chromium/canvaskit.wasm', 'canvaskit/skwasm.js', 'canvaskit/skwasm.wasm', 'canvaskit/skwasm_heavy.js', 'canvaskit/skwasm_heavy.wasm', 'canvaskit/wimp.js', 'canvaskit/wimp.wasm') {
  $path = Join-Path 'build/web' $required
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing web release asset: $required" }
}

# Every service-worker precache entry must exist, otherwise cache.addAll()
# rejects and the PWA never installs its offline shell.
$workerSource = Get-Content -LiteralPath 'build/web/service-worker.js' -Raw
$coreBlock = [regex]::Match($workerSource, '(?s)const CORE = \[(.*?)\];')
if (-not $coreBlock.Success) { throw 'build/web/service-worker.js has no CORE precache list.' }
$coreEntries = [regex]::Matches($coreBlock.Groups[1].Value, "'\./([^']*)'") | ForEach-Object { $_.Groups[1].Value }
if (@($coreEntries).Count -lt 10) { throw 'service-worker.js CORE precache list could not be parsed.' }
foreach ($entry in $coreEntries) {
  $relative = if ($entry -eq '') { 'index.html' } else { $entry }
  if (-not (Test-Path -LiteralPath (Join-Path 'build/web' $relative) -PathType Leaf)) {
    throw "service-worker.js precaches './$entry' but build/web/$relative does not exist."
  }
}

$bootstrap = Get-Content -LiteralPath 'build/web/flutter_bootstrap.js' -Raw
if (-not $bootstrap.Contains("fontFallbackBaseUrl: 'fonts/'") -or $bootstrap -match 'serviceWorkerSettings\s*:\s*\{' -or $bootstrap.Contains('{{')) {
  throw "build/web/flutter_bootstrap.js must come from web/flutter_bootstrap.js: fontFallbackBaseUrl 'fonts/', no service worker settings, no unresolved template tokens."
}
# flutter.js always contains the gstatic CanvasKit URL, but only uses it when
# the build config lacks useLocalCanvasKit, which --no-web-resources-cdn sets.
# main.dart.js may only contain the engine's default fontFallbackBaseUrl, which
# the self-hosted CSP (connect-src 'self') blocks; any other gstatic reference
# means CDN-loaded runtime code.
if (-not $bootstrap.Contains('"useLocalCanvasKit":true')) {
  throw 'flutter_bootstrap.js build config lacks "useLocalCanvasKit":true; expected --no-web-resources-cdn output.'
}
$mainJs = Get-Content -LiteralPath 'build/web/main.dart.js' -Raw
if ([regex]::Matches($mainJs, 'gstatic\.com').Count -ne [regex]::Matches($mainJs, '"https://fonts\.gstatic\.com/s/"').Count) {
  throw 'main.dart.js references gstatic.com beyond the engine font-fallback default; expected --no-web-resources-cdn output.'
}

# Same-origin fallback fonts: every vendored file matches web/fonts/SHA256SUMS,
# and every URL of a vendored family that this engine build can request exists.
# A Flutter upgrade that changes font versions fails here instead of shipping a
# UI without text.
$fontEntries = @{}
foreach ($line in Get-Content -LiteralPath 'build/web/fonts/SHA256SUMS') {
  if (-not $line.Trim()) { continue }
  $parts = $line.Trim() -split '\s+', 2
  $fontEntries[$parts[1]] = $parts[0].ToUpperInvariant()
}
if ($fontEntries.Count -eq 0) { throw 'build/web/fonts/SHA256SUMS lists no fonts.' }
foreach ($font in $fontEntries.GetEnumerator()) {
  $path = Join-Path 'build/web/fonts' $font.Key
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing fallback font: fonts/$($font.Key)" }
  if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $font.Value) {
    throw "Fallback font does not match web/fonts/SHA256SUMS: fonts/$($font.Key)"
  }
}
$fontFiles = @(Get-ChildItem -LiteralPath 'build/web/fonts' -Recurse -File -Include '*.woff2','*.ttf')
if ($fontFiles.Count -ne $fontEntries.Count) {
  throw "build/web/fonts has $($fontFiles.Count) font files but SHA256SUMS lists $($fontEntries.Count)."
}
# Roboto (Latin UI) and Noto Sans SC (Chinese UI) are always required; any
# other vendored family is checked as well.
$fontFamilies = @('roboto', 'notosanssc') + @($fontEntries.Keys | ForEach-Object { ($_ -split '/')[0] }) | Sort-Object -Unique
$fallbackPattern = '"((?:' + (($fontFamilies | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')/v\d+/[^"]+\.(?:woff2|ttf))"'
$fallbackUrls = @([regex]::Matches($mainJs, $fallbackPattern) | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if ($fallbackUrls.Count -eq 0) { throw 'No fallback font URLs found in main.dart.js; the engine font fallback format changed.' }
foreach ($url in $fallbackUrls) {
  if (-not $fontEntries.ContainsKey($url)) { throw "main.dart.js can request fallback font fonts/$url, which is not vendored in web/fonts." }
}
Assert-LockedWasm 'build/web/sqlite3.wasm'
if ((Get-FileHash -LiteralPath 'build/web/drift_worker.js').Hash -ne (Get-FileHash -LiteralPath 'web/drift_worker.js').Hash) {
  throw 'build/web/drift_worker.js differs from the freshly compiled web/drift_worker.js.'
}
foreach ($forbidden in '.last_build_id', 'drift_worker.dart', 'drift_worker.js.deps', 'drift_worker.js.map') {
  if (Test-Path -LiteralPath (Join-Path 'build/web' $forbidden)) {
    throw "Web release must not publish worker source or debug sidecar: $forbidden"
  }
}
$sidecars = @(Get-ChildItem -LiteralPath 'build/web' -Recurse -File -Include '*.symbols','*.map','*.deps')
if ($sidecars.Count -gt 0) {
  throw "Web release must not publish debug sidecars: $($sidecars.Name -join ', ')"
}

Write-Host "Web build complete: build/web ($(@(Get-ChildItem -LiteralPath 'build/web' -Recurse -File).Count) files, $(@($coreEntries).Count) precache entries and $($fontEntries.Count) fallback fonts verified)"
