#!/bin/bash
#
# PreToolUse:Task - Enforce bead exists before supervisor dispatch
#
# All supervisors must have BEAD_ID in prompt.
# This ensures all work is tracked.
#

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

[[ "$TOOL_NAME" != "Task" ]] && exit 0

SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty')
PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty')

# Only enforce for supervisors
[[ ! "$SUBAGENT_TYPE" =~ supervisor ]] && exit 0

# Check for BEAD_ID in prompt
if [[ "$PROMPT" != *"BEAD_ID:"* ]]; then
  cat << 'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<bead-required>\nAll supervisor work MUST be tracked with a bead.\n\n<action>\nFor standalone tasks:\n  1. bd create \"Task title\" -d \"Description\"\n  2. Dispatch with: BEAD_ID: {id}\n\nFor epic children (cross-domain features):\n  1. bd create \"Epic\" -d \"...\" --type epic\n  2. bd create \"Child\" -d \"...\" --parent {EPIC_ID}\n  3. Dispatch with: BEAD_ID: {child_id}, EPIC_BRANCH: bd-{epic_id}, EPIC_ID: {epic_id}\n</action>\n</bead-required>"}}
EOF
  exit 0
fi

# If child task (BEAD_ID contains dot like BD-001.1), require EPIC_BRANCH
BEAD_ID=$(echo "$PROMPT" | grep -oE "BEAD_ID: [A-Za-z0-9._-]+" | head -1 | sed 's/BEAD_ID: //')
if [[ "$BEAD_ID" == *"."* ]] && [[ "$PROMPT" != *"EPIC_BRANCH:"* ]]; then
  cat << 'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<epic-branch-required>\nChild task detected (BEAD_ID contains dot). EPIC_BRANCH is required.\n\nChild tasks work on the shared epic branch, not their own branch.\n\n<format>\nBEAD_ID: {CHILD_ID}       (e.g., BD-001.2)\nEPIC_BRANCH: bd-{EPIC_ID} (e.g., bd-BD-001)\nEPIC_ID: {EPIC_ID}        (e.g., BD-001)\n\n[Task description]\n</format>\n\nThis ensures all epic children work on the same branch for consistency.\n</epic-branch-required>"}}
EOF
  exit 0
fi

exit 0
