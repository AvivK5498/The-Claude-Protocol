#!/bin/bash
#
# PreToolUse:Task - Inject knowledge base reminder for supervisor dispatches
#
# When orchestrator dispatches a supervisor via Task(), check if a project
# knowledge base exists and remind the supervisor to search it before
# implementing.
#

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only check Task tool
[[ "$TOOL_NAME" != "Task" ]] && exit 0

# Check if dispatching a supervisor
SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty')

# Only inject for supervisors
[[ "$SUBAGENT_TYPE" != *"supervisor"* ]] && exit 0

# Find repo root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[[ -z "$REPO_ROOT" ]] && exit 0

# Check if knowledge file exists and is non-empty
KNOWLEDGE_FILE="${REPO_ROOT}/.beads/memory/knowledge.jsonl"
[[ ! -s "$KNOWLEDGE_FILE" ]] && exit 0

# Full path to recall script
RECALL_PATH="${REPO_ROOT}/.beads/memory/recall.sh"

# Extract BEAD_ID from the prompt for context (optional, for logging)
PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty')
BEAD_ID=$(echo "$PROMPT" | grep -oE 'BEAD_ID: [A-Za-z0-9._-]+' | head -1 | sed 's/BEAD_ID: //')

cat << EOF
<system-reminder>
<project-knowledge>
This project has a knowledge base with learnings and investigation notes from previous work.
Before implementing, consider searching for relevant patterns:

  ${RECALL_PATH} "relevant keyword"

Examples of useful searches based on the task context:
  ${RECALL_PATH} "rust"          # Rust/backend patterns
  ${RECALL_PATH} "react"         # React/frontend patterns
  ${RECALL_PATH} "pattern"       # Established code patterns
  ${RECALL_PATH} --type learned  # All project learnings

This can surface gotchas, conventions, and patterns discovered in previous tasks.
</project-knowledge>
</system-reminder>
EOF

exit 0
