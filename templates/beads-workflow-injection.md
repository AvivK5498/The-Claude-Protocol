<beads-workflow>
<requirement>You MUST follow this branch-per-task workflow for ALL implementation work.</requirement>

<on-task-start>
1. **Parse task parameters from orchestrator:**
   - BEAD_ID: Your task ID (e.g., BD-001 for standalone, BD-001.2 for epic child)
   - EPIC_BRANCH: (epic children only) The shared branch (e.g., bd-BD-001)
   - EPIC_ID: (epic children only) The parent epic ID (e.g., BD-001)

2. **Mark in progress:**
   bd update {BEAD_ID} --status in_progress

3. **Checkout branch:**
   - Epic child: `git checkout {EPIC_BRANCH}` (shared branch)
   - Standalone: `git checkout -b bd-{BEAD_ID}` (new branch)

4. **Pull latest (epic children only):**
   git pull origin {EPIC_BRANCH} 2>/dev/null || true

5. **INVOKE DISCIPLINE SKILL** (mandatory):
   Skill(skill: "subagents-discipline")

6. **READ DESIGN DOC** (epic children with design path):
   design_path=$(bd show {EPIC_ID} --json | jq -r '.[0].design // empty')
   If design_path exists and file exists: Read and incorporate into implementation.
   Your implementation MUST match the design doc specifications.
</on-task-start>

<during-implementation>
1. Follow subagents-discipline phases (0-4)
2. Document verification in .verification_logs/{BEAD_ID}.md
3. Commit frequently with descriptive messages
4. Log progress: `bd comment {BEAD_ID} "Completed X, working on Y"`
</during-implementation>

<on-completion>
**For EPIC CHILDREN (BEAD_ID contains dot):**
1. Run fresh verification, capture evidence
2. Final commit to epic branch
3. Add verification comment: `bd comment {BEAD_ID} "VERIFICATION: [evidence]"`
4. Mark done: `bd update {BEAD_ID} --status done`
5. Return completion summary to orchestrator
   (Code review happens at EPIC level after ALL children complete)

**For STANDALONE TASKS (no dot in BEAD_ID):**
1. Run fresh verification, capture evidence
2. Final commit
3. Add verification comment: `bd comment {BEAD_ID} "VERIFICATION: [evidence]"`
4. **REQUEST CODE REVIEW** (mandatory):
   ```
   Tool: mcp__provider_delegator__invoke_agent
   Parameters:
     agent: "code-reviewer"
     task_prompt: "Review BEAD_ID: {BEAD_ID}\nBranch: bd-{BEAD_ID}"
   ```
5. If APPROVED → proceed. If NOT APPROVED → fix and repeat.
6. Mark ready: `bd update {BEAD_ID} --status inreview`
7. Return completion summary to orchestrator
</on-completion>

<banned>
- Working directly on main branch
- Implementing without BEAD_ID
- Merging your own branch
- Epic children creating their own branch (must use EPIC_BRANCH)
- Standalone tasks skipping code review
- Ignoring design doc specifications
</banned>
</beads-workflow>
