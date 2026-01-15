# MCP Provider Delegator

Delegates orchestration agents to AI providers with automatic fallback support.

## Fallback Chain

```
Codex (primary) → Gemini (fallback) → Skip/Fallback Hint
```

- **Codex**: Primary provider, maps agent models to Codex tiers
- **Gemini**: Fallback when Codex hits rate limits (`gemini-3-flash-preview`)
- **Skip**: For code-reviewer only - returns skip message if all providers fail
- **Fallback Hint**: For other agents - returns structured Task() suggestion

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
2. Falls back to Gemini CLI (`gemini -p {prompt} -m gemini-3-flash-preview`)
3. If Gemini also fails:
   - **code-reviewer**: Returns `SKIPPED: All providers rate limited`
   - **Other agents**: Returns structured fallback hint with Task() suggestion

## Fallback Hints

When all providers fail for non-code-reviewer agents, the delegator returns a structured fallback hint:

```
PROVIDER_FALLBACK_REQUIRED

All external providers (Codex, Gemini) failed for agent 'scout'.
Errors: codex: rate limited; gemini: rate limited

To complete this task, use Claude Task tool instead:

Task(
    subagent_type="scout",
    model="haiku",
    prompt="PROVIDER_FALLBACK: {original prompt}"
)

Note: The Task tool runs locally and doesn't have the same rate limits.
```

### Agent to Subagent Mapping

| Agent | Task subagent_type |
|-------|-------------------|
| scout | scout |
| detective | scout |
| architect | Plan |
| scribe | scout |
| code-reviewer | superpowers:code-reviewer |

## PROVIDER_FALLBACK Bypass

The `enforce-codex-delegation.sh` hook normally blocks direct Task() calls for read-only agents, requiring them to go through the provider_delegator. However, when all providers fail and a fallback hint is returned, the orchestrator needs to use Task() directly.

The bypass mechanism:
1. Fallback hints include `PROVIDER_FALLBACK:` prefix in the prompt
2. The hook checks for this prefix and allows the Task() call
3. This prevents infinite recursion: provider fails → hint → Task blocked → retry provider

```bash
# In enforce-codex-delegation.sh
PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty')
if [[ "$PROMPT" == *"PROVIDER_FALLBACK"* ]]; then
  exit 0  # Allow bypass
fi
```
