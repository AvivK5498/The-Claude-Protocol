#!/bin/bash
#
# PreToolUse: Block orchestrator from implementation tools
#
# Orchestrators delegate - they don't code.
#

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Always allow Task (delegation)
[[ "$TOOL_NAME" == "Task" ]] && exit 0

# Detect SUBAGENT context - only subagents get full tool access
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

[[ "$IS_SUBAGENT" == "true" ]] && exit 0

# Orchestrator allowlist (NO Skill - supervisors use skills, orchestrators delegate)
ALLOWED="Task|Bash|Glob|Read|AskUserQuestion|TodoWrite|EnterPlanMode|ExitPlanMode|mcp__provider_delegator__invoke_agent"

if [[ ! "$TOOL_NAME" =~ ^($ALLOWED)$ ]]; then
  cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Tool '$TOOL_NAME' blocked. Orchestrators delegate via Task() or mcp__provider_delegator__invoke_agent(). They don't implement."}}
EOF
  exit 0
fi

# Validate Codex agent invocations - block implementation agents
if [[ "$TOOL_NAME" == "mcp__provider_delegator__invoke_agent" ]]; then
  AGENT=$(echo "$INPUT" | jq -r '.tool_input.agent // empty')
  CODEX_ALLOWED="scout|detective|architect|scribe|code-reviewer"

  if [[ ! "$AGENT" =~ ^($CODEX_ALLOWED)$ ]]; then
    cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Agent '$AGENT' cannot be invoked via Codex. Implementation agents (*-supervisor, discovery) must use Task() with BEAD_ID for beads workflow."}}
EOF
    exit 0
  fi
fi

# Validate Bash commands for orchestrator
if [[ "$TOOL_NAME" == "Bash" ]]; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

  # Check for command chaining (&&, ||, ;, |)
  if [[ "$COMMAND" == *";"* ]] || [[ "$COMMAND" == *"|"* ]] || [[ "$COMMAND" == *"&&"* ]] || [[ "$COMMAND" == *"||"* ]]; then
    CHAIN_CHECK="${TMPDIR:-/tmp}/chain_check_$$"
    echo "$COMMAND" | sed 's/&&/\n/g; s/||/\n/g; s/;/\n/g; s/|/\n/g' | while IFS= read -r part; do
      trimmed=$(echo "$part" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      first_word="${trimmed%% *}"
      if [[ "$first_word" != "bd" ]] && [[ -n "$first_word" ]]; then
        echo "BLOCKED" > "$CHAIN_CHECK"
      fi
    done

    if [[ -f "$CHAIN_CHECK" ]]; then
      rm -f "$CHAIN_CHECK"
      SAFE_CMD=$(echo "$COMMAND" | head -c 100 | tr '\n' ' ' | sed 's/"/\\"/g')
      cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Command chaining blocked. Only bd commands can be chained: ${SAFE_CMD}..."}}
EOF
      exit 0
    fi
    rm -f "$CHAIN_CHECK" 2>/dev/null
    exit 0
  fi

  FIRST_WORD="${COMMAND%% *}"

  # ALLOW git commands (check second word for read vs write)
  if [[ "$FIRST_WORD" == "git" ]]; then
    SECOND_WORD=$(echo "$COMMAND" | awk '{print $2}')
    case "$SECOND_WORD" in
      status|log|diff|branch|checkout|merge|fetch|remote|stash)
        exit 0
        ;;
      add|commit|push|rebase|reset)
        cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Git '$SECOND_WORD' blocked. Supervisors handle commits."}}
EOF
        exit 0
        ;;
    esac
  fi

  # ALLOW beads commands (with validation)
  if [[ "$FIRST_WORD" == "bd" ]]; then
    SECOND_WORD=$(echo "$COMMAND" | awk '{print $2}')

    # Validate bd create requires description
    if [[ "$SECOND_WORD" == "create" ]] || [[ "$SECOND_WORD" == "new" ]]; then
      if [[ "$COMMAND" != *"-d "* ]] && [[ "$COMMAND" != *"--description "* ]] && [[ "$COMMAND" != *"--description="* ]]; then
        cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"bd create requires description (-d or --description) for supervisor context."}}
EOF
        exit 0
      fi
    fi

    # CRITICAL: Validate code review AND merge before closing bead
    if [[ "$SECOND_WORD" == "update" ]] && [[ "$COMMAND" == *"done"* ]]; then
      # Extract bead ID from command (e.g., "bd update BD-001 --status done")
      BEAD_ID=$(echo "$COMMAND" | grep -oE 'BD-[0-9]+' | head -1)

      if [[ -n "$BEAD_ID" ]]; then
        # Check 1: Code review approval
        COMMENTS=$(bd comments "$BEAD_ID" 2>/dev/null)

        if [[ "$COMMENTS" != *"CODE REVIEW: APPROVED"* ]]; then
          cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Cannot close $BEAD_ID - no code review approval found. Dispatch code-reviewer first: Task(subagent_type='code-reviewer', prompt='Review BEAD_ID: $BEAD_ID on branch bd-$BEAD_ID'). After approval, retry closing."}}
EOF
          exit 0
        fi

        # Check 2: Branch must be merged
        BRANCH_NAME="bd-$BEAD_ID"

        # Check if branch still exists (not merged/deleted)
        if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null; then
          # Branch exists - check if it's been merged into current branch (main)
          CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)

          # Check if branch is merged into main
          if ! git branch --merged main 2>/dev/null | grep -q "$BRANCH_NAME"; then
            cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Cannot close $BEAD_ID - branch '$BRANCH_NAME' not merged. Merge first: git checkout main && git merge $BRANCH_NAME && git branch -d $BRANCH_NAME. Then retry closing."}}
EOF
            exit 0
          fi
        fi
      fi
    fi

    exit 0
  fi

  # BLOCK everything else
  SAFE_CMD=$(echo "$COMMAND" | head -c 100 | tr '\n' ' ' | sed 's/"/\\"/g')
  cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Bash command blocked: ${SAFE_CMD}... Orchestrators only run: git (status|log|diff|branch|checkout|merge|stash) and bd commands."}}
EOF
  exit 0
fi

exit 0
