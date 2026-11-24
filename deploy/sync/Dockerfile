FROM debian:bookworm-slim AS flutter-sdk
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils zip \
    && rm -rf /var/lib/apt/lists/* \
    && git clone --quiet --depth 1 --branch 3.44.1 --single-branch \
       https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}" CI=true FLUTTER_SUPPRESS_ANALYTICS=true
RUN flutter precache --web

FROM flutter-sdk AS build
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get --enforce-lockfile
COPY lib ./lib
COPY assets ./assets
COPY web ./web
COPY tool/build_web.sh tool/drift_worker.dart tool/sqlite3_wasm.lock ./tool/
RUN sed -i 's/\r$//' pubspec.lock tool/build_web.sh tool/sqlite3_wasm.lock \
    && SKIP_PUB_GET=1 FINANCE_SYNC_WEB=true sh tool/build_web.sh

FROM caddy:2.11.9-alpine AS web
RUN setcap -r /usr/bin/caddy
COPY deploy/sync/Caddyfile /etc/caddy/Caddyfile
COPY --from=build /src/build/web /srv
EXPOSE 8080

FROM node:24-bookworm-slim AS sync
WORKDIR /app
COPY server/package.json server/package-lock.json ./server/
RUN cd server && npm ci --omit=dev --ignore-scripts --no-audit --no-fund
COPY --chown=node:node server/ ./server/
RUN install -d -m 0700 -o node -g node /data /data/backups
ENV NODE_ENV=production
USER node
EXPOSE 8081
CMD ["node", "server/sync.mjs"]
