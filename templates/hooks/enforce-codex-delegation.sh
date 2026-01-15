#!/bin/bash
#
# PreToolUse: Enforce Codex for non-implementing agents
#

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

[[ "$TOOL_NAME" != "Task" ]] && exit 0

SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty')
[[ -z "$SUBAGENT_TYPE" ]] && exit 0

# Read-only agents MUST use Codex (no Write/Edit tools)
READ_ONLY_AGENTS="scout|detective|architect|scribe"

if [[ "$SUBAGENT_TYPE" =~ ^($READ_ONLY_AGENTS)$ ]]; then
  cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Agent '$SUBAGENT_TYPE' is read-only - must use provider delegator: mcp__provider_delegator__invoke_agent(agent=\"$SUBAGENT_TYPE\", task_prompt=\"...\")"}}
EOF
  exit 0
fi

# Implementing agents (discovery, *-supervisor) use Task() - approved
exit 0
