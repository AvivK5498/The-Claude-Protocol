#!/bin/bash
#
# UserPromptSubmit: Force clarification on vague requests + epic reminder
#
# Uses plain text stdout for context injection (per Claude Code docs)
#

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')
LENGTH=${#PROMPT}

if [[ $LENGTH -lt 50 ]]; then
  cat << 'EOF'
<system-reminder>
STOP. This request is too short to act on safely.

BEFORE doing anything else, you MUST use the AskUserQuestion tool to clarify:
- What specific outcome does the user want?
- What files/components are involved?
- Are there any constraints or preferences?

Do NOT guess. Do NOT start working. Ask first.
</system-reminder>
EOF
elif [[ $LENGTH -lt 200 ]]; then
  cat << 'EOF'
<system-reminder>
This request may be ambiguous. Consider using AskUserQuestion to clarify before proceeding.
</system-reminder>
EOF
fi

# Always remind about epic workflow
cat << 'EOF'
<cross-domain-check>
CRITICAL: If this task spans multiple supervisors, you MUST create an EPIC.
Cross-domain = Epic. No exceptions.
</cross-domain-check>
EOF
