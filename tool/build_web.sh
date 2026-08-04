#!/usr/bin/env sh
set -eu

FLUTTER="${FLUTTER:-flutter}"
DART="${DART:-dart}"
BASE_HREF="${BASE_HREF:-/}"
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
. tool/sqlite3_wasm.lock

locked_sqlite3=$(awk '/^  sqlite3:/{in_sqlite3=1; next} in_sqlite3 && /^    version:/{gsub(/"/, "", $2); print $2; exit}' pubspec.lock)
if [ "$locked_sqlite3" != "$SQLITE3_VERSION" ]; then
  echo "pubspec.lock sqlite3 version '$locked_sqlite3' does not match tool/sqlite3_wasm.lock '$SQLITE3_VERSION'." >&2
  exit 1
fi

test -f web/sqlite3.wasm || { echo 'web/sqlite3.wasm is missing.' >&2; exit 1; }
actual_size=$(wc -c < web/sqlite3.wasm | tr -d ' ')
actual_hash=$(sha256sum web/sqlite3.wasm | awk '{print toupper($1)}')
if [ "$actual_size" != "$SIZE_BYTES" ] || [ "$actual_hash" != "$SHA256" ]; then
  echo "web/sqlite3.wasm does not match sqlite3 $SQLITE3_VERSION: expected $SHA256 / $SIZE_BYTES bytes from $SOURCE_URL" >&2
  exit 1
fi

if [ "${SKIP_PUB_GET:-0}" != "1" ]; then
  "$FLUTTER" pub get
fi
"$DART" compile js -O4 -o web/drift_worker.js tool/drift_worker.dart
rm -f web/drift_worker.js.deps web/drift_worker.js.map
"$FLUTTER" build web --release --no-web-resources-cdn --base-href "$BASE_HREF"
rm -f build/web/drift_worker.dart build/web/drift_worker.js.deps build/web/drift_worker.js.map

for file in index.html manifest.json service-worker.js flutter_service_worker.js pwa_bootstrap.js sqlite3.wasm drift_worker.js main.dart.js flutter.js assets/AssetManifest.bin assets/FontManifest.json assets/fonts/MaterialIcons-Regular.otf canvaskit/canvaskit.js canvaskit/canvaskit.wasm canvaskit/skwasm.js canvaskit/skwasm.wasm canvaskit/skwasm_heavy.js canvaskit/skwasm_heavy.wasm canvaskit/wimp.js canvaskit/wimp.wasm; do
  test -f "build/web/$file" || { echo "Missing web release asset: $file" >&2; exit 1; }
done
if grep -q 'gstatic\.com' build/web/flutter.js build/web/flutter_bootstrap.js build/web/main.dart.js; then
  echo 'Web release still references gstatic.com; expected --no-web-resources-cdn output.' >&2
  exit 1
fi
for forbidden in drift_worker.dart drift_worker.js.deps drift_worker.js.map; do
  test ! -e "build/web/$forbidden" || { echo "Unexpected worker source/debug sidecar: $forbidden" >&2; exit 1; }
done
echo 'Web build complete: build/web'
