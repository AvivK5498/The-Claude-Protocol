# Beads Workflow

## Beads = single source of truth. Nothing lives only in your head.

Context gets compacted. Sessions restart. Beads persist.

### When to create a bead — ALWAYS if:
- User asks to implement, fix, refactor, or change anything
- You discover a bug, tech debt, or improvement during work
- A task needs follow-up that won't happen right now
- You start investigating something non-trivial

### After planning — size check then create beads:
When a plan is finalized and user confirms, BEFORE implementation:

**Step 1: Size check (one sentence decision):**
- >3 files OR >1 domain (DB + API, backend + frontend) → epic with children
- Description has "and then", "after that", multiple steps → multiple beads
- >50 lines estimated → consider splitting
- Otherwise → single bead

Rule of thumb: 1 bead = 1 PR = 1 reviewable diff.

**Step 2: Create beads:**
- Single task: `bd create "Task" -d "..."`
- Epic: `bd create "Feature" -d "..." --type epic`, then children with `--parent` and `--deps`
- Verify: `bd list` — the plan now lives in beads, not just in context

**Step 3: Only then start work** with `bd ready` → dispatch

### When NOT to create a bead:
- Quick fix approved by user (<10 lines, feature branch)
- Pure research/discussion with no code changes planned

### Status discipline:
- Created → `open` (default)
- Starting work → `bd update {ID} --status in_progress`
- Submitted for review → `bd update {ID} --status inreview`
- Merged/done → `bd close {ID}`
- **Epic status:** When starting work on the first child → `bd update {EPIC_ID} --status in_progress`. Epic stays `in_progress` until all children are done.
- **Never leave a bead in `in_progress` across sessions without reason**

### Discovered during work:
When you find tech debt, bugs, or improvements while working on something else:
```bash
bd create "Fix: [what]" -d "Discovered while working on {CURRENT_BEAD}: [details]"
```
Don't try to fix it now (unless trivial). Create the bead so it's not forgotten.

## Task Start

1. Parse BEAD_ID from dispatch prompt
2. Create worktree:
   ```bash
   REPO_ROOT=$(git rev-parse --show-toplevel)
   WORKTREE_PATH="$REPO_ROOT/.worktrees/bd-{BEAD_ID}"
   mkdir -p "$REPO_ROOT/.worktrees"
   [[ ! -d "$WORKTREE_PATH" ]] && git worktree add "$WORKTREE_PATH" -b bd-{BEAD_ID}
   cd "$WORKTREE_PATH"
   ```
3. Mark in progress: `bd update {BEAD_ID} --status in_progress`
4. If this is a child of an epic — check epic status. If epic is still `open`, mark it too: `bd update {EPIC_ID} --status in_progress`
5. Read bead context: `bd show {BEAD_ID}` and `bd comments {BEAD_ID}`

## During Implementation

- Work ONLY in your worktree: `.worktrees/bd-{BEAD_ID}/`
- Commit frequently with descriptive messages
- Log progress: `bd comments add {BEAD_ID} "Completed X, working on Y"`

## Task Completion

Execute ALL steps in order:

1. **Self-verify against requirements:**
   - Run `bd show {BEAD_ID}` — re-read the description
   - Check every item/requirement from the description
   - If anything is missing — implement it now, don't skip
2. `git add -A && git commit -m "..."`
3. `git push origin bd-{BEAD_ID}`
4. Log what you learned (MUST be specific and actionable, not vague):
   `bd comments add {BEAD_ID} "LEARNED: [specific problem] → [specific solution]. [context why]"`
   BAD: "LEARNED: fixed async issue" — useless for future search
   GOOD: "LEARNED: pg connection pool exhaustion under load → set max=20 and idle_timeout=30s. Default max=10 caused 503s at >50 rps"
5. Leave completion comment: `bd comments add {BEAD_ID} "Completed: [summary]"`
6. Mark status: `bd update {BEAD_ID} --status inreview`
7. Return completion report (checklist is MANDATORY — hook will block without it):
   ```
   BEAD {BEAD_ID} COMPLETE
   Worktree: .worktrees/bd-{BEAD_ID}
   Checklist:
   - [x] requirement 1 from description
   - [x] requirement 2 from description
   Files: [names only]
   Tests: pass
   Summary: [1 sentence]
   ```

## bd command reference (use ONLY these — do NOT invent commands)

| Action | Command |
|--------|---------|
| Create | `bd create --title="..." -d "..." [--type task\|bug\|feature\|epic] [--parent ID]` |
| List | `bd list [--status open\|in_progress\|inreview\|done] [--json]` |
| Show | `bd show {ID} [--json]` |
| Update | `bd update {ID} --status in_progress\|inreview [--title\|--description\|--notes]` |
| Close | `bd close {ID} [--reason "..."]` |
| Comments | `bd comments {ID}` / `bd comments add {ID} "text"` |
| Dependencies | `bd dep add {ID} {BLOCKS_ID}` |
| Ready | `bd ready` (unblocked open beads) |
| Blocked | `bd blocked` |
| Search | `bd search "query"` |
| Status | `bd status` (overview/statistics) |
| Prime | `bd prime` (AI context recovery) |

All commands support `--json` for structured output. There is NO `export`, `import`, or `stats` command.

## Banned

- Working directly on main branch
- Implementing without BEAD_ID
- Merging your own branch (user merges via PR)
- Editing files outside your worktree
