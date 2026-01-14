#!/bin/bash
#
# UserPromptSubmit: Remind orchestrator to clarify vague requests
#
# Adaptive reminder based on prompt length:
# - Short prompts (<50 chars): Full reminder
# - Medium prompts (50-200 chars): Short reminder
# - Long prompts (>200 chars): No reminder (assume detailed)
#

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.user_prompt // empty')
LENGTH=${#PROMPT}

if [[ $LENGTH -lt 50 ]]; then
  cat << 'EOF'
{"decision":"approve","message":"<important>\nVague request? Use AskUserQuestion tool to clarify before delegating.\nDo NOT guess. Do NOT delegate unclear tasks.\n</important>"}
EOF
elif [[ $LENGTH -lt 200 ]]; then
  echo '{"decision":"approve","message":"<tip>Vague? Use AskUserQuestion tool first.</tip>"}'
else
  echo '{"decision":"approve"}'
fi
