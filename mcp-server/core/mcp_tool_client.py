from __future__ import annotations

import asyncio
import os
import sys
from datetime import timedelta
from pathlib import Path
from typing import Any

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


def call_local_mcp_tool(tool_name: str, arguments: dict[str, Any]) -> str:
    """Call this project's FastMCP server over the stdio MCP protocol."""
    return asyncio.run(_call_local_mcp_tool(tool_name, arguments))


async def _call_local_mcp_tool(tool_name: str, arguments: dict[str, Any]) -> str:
    project_dir = Path(__file__).resolve().parents[1]
    server_path = project_dir / "mcp_server" / "server.py"
    env = dict(os.environ)
    env["PYTHONPATH"] = str(project_dir)
    params = StdioServerParameters(
        command=sys.executable,
        args=[str(server_path)],
        cwd=str(project_dir),
        env=env,
    )
    async with stdio_client(params) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()
            result = await session.call_tool(
                tool_name,
                arguments,
                read_timeout_seconds=timedelta(seconds=30),
            )
    if result.isError:
        raise RuntimeError(f"MCP tool failed: {tool_name}")
    parts = []
    for item in result.content:
        text = getattr(item, "text", None)
        if text is not None:
            parts.append(text)
    return "\n".join(parts)
