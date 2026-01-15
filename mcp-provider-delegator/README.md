# MCP Provider Delegator

Delegates orchestration agents to AI providers with automatic fallback support.

## Fallback Chain

```
Codex (primary) → Gemini (fallback) → Skip (code-reviewer only)
```

- **Codex**: Primary provider, maps agent models to Codex tiers
- **Gemini**: Fallback when Codex hits rate limits (`gemini-3-flash-preview`)
- **Skip**: For code-reviewer only - returns skip message if all providers fail

## Installation

```bash
pip install -e .
```

## Configuration

Add to your project's `.mcp.json`:

```json
{
  "mcpServers": {
    "provider_delegator": {
      "type": "stdio",
      "command": "/path/to/.venv/bin/python",
      "args": ["-m", "mcp_provider_delegator.server"],
      "env": {
        "AGENT_TEMPLATES_PATH": ".claude/agents"
      }
    }
  }
}
```

## Usage

```python
mcp__provider_delegator__invoke_agent(
  agent="detective",
  task_prompt="Investigate authentication failure",
  task_id="RCH-123"
)
```

## Available Agents

| Agent | Model | Codex Tier |
|-------|-------|------------|
| scout | haiku | gpt-5.1-codex-mini |
| scribe | haiku | gpt-5.1-codex-mini |
| code-reviewer | haiku | gpt-5.1-codex-mini |
| detective | opus | gpt-5.1-codex-max |
| architect | opus | gpt-5.1-codex-max |

## Rate Limit Handling

When Codex returns HTTP 429 (rate limit), the delegator automatically:
1. Logs the rate limit error
2. Falls back to Gemini CLI
3. If Gemini also fails, returns skip message (code-reviewer) or error (other agents)
