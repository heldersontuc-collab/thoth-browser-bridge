#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/heldersontuc-collab/thoth-browser-bridge.git"
DIR="/opt/thoth-browser-bridge"
NODE_DIR="/opt/thoth-browser-node/THOTH_BROWSER_NODE_V1_2_1_VPS_SAFE"

say(){ printf '\n==> %s\n' "$*"; }
fail(){ printf '\nERRO: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "rode como root"
command -v git >/dev/null 2>&1 || fail "git nao encontrado"
command -v docker >/dev/null 2>&1 || fail "docker nao encontrado"
docker compose version >/dev/null 2>&1 || fail "docker compose nao encontrado"
[ -f "$NODE_DIR/.env" ] || fail "nao encontrei o THOTH Browser Node em $NODE_DIR"

API_KEY="$(sed -n 's/^THOTH_API_KEY=//p' "$NODE_DIR/.env" | tail -1 | tr -d '\r')"
[ -n "$API_KEY" ] || fail "THOTH_API_KEY ausente no Browser Node"

say "Verificando rede isolada de controle"
docker network inspect thoth-browser-node_control_api >/dev/null 2>&1 || fail "rede thoth-browser-node_control_api nao encontrada"

say "Atualizando arquivos da ponte"
if [ -d "$DIR/.git" ]; then
  git -C "$DIR" fetch origin main
  git -C "$DIR" reset --hard origin/main
else
  mkdir -p "$DIR"
  git clone --depth 1 "$REPO" "$DIR"
fi

mkdir -p "$DIR/data/keys" "$DIR/data/results"
chown -R 65532:65532 "$DIR/data"
chmod 700 "$DIR/data" "$DIR/data/keys" "$DIR/data/results"

say "Construindo e iniciando somente o THOTH Browser Bridge"
cd "$DIR"
install -d -m 700 -o 65532 -g 65532 "$DIR/data" "$DIR/data/keys" "$DIR/data/results"

# IMPORTANTE: nao carregar o .env inteiro do Browser Node no Docker Compose.
# Ele contem COMPOSE_PROJECT_NAME=thoth-browser-node e causava o Bridge a
# tentar entrar no projeto do Browser Node, gerando orfaos e colisao na 8800.
dc(){ THOTH_API_KEY="$API_KEY" COMPOSE_PROJECT_NAME=thoth-browser-bridge docker compose "$@"; }

# Limpa apenas o container espurio criado pelo bug antigo de project-name.
if docker inspect thoth-browser-node-bridge-1 >/dev/null 2>&1; then
  STATE="$(docker inspect thoth-browser-node-bridge-1 --format '{{.State.Status}}' 2>/dev/null || true)"
  if [ "$STATE" != "running" ]; then
    docker rm -f thoth-browser-node-bridge-1 >/dev/null 2>&1 || true
  else
    fail "container espurio thoth-browser-node-bridge-1 esta rodando; nao vou remove-lo automaticamente"
  fi
fi

dc up -d --build bridge

say "Confirmando que o container ficou em execucao"
sleep 2
dc ps

say "Testando endpoint local"
for i in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8800/healthz >/tmp/thoth_bridge_health.json 2>/dev/null; then
    cat /tmp/thoth_bridge_health.json
    echo
    break
  fi
  sleep 2
  [ "$i" -lt 30 ] || { echo; echo "=== LOGS DO BRIDGE ==="; dc logs --tail=120 bridge || true; fail "bridge nao respondeu em 127.0.0.1:8800"; }
done

say "Testando prontidao real: fila GitHub + API autenticada do navegador"
READY_OK=false
for i in $(seq 1 20); do
  if curl -fsS http://127.0.0.1:8800/readyz >/tmp/thoth_bridge_ready.json 2>/dev/null; then
    cat /tmp/thoth_bridge_ready.json
    echo
    READY_OK=true
    break
  fi
  sleep 2
done
[ "$READY_OK" = true ] || { echo; echo "=== LOGS DO BRIDGE ==="; dc logs --tail=120 bridge || true; fail "bridge iniciou, mas nao ficou pronto de ponta a ponta"; }

say "Estado atual"
dc ps


echo
echo "THOTH_BROWSER_BRIDGE_BOOTSTRAP_OK"
echo "Bridge local: http://127.0.0.1:8800"
echo "A exposicao Tailscale e configurada separadamente apos a auditoria."
