---
name: create-beads-orchestration
description: Bootstrap lean multi-agent orchestration with beads task tracking. Use for projects needing agent delegation without heavy MCP overhead.
user-invocable: true
---

# Create Beads Orchestration

Set up lightweight multi-agent orchestration with git-native task tracking and mandatory code review gates.

---

## CRITICAL: Mandatory 4-Step Workflow

<mandatory-workflow>
You MUST follow ALL 4 steps below in exact order. Missing ANY step is a CATASTROPHIC FAILURE.

| Step | Action | Checkpoint |
|------|--------|------------|
| 1 | Get project info from user | Have project name and directory |
| 2 | Clone repo and run bootstrap | Bootstrap completes successfully |
| 3 | **STOP** - Instruct user to restart Claude Code | User confirms they will restart |
| 4 | After restart: Run discovery agent | Supervisors created in .claude/agents/ |

**DO NOT:**
- Skip asking for project info
- Continue after bootstrap without telling user to restart
- Forget to run discovery after restart
- Consider setup complete until discovery has run

**The setup is NOT complete until Step 4 (discovery) has run.**
</mandatory-workflow>

---

## Step 1: Get Project Info

Ask the user for:
- **Project directory**: Where to install (default: current working directory)
- **Project name**: For agent templates (will auto-infer from package.json/pyproject.toml if not provided)

Wait for user response before proceeding.

---

## Step 2: Clone and Run Bootstrap

```bash
git clone --depth=1 https://github.com/AvivK5498/Claude-Code-Beads-Orchestration "${TMPDIR:-/tmp}/beads-orchestration-setup"
```

```bash
python3 "${TMPDIR:-/tmp}/beads-orchestration-setup/bootstrap.py" \
  --project-name "{{PROJECT_NAME}}" \
  --project-dir "{{PROJECT_DIR}}"
```

The bootstrap script will:
1. Install beads CLI (via brew, npm, or go)
2. Initialize `.beads/` directory
3. Copy agent templates to `.claude/agents/`
4. Copy hooks to `.claude/hooks/`
5. Configure `.claude/settings.json`
6. Set up `.mcp.json` for provider_delegator
7. Create `CLAUDE.md` with orchestrator instructions
8. Update `.gitignore`

**Verify bootstrap completed successfully before proceeding.**

---

## Step 3: STOP - User Must Restart

<critical>
**YOU MUST STOP HERE AND INSTRUCT THE USER TO RESTART CLAUDE CODE.**

Tell the user:

> **Setup phase complete. You MUST restart Claude Code now.**
>
> The new hooks and MCP configuration will only load after restart.
>
> After restarting:
> 1. Open this same project directory
> 2. Tell me "Continue orchestration setup" or run `/create-beads-orchestration` again
> 3. I will run the discovery agent to complete setup
>
> **Do not skip this restart - the orchestration will not work without it.**

**DO NOT proceed to Step 4 in this session. The restart is mandatory.**
</critical>

---

## Step 4: Run Discovery (After Restart)

<post-restart>
If the user returns after restart and says "continue setup" or similar:

1. Verify bootstrap completed (check for `.claude/agents/scout.md`)
2. Run the discovery agent:

```python
Task(
    subagent_type="discovery",
    prompt="Detect tech stack and create supervisors for this project"
)
```

Discovery will:
- Scan package.json, requirements.txt, Dockerfile, etc.
- Fetch specialist agents from external directory
- Inject beads workflow into each supervisor
- Write supervisors to `.claude/agents/`

3. After discovery completes, tell the user:

> **Orchestration setup complete!**
>
> Created supervisors: [list what discovery created]
>
> You can now use the orchestration workflow:
> - Create tasks with `bd create "Task name" -d "Description"`
> - The orchestrator will delegate to appropriate supervisors
> - All work requires code review before completion
</post-restart>

---

## Cleanup (Optional)

```bash
rm -rf "${TMPDIR:-/tmp}/beads-orchestration-setup"
```

---

## What This Creates

- **Beads CLI** for git-native task tracking (one bead = one branch = one task)
- **Core agents**: scout, detective, architect, scribe, code-reviewer (run via provider delegator)
- **Discovery agent**: Auto-detects tech stack and creates specialized supervisors
- **MCP Provider Delegator**: Enables read-only agent delegation with Codex→Gemini fallback
- **7 hooks**: Enforce orchestrator discipline, code review gates, concise responses
- **Branch-per-task workflow**: Parallel development with automated merge conflict handling

## Requirements

- **Codex CLI**: `codex login` for authentication (primary provider)
- **Gemini CLI**: Optional fallback when Codex hits rate limits
- **uv**: Python package manager for MCP server
- **beads CLI**: Installed automatically (or manually via brew/npm/go)

## More Information

See the full documentation: https://github.com/AvivK5498/Claude-Code-Beads-Orchestration
