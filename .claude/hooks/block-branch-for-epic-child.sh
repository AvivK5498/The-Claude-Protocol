#!/bin/bash
#
# PreToolUse:Bash - Block branch creation for epic children
#
# Epic children MUST work on the shared EPIC_BRANCH (bd-{EPIC_ID}).
# This hook blocks any `git checkout -b` command when working on an epic child.
#
# Detection: BEAD_ID contains a dot (e.g., BD-001.2 = child of BD-001)
#

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only check Bash commands
[[ "$TOOL_NAME" != "Bash" ]] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only care about git checkout -b (branch creation)
if ! echo "$COMMAND" | grep -qE 'git\s+checkout\s+-b|git\s+switch\s+-c|git\s+branch\s+[^-]'; then
  exit 0
fi

# Check if we're in an epic child context by looking at recent bead context
# Strategy: Look for BEAD_ID pattern in the prompt/context that contains a dot
CONVERSATION_CONTEXT=$(echo "$INPUT" | jq -r '.conversation_context // empty')

# Extract BEAD_ID from various patterns
BEAD_ID=""

# Try to find BEAD_ID in conversation context
if [[ -n "$CONVERSATION_CONTEXT" ]]; then
  BEAD_ID=$(echo "$CONVERSATION_CONTEXT" | grep -oE "BEAD_ID:?\s*[A-Za-z0-9._-]+" | head -1 | sed 's/BEAD_ID:*\s*//')
fi

# If no context, try to infer from current branch name
if [[ -z "$BEAD_ID" ]]; then
  CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
  if [[ "$CURRENT_BRANCH" =~ ^bd-([A-Za-z0-9._-]+) ]]; then
    BEAD_ID="${BASH_REMATCH[1]}"
  fi
fi

# If still no BEAD_ID, allow the command
[[ -z "$BEAD_ID" ]] && exit 0

# Check if this is an epic child (contains a dot like BD-001.2)
if [[ "$BEAD_ID" == *"."* ]]; then
  # Extract the parent epic ID
  EPIC_ID=$(echo "$BEAD_ID" | sed 's/\.[0-9]*$//')

  cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<epic-branch-enforcement>
BLOCKED: Cannot create new branch for epic child ${BEAD_ID}

Epic children MUST work on the shared epic branch: bd-${EPIC_ID}

Instead of creating a new branch, use:
  git checkout bd-${EPIC_ID}

This ensures all epic children's work stays on the same branch for atomic merging.
</epic-branch-enforcement>"}}
EOF
  exit 0
fi

# Not an epic child, allow branch creation
exit 0
