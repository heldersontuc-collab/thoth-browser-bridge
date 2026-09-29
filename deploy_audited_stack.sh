#!/usr/bin/env bash
set -Eeuo pipefail

NODE_DIR="/opt/thoth-browser-node/THOTH_BROWSER_NODE_V1_2_1_VPS_SAFE"
BRIDGE_DIR="/opt/thoth-browser-bridge"
RAW="https://raw.githubusercontent.com/heldersontuc-collab/thoth-browser-bridge/main"
PATCH_SHA="0aac3b284d06df9e80212b03c664ddfb0655478bf8d0d849b1e9dc74512523dd"
STAMP="$(date +%Y%m%d_%H%M%S)"
WORK="$(mktemp -d /tmp/thoth-audited-deploy.XXXXXX)"
STAGE="$WORK/node"
PATCH="$WORK/THOTH_BROWSER_NODE_V1_2_2_AUDITED.patch"
BACKUP="/root/THOTH_AUDITED_PREDEPLOY_$STAMP"
NODE_DEPLOYED=false

say(){ printf '\n==> %s\n' "$*"; }
fail(){ printf '\nERRO: %s\n' "$*" >&2; exit 1; }
cleanup(){ rm -rf "$WORK"; }
trap cleanup EXIT

[ "$(id -u)" -eq 0 ] || fail "rode como root"
for cmd in docker git curl sha256sum python3 tar; do
  command -v "$cmd" >/dev/null 2>&1 || fail "ferramenta ausente: $cmd"
done
docker compose version >/dev/null 2>&1 || fail "docker compose indisponivel"
[ -d "$NODE_DIR" ] || fail "Browser Node atual nao encontrado"
[ -f "$NODE_DIR/.env" ] || fail ".env do Browser Node nao encontrado"
[ -d "$BRIDGE_DIR/.git" ] || fail "Bridge Git nao encontrado"

say "0/9 - PRE-FLIGHT RECURSOS"
FREE_KB="$(df -Pk / | awk 'NR==2{print $4}')"
MEM_AVAIL_KB="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
MEM_AVAIL_MB=$(( MEM_AVAIL_KB / 1024 ))
echo "Espaco livre: $((FREE_KB/1024/1024)) GB"
echo "Memoria disponivel: $MEM_AVAIL_MB MB"
[ "$FREE_KB" -ge 5242880 ] || fail "menos de 5 GB livres; deploy abortado sem alterar nada"
[ "$MEM_AVAIL_MB" -ge 700 ] || fail "menos de 700 MB de memoria disponivel; deploy abortado sem alterar nada"
echo "PRECHECK_RESOURCES_OK"

rollback_node(){
  if [ "$NODE_DEPLOYED" = true ] && [ -d "$BACKUP/node_files" ]; then
    echo
    echo "!!! FALHA APOS ALTERAR O BROWSER NODE. RESTAURANDO ARQUIVOS ANTERIORES !!!"
    cp -a "$BACKUP/node_files/." "$NODE_DIR/"
    cd "$NODE_DIR"
    docker compose --env-file .env up -d --build browser cdp-proxy api mcp caddy || true
    echo "Rollback do Browser Node executado."
  fi
}
trap 'rc=$?; rollback_node; exit $rc' ERR

say "1/9 - Coletando patch auditado e verificando SHA-256"
: > "$PATCH"
for n in 01 02 03 04 05; do
  curl -fsSL "$RAW/node_v1_2_2/patch.part$n" >> "$PATCH"
done
ACTUAL="$(sha256sum "$PATCH" | awk '{print $1}')"
[ "$ACTUAL" = "$PATCH_SHA" ] || fail "SHA-256 do patch divergiu. Esperado $PATCH_SHA, recebido $ACTUAL"
echo "PATCH_SHA256_OK"

say "2/9 - Montando copia de teste sem tocar na instalacao ativa"
cp -a "$NODE_DIR" "$STAGE"
# A VPS ja recebeu manualmente o rewrite do healthz. Normalizamos a copia
# para o estado V1.2.1 original antes de aplicar o patch auditado completo.
python3 - "$STAGE/deploy/Caddyfile" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
s=s.replace("        rewrite * /healthz\n        reverse_proxy api:8080", "        reverse_proxy api:8080")
p.write_text(s)
PY
cd "$STAGE"
git apply --check "$PATCH"
git apply "$PATCH"
python3 -m compileall -q app mcp_server.py tests
echo "PATCH_APPLY_AND_COMPILE_OK"

say "3/9 - Validando Compose e construindo imagens em staging"
docker compose --env-file .env config >/dev/null
docker compose --env-file .env build api mcp
echo "STAGING_BUILD_OK"

say "4/9 - Criando backup reversivel da versao ativa"
mkdir -p "$BACKUP/node_files"
for f in .env.example README.md VPS_ALVO_AUDITADA.txt app/browser_manager.py app/main.py deploy/Caddyfile docker-compose.yml instalar.sh pyproject.toml tests/test_browser_manager.py; do
  mkdir -p "$BACKUP/node_files/$(dirname "$f")"
  cp -a "$NODE_DIR/$f" "$BACKUP/node_files/$f"
done
cp -a "$NODE_DIR/.env" "$BACKUP/.env"
chmod 600 "$BACKUP/.env"
docker ps -a > "$BACKUP/docker_ps_before.txt" 2>&1 || true
docker stats --no-stream > "$BACKUP/docker_stats_before.txt" 2>&1 || true
tailscale serve status > "$BACKUP/tailscale_serve_before.txt" 2>&1 || true
tailscale funnel status > "$BACKUP/tailscale_funnel_before.txt" 2>&1 || true
echo "BACKUP_DIR=$BACKUP"

say "5/9 - Publicando somente os arquivos auditados do Browser Node"
for f in .env.example README.md VPS_ALVO_AUDITADA.txt app/browser_manager.py app/main.py deploy/Caddyfile docker-compose.yml instalar.sh pyproject.toml tests/test_browser_manager.py; do
  cp -a "$STAGE/$f" "$NODE_DIR/$f"
done
NODE_DEPLOYED=true

say "6/9 - Recriando somente os containers do THOTH Browser Node"
cd "$NODE_DIR"
docker compose --env-file .env up -d --build browser cdp-proxy api mcp caddy

say "7/9 - Validando Node V1.2.2, API autenticada e CDP"
NODE_OK=false
for i in $(seq 1 40); do
  if OUT="$(curl -fsS --max-time 4 http://127.0.0.1:8790/api/healthz 2>/dev/null)" && echo "$OUT" | grep -q '1.2.2-audited'; then
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
import json, os, urllib.request
key=os.environ["THOTH_TEST_KEY"]
req=urllib.request.Request("http://127.0.0.1:8080/v1/sessions", headers={"X-THOTH-Key":key})
with urllib.request.urlopen(req, timeout=5) as r:
    obj=json.loads(r.read())
assert obj.get("mode") == "shared-visible", obj
print("AUTHENTICATED_API_OK", json.dumps(obj, ensure_ascii=False))
with urllib.request.urlopen("http://browser:9223/json/version", timeout=5) as r:
    raw=r.read(1200).decode("utf-8","replace")
assert "webSocketDebuggerUrl" in raw, raw
print("CDP_OK")
PY
NODE_DEPLOYED=false

say "8/9 - Atualizando e validando o Bridge auditado"
git -C "$BRIDGE_DIR" fetch origin main
git -C "$BRIDGE_DIR" reset --hard origin/main
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
[ "$READY" = true ] || { docker compose --env-file "$NODE_DIR/.env" logs --tail=120 bridge; fail "Bridge nao passou no readyz"; }
echo "BRIDGE_READYZ_OK"

say "9/9 - Mantendo navegador privado e publicando somente o canal cifrado"
tailscale serve --bg --https=8444 http://127.0.0.1:8790
set +e
FUNNEL_OUT="$(tailscale funnel --bg --https=443 --set-path=/thoth-bridge http://127.0.0.1:8800 2>&1)"
RC=$?
set -e
printf '%s\n' "$FUNNEL_OUT"
[ "$RC" -eq 0 ] || fail "Tailscale Funnel do Bridge nao iniciou"

echo
echo "=== TAILSCALE SERVE ==="
tailscale serve status || true
echo
echo "=== TAILSCALE FUNNEL ==="
tailscale funnel status || true
echo
echo "=== RECURSOS ==="
free -h
df -h /
vmstat 1 5 || true
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.PIDs}}' || true

echo
echo "============================================================"
echo " THOTH AUDITED STACK DEPLOYED"
echo " Browser Node: 1.2.2-audited"
echo " Browser privado: https://thoth-browser-vps.tail819f67.ts.net:8444/"
echo " Bridge publico cifrado: https://thoth-browser-vps.tail819f67.ts.net/thoth-bridge"
echo " Backup: $BACKUP"
echo "============================================================"
echo "THOTH_AUDITED_STACK_OK"
