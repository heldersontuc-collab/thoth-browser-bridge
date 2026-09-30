from __future__ import annotations

import os

from mcp.server import MCPServer
from mcp.types import ToolAnnotations
from pydantic import BaseModel


VERSION = "0.1.0"


class PingResult(BaseModel):
    ok: bool
    service: str
    version: str
    message: str


mcp = MCPServer(
    "thoth-web",
    title="THOTH Web",
    description="Private browser-control foundation for THOTH.",
    instructions=(
        "This is the THOTH Web connectivity foundation. "
        "At this stage, only use thoth_ping to verify the MCP path. "
        "No browser-control actions are enabled yet."
    ),
    version=VERSION,
)


@mcp.tool(
    title="Test THOTH Web connection",
    description=(
        "Use this to verify that ChatGPT can reach the THOTH Web MCP server. "
        "It does not access the browser and does not change any state."
    ),
    annotations=ToolAnnotations(
        read_only_hint=True,
        destructive_hint=False,
        open_world_hint=False,
        idempotent_hint=True,
    ),
)
def thoth_ping() -> PingResult:
    """Return a minimal connectivity response from THOTH Web."""
    return PingResult(
        ok=True,
        service="THOTH Web",
        version=VERSION,
        message="PONG",
    )


if __name__ == "__main__":
    port = int(os.getenv("THOTH_WEB_PORT", "8810"))
    mcp.run(
        transport="streamable-http",
        host="0.0.0.0",
        port=port,
        streamable_http_path="/mcp",
        json_response=True,
        stateless_http=True,
    )
