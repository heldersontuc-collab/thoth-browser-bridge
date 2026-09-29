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

say "Verificando rede Docker do THOTH Browser"
docker network inspect thoth-browser-node_default >/dev/null 2>&1 || fail "rede thoth-browser-node_default nao encontrada"

say "Atualizando arquivos da ponte"
if [ -d "$DIR/.git" ]; then
  git -C "$DIR" fetch origin main
  git -C "$DIR" reset --hard origin/main
else
  mkdir -p "$DIR"
  git clone --depth 1 "$REPO" "$DIR"
fi

mkdir -p "$DIR/data/keys" "$DIR/data/results"
chown -R 0:0 "$DIR/data"
chmod 700 "$DIR/data" "$DIR/data/keys" "$DIR/data/results"

say "Construindo e iniciando somente o THOTH Browser Bridge"
cd "$DIR"
install -d -m 700 -o 0 -g 0 "$DIR/data" "$DIR/data/keys" "$DIR/data/results"
docker compose up -d --build bridge

say "Confirmando que o container ficou em execucao"
sleep 2
docker compose ps

say "Testando endpoint local"
for i in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8800/healthz >/tmp/thoth_bridge_health.json 2>/dev/null; then
    cat /tmp/thoth_bridge_health.json
    echo
    break
  fi
  sleep 2
  [ "$i" -lt 30 ] || { echo; echo "=== LOGS DO BRIDGE ==="; docker compose logs --tail=80 bridge || true; fail "bridge nao respondeu em 127.0.0.1:8800"; }
done

say "Estado atual"
docker compose ps

if command -v tailscale >/dev/null 2>&1 && tailscale status >/dev/null 2>&1; then
  say "Tentando publicar SOMENTE resultados cifrados via Tailscale Funnel :10000"
  set +e
  FUNNEL_OUT=$(tailscale funnel --bg --https=10000 http://127.0.0.1:8800 2>&1)
  RC=$?
  set -e
  printf '%s\n' "$FUNNEL_OUT"
  if [ "$RC" -ne 0 ]; then
    echo
    echo "O Bridge esta instalado e privado em 127.0.0.1:8800."
    echo "O Tailscale pode pedir uma autorizacao unica para Funnel."
    echo "Autorize o link mostrado acima e rode este bootstrap novamente."
    exit 0
  fi
  say "Funnel ativo"
  tailscale funnel status || true
else
  echo
  echo "Tailscale nao esta ativo. Bridge ficou somente em 127.0.0.1:8800."
fi

echo
echo "THOTH_BROWSER_BRIDGE_BOOTSTRAP_OK"
echo "Chave publica: http://127.0.0.1:8800/public-key"
