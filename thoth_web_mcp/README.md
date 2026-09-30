# THOTH Web MCP — Sprint 0

This is the deliberately minimal MCP foundation for THOTH Web.

Current tool:

- `thoth_ping` — returns `PONG` and changes nothing.

It intentionally does **not** connect to the Browser Node yet.

## Goal

Prove the path:

```
MCP client -> THOTH Web -> PONG
```

before adding browser access.

## Local test

```bash
cd thoth_web_mcp
python -m pip install -r requirements-dev.txt
PYTHONPATH=.. pytest -q
```

## Container

```bash
docker compose up -d --build
```

The service is bound only to `127.0.0.1:8810` on the VPS host.

MCP endpoint:

```
http://127.0.0.1:8810/mcp
```

No Browser Node, Tailscale, Nginx, BI, THOTH Brain, or other production service is modified by this Sprint.
