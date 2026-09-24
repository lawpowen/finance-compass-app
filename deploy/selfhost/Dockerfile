# Build the Flutter Web app, including the Drift worker required by SQLite WASM.
FROM ghcr.io/cirruslabs/flutter:3.44.1 AS build
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
# The same script as the Windows/Linux release path: sqlite3.wasm lock check,
# Drift worker compile, clean build/web, debug-sidecar removal, and the
# webroot/service-worker precache contract checks.
RUN SKIP_PUB_GET=1 sh tool/build_web.sh

# Caddy only serves immutable client files. No finance API or server database
# is included in this image.
FROM caddy:2.10.2-alpine
RUN setcap -r /usr/bin/caddy
COPY deploy/selfhost/Caddyfile /etc/caddy/Caddyfile
COPY --from=build /src/build/web /srv
EXPOSE 8080
