"""Tests for agent template loader."""

import os
import pytest
from pathlib import Path
from mcp_provider_delegator.agent_loader import AgentLoader, AgentTemplate

FIXTURES_DIR = Path(__file__).parent / "fixtures"

def test_load_agent_template():
    """Test loading agent template from .md file."""
    loader = AgentLoader(templates_path=str(FIXTURES_DIR))
    template = loader.load_agent("scout")

    assert template.name == "scout"
    assert template.model == "haiku"
    assert template.description == "Scout agent for codebase exploration"
    assert "Read" in template.tools
    assert "Ivy" in template.system_prompt
    assert "Your Purpose" in template.system_prompt

def test_load_nonexistent_agent():
    """Test loading non-existent agent raises error."""
    loader = AgentLoader(templates_path=str(FIXTURES_DIR))
    with pytest.raises(FileNotFoundError):
        loader.load_agent("nonexistent")
