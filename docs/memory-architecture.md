# Memory Architecture

## Overview

Beads orchestration includes a passive knowledge capture system. As agents work, their insights are automatically extracted into a persistent knowledge base that grows across sessions.

## How It Works

```
Agent runs bd comment BD-001 "LEARNED: ..."
       |
       v
PostToolUse hook (memory-capture.sh) detects LEARNED: or INVESTIGATION: prefix
       |
       v
Extracts structured entry into .beads/memory/knowledge.jsonl
       |
       v
Next session: session-start.sh surfaces recent knowledge
              Orchestrator searches before re-investigating
```

## Write Path

Agents write knowledge through the existing `bd comment` interface with two recognized prefixes:

| Prefix | Who writes | Purpose |
|--------|-----------|---------|
| `INVESTIGATION:` | Orchestrator | Root cause analysis, file:line pointers, fix strategy |
| `LEARNED:` | Supervisors | Conventions, gotchas, patterns discovered during implementation |

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
| `type` | `learned` or `investigation` |
| `content` | The raw insight text |
| `source` | `orchestrator` or `supervisor` (detected from CWD) |
| `tags` | Auto-detected from content via keyword scan |
| `ts` | Unix timestamp |
| `bead` | The bead ID that produced this knowledge |

Same key = latest entry wins (deduplication on read).

## Read Path

### Automatic (session start)

`session-start.sh` displays the 5 most recent deduplicated entries when a new session begins:

```
## Recent Knowledge (12 entries)

  [LEARN] MenuBarExtra popup closes on NSWindow activate. Use activates:false.  (supervisor)
  [INVES] Root cause: SparkleAdapter.swift:45 - nil SUFeedURL crashes XMLParser  (orchestrator)

  Search: .beads/memory/recall.sh "keyword"
```

### On-demand (recall script)

```bash
.beads/memory/recall.sh "keyword"                  # Search by keyword
.beads/memory/recall.sh "keyword" --type learned   # Filter by type
.beads/memory/recall.sh --recent 10                # Show latest entries
.beads/memory/recall.sh --stats                    # Entry counts
.beads/memory/recall.sh "keyword" --all            # Include archived entries
```

## Enforcement

The `SubagentStop` hook (`validate-completion.sh`) blocks supervisors from completing without a `LEARNED:` comment. This ensures every implementation task contributes to the knowledge base.

Exempt: `worker-supervisor` (low-level tasks that don't produce architectural insight).

## Rotation

When `knowledge.jsonl` exceeds 1,000 lines, the oldest 500 are moved to `knowledge.archive.jsonl`. The archive is searchable via `recall.sh --all`.

## File Layout

```
.beads/
  memory/
    knowledge.jsonl          # Active knowledge store
    knowledge.archive.jsonl  # Rotated older entries
    recall.sh                # On-demand search script
.claude/
  hooks/
    memory-capture.sh        # PostToolUse async hook (captures entries)
    validate-completion.sh   # SubagentStop hook (enforces LEARNED:)
    session-start.sh         # SessionStart hook (surfaces knowledge)
```

## Design Decisions

- **JSONL over SQLite**: Simpler, append-only, human-readable, git-trackable
- **grep + jq over embeddings**: Sufficient for project-scoped knowledge; no external dependencies
- **Passive capture via hooks**: Zero friction -- agents use `bd comment` as they already do
- **Hard enforcement**: Supervisors must contribute; knowledge base grows with every task
- **Same key = latest wins**: No explicit update/close lifecycle; knowledge self-corrects over time
