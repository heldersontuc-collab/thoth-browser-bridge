#!/usr/bin/env bash
set -u

NODE_DIR="/opt/thoth-browser-node/THOTH_BROWSER_NODE_V1_2_1_VPS_SAFE"
BRIDGE_DIR="/opt/thoth-browser-bridge"

section(){ printf '\n===== %s =====\n' "$*"; }

section "HOST"
date -Is
uname -a
uptime
df -h /
free -h
printf '\nSwap summary:\n'
swapon --show 2>/dev/null || true

section "DOCKER PS"
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true

section "DOCKER RESOURCES"
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.PIDs}}' 2>/dev/null || true
printf '\nDocker disk:\n'
docker system df 2>/dev/null || true

section "THOTH BROWSER NODE NETWORK"
docker network inspect thoth-browser-node_default --format '{{json .Containers}}' 2>/dev/null || true

section "CONTAINER HARDENING"
for c in   thoth-browser-node-browser-1   thoth-browser-node-cdp-proxy-1   thoth-browser-node-api-1   thoth-browser-node-mcp-1   thoth-browser-node-caddy-1   thoth-browser-bridge-bridge-1
do
  if docker inspect "$c" >/dev/null 2>&1; then
    docker inspect "$c" --format 'NAME={{.Name}} USER={{.Config.User}} READONLY={{.HostConfig.ReadonlyRootfs}} PRIVILEGED={{.HostConfig.Privileged}} CAPDROP={{json .HostConfig.CapDrop}} SECURITY={{json .HostConfig.SecurityOpt}} RESTARTS={{.RestartCount}}'
  fi
done

section "HOST PORTS"
ss -lntup 2>/dev/null | sed -n '1,160p'

section "TAILSCALE"
tailscale status 2>/dev/null || true
printf '\n--- serve status ---\n'
tailscale serve status 2>/dev/null || true
printf '\n--- funnel status ---\n'
tailscale funnel status 2>/dev/null || true

section "LOCAL ENDPOINTS"
printf 'Browser panel local: '
curl -fsS --max-time 4 http://127.0.0.1:8790/ >/dev/null 2>&1 && echo OK || echo FAIL
printf 'Bridge health: '
curl -fsS --max-time 4 http://127.0.0.1:8800/healthz 2>/dev/null || echo FAIL
printf '\nBridge ready: '
curl -fsS --max-time 6 http://127.0.0.1:8800/readyz 2>/dev/null || echo NOT_READY_OR_OLD_VERSION
echo

section "BRIDGE CONTAINER LOGS"
if [ -d "$BRIDGE_DIR" ]; then
  cd "$BRIDGE_DIR"
  if [ -f "$NODE_DIR/.env" ]; then
    docker compose --env-file "$NODE_DIR/.env" logs --tail=100 bridge 2>&1 |       sed -E 's/(THOTH_API_KEY|PASSWORD|TOKEN|SECRET|KEY)=([^ ]+)/\1=<redacted>/Ig'
  else
    docker compose logs --tail=100 bridge 2>&1 |       sed -E 's/(THOTH_API_KEY|PASSWORD|TOKEN|SECRET|KEY)=([^ ]+)/\1=<redacted>/Ig'
  fi
fi

section "BROWSER NODE HEALTH FROM INSIDE API"
if docker inspect thoth-browser-node-api-1 >/dev/null 2>&1; then
  docker exec thoth-browser-node-api-1 python - <<'PY' 2>/dev/null || true
import urllib.request
for url in [
    "http://127.0.0.1:8080/healthz",
    "http://browser:9223/json/version",
]:
    try:
        r=urllib.request.urlopen(url,timeout=4)
        print(url, r.status, r.read(600).decode("utf-8","replace"))
    except Exception as e:
        print(url, "ERROR", type(e).__name__, str(e)[:180])
PY
fi

section "BROWSER NODE CONFIG SHAPE"
if [ -f "$NODE_DIR/.env" ]; then
  grep -E '^(COMPOSE_PROJECT_NAME|THOTH_DATA_DIR|THOTH_BLOCK_PRIVATE_NETWORKS|THOTH_SHARED_PROFILE|THOTH_BIND_IP|THOTH_PUBLIC_PORT|THOTH_SITE_ADDR|THOTH_BROWSER_MEM_LIMIT|THOTH_API_MEM_LIMIT|THOTH_MCP_MEM_LIMIT|THOTH_PROXY_MEM_LIMIT|THOTH_CADDY_MEM_LIMIT)=' "$NODE_DIR/.env" || true
fi

section "FAILED SERVICES"
systemctl --failed --no-pager 2>/dev/null || true

section "AUDIT COMPLETE"
echo "THOTH_RUNTIME_AUDIT_DONE"
