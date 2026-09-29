#!/usr/bin/env bash
set -Eeuo pipefail

BRIDGE="http://127.0.0.1:8800"
PUBLIC_BASE="https://thoth-browser-vps.tail819f67.ts.net"
PRIVATE_BROWSER="https://thoth-browser-vps.tail819f67.ts.net:8444/"

say(){ printf '\n==> %s\n' "$*"; }
fail(){ printf '\nERRO: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "rode como root"
command -v tailscale >/dev/null 2>&1 || fail "tailscale nao encontrado"
command -v curl >/dev/null 2>&1 || fail "curl nao encontrado"

say "1/5 - Verificando Bridge local"
HEALTH="$(curl -fsS --max-time 5 "$BRIDGE/healthz")" || fail "Bridge local nao respondeu"
READY="$(curl -fsS --max-time 7 "$BRIDGE/readyz")" || fail "Bridge local nao esta pronto"
echo "$HEALTH"
echo "$READY"
echo "$READY" | grep -q '"ok":true' || fail "readyz nao confirmou ok=true"

say "2/5 - Confirmando navegador privado em 8444"
SERVE="$(tailscale serve status 2>&1 || true)"
printf '%s\n' "$SERVE"
echo "$SERVE" | grep -q ':8444' || fail "Serve privado 8444 nao encontrado"
echo "$SERVE" | grep -q '127.0.0.1:8790' || fail "Serve 8444 nao aponta para o painel local 8790"

say "3/5 - Limpando somente Funnel antigo"
tailscale funnel reset >/dev/null 2>&1 || true

say "4/5 - Publicando somente /thoth-bridge na porta HTTPS padrao"
OUT="$(tailscale funnel --bg --https=443 --set-path=/thoth-bridge "$BRIDGE" 2>&1)" || {
  printf '%s\n' "$OUT"
  fail "nao foi possivel iniciar o Funnel do Bridge"
}
printf '%s\n' "$OUT"

say "5/5 - Verificacao final da configuracao"
echo "--- SERVE PRIVADO ---"
tailscale serve status || true
echo "--- FUNNEL PUBLICO ---"
tailscale funnel status || true

FUNNEL="$(tailscale funnel status 2>&1 || true)"
echo "$FUNNEL" | grep -q '/thoth-bridge' || fail "Funnel nao mostra /thoth-bridge"
echo "$FUNNEL" | grep -q '127.0.0.1:8800' || fail "Funnel nao aponta para o Bridge local"

echo
echo "============================================================"
echo " THOTH BRIDGE PUBLICADO PARA TESTE E2E"
echo " Browser privado: $PRIVATE_BROWSER"
echo " Bridge publico:  $PUBLIC_BASE/thoth-bridge"
echo "============================================================"
echo "THOTH_BRIDGE_FUNNEL_OK"
