<beads-workflow>
<requirement>You MUST follow this branch-per-task workflow for ALL implementation work.</requirement>

<on-task-start>
1. Receive BEAD_ID from orchestrator (format: `BD-XXX`)
2. Create branch: `git checkout -b bd-{BEAD_ID}`
3. Verify branch: `git branch --show-current`
</on-task-start>

<during-implementation>
1. Implement the task using your specialty knowledge
2. Commit frequently with descriptive messages
3. Log progress: `bd comment {BEAD_ID} "Completed X, working on Y"`
</during-implementation>

<on-completion>
1. Run tests - verify your changes work
2. Final commit - include all changes
3. **REQUEST CODE REVIEW** (mandatory before completion):
   Use the MCP tool directly (NOT via Bash - this is a Claude tool, not a shell command):
   ```
   Tool: mcp__provider_delegator__invoke_agent
   Parameters:
     agent: "code-reviewer"
     task_prompt: "Review BEAD_ID: {BEAD_ID}\nBranch: bd-{BEAD_ID}"
   ```
4. If APPROVED: code-reviewer adds comment automatically, proceed to step 6
5. If NOT APPROVED: Fix issues and repeat from step 1
6. Mark ready: `bd update {BEAD_ID} --status inreview`
7. Return to orchestrator with completion summary
</on-completion>

<code-review-loop>
You MUST get code review approval before completing:
- ALWAYS use agent="code-reviewer" - NO OTHER AGENT (not detective, not scout, not architect)
- Code review is required even if you made no code changes (reviewer verifies the task is complete)
- Call code-reviewer using the mcp__provider_delegator__invoke_agent TOOL (not Bash!)
- If not approved, fix ALL issues raised
- Loop until "CODE REVIEW: APPROVED"
- The code-reviewer adds the APPROVED comment (not you)
- SubagentStop hook will block if no APPROVED comment exists
</code-review-loop>

<branch-rules>
- Always use: `bd-{BEAD_ID}` (e.g., `bd-BD-001`)
- Never work directly on `main`
- One branch per task
</branch-rules>

<completion-report>
CRITICAL: Keep completion report under 10 lines total. Verbose responses waste orchestrator context.

```
BEAD {BEAD_ID} COMPLETE
Branch: bd-{BEAD_ID}
Files: [filename1, filename2]
Tests: pass
Summary: [1 sentence max]
```

BAD (too verbose):
- Listing implementation details
- Explaining technical decisions
- Describing what each file does
- Multiple paragraphs

GOOD (concise):
- Just the facts
- File names only, no paths
- 1 sentence summary
</completion-report>

<if-blocked>
- Log blocker: `bd comment {BEAD_ID} "BLOCKED: [reason]"`
- Return to orchestrator immediately
- Do NOT attempt workarounds without approval
</if-blocked>

<banned>
- Working directly on main branch
- Skipping beads status updates
- Implementing without BEAD_ID
- Merging your own branch
- Completing without code review approval
- Adding APPROVED comment without actual review
- Using detective/scout/architect for code review (ONLY code-reviewer)
</banned>
</beads-workflow>
