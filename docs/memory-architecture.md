# Memory Architecture

## Overview

Beads orchestration includes a passive knowledge capture system. As agents work, their insights can be voluntarily recorded into a persistent knowledge base that grows across sessions.

## How It Works

```
Agent runs bd comment BD-001 "LEARNED: ..."
       |
       v
PostToolUse hook (memory-capture.cjs) detects LEARNED: prefix
       |
       v
Extracts structured entry into .beads/memory/knowledge.jsonl
       |
       v
Next session: session-start.cjs surfaces recent knowledge
              Agents search when investigating unfamiliar code
```

## Write Path

Agents write knowledge through the existing `bd comment` interface:

| Prefix | Who writes | Purpose |
|--------|-----------|---------|
| `LEARNED:` | Any agent (voluntary) | Conventions, gotchas, patterns discovered during implementation |

Example:
```bash
bd comment BD-001 "LEARNED: TaskGroup requires @Sendable closures in strict concurrency mode."
```

An async `PostToolUse` hook on the Bash tool intercepts these commands and extracts a structured JSONL entry. No changes to the beads CLI are required.

## Storage Format

`.beads/memory/knowledge.jsonl` -- one JSON object per line:

```json
{"key":"learned-taskgroup-requires-sendable-closures","type":"learned","content":"TaskGroup requires @Sendable closures in strict concurrency mode.","source":"supervisor","tags":["learned","async","concurrency"],"ts":1706360000,"bead":"BD-001"}
```

| Field | Description |
|-------|-------------|
| `key` | Auto-generated slug from type + first 60 chars of content |
| `type` | `learned` |
| `content` | The raw insight text |
| `source` | `orchestrator` or `supervisor` (detected from CWD) |
| `tags` | Auto-detected from content via keyword scan |
| `ts` | Unix timestamp |
| `bead` | The bead ID that produced this knowledge |

Same key = latest entry wins (deduplication on read).

## Read Path

### Automatic (session start)

`session-start.cjs` displays the 5 most recent deduplicated entries when a new session begins:

```
## Recent Knowledge (12 entries)

  [LEARN] MenuBarExtra popup closes on NSWindow activate. Use activates:false.  (supervisor)

  Search: .beads/memory/recall.cjs "keyword"
```

### On-demand (recall script)

```bash
.beads/memory/recall.cjs "keyword"                  # Search by keyword
.beads/memory/recall.cjs "keyword" --type learned   # Filter by type
.beads/memory/recall.cjs --recent 10                # Show latest entries
.beads/memory/recall.cjs --stats                    # Entry counts
.beads/memory/recall.cjs "keyword" --all            # Include archived entries
```

## Voluntary Contribution

Knowledge capture is opt-in. Agents are encouraged to log insights when they discover something worth remembering, but it is not enforced. The `SubagentStop` hook verifies worktree state, push status, and bead status — not knowledge contributions.

Exempt: `worker-supervisor` (low-level tasks that don't produce architectural insight).

## Rotation

When `knowledge.jsonl` exceeds 1,000 lines, the oldest 500 are moved to `knowledge.archive.jsonl`. The archive is searchable via `recall.cjs --all`.

## File Layout

```
.beads/
  memory/
    knowledge.jsonl          # Active knowledge store
    knowledge.archive.jsonl  # Rotated older entries
    recall.cjs               # On-demand search script (Node.js)
.claude/
  hooks/
    memory-capture.cjs       # PostToolUse hook (captures entries)
    validate-completion.cjs  # SubagentStop hook (verifies work completion)
    session-start.cjs        # SessionStart hook (surfaces knowledge)
```

## Design Decisions

- **JSONL over SQLite**: Simpler, append-only, human-readable, git-trackable
- **grep + jq over embeddings**: Sufficient for project-scoped knowledge; no external dependencies
- **Passive capture via hooks**: Zero friction -- agents use `bd comment` as they already do
- **Voluntary contribution**: Knowledge base grows organically from genuine insights, not forced boilerplate
- **Same key = latest wins**: No explicit update/close lifecycle; knowledge self-corrects over time
