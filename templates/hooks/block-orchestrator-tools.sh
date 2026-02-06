#!/bin/bash
#
# PreToolUse: Block orchestrator from implementation tools
#
# Orchestrators investigate and delegate - they don't implement.
#

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Always allow Task (delegation)
[[ "$TOOL_NAME" == "Task" ]] && exit 0

# Detect SUBAGENT context - subagents get full tool access
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

# Allow Plan mode — orchestrator can write to ~/.claude/plans/
# Allow CLAUDE.md — orchestrator maintains project documentation
if [[ "$TOOL_NAME" == "Edit" ]] || [[ "$TOOL_NAME" == "Write" ]]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
  if [[ "$FILE_PATH" == *"/.claude/plans/"* ]]; then
    exit 0
  fi
  # Allow CLAUDE.md updates (project documentation is orchestrator responsibility)
  if [[ "$(basename "$FILE_PATH")" == "CLAUDE.md" ]] || [[ "$(basename "$FILE_PATH")" == "CLAUDE.local.md" ]]; then
    exit 0
  fi
  # Allow git-issues.md updates (issue tracking is orchestrator responsibility)
  if [[ "$(basename "$FILE_PATH")" == "git-issues.md" ]]; then
    exit 0
  fi
  # Allow memory files (orchestrator maintains persistent learnings)
  if [[ "$FILE_PATH" == *"/.claude/"*"/memory/"* ]] || [[ "$FILE_PATH" == *"/.claude/memory/"* ]]; then
    exit 0
  fi
fi

# QUICK-FIX ESCAPE HATCH with branch enforcement
# Orchestrators can make small edits on feature branches with user approval
# But NEVER on main/master - must use full bead + worktree workflow
if [[ "$TOOL_NAME" == "Edit" ]] || [[ "$TOOL_NAME" == "Write" ]]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
  FILE_NAME=$(basename "$FILE_PATH")

  # Check if editing within a worktree (always allowed for orchestrator)
  if [[ "$FILE_PATH" == *"/.worktrees/"* ]]; then
    exit 0
  fi

  # Check current branch
  CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)

  # On main/master → hard deny, guide to alternatives
  if [[ "$CURRENT_BRANCH" == "main" ]] || [[ "$CURRENT_BRANCH" == "master" ]]; then
    cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Cannot edit files on $CURRENT_BRANCH branch.\n\nFor quick fixes (<10 lines):\n  git checkout -b quick-fix-description\n  Then retry the edit (you'll be prompted for approval)\n\nFor larger changes:\n  Use the full bead workflow with supervisors."}}
EOF
    exit 0
  fi

  # On feature branch → ask for quick-fix approval
  # Estimate change size for Edit tool
  if [[ "$TOOL_NAME" == "Edit" ]]; then
    OLD_STRING=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty')
    NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')
    OLD_LINES=$(echo "$OLD_STRING" | wc -l | tr -d ' ')
    NEW_LINES=$(echo "$NEW_STRING" | wc -l | tr -d ' ')
    OLD_CHARS=${#OLD_STRING}
    NEW_CHARS=${#NEW_STRING}
    SIZE_INFO="~${NEW_LINES} lines (${OLD_CHARS} → ${NEW_CHARS} chars)"
  else
    # Write tool - estimate from content
    CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
    CONTENT_LINES=$(echo "$CONTENT" | wc -l | tr -d ' ')
    SIZE_INFO="~${CONTENT_LINES} lines (new file)"
  fi

  cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Quick fix on branch '$CURRENT_BRANCH'?\n  File: $FILE_NAME\n  Change: $SIZE_INFO\n\nApprove for trivial changes (<10 lines).\nDeny to use full bead workflow instead."}}
EOF
  exit 0
fi

# Block NotebookEdit (no quick-fix escape for notebooks)
if [[ "$TOOL_NAME" == "NotebookEdit" ]]; then
  cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Tool '$TOOL_NAME' blocked. Orchestrators investigate and delegate via Task(). Supervisors implement."}}
EOF
  exit 0
fi

# Validate provider_delegator agent invocations - block implementation agents
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
  FIRST_WORD="${COMMAND%% *}"

  # ALLOW git commands (check second word for read vs write)
  if [[ "$FIRST_WORD" == "git" ]]; then
    SECOND_WORD=$(echo "$COMMAND" | awk '{print $2}')
    case "$SECOND_WORD" in
      status|log|diff|branch|checkout|merge|fetch|remote|stash|show)
        exit 0
        ;;
      add)
        # Allow git add for quick-fix flow
        exit 0
        ;;
      commit)
        # Block --no-verify to ensure pre-commit hooks run
        if [[ "$COMMAND" == *"--no-verify"* ]] || [[ "$COMMAND" == *"-n"* ]]; then
          cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"git commit --no-verify is blocked.\n\nPre-commit hooks exist for a reason (type-check, lint, tests).\nRun the commit without --no-verify and fix any issues."}}
EOF
          exit 0
        fi
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

    exit 0
  fi

  # Allow other bash commands (npm, cargo, etc. for investigation)
  exit 0
fi

# Allow everything else
exit 0
