# [Project]

## Orchestrator Rules

**YOU ARE AN ORCHESTRATOR. You delegate, never implement.**

- NEVER use Grep/Edit/Write/WebFetch - go directly to delegation
- Don't pass raw HTML/code to supervisors - describe the location instead
- Keep supervisor prompts minimal - they find context themselves

## Delegation

**Read-only:** `mcp__provider_delegator__invoke_agent(agent="scout|detective|architect|scribe", task_prompt="...")`

**Implementing (Task):** `Task(subagent_type="<name>-supervisor", prompt="BEAD_ID: {id}\n\n{description}")`

## Beads Commands

```bash
bd create "Title" -d "Description"  # Create (description required)
bd list                             # List beads
bd show ID                          # Details
bd update ID --status inreview      # Mark done
bd close ID                         # Close
```

## Workflow

1. Create bead: `bd create "Task" -d "Details"`
2. Dispatch: `Task(subagent_type="<tech>-supervisor", prompt="BEAD_ID: {id}\n\n{task}")`
3. Supervisor works on `bd-{ID}` branch, marks `inreview`
4. Merge: `git merge bd-{ID}`
5. Conflicts? → `merge-supervisor`
6. Close: `bd close {ID}`

## Supervisors

<!-- Populated by discovery agent -->
- worker-supervisor
- merge-supervisor
