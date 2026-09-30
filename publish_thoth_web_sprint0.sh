#!/usr/bin/env bash
set -Eeuo pipefail

LOCAL_MCP="http://127.0.0.1:8810/mcp"
PUBLIC_HOST="https://thoth-browser-vps.tail819f67.ts.net"
PUBLIC_MCP="$PUBLIC_HOST/mcp"

say(){ printf '\n==> %s\n' "$*"; }
fail(){ printf '\nERRO: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "rode como root"
command -v tailscale >/dev/null 2>&1 || fail "tailscale nao encontrado"
command -v docker >/dev/null 2>&1 || fail "docker nao encontrado"

say "1/4 - Confirmando THOTH Web MCP local"
docker ps --format '{{.Names}}' | grep -qx 'thoth-web-mcp-mcp-1' || fail "container thoth-web-mcp-mcp-1 nao esta em execucao"

say "2/4 - Preservando rotas existentes do Funnel"
echo "--- ANTES ---"
tailscale funnel status || true

say "3/4 - Adicionando somente /mcp ao Funnel HTTPS 443"
tailscale funnel --bg --https=443 --set-path=/mcp "$LOCAL_MCP"

say "4/4 - Confirmando configuracao final"
STATUS="$(tailscale funnel status 2>&1 || true)"
printf '%s\n' "$STATUS"
echo "$STATUS" | grep -q '/mcp' || fail "rota publica /mcp nao apareceu no Funnel"
echo "$STATUS" | grep -q '127.0.0.1:8810/mcp' || fail "rota /mcp nao aponta para o THOTH Web MCP"

# O Bridge antigo pode continuar coexistindo; este Sprint nao o remove.
echo
echo "THOTH_WEB_PUBLIC_MCP_OK"
echo "MCP publico: $PUBLIC_MCP"
echo "Navegador privado permanece separado em :8444"
