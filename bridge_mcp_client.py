from __future__ import annotations

import os
import re
from typing import Any
from urllib.parse import quote, urlparse

_NAV_BLOCK = re.compile(
    r"(?:^|[/_?&=.-])(checkout|pay|payment|purchase|buy|order|transfer|pix|bet|wager|"
    r"delete|remove|unsubscribe|cancel|submit|save)(?:$|[/_?&=.-])",
    re.I,
)

def _safe_navigation_url(url: str) -> str:
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ValueError("bridge navigation allows only explicit http/https URLs")
    target = f"{parsed.path}?{parsed.query}"
    if _NAV_BLOCK.search(target):
        raise ValueError("bridge v1 blocks navigation to URLs that look like payment, transfer, purchase or destructive actions")
    return url

import httpx

API_URL = os.getenv("THOTH_API_URL", "http://api:8080").rstrip("/")
API_KEY = os.environ["THOTH_API_KEY"]
DEFAULT_PROFILE = os.getenv("BRIDGE_PROFILE", "sorteios")

async def api(method: str, path: str, body: dict[str, Any] | None = None) -> Any:
    async with httpx.AsyncClient(timeout=90.0) as client:
        r = await client.request(
            method,
            f"{API_URL}{path}",
            headers={"X-THOTH-Key": API_KEY},
            json=body,
        )
        r.raise_for_status()
        return r.json()

async def ensure_session(session_id: str | None = None) -> str:
    if session_id:
        return session_id
    opened = await api("POST", "/v1/sessions/open", {"profile": DEFAULT_PROFILE, "start_url": None})
    return opened["session_id"]

async def call_tool(action: str, args: dict[str, Any]) -> Any:
    if action == "health":
        node = await api("GET", "/v1/sessions")
        return {"ok": True, "browser_api": "authenticated", "node": node}
    if action == "sessions":
        return await api("GET", "/v1/sessions")
    if action == "open":
        return await api(
            "POST",
            "/v1/sessions/open",
            {"profile": args.get("profile", DEFAULT_PROFILE), "start_url": args.get("start_url")},
        )

    sid = await ensure_session(args.get("session_id"))

    if action == "state":
        return await api("GET", f"/v1/sessions/{sid}")
    if action == "navigate":
        return await api("POST", f"/v1/sessions/{sid}/navigate", {"url": _safe_navigation_url(str(args["url"]))})
    if action == "inspect":
        raise ValueError("bridge v1 blocks DOM form inspection until Browser Node V1.2.2 redaction is deployed")
    if action == "extract":
        mode = str(args.get("mode", "text")).lower()
        if mode not in {"text", "links"}:
            raise ValueError("bridge v1 blocks raw HTML extraction because it can expose hidden credentials or tokens")
        return await api("GET", f"/v1/sessions/{sid}/extract?mode={quote(mode)}")
    if action == "wait":
        return await api("POST", f"/v1/sessions/{sid}/wait", {"milliseconds": int(args.get("milliseconds", 1000))})
    if action == "screenshot":
        raise ValueError("bridge v1 keeps screenshots human-only until redaction is implemented")
    if action == "tabs":
        return await api("GET", f"/v1/sessions/{sid}/tabs")
    if action == "new_tab":
        return await api("POST", f"/v1/sessions/{sid}/tabs/new", {"url": _safe_navigation_url(str(args["url"])) if args.get("url") else None})
    if action == "switch_tab":
        return await api("POST", f"/v1/sessions/{sid}/tabs/switch", {"index": int(args["index"])})
    if action == "close_tab":
        return await api("POST", f"/v1/sessions/{sid}/tabs/close", {"index": int(args["index"])})
    if action == "events":
        raise ValueError("bridge v1 blocks historical event logs because old Browser Node versions may contain unredacted field values")
    if action == "close":
        return await api("DELETE", f"/v1/sessions/{sid}")

    raise ValueError(f"action not allowed in bridge v1: {action}")
