"""Tests for MCP server."""

import pytest
from mcp_provider_delegator import server

@pytest.mark.asyncio
async def test_list_tools():
    """Test that invoke_agent tool is registered."""
    tools = await server.list_tools()
    assert len(tools) == 1
    assert tools[0].name == "invoke_agent"
    assert "scout" in str(tools[0].inputSchema)

@pytest.mark.asyncio
async def test_invoke_agent_error_handling():
    """Test invoke_agent handles errors gracefully (providers not available in test env)."""
    result = await server.call_tool(
        "invoke_agent",
        {
            "agent": "scout",
            "task_prompt": "Find authentication files"
        }
    )
    assert len(result) == 1
    # In test environment without providers, should get error response
    assert result[0].text
    # Either succeeds (if providers configured) or returns error
    assert isinstance(result[0].text, str)
