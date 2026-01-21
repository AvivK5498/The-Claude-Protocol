#!/bin/bash
#
# PreToolUse: Block Edit/Write on main branch
#
# Supervisors must work on bd-{BEAD_ID} branches, not main.
# This prevents accidental commits to main.
#

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only check Edit and Write tools
[[ "$TOOL_NAME" != "Edit" ]] && [[ "$TOOL_NAME" != "Write" ]] && exit 0

# Check current branch
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)

# Block if on main or master
if [[ "$CURRENT_BRANCH" == "main" ]] || [[ "$CURRENT_BRANCH" == "master" ]]; then
  cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Cannot edit files on $CURRENT_BRANCH branch. Create feature branch first: git checkout -b bd-{BEAD_ID}. Supervisors must work on feature branches."}}
EOF
  exit 0
fi

exit 0
