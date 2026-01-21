#!/bin/bash
#
# PreToolUse: Warn orchestrator when reading code files
#
# Orchestrators can read docs/configs freely, but reading code files
# leads to prescribing solutions. Inject a reminder to describe problems,
# not solutions.
#

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only check Read tool
[[ "$TOOL_NAME" != "Read" ]] && exit 0

# Detect SUBAGENT context - subagents can read anything
IS_SUBAGENT="false"

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
TOOL_USE_ID=$(echo "$INPUT" | jq -r '.tool_use_id // empty')

if [[ -n "$TRANSCRIPT_PATH" ]] && [[ -n "$TOOL_USE_ID" ]]; then
  SESSION_DIR="${TRANSCRIPT_PATH%.jsonl}"
  SUBAGENTS_DIR="$SESSION_DIR/subagents"

  if [[ -d "$SUBAGENTS_DIR" ]]; then
    MATCHING_SUBAGENT=$(grep -l "\"id\":\"$TOOL_USE_ID\"" "$SUBAGENTS_DIR"/agent-*.jsonl 2>/dev/null | head -1)
    [[ -n "$MATCHING_SUBAGENT" ]] && IS_SUBAGENT="true"
  fi
fi

# Subagents can read anything without warning
[[ "$IS_SUBAGENT" == "true" ]] && exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
FILENAME=$(basename "$FILE_PATH")
EXTENSION="${FILENAME##*.}"

# Path-based allowlist (always safe)
[[ "$FILE_PATH" == *"/.claude/"* ]] && exit 0
[[ "$FILE_PATH" == *"/.designs/"* ]] && exit 0
[[ "$FILE_PATH" == *"/.beads/"* ]] && exit 0
[[ "$FILE_PATH" == *"/node_modules/"* ]] && exit 0

# Extension allowlist (docs/configs - safe to read)
SAFE_EXTENSIONS="md|txt|yaml|yml|toml|json|gitignore|gitattributes|editorconfig|lock|log"
if [[ "$EXTENSION" =~ ^($SAFE_EXTENSIONS)$ ]]; then
  exit 0
fi

# Files without extensions that are safe
SAFE_FILES="Dockerfile|Makefile|README|LICENSE|CHANGELOG|CLAUDE"
if [[ "$FILENAME" =~ ^($SAFE_FILES)$ ]]; then
  exit 0
fi

# Code file detected - inject warning
cat << EOF
<system-reminder>
ORCHESTRATOR: You read a code file ($FILENAME).

When dispatching supervisors:
- DESCRIBE the problem and expected behavior
- Do NOT prescribe fixes or guess at root causes
- Do NOT include "Likely cause:", "Fix approach:", or "Try this:"

For technical investigation, dispatch detective FIRST:
  mcp__provider_delegator__invoke_agent(agent="detective", task_prompt="...")

Then include detective findings (marked as hypotheses) in supervisor dispatch.
</system-reminder>
EOF

exit 0
