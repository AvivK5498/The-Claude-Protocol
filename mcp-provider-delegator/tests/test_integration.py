"""Integration tests for full agent delegation flow."""

import pytest
from mcp_provider_delegator.server import app

@pytest.mark.integration
@pytest.mark.asyncio
async def test_invoke_scout_end_to_end():
    """Test full scout agent invocation. Requires Codex CLI and agent templates."""
    result = await app.call_tool(
        "invoke_agent",
        {
            "agent": "scout",
            "task_prompt": "Find all Python files in the src/ directory",
        }
    )

    assert len(result) == 1
    # Scout should report findings or indicate agent was invoked
    assert result[0].text
    assert not result[0].text.startswith("ERROR")

@pytest.mark.integration
@pytest.mark.asyncio
async def test_invoke_detective_with_task_id():
    """Test detective agent with Kanban task tracking."""
    result = await app.call_tool(
        "invoke_agent",
        {
            "agent": "detective",
            "task_prompt": "Investigate why tests are failing",
            "task_id": "RCH-999",
        }
    )

    assert len(result) == 1
    assert result[0].text
    assert not result[0].text.startswith("ERROR")
