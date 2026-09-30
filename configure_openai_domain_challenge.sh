#!/usr/bin/env bash
set -Eeuo pipefail

HOST="https://thoth-browser-vps.tail819f67.ts.net"
PATH_CHALLENGE="/.well-known/openai-apps-challenge"
DIR="/opt/thoth-openai-challenge"
PORT="8811"
SERVICE="/etc/systemd/system/thoth-openai-challenge.service"

say(){ printf '\n==> %s\n' "$*"; }
fail(){ printf '\nERRO: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "rode como root"
for cmd in python3 curl tailscale systemctl; do
  command -v "$cmd" >/dev/null 2>&1 || fail "ferramenta ausente: $cmd"
done

printf 'Cole o token de verificacao da OpenAI e pressione Enter: '
IFS= read -r TOKEN
TOKEN="${TOKEN//$'\r'/}"
[ -n "$TOKEN" ] || fail "token vazio"
[[ "$TOKEN" =~ ^[A-Za-z0-9_-]{20,200}$ ]] || fail "formato do token inesperado"

say "1/4 - Criando servidor isolado de desafio"
install -d -m 755 "$DIR"
printf '%s' "$TOKEN" > "$DIR/token.txt"
chmod 644 "$DIR/token.txt"

cat > "$DIR/server.py" <<'PY'
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

TOKEN = Path("/opt/thoth-openai-challenge/token.txt").read_text("utf-8")
PATH = "/.well-known/openai-apps-challenge"

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.split("?",1)[0] != PATH:
            self.send_response(404)
            self.end_headers()
            return
        body = TOKEN.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        return

ThreadingHTTPServer(("127.0.0.1", 8811), Handler).serve_forever()
PY

cat > "$SERVICE" <<'UNIT'
[Unit]
Description=THOTH OpenAI domain verification challenge
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=/usr/bin/python3 /opt/thoth-openai-challenge/server.py
Restart=on-failure
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadOnlyPaths=/opt/thoth-openai-challenge

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now thoth-openai-challenge.service

say "2/4 - Validando resposta local exata"
for i in $(seq 1 20); do
  GOT="$(curl -fsS --max-time 3 "http://127.0.0.1:$PORT$PATH_CHALLENGE" 2>/dev/null || true)"
  if [ "$GOT" = "$TOKEN" ]; then
    echo "LOCAL_CHALLENGE_OK"
    break
  fi
  [ "$i" -lt 20 ] || fail "servidor local nao devolveu o token exato"
  sleep 1
done

say "3/4 - Publicando somente o caminho de verificacao"
tailscale funnel --bg --https=443 --set-path="$PATH_CHALLENGE" "http://127.0.0.1:$PORT$PATH_CHALLENGE"

say "4/4 - Confirmando configuracao"
STATUS="$(tailscale funnel status 2>&1 || true)"
printf '%s\n' "$STATUS"
echo "$STATUS" | grep -Fq "$PATH_CHALLENGE" || fail "rota de desafio nao apareceu no Funnel"
echo "$STATUS" | grep -Fq "127.0.0.1:$PORT$PATH_CHALLENGE" || fail "rota de desafio aponta para destino inesperado"

echo
echo "THOTH_OPENAI_DOMAIN_CHALLENGE_OK"
echo "Agora volte ao portal da OpenAI e toque em Verify Domain."
