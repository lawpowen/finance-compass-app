# Build the Flutter Web app, including the Drift worker required by SQLite WASM.
FROM ghcr.io/cirruslabs/flutter:3.44.1 AS build
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
RUN dart compile js -O4 -o web/drift_worker.js tool/drift_worker.dart \
 && rm -f web/drift_worker.js.deps web/drift_worker.js.map \
 && test "$(awk '/^  sqlite3:/{in_sqlite3=1; next} in_sqlite3 && /^    version:/{gsub(/"/, "", $2); print $2; exit}' pubspec.lock)" = "$(grep '^SQLITE3_VERSION=' tool/sqlite3_wasm.lock | cut -d= -f2)" \
 && test "$(wc -c < web/sqlite3.wasm | tr -d ' ')" = "$(grep '^SIZE_BYTES=' tool/sqlite3_wasm.lock | cut -d= -f2)" \
 && test "$(sha256sum web/sqlite3.wasm | awk '{print toupper($1)}')" = "$(grep '^SHA256=' tool/sqlite3_wasm.lock | cut -d= -f2)" \
 && flutter build web --release --no-web-resources-cdn \
 && test -f build/web/sqlite3.wasm \
 && test -f build/web/drift_worker.js \
 && test ! -e build/web/drift_worker.dart \
 && test ! -e build/web/drift_worker.js.deps \
 && test ! -e build/web/drift_worker.js.map \
 && test -f build/web/main.dart.js \
 && test -f build/web/canvaskit/canvaskit.wasm \
 && test -f build/web/canvaskit/skwasm.wasm \
 && test -f build/web/canvaskit/skwasm_heavy.wasm \
 && test -f build/web/canvaskit/wimp.wasm \
 && ! grep -q 'gstatic\.com' build/web/flutter.js build/web/flutter_bootstrap.js build/web/main.dart.js

# Caddy only serves immutable client files. No finance API or server database
# is included in this image.
FROM caddy:2.10.2-alpine
COPY deploy/selfhost/Caddyfile /etc/caddy/Caddyfile
COPY --from=build /src/build/web /srv
EXPOSE 8080
