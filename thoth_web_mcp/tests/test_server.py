from __future__ import annotations

import pytest
from mcp import Client

from thoth_web_mcp.server import mcp


@pytest.mark.asyncio
async def test_ping_tool_contract():
    async with Client(mcp) as client:
        listed = await client.list_tools()
        tools = {tool.name: tool for tool in listed.tools}

        assert set(tools) == {"thoth_ping"}
        tool = tools["thoth_ping"]
        assert tool.title == "Test THOTH Web connection"
        assert tool.annotations is not None
        assert tool.annotations.read_only_hint is True
        assert tool.annotations.destructive_hint is False
        assert tool.annotations.open_world_hint is False
        assert tool.annotations.idempotent_hint is True
        assert tool.output_schema is not None

        result = await client.call_tool("thoth_ping", {})
        assert result.is_error is False
        assert result.structured_content == {
            "ok": True,
            "service": "THOTH Web",
            "version": "0.1.0",
            "message": "PONG",
        }
