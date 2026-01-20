#!/bin/bash
#
# SubagentStop: Enforce bead lifecycle - supervisors must mark inreview
#

INPUT=$(cat)
AGENT_TRANSCRIPT=$(echo "$INPUT" | jq -r '.agent_transcript_path // empty')

[[ -z "$AGENT_TRANSCRIPT" || ! -f "$AGENT_TRANSCRIPT" ]] && echo '{"decision":"approve"}' && exit 0

# Extract last response
LAST_RESPONSE=$(tail -50 "$AGENT_TRANSCRIPT" | grep -o '"text":"[^"]*"' | tail -1 | sed 's/"text":"//;s/"$//')

# Check for supervisor agents (they must report BEAD_ID and inreview status)
AGENT_TYPE=$(echo "$INPUT" | jq -r '.subagent_type // empty')

if [[ "$AGENT_TYPE" =~ supervisor ]]; then
  # Worker supervisor is exempt from bead requirements (handles small tasks without beads)
  # But still subject to verbosity limits
  IS_WORKER="false"
  if [[ "$AGENT_TYPE" == *"worker"* ]]; then
    IS_WORKER="true"
  fi

  if [[ "$IS_WORKER" == "false" ]]; then
    # Check if this is an epic child task (BEAD_ID contains dot like BD-001.1)
    # Epic children do NOT require code review - review happens at epic level
    BEAD_ID_FROM_RESPONSE=$(echo "$LAST_RESPONSE" | grep -oE "BEAD [A-Za-z0-9._-]+" | head -1 | awk '{print $2}')
    IS_EPIC_CHILD="false"
    if [[ "$BEAD_ID_FROM_RESPONSE" == *"."* ]]; then
      IS_EPIC_CHILD="true"
    fi

    # Supervisors must include completion report
    HAS_BEAD_COMPLETE=$(echo "$LAST_RESPONSE" | grep -cE "BEAD.*COMPLETE" 2>/dev/null || true)
    HAS_BRANCH=$(echo "$LAST_RESPONSE" | grep -cE "Branch:.*bd-" 2>/dev/null || true)
    [[ -z "$HAS_BEAD_COMPLETE" ]] && HAS_BEAD_COMPLETE=0
    [[ -z "$HAS_BRANCH" ]] && HAS_BRANCH=0

    # Check completion format first (required for all)
    if [[ "$HAS_BEAD_COMPLETE" -lt 1 ]] || [[ "$HAS_BRANCH" -lt 1 ]]; then
      if [[ "$IS_EPIC_CHILD" == "true" ]]; then
        cat << 'EOF'
{"decision":"block","reason":"Epic child task completion format required:\n\nBEAD {BEAD_ID} COMPLETE\nBranch: {EPIC_BRANCH}\nFiles: [list]\nSummary: [1 sentence]\n\nRun: bd update {BEAD_ID} --status done\n\nNote: Code review happens at EPIC level after all children complete."}
EOF
      else
        cat << 'EOF'
{"decision":"block","reason":"Supervisor must use completion report format:\n\nBEAD {BEAD_ID} COMPLETE\nBranch: bd-{BEAD_ID}\nFiles: [list]\nTests: pass\nSummary: [1 sentence]\n\nRun bd update {BEAD_ID} --status inreview first."}
EOF
      fi
      exit 0
    fi

    # Epic children skip code review - approve if completion format is correct
    if [[ "$IS_EPIC_CHILD" == "true" ]]; then
      # Just check for at least 1 comment
      HAS_COMMENT=$(grep -c '"bd comment\|"command":"bd comment' "$AGENT_TRANSCRIPT" 2>/dev/null) || HAS_COMMENT=0
      [[ -z "$HAS_COMMENT" ]] && HAS_COMMENT=0

      if [[ "$HAS_COMMENT" -lt 1 ]]; then
        cat << 'EOF'
{"decision":"block","reason":"Child task must leave at least 1 comment.\n\nRun: bd comment {BEAD_ID} \"Completed: [brief summary]\"\n\nThis provides context for epic-level code review."}
EOF
        exit 0
      fi

      # Epic child approved (no code review needed)
      echo '{"decision":"approve"}'
      exit 0
    fi

    # Non-epic tasks: require code review
    HAS_COMMENT=$(grep -c '"bd comment\|"command":"bd comment' "$AGENT_TRANSCRIPT" 2>/dev/null) || HAS_COMMENT=0
    HAS_CODE_REVIEW_DISPATCH=$(grep -cE '"subagent_type":\s*"code-reviewer"|"subagent_type":"code-reviewer"|subagent_type.*code-reviewer|mcp__provider_delegator__invoke_agent.*code-reviewer|"agent":\s*"code-reviewer"' "$AGENT_TRANSCRIPT" 2>/dev/null) || HAS_CODE_REVIEW_DISPATCH=0
    HAS_APPROVED=$(grep -c 'CODE REVIEW: APPROVED\|"CODE REVIEW: APPROVED"' "$AGENT_TRANSCRIPT" 2>/dev/null) || HAS_APPROVED=0

    [[ -z "$HAS_COMMENT" ]] && HAS_COMMENT=0
    [[ -z "$HAS_CODE_REVIEW_DISPATCH" ]] && HAS_CODE_REVIEW_DISPATCH=0
    [[ -z "$HAS_APPROVED" ]] && HAS_APPROVED=0

    # Check for code review approval (must have actual dispatch AND approval)
    if [[ "$HAS_CODE_REVIEW_DISPATCH" -lt 1 ]] || [[ "$HAS_APPROVED" -lt 1 ]]; then
      cat << 'EOF'
{"decision":"block","reason":"Code review required before completion. You MUST dispatch the code-reviewer agent.\n\nOption 1 (Claude-only):\n   Task(\n     subagent_type=\"code-reviewer\",\n     prompt=\"Review BEAD_ID: {ID}\"\n   )\n\nOption 2 (External providers):\n   mcp__provider_delegator__invoke_agent(\n     agent=\"code-reviewer\",\n     task_prompt=\"Review BEAD_ID: {ID}\"\n   )\n\nYou cannot self-approve. The code-reviewer agent must return APPROVED."}
EOF
      exit 0
    fi

    # Check for at least 1 comment
    if [[ "$HAS_COMMENT" -lt 1 ]]; then
      cat << 'EOF'
{"decision":"block","reason":"Supervisor must leave at least 1 comment on the bead.\n\nRun: bd comment {BEAD_ID} \"Completed: [brief summary of work done]\"\n\nComments provide context for code review and future reference."}
EOF
      exit 0
    fi
  fi

  # Enforce concise responses for ALL supervisors (including worker)
  # Note: JSON escapes \n as literal chars, use printf to interpret
  DECODED_RESPONSE=$(printf '%b' "$LAST_RESPONSE")
  LINE_COUNT=$(echo "$DECODED_RESPONSE" | wc -l | tr -d ' ')
  CHAR_COUNT=${#DECODED_RESPONSE}

  if [[ "$LINE_COUNT" -gt 15 ]] || [[ "$CHAR_COUNT" -gt 800 ]]; then
    cat << EOF
{"decision":"block","reason":"Response too verbose (${LINE_COUNT} lines, ${CHAR_COUNT} chars). Max: 15 lines, 800 chars.\n\nUse concise format:\nBEAD {ID} COMPLETE\nBranch: bd-{ID}\nFiles: [names only]\nTests: pass\nSummary: [1 sentence]"}
EOF
    exit 0
  fi
fi

echo '{"decision":"approve"}'
