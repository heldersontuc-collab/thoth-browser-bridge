import pytest

import bridge_mcp_client as client


@pytest.mark.asyncio
async def test_health_checks_authenticated_node_api(monkeypatch):
    calls = []

    async def fake_api(method, path, body=None):
        calls.append((method, path, body))
        return {"mode": "shared-visible", "sessions": []}

    monkeypatch.setattr(client, "api", fake_api)
    out = await client.call_tool("health", {})
    assert out["ok"] is True
    assert out["browser_api"] == "authenticated"
    assert calls == [("GET", "/v1/sessions", None)]


@pytest.mark.asyncio
async def test_bridge_v1_rejects_click(monkeypatch):
    async def fake_api(method, path, body=None):
        if path == "/v1/sessions/open":
            return {"session_id": "s1"}
        return {}

    monkeypatch.setattr(client, "api", fake_api)
    with pytest.raises(ValueError, match="action not allowed"):
        await client.call_tool("click", {"session_id": "s1", "selector": "Comprar"})


@pytest.mark.asyncio
async def test_bridge_v1_blocks_raw_html_and_screenshot(monkeypatch):
    async def fake_api(method, path, body=None):
        if path == "/v1/sessions/open":
            return {"session_id": "s1"}
        return {"ok": True}

    monkeypatch.setattr(client, "api", fake_api)
    with pytest.raises(ValueError, match="raw HTML"):
        await client.call_tool("extract", {"session_id": "s1", "mode": "html"})
    with pytest.raises(ValueError, match="screenshots human-only"):
        await client.call_tool("screenshot", {"session_id": "s1"})
