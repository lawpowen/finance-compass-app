#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
command -v docker >/dev/null 2>&1 || {
  echo 'Docker Engine/Desktop with Docker Compose is required.' >&2; exit 1;
}
docker compose version >/dev/null
docker compose up -d --build
echo 'Finance Compass is listening only on http://127.0.0.1:8080 by default.'
echo 'Use Caddyfile.reverse-proxy.example with HTTPS and access control before public exposure.'
