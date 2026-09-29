#!/usr/bin/env bash
set -euo pipefail

RAW="https://raw.githubusercontent.com/heldersontuc-collab/thoth-browser-bridge/main"

echo "==> Preparando rede isolada sem reiniciar Browser Node"
curl -fsSL "$RAW/prepare_control_network.sh" | bash

echo
echo "==> Atualizando Bridge auditado"
curl -fsSL "$RAW/bootstrap.sh" | bash

echo
echo "THOTH_BRIDGE_CORE_DEPLOY_OK"
