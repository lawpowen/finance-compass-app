#!/usr/bin/env sh
set -eu

FLUTTER="${FLUTTER:-flutter}"
DART="${DART:-dart}"
BASE_HREF="${BASE_HREF:-/}"
# pwd -P resolves symlinks: Flutter tracks outputs by path string and deletes
# "stale" outputs whose string no longer matches, so building through a linked
# path can delete files it has just written.
ROOT=$(CDPATH= cd -P -- "$(dirname -- "$0")/.." && pwd -P)
cd "$ROOT"
. tool/sqlite3_wasm.lock

locked_sqlite3=$(awk '/^  sqlite3:/{in_sqlite3=1; next} in_sqlite3 && /^    version:/{gsub(/"/, "", $2); print $2; exit}' pubspec.lock)
if [ "$locked_sqlite3" != "$SQLITE3_VERSION" ]; then
  echo "pubspec.lock sqlite3 version '$locked_sqlite3' does not match tool/sqlite3_wasm.lock '$SQLITE3_VERSION'." >&2
  exit 1
fi

assert_locked_wasm() {
  test -f "$1" || { echo "$1 is missing." >&2; exit 1; }
  actual_size=$(wc -c < "$1" | tr -d ' ')
  actual_hash=$(sha256sum "$1" | awk '{print toupper($1)}')
  if [ "$actual_size" != "$SIZE_BYTES" ] || [ "$actual_hash" != "$SHA256" ]; then
    echo "$1 does not match sqlite3 $SQLITE3_VERSION: expected $SHA256 / $SIZE_BYTES bytes from $SOURCE_URL" >&2
    exit 1
  fi
}
assert_locked_wasm web/sqlite3.wasm

if [ "${SKIP_PUB_GET:-0}" != "1" ]; then
  "$FLUTTER" pub get
fi
"$DART" compile js -O4 -o web/drift_worker.js tool/drift_worker.dart
rm -f web/drift_worker.js.deps web/drift_worker.js.map

# Always start from an empty output directory. Flutter records the previous
# build configuration in build/web/.last_build_id and, after a build with a
# different configuration (the hash includes the project path), deletes every
# file listed in that configuration's outputs.json. A clean directory also
# keeps stale files from older builds out of the release.
rm -rf build/web
# A failed build or check must not leave a partial webroot for packaging.
trap 'status=$?; if [ "$status" -ne 0 ]; then rm -rf build/web; fi; exit "$status"' EXIT
"$FLUTTER" build web --release --no-web-resources-cdn --base-href "$BASE_HREF"
# Debug-only sidecars and Flutter's build bookkeeping are not loaded at runtime
# and are not published.
rm -f build/web/.last_build_id build/web/drift_worker.dart build/web/drift_worker.js.deps build/web/drift_worker.js.map
find build/web -type f \( -name '*.symbols' -o -name '*.map' \) -exec rm -f {} +

for file in index.html flutter_bootstrap.js manifest.json service-worker.js pwa_bootstrap.js sqlite3.wasm drift_worker.js main.dart.js flutter.js version.json favicon.png assets/AssetManifest.bin assets/FontManifest.json assets/fonts/MaterialIcons-Regular.otf canvaskit/canvaskit.js canvaskit/canvaskit.wasm canvaskit/chromium/canvaskit.js canvaskit/chromium/canvaskit.wasm canvaskit/skwasm.js canvaskit/skwasm.wasm canvaskit/skwasm_heavy.js canvaskit/skwasm_heavy.wasm canvaskit/wimp.js canvaskit/wimp.wasm; do
  test -f "build/web/$file" || { echo "Missing web release asset: $file" >&2; exit 1; }
done

# Every service-worker precache entry must exist, otherwise cache.addAll()
# rejects and the PWA never installs its offline shell.
core_entries=$(awk '/const CORE = \[/{in_core=1; next} in_core && /^\];/{exit} in_core' build/web/service-worker.js \
  | sed -n "s/^[[:space:]]*'\.\/\([^']*\)',.*$/\1/p")
core_count=$(printf '%s\n' "$core_entries" | grep -c . || true)
if [ "$core_count" -lt 10 ]; then
  echo 'service-worker.js CORE precache list could not be parsed.' >&2
  exit 1
fi
test -f build/web/index.html || { echo "service-worker.js precaches './' but build/web/index.html does not exist." >&2; exit 1; }
for entry in $core_entries; do
  test -f "build/web/$entry" || { echo "service-worker.js precaches './$entry' but build/web/$entry does not exist." >&2; exit 1; }
done

if ! grep -qF "fontFallbackBaseUrl: 'fonts/'" build/web/flutter_bootstrap.js \
  || grep -qE 'serviceWorkerSettings[[:space:]]*:[[:space:]]*\{' build/web/flutter_bootstrap.js \
  || grep -qF '{{' build/web/flutter_bootstrap.js; then
  echo "build/web/flutter_bootstrap.js must come from web/flutter_bootstrap.js: fontFallbackBaseUrl 'fonts/', no service worker settings, no unresolved template tokens." >&2
  exit 1
fi
# flutter.js always contains the gstatic CanvasKit URL, but only uses it when
# the build config lacks useLocalCanvasKit, which --no-web-resources-cdn sets.
# main.dart.js may only contain the engine's default fontFallbackBaseUrl, which
# the self-hosted CSP (connect-src 'self') blocks; any other gstatic reference
# means CDN-loaded runtime code.
grep -qF '"useLocalCanvasKit":true' build/web/flutter_bootstrap.js || {
  echo 'flutter_bootstrap.js build config lacks "useLocalCanvasKit":true; expected --no-web-resources-cdn output.' >&2
  exit 1
}
all_gstatic=$(grep -o 'gstatic\.com' build/web/main.dart.js | wc -l | tr -d ' ')
font_fallback=$(grep -oF '"https://fonts.gstatic.com/s/"' build/web/main.dart.js | wc -l | tr -d ' ')
if [ "$all_gstatic" != "$font_fallback" ]; then
  echo 'main.dart.js references gstatic.com beyond the engine font-fallback default; expected --no-web-resources-cdn output.' >&2
  exit 1
fi

# Same-origin fallback fonts: every vendored file matches web/fonts/SHA256SUMS,
# and every URL of a vendored family that this engine build can request exists.
# A Flutter upgrade that changes font versions fails here instead of shipping a
# UI without text. tr strips CR in case a Windows checkout converted line ends.
test -f build/web/fonts/SHA256SUMS || { echo 'Missing build/web/fonts/SHA256SUMS.' >&2; exit 1; }
font_list=$(tr -d '\r' < build/web/fonts/SHA256SUMS | awk 'NF')
font_count=$(printf '%s\n' "$font_list" | grep -c . || true)
if [ "$font_count" -eq 0 ]; then
  echo 'build/web/fonts/SHA256SUMS lists no fonts.' >&2
  exit 1
fi
(cd build/web/fonts && printf '%s\n' "$font_list" | sha256sum -c --quiet -) || {
  echo 'Fallback fonts do not match web/fonts/SHA256SUMS.' >&2
  exit 1
}
font_paths=$(printf '%s\n' "$font_list" | awk '{print $2}')
font_files=$(find build/web/fonts -type f \( -name '*.woff2' -o -name '*.ttf' \) | wc -l | tr -d ' ')
if [ "$font_files" != "$font_count" ]; then
  echo "build/web/fonts has $font_files font files but SHA256SUMS lists $font_count." >&2
  exit 1
fi
# Roboto (Latin UI) and Noto Sans SC (Chinese UI) are always required; any
# other vendored family is checked as well.
font_families=$( (printf 'roboto\nnotosanssc\n'; printf '%s\n' "$font_paths" | cut -d/ -f1) | sort -u | paste -sd'|' -)
fallback_urls=$(grep -oE "\"($font_families)/v[0-9]+/[^\"]+\.(woff2|ttf)\"" build/web/main.dart.js | tr -d '"' | sort -u || true)
if [ -z "$fallback_urls" ]; then
  echo 'No fallback font URLs found in main.dart.js; the engine font fallback format changed.' >&2
  exit 1
fi
for url in $fallback_urls; do
  printf '%s\n' "$font_paths" | grep -qxF "$url" || {
    echo "main.dart.js can request fallback font fonts/$url, which is not vendored in web/fonts." >&2
    exit 1
  }
done
assert_locked_wasm build/web/sqlite3.wasm
cmp -s web/drift_worker.js build/web/drift_worker.js || { echo 'build/web/drift_worker.js differs from the freshly compiled web/drift_worker.js.' >&2; exit 1; }
for forbidden in .last_build_id drift_worker.dart drift_worker.js.deps drift_worker.js.map; do
  test ! -e "build/web/$forbidden" || { echo "Unexpected worker source/debug sidecar: $forbidden" >&2; exit 1; }
done
sidecars=$(find build/web -type f \( -name '*.symbols' -o -name '*.map' -o -name '*.deps' \))
if [ -n "$sidecars" ]; then
  echo "Web release must not publish debug sidecars: $sidecars" >&2
  exit 1
fi
echo "Web build complete: build/web ($(find build/web -type f | wc -l | tr -d ' ') files, $((core_count + 1)) precache entries and $font_count fallback fonts verified)"
