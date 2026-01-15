"""Tests for Provider API clients."""

import pytest
from mcp_provider_delegator.provider_client import (
    CodexClient,
    GeminiClient,
    ProviderChain,
    RateLimitError,
    create_provider_chain,
)


def test_codex_model_mapping():
    """Test model mapping from agent models to Codex models."""
    assert CodexClient.map_model("haiku") == "gpt-5.1-codex-mini"
    assert CodexClient.map_model("sonnet") == "gpt-5.2-codex"
    assert CodexClient.map_model("opus") == "gpt-5.1-codex-max"
    assert CodexClient.map_model("unknown") == "gpt-5.2-codex"


def test_create_provider_chain_code_reviewer():
    """Test that code-reviewer allows skip on failure."""
    chain = create_provider_chain("haiku", "code-reviewer")
    assert chain.allow_skip is True
    assert len(chain.providers) == 2  # Codex + Gemini


def test_create_provider_chain_other_agents():
    """Test that other agents don't allow skip."""
    chain = create_provider_chain("opus", "detective")
    assert chain.allow_skip is False
    assert len(chain.providers) == 2


@pytest.mark.integration
@pytest.mark.asyncio
async def test_invoke_codex_simple():
    """Test invoking Codex with simple prompt. Requires Codex CLI."""
    client = CodexClient(model="gpt-5.2-codex")

    result = await client.invoke(
        prompt="You are a helpful assistant. Say hello."
    )

    assert "hello" in result.lower()


@pytest.mark.integration
@pytest.mark.asyncio
async def test_invoke_gemini_simple():
    """Test invoking Gemini with simple prompt. Requires Gemini CLI."""
    client = GeminiClient()

    result = await client.invoke(
        prompt="You are a helpful assistant. Say hello."
    )

    assert "hello" in result.lower()
