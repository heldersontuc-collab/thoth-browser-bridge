#!/usr/bin/env bash
set -Eeuo pipefail

NODE_DIR="/opt/thoth-browser-node/THOTH_BROWSER_NODE_V1_2_1_VPS_SAFE"
BRIDGE_DIR="/opt/thoth-browser-bridge"
RAW="https://raw.githubusercontent.com/heldersontuc-collab/thoth-browser-bridge/main"
STAMP="$(date +%Y%m%d_%H%M%S)"
WORK="$(mktemp -d /tmp/thoth-audited-deploy.XXXXXX)"
STAGE="$WORK/node"
BACKUP="/root/THOTH_AUDITED_PREDEPLOY_$STAMP"
UPGRADER="$WORK/upgrade_v1_2_2.py"

NODE_CHANGED=false
BRIDGE_CHANGED=false
CORE_OK=false
BRIDGE_OLD_SHA=""

say(){ printf '\n==> %s\n' "$*"; }
fail(){ printf '\nERRO: %s\n' "$*" >&2; exit 1; }
cleanup(){ rm -rf "$WORK"; }

rollback(){
  rc=$?
  if [ "$CORE_OK" = true ]; then
    exit "$rc"
  fi
  echo
  echo "!!! DEPLOY INTERROMPIDO. INICIANDO ROLLBACK SEGURO !!!"

  if [ "$BRIDGE_CHANGED" = true ] && [ -n "$BRIDGE_OLD_SHA" ] && [ -d "$BRIDGE_DIR/.git" ]; then
    echo "Restaurando Bridge para $BRIDGE_OLD_SHA"
    git -C "$BRIDGE_DIR" reset --hard "$BRIDGE_OLD_SHA" || true
    if [ -f "$NODE_DIR/.env" ]; then
      (cd "$BRIDGE_DIR" && docker compose --env-file "$NODE_DIR/.env" up -d --build bridge) || true
    fi
  fi

  if [ "$NODE_CHANGED" = true ] && [ -d "$BACKUP/node_files" ]; then
    echo "Restaurando arquivos anteriores do Browser Node"
    cp -a "$BACKUP/node_files/." "$NODE_DIR/" || true
    (cd "$NODE_DIR" && docker compose --env-file .env up -d --build --no-deps api mcp) || true
    (cd "$NODE_DIR" && docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile) || true
  fi

  echo "Rollback concluido. Browser e outros sistemas da VPS nao foram reiniciados."
  exit "$rc"
}
trap cleanup EXIT
trap rollback ERR

[ "$(id -u)" -eq 0 ] || fail "rode como root"
for cmd in docker git curl sha256sum python3 tar df awk grep; do
  command -v "$cmd" >/dev/null 2>&1 || fail "ferramenta ausente: $cmd"
done
docker compose version >/dev/null 2>&1 || fail "docker compose indisponivel"
[ -d "$NODE_DIR" ] || fail "Browser Node atual nao encontrado"
[ -f "$NODE_DIR/.env" ] || fail ".env do Browser Node nao encontrado"
[ -d "$BRIDGE_DIR/.git" ] || fail "Bridge Git nao encontrado"

say "0/10 - PRE-FLIGHT: recursos e estado"
FREE_KB="$(df -Pk / | awk 'NR==2{print $4}')"
MEM_AVAIL_KB="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
MEM_AVAIL_MB=$(( MEM_AVAIL_KB / 1024 ))
echo "Espaco livre: $((FREE_KB/1024/1024)) GB"
echo "Memoria disponivel: $MEM_AVAIL_MB MB"
[ "$FREE_KB" -ge 3145728 ] || fail "menos de 3 GB livres; deploy abortado sem alterar nada"
[ "$MEM_AVAIL_MB" -ge 600 ] || fail "menos de 600 MB de memoria disponivel; deploy abortado sem alterar nada"
docker ps --format '{{.Names}}' | grep -qx 'thoth-browser-node-browser-1' || fail "container Chromium atual nao encontrado"
echo "PRECHECK_RESOURCES_OK"

say "1/10 - Baixando upgrader auditado"
curl -fsSL "$RAW/node_v1_2_2/upgrade_v1_2_2.py" -o "$UPGRADER"
python3 -m py_compile "$UPGRADER"
echo "UPGRADER_SYNTAX_OK"

say "2/10 - Staging completo sem tocar na instalacao ativa"
cp -a "$NODE_DIR" "$STAGE"
cd "$STAGE"
python3 "$UPGRADER"
python3 -m compileall -q app mcp_server.py
docker compose --env-file .env config >/dev/null
echo "STAGING_SOURCE_AND_COMPOSE_OK"

say "3/10 - Construindo API/MCP em staging"
docker compose --env-file .env build api mcp
echo "STAGING_BUILD_OK"

say "4/10 - Criando backup reversivel"
mkdir -p "$BACKUP/node_files"
for f in   .env.example README.md VPS_ALVO_AUDITADA.txt   app/browser_manager.py app/db.py app/main.py   deploy/Caddyfile docker-compose.yml instalar.sh   mcp_server.py pyproject.toml
do
  mkdir -p "$BACKUP/node_files/$(dirname "$f")"
  cp -a "$NODE_DIR/$f" "$BACKUP/node_files/$f"
done
[ -f "$NODE_DIR/VERSION_AUDITED" ] && cp -a "$NODE_DIR/VERSION_AUDITED" "$BACKUP/node_files/VERSION_AUDITED" || true
cp -a "$NODE_DIR/.env" "$BACKUP/.env"
chmod 600 "$BACKUP/.env"
BRIDGE_OLD_SHA="$(git -C "$BRIDGE_DIR" rev-parse HEAD)"
printf '%s\n' "$BRIDGE_OLD_SHA" > "$BACKUP/bridge_commit_before.txt"
docker ps -a > "$BACKUP/docker_ps_before.txt" 2>&1 || true
docker stats --no-stream > "$BACKUP/docker_stats_before.txt" 2>&1 || true
tailscale serve status > "$BACKUP/tailscale_serve_before.txt" 2>&1 || true
tailscale funnel status > "$BACKUP/tailscale_funnel_before.txt" 2>&1 || true
echo "BACKUP_DIR=$BACKUP"

say "5/10 - Publicando somente arquivos Node auditados"
for f in   .env.example README.md VPS_ALVO_AUDITADA.txt   app/browser_manager.py app/db.py app/main.py   deploy/Caddyfile docker-compose.yml instalar.sh   mcp_server.py pyproject.toml VERSION_AUDITED
do
  mkdir -p "$NODE_DIR/$(dirname "$f")"
  cp -a "$STAGE/$f" "$NODE_DIR/$f"
done
NODE_CHANGED=true

say "6/10 - Recriando somente API e MCP; Chromium permanece ligado"
cd "$NODE_DIR"
docker compose --env-file .env config >/dev/null
docker compose --env-file .env build api mcp
docker compose --env-file .env up -d --no-deps api mcp
docker compose exec -T caddy caddy validate --config /etc/caddy/Caddyfile >/dev/null
docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile
echo "NODE_CONTAINERS_UPDATED_WITHOUT_BROWSER_RESTART"

say "7/10 - Testes reais do Node: versao, API, CDP e protecoes"
NODE_OK=false
for i in $(seq 1 40); do
  if OUT="$(curl -fsS --max-time 4 http://127.0.0.1:8790/api/healthz 2>/dev/null)" && echo "$OUT" | grep -q '"version":"1.2.2"'; then
    echo "$OUT"
    NODE_OK=true
    break
  fi
  sleep 2
done
[ "$NODE_OK" = true ] || fail "Browser Node V1.2.2 nao respondeu pelo painel local"

API_KEY="$(grep '^THOTH_API_KEY=' .env | tail -1 | cut -d= -f2-)"
[ -n "$API_KEY" ] || fail "THOTH_API_KEY ausente"

docker compose --env-file .env exec -T -e THOTH_TEST_KEY="$API_KEY" api python - <<'PY'
import json, os, tempfile, urllib.request
from pathlib import Path
from app.browser_manager import BrowserManager
from app.db import EventStore

key=os.environ["THOTH_TEST_KEY"]
req=urllib.request.Request("http://127.0.0.1:8080/v1/sessions", headers={"X-THOTH-Key":key})
with urllib.request.urlopen(req, timeout=8) as r:
    sessions=json.loads(r.read())
assert sessions.get("mode") == "shared-visible", sessions
print("AUTHENTICATED_API_OK")

with urllib.request.urlopen("http://browser:9223/json/version", timeout=8) as r:
    raw=r.read(1600).decode("utf-8","replace")
assert "webSocketDebuggerUrl" in raw, raw
print("CDP_OK")

tmp=Path(tempfile.mkdtemp())/"events.sqlite3"
store=EventStore(tmp)
mgr=BrowserManager(store)
assert mgr._human_only({"type":"text","name":"cardNumber","text":"","aria_label":"","id":"","placeholder":"","label":""})
assert mgr._human_only({"type":"text","name":"password_value","text":"","aria_label":"","id":"","placeholder":"","label":""})
store.add(session_id="s",profile="p",action="audit",success=True,detail={"value":"LEAK","token":"TOKEN","safe":"ok"})
detail=store.recent(1)[0]["detail"]
assert detail["value"] == "<redacted>" and detail["token"] == "<redacted>" and detail["safe"] == "ok", detail
print("SENSITIVE_GUARDS_OK")
PY

docker network inspect thoth-browser-node_control_api >/dev/null 2>&1 || fail "rede control_api nao foi criada"
docker network inspect thoth-browser-node_control_api --format '{{range $id,$c := .Containers}}{{$c.Name}} {{end}}' | grep -q 'thoth-browser-node-api-1' || fail "API nao esta na rede control_api"
docker network inspect thoth-browser-node_control_api --format '{{range $id,$c := .Containers}}{{$c.Name}} {{end}}' | grep -q 'thoth-browser-node-browser-1' && fail "Chromium nao pode estar na rede control_api"
echo "CONTROL_NETWORK_ISOLATION_OK"

say "8/10 - Atualizando e validando Bridge auditado"
git -C "$BRIDGE_DIR" fetch origin main
git -C "$BRIDGE_DIR" reset --hard origin/main
BRIDGE_CHANGED=true
mkdir -p "$BRIDGE_DIR/data/keys" "$BRIDGE_DIR/data/results"
chown -R 65532:65532 "$BRIDGE_DIR/data"
chmod 700 "$BRIDGE_DIR/data" "$BRIDGE_DIR/data/keys" "$BRIDGE_DIR/data/results"
cd "$BRIDGE_DIR"
docker compose --env-file "$NODE_DIR/.env" config >/dev/null
docker compose --env-file "$NODE_DIR/.env" up -d --build bridge

READY=false
for i in $(seq 1 30); do
  if OUT="$(curl -fsS --max-time 6 http://127.0.0.1:8800/readyz 2>/dev/null)"; then
    echo "$OUT"
    READY=true
    break
  fi
  sleep 2
done
[ "$READY" = true ] || { docker compose --env-file "$NODE_DIR/.env" logs --tail=160 bridge; fail "Bridge nao passou no readyz"; }
echo "BRIDGE_READYZ_OK"

docker network inspect thoth-browser-node_control_api --format '{{range $id,$c := .Containers}}{{$c.Name}} {{end}}' | grep -q 'thoth-browser-bridge-bridge-1' || fail "Bridge nao entrou na control_api"
docker network inspect thoth-browser-node_browser_net >/dev/null 2>&1 &&   docker network inspect thoth-browser-node_browser_net --format '{{range $id,$c := .Containers}}{{$c.Name}} {{end}}' | grep -q 'thoth-browser-bridge-bridge-1' &&   fail "Bridge nao pode entrar na rede do Chromium"
echo "BRIDGE_NETWORK_ISOLATION_OK"

say "9/10 - Tailscale: navegador privado; somente Bridge cifrado publico"
tailscale serve --bg --https=8444 http://127.0.0.1:8790
tailscale funnel reset >/dev/null 2>&1 || true
FUNNEL_OUT="$(tailscale funnel --bg --https=443 --set-path=/thoth-bridge http://127.0.0.1:8800 2>&1)"
printf '%s\n' "$FUNNEL_OUT"

echo "--- SERVE PRIVADO ---"
tailscale serve status || true
echo "--- FUNNEL PUBLICO ---"
tailscale funnel status || true

say "10/10 - Saude final e recursos"
curl -fsS http://127.0.0.1:8790/api/healthz
echo
curl -fsS http://127.0.0.1:8800/readyz
echo
free -h
df -h /
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.PIDs}}' || true

CORE_OK=true
NODE_CHANGED=false
BRIDGE_CHANGED=false

echo
echo "============================================================"
echo " THOTH AUDITED STACK CORE OK"
echo " Browser Node: V1.2.2 AUDITED"
echo " Browser privado: https://thoth-browser-vps.tail819f67.ts.net:8444/"
echo " Bridge cifrado: https://thoth-browser-vps.tail819f67.ts.net/thoth-bridge"
echo " Backup: $BACKUP"
echo "============================================================"
echo "THOTH_AUDITED_STACK_OK"
