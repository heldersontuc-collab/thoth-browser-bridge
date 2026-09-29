#!/usr/bin/env bash
set -euo pipefail

NET="thoth-browser-node_control_api"
API="thoth-browser-node-api-1"
BROWSER="thoth-browser-node-browser-1"

docker inspect "$API" >/dev/null
docker inspect "$BROWSER" >/dev/null

if ! docker network inspect "$NET" >/dev/null 2>&1; then
  docker network create --driver bridge --internal "$NET" >/dev/null
fi

if ! docker inspect "$API" --format '{{json .NetworkSettings.Networks}}' | grep -q "\"$NET\""; then
  docker network connect --alias api "$NET" "$API"
fi

if docker inspect "$BROWSER" --format '{{json .NetworkSettings.Networks}}' | grep -q "\"$NET\""; then
  echo "ERRO: Chromium apareceu na rede de controle."
  exit 1
fi

echo "THOTH_CONTROL_NETWORK_OK"
