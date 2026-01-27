# Beads Orchestration

Multi-agent orchestration for Claude Code. An orchestrator investigates issues, manages tasks automatically, and delegates implementation to specialized supervisors.

**[Beads Kanban UI](https://github.com/AvivK5498/Beads-Kanban-UI)** — Visual task management fully compatible with this workflow. Supports tasks, epics, subtasks, dependencies, and design docs.

## Installation

```bash
npx skills add AvivK5498/beads-orchestration
```

Or via npm:

```bash
npm install -g @avivkaplan/beads-orchestration
```

> macOS and Linux only.

## Quick Start

```bash
# In any Claude Code session
/create-beads-orchestration
```

The skill walks you through setup, runs the bootstrap via `npx`, then creates tech-specific supervisors based on your codebase.

### Requirements

- Claude Code with hooks support
- Node.js (for npx)
- Python 3 (for bootstrap)
- beads CLI (installed automatically by bootstrap)

## How It Works

```
┌─────────────────────────────────────────┐
│            ORCHESTRATOR                 │
│  Investigates with Grep/Read/Glob       │
│  Manages tasks automatically (beads)    │
│  Delegates implementation via Task()    │
└──────────────────┬──────────────────────┘
                   │
       ┌───────────┼───────────┐
       ▼           ▼           ▼
  ┌─────────┐ ┌─────────┐ ┌─────────┐
  │ react-  │ │ python- │ │ nextjs- │
  │supervisor│ │supervisor│ │supervisor│
  └────┬────┘ └────┬────┘ └────┬────┘
       │           │           │
  .worktrees/ .worktrees/ .worktrees/
  bd-BD-001   bd-BD-002   bd-BD-003
```

**Orchestrator:** Investigates the issue, identifies root cause, logs findings to bead, delegates with brief fix instructions.

**Supervisors:** Read bead comments for context, create isolated worktrees, execute the fix confidently. Created by discovery agent based on your tech stack.

## Worktree Workflow

Each task gets its own isolated worktree at `.worktrees/bd-{BEAD_ID}/`. This keeps the main directory clean and allows parallel work without branch conflicts.

```bash
# Supervisor creates worktree via API
curl -X POST http://localhost:3008/api/git/worktree \
  -H "Content-Type: application/json" \
  -d '{"repo_path": "...", "bead_id": "BD-001"}'

# Work happens in worktree
cd .worktrees/bd-BD-001/
# ... make changes ...
git add -A && git commit -m "..."
git push origin bd-BD-001

# User merges via PR in UI
```

## Automatic Task Management

The orchestrator handles task tracking automatically using [beads](https://github.com/steveyegge/beads). You don't need to manage tasks manually—the orchestrator creates beads, tracks progress, and closes them when work completes.

```bash
bd create "Add auth" -d "JWT-based authentication"  # Orchestrator creates
bd update BD-001 --status in_progress               # Supervisor marks started
bd comment BD-001 "Completed login endpoint"        # Progress logged
bd update BD-001 --status inreview                  # Supervisor marks done
bd close BD-001                                     # User closes after merge
```

## Delegation Format

```python
Task(
  subagent_type="react-supervisor",
  prompt="""BEAD_ID: BD-001

Fix: Add router.push('/dashboard') after successful auth
(Supervisor reads bead comments for full investigation context)"""
)
```

## Epics (Cross-Domain Features)

When a feature spans multiple supervisors (e.g., DB + API + Frontend), the orchestrator creates an epic with child tasks and manages dependencies. Each child gets its own worktree and is dispatched sequentially after the previous child's PR is merged.

You can also explicitly request an epic: *"Add user profiles and create an epic for it."*

## Knowledge Base

Agents build a persistent knowledge base as they work. No extra steps — it piggybacks on `bd comment`.

```bash
# Supervisor finishes a task and records what it learned
bd comment BD-001 "LEARNED: TaskGroup requires @Sendable closures in strict concurrency mode."

# Orchestrator logs investigation findings
bd comment BD-002 "INVESTIGATION: Root cause: SparkleAdapter.swift:45 - nil SUFeedURL crashes XMLParser."
```

An async hook intercepts these comments and extracts them into `.beads/memory/knowledge.jsonl`. Each entry is auto-tagged by keyword and attributed to its source (orchestrator vs supervisor).

**Why this works:**
- Zero friction — agents already use `bd comment`, they just add a prefix
- No database, no embeddings, no external services — one JSONL file, grep + jq to search
- Enforced — supervisors are blocked from completing without a `LEARNED:` comment
- Surfaces automatically — session start shows recent knowledge so agents don't re-investigate solved problems

```bash
# Search the knowledge base
.beads/memory/recall.sh "concurrency"
.beads/memory/recall.sh --recent 10
.beads/memory/recall.sh --stats
```

See [docs/memory-architecture.md](docs/memory-architecture.md) for the full design.

## What Gets Installed

```
.claude/
├── agents/           # Supervisors (discovery creates tech-specific ones)
├── hooks/            # Workflow enforcement
├── skills/           # subagents-discipline, react-best-practices
└── settings.json
CLAUDE.md             # Orchestrator instructions
.beads/               # Task database
  memory/             # Knowledge base (knowledge.jsonl + recall.sh)
.worktrees/           # Isolated worktrees for each task (created dynamically)
```

## Hooks

| Hook | Purpose |
|------|---------|
| `block-orchestrator-tools.sh` | Orchestrator can't Edit/Write |
| `enforce-bead-for-supervisor.sh` | Supervisors need BEAD_ID |
| `enforce-branch-before-edit.sh` | Must be in worktree to edit (not main) |
| `enforce-sequential-dispatch.sh` | Blocks epic children with unresolved deps |
| `validate-epic-close.sh` | Can't close epic with open children |
| `inject-discipline-reminder.sh` | Injects discipline skill reminder |
| `remind-inprogress.sh` | Warns about in-progress beads |
| `validate-completion.sh` | Verifies worktree, push, bead status |
| `enforce-concise-response.sh` | Limits response verbosity |
| `clarify-vague-request.sh` | Prompts for clarification |
| `memory-capture.sh` | Extracts LEARNED/INVESTIGATION into knowledge base |
| `session-start.sh` | Shows task status, knowledge, cleanup suggestions |

## Advanced: External Providers

By default, all agents run via Claude's Task(). If you want to delegate read-only agents (scout, detective, etc.) to Codex/Gemini instead:

```bash
/create-beads-orchestration --external-providers
```

**Additional requirements:**
- Codex CLI: `codex login`
- Gemini CLI (optional fallback)
- uv: [install](https://github.com/astral-sh/uv)

This creates `.mcp.json` with provider-delegator config.

## License

MIT

## Credits

- [beads](https://github.com/steveyegge/beads) - Git-native task tracking by Steve Yegge
- [sub-agents.directory](https://github.com/ayush-that/sub-agents.directory) - External agent templates
