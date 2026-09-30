#!/usr/bin/env bash
set -Eeuo pipefail

REPO="https://github.com/heldersontuc-collab/thoth-browser-bridge.git"
DIR="/opt/thoth-web-mcp-src"
APP="$DIR/thoth_web_mcp"

say(){ printf '\n==> %s\n' "$*"; }
fail(){ printf '\nERRO: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "rode como root"
command -v git >/dev/null 2>&1 || fail "git nao encontrado"
command -v docker >/dev/null 2>&1 || fail "docker nao encontrado"
docker compose version >/dev/null 2>&1 || fail "docker compose nao encontrado"

FREE_KB="$(df -Pk / | awk 'NR==2{print $4}')"
MEM_AVAIL_KB="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
MEM_AVAIL_MB=$(( MEM_AVAIL_KB / 1024 ))
[ "$FREE_KB" -ge 2097152 ] || fail "menos de 2 GB livres"
[ "$MEM_AVAIL_MB" -ge 400 ] || fail "menos de 400 MB de memoria disponivel"

say "Atualizando somente o codigo-fonte isolado do THOTH Web MCP"
if [ -d "$DIR/.git" ]; then
  git -C "$DIR" fetch origin main
  git -C "$DIR" reset --hard origin/main
else
  git clone --depth 1 "$REPO" "$DIR"
fi

[ -f "$APP/docker-compose.yml" ] || fail "Sprint 0 nao encontrado em $APP"

say "Subindo somente o THOTH Web MCP em 127.0.0.1:8810"
cd "$APP"
COMPOSE_PROJECT_NAME=thoth-web-mcp docker compose up -d --build mcp

say "Teste MCP real dentro do container"
for i in $(seq 1 30); do
  if COMPOSE_PROJECT_NAME=thoth-web-mcp docker compose exec -T mcp python - <<'PY' >/tmp/thoth_web_ping.txt 2>&1
import anyio
from mcp import Client

async def main():
    async with Client("http://127.0.0.1:8810/mcp") as client:
        tools = await client.list_tools()
        names = [t.name for t in tools.tools]
        assert names == ["thoth_ping"], names
        result = await client.call_tool("thoth_ping", {})
        assert result.is_error is False
        assert result.structured_content["message"] == "PONG", result
        print("THOTH_WEB_MCP_PONG_OK")
        print(result.structured_content)

anyio.run(main)
PY
  then
    cat /tmp/thoth_web_ping.txt
    break
  fi
  if [ "$i" -eq 30 ]; then
    cat /tmp/thoth_web_ping.txt || true
    COMPOSE_PROJECT_NAME=thoth-web-mcp docker compose logs --tail=120 mcp || true
    fail "MCP nao respondeu ao teste real"
  fi
  sleep 2
done

say "Estado final"
COMPOSE_PROJECT_NAME=thoth-web-mcp docker compose ps

echo
echo "THOTH_WEB_SPRINT0_OK"
echo "MCP local: http://127.0.0.1:8810/mcp"
echo "Nenhum Browser Node, Tailscale, Nginx, BI ou THOTH Brain foi alterado."
