#!/usr/bin/env bash
set -Eeuo pipefail

DIR="/opt/thoth-openai-challenge"
PORT="8811"
PATH_CHALLENGE="/.well-known/openai-apps-challenge"

say(){ printf '\n==> %s\n' "$*"; }
fail(){ printf '\nERRO: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "rode como root"
[ -s "$DIR/token.txt" ] || fail "token de verificacao existente nao encontrado"

say "1/3 - Tornando o endpoint compativel com slash final e HEAD"
cat > "$DIR/server.py" <<'PY'
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

TOKEN = Path("/opt/thoth-openai-challenge/token.txt").read_text("utf-8")
PATH = "/.well-known/openai-apps-challenge"

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _matches(self):
        path = urlsplit(self.path).path
        return path.rstrip("/") == PATH

    def _send(self, include_body: bool):
        if not self._matches():
            body = b"not found"
            self.send_response(404)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Cache-Control", "no-store, max-age=0")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "close")
            self.end_headers()
            if include_body:
                self.wfile.write(body)
            return

        body = TOKEN.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Cache-Control", "no-store, max-age=0, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        if include_body:
            self.wfile.write(body)

    def do_GET(self):
        self._send(True)

    def do_HEAD(self):
        self._send(False)

    def log_message(self, fmt, *args):
        return

ThreadingHTTPServer(("127.0.0.1", 8811), Handler).serve_forever()
PY

systemctl restart thoth-openai-challenge.service

say "2/3 - Testando localmente as duas formas"
TOKEN="$(cat "$DIR/token.txt")"
for path in "$PATH_CHALLENGE" "$PATH_CHALLENGE/"; do
  for i in $(seq 1 20); do
    GOT="$(curl -fsS --max-time 3 "http://127.0.0.1:$PORT$path" 2>/dev/null || true)"
    if [ "$GOT" = "$TOKEN" ]; then
      echo "GET_OK $path"
      break
    fi
    [ "$i" -lt 20 ] || fail "GET falhou em $path"
    sleep 1
  done
  CODE="$(curl -sS -o /dev/null -w '%{http_code}' -I "http://127.0.0.1:$PORT$path" || true)"
  [ "$CODE" = "200" ] || fail "HEAD falhou em $path (HTTP $CODE)"
  echo "HEAD_OK $path"
done

say "3/3 - Confirmando servico"
systemctl is-active --quiet thoth-openai-challenge.service || fail "servico nao esta ativo"
echo "THOTH_OPENAI_CHALLENGE_ROBUST_OK"
