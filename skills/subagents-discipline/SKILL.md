---
name: subagents-discipline
description: Invoke at the start of any implementation task to enforce verification-first development discipline
---

# Subagent Discipline: Verification-First Development

## Quick Reference

```
BEFORE:  List assumptions → Verify each with a command → Document results (see Phase 1)
DURING:  For each operation → List failure modes → Add explicit handling (see Phase 2)
AFTER:   Run code against real infrastructure → Capture output → Verify match (see Phase 3)
DONE:    Run verification command → Read full output → Only then claim complete (see Phase 4)
```

**Core principle:** Assumptions are bugs waiting to happen. Verify them.

**Violating the letter of the rules is violating the spirit of the rules.**

---

## The Iron Laws

```
1. NEVER implement against assumed state - verify first
2. NEVER claim done without fresh verification evidence
3. NEVER proceed with uncertainty - investigate or ask
```

### Machine-Testable Definitions

| Term | Definition | Test |
|------|------------|------|
| **Assumed state** | Any belief about system state not confirmed by command output from THIS session | Can you cite a command + output from THIS session that proves it? No = assumed |
| **Fresh evidence** | Verification command executed AFTER your last code change, in THIS session | Is there verification output AFTER your last edit? No = stale |
| **Uncertainty** | Inability to predict command output with confidence | If asked "what will this command return?", can you answer specifically? No = uncertain |

**No exceptions. No shortcuts. No "just this once."**

### Gate Failure Handling

When a GATE condition cannot be met:

```
RETRY POLICY:
- Transient failures (network timeout, 5xx status, connection refused):
  Retry up to 3 times with 5-second delay between attempts.
- Permanent failures (4xx status, missing data, wrong schema):
  No retry. Escalate immediately.

TIMEOUT POLICY:
- Maximum time per verification command: 30 seconds
- If command hangs: Kill and document as TIMEOUT

ESCALATION PATH:
When gate cannot be passed after retries:

STEP 1: Document the blocker in .verification_logs/{BEAD_ID}.md
        Format: "GATE BLOCKED: [Phase X] - [Gate condition] - [Specific failure] - [Attempts: N]"

STEP 2: ASK human partner with specific question
        Format: "Cannot proceed past [Phase X].
        Blocker: [specific description]
        Tried: [commands attempted]
        Need: [what would unblock - credentials, fix, permission, etc.]"

STEP 3: Wait for human response. Do NOT:
        - Proceed to next phase
        - Claim completion
        - Guess or assume the blocker is resolved
```

---

## Setup: Create Verification Log

**Execute FIRST, before any other phase.**

```
STEP 1: Extract BEAD_ID from your task prompt
        The orchestrator provides: "BEAD_ID: BD-XXX"
        If no BEAD_ID provided: Use "NO-BEAD" as identifier

STEP 2: Create verification log directory and file
        Run: mkdir -p .verification_logs
        Run: touch .verification_logs/{BEAD_ID}.md

        Example: .verification_logs/BD-001.md

        NOTE: This directory is gitignored. Logs are ephemeral working documents.
        Permanent audit trail goes in bead comments (see Phase 4).

STEP 3: Initialize with session header
        Write to file:

        # Verification Log: {BEAD_ID}
        ## Session: [YYYY-MM-DD HH:MM]
        ## Task: [Brief description]

        ### Phase 0: Discovery
        | Variable | Value | Status |
        |----------|-------|--------|

        ### Phase 1: Assumptions
        | # | Assumption | Command | Output | Status |
        |---|------------|---------|--------|--------|

        ### Phase 2: Error Handling
        Search results:

        ### Phase 3: Reality Tests
        | Test | Expected | Actual | Pass/Fail |
        |------|----------|--------|-----------|

        ### Phase 4: Completion Evidence
        Claim:
        Command:
        Output:

STEP 4: Ensure .verification_logs/ is gitignored
        Run: grep -q "^\.verification_logs/" .gitignore 2>/dev/null || echo ".verification_logs/" >> .gitignore

        These logs are ephemeral working documents.
        Permanent audit trail: Add summary to bead via `bd comment` in Phase 4.
```

**All subsequent phases: Document results in .verification_logs/{BEAD_ID}.md as you go.**

---

## Phase 0: DISCOVER - Find Infrastructure

**Execute BEFORE Phase 1. Do not skip.**

### Procedure

```
STEP 1: DISCOVER configuration files
        Run: ls -la .env* config/*.json 2>/dev/null
        Run: cat package.json | grep -A5 '"config"' 2>/dev/null

STEP 2: LOAD environment variables into shell
        Run: set -a && source .env 2>/dev/null && source .env.local 2>/dev/null && set +a

        If .env files not readable (permission denied, not found):
        Run: grep "^DATABASE_URL\|^API" .env .env.local 2>/dev/null

        If still no access: Document "ENV_NOT_ACCESSIBLE" and proceed to STEP 6.

STEP 3: EXTRACT connection strings and URLs
        Run: echo "DATABASE_URL=$DATABASE_URL"
        Run: echo "API_BASE_URL=${API_BASE_URL:-$API_URL}"

        If variables are empty, try reading raw values:
        Run: grep -h "^DATABASE_URL\|^API" .env .env.local 2>/dev/null | head -5

STEP 4: IDENTIFY database type
        Run: echo $DATABASE_URL | grep -oE "^[a-z]+" | head -1
        Result: postgresql, mysql, sqlite, mongodb, etc.
        This determines which client and SQL syntax to use.

STEP 5: VERIFY not production
        Run: echo "$DATABASE_URL $API_BASE_URL" | grep -iE "prod|production|live" && echo "WARNING: Production detected"
        If production detected: STOP. Ask human partner for test environment.

STEP 6: RECORD discovered values
        Document in .verification_logs/{BEAD_ID}.md:
        - DATABASE_URL: [value or "NOT_ACCESSIBLE"]
        - API_BASE_URL: [value or "NOT_ACCESSIBLE"]
        - AUTH_TOKEN: [available/NOT_ACCESSIBLE]
        - DB_TYPE: [postgresql/mysql/etc. or "unknown"]

STEP 7: HANDLE inaccessible credentials
        If any critical value is NOT_ACCESSIBLE:

        ASK human partner:
        "I need [CREDENTIAL_NAME] to verify [what assumption].
        Options:
        (A) Provide the value
        (B) Run this command and paste output: [verification command]
        (C) Skip verification - accept risk and document as UNVERIFIED"

        Record human's choice in .verification_logs/{BEAD_ID}.md.
```

### Design Doc Discovery (Epic Children)

If your BEAD_ID contains a dot (e.g., BD-001.2), you are a child task of an epic. Check for design doc:

```
STEP 1: EXTRACT epic ID
        EPIC_ID = everything before the last dot
        Example: BD-001.2 → EPIC_ID = BD-001

STEP 2: CHECK for design doc
        Run: design_path=$(bd show {EPIC_ID} --json | jq -r '.[0].design // empty')
        Run: echo "Design path: $design_path"

STEP 3: If design doc exists, READ it
        Run: [[ -n "$design_path" && -f "$design_path" ]] && cat "$design_path"

STEP 4: EXTRACT specifications from design doc
        Document in verification log:
        - Schema: [exact column names, types from design]
        - API contracts: [endpoints, request/response shapes]
        - Shared constants: [any enums or constants defined]

STEP 5: Your implementation MUST match design doc
        - Use EXACT column names from design (not variations)
        - Use EXACT API shapes from design
        - Use EXACT constant values from design

        If design says: column "reference_image_url" VARCHAR(255)
        You MUST use: reference_image_url (not reference_images, not image_url)
```

**Why this matters:** Design docs exist to ensure consistency across epic children. DB supervisor creates schema matching design. API supervisor creates endpoints matching design. Frontend supervisor consumes API matching design. If any layer deviates, the integration fails.

### Infrastructure Discovery Checklist

Before proceeding to Phase 1, you must know:

- [ ] Database connection string (or confirmed no database, or documented as UNVERIFIED)
- [ ] API base URL (or confirmed no external API, or documented as UNVERIFIED)
- [ ] Authentication method (token, API key, none, or documented as UNVERIFIED)
- [ ] Environment confirmed as non-production (or human accepted risk)
- [ ] Design doc read and specifications extracted (epic children only)

---

## Phase 1: BEFORE - Verify Assumptions

### Procedure (Execute These Steps)

```
STEP 1: LIST all assumptions
        Create a numbered list of everything you believe to be true:
        - What exists? (tables, columns, APIs, files, configs)
        - What types/formats? (string vs int, nullable vs required)
        - What state? (data present, service running)

STEP 2: For EACH assumption, IDENTIFY verification command
        Use the Assumption → Command table below.
        Replace ALL placeholders with values from Phase 0.

STEP 3: RUN each verification command
        Execute the command. Capture the output.

STEP 4: COMPARE output to assumption
        Does the output confirm or contradict your assumption?
        - If CONFIRMED: Mark assumption as verified, proceed
        - If CONTRADICTED: STOP. Fix the discrepancy before implementing
        - If UNCLEAR: Investigate further or ask human partner

STEP 5: Document results
        Record: Assumption → Command → Result → Status (verified/failed)

GATE: Do not write implementation code until ALL assumptions are verified.
```

### Assumption → Command Mapping

| Assumption Type | Verification Command |
|-----------------|---------------------|
| Table exists | `SELECT table_name FROM information_schema.tables WHERE table_name = '{TABLE}';` |
| Column exists | `SELECT column_name, data_type FROM information_schema.columns WHERE table_name = '{TABLE}';` |
| Column type | `SELECT data_type FROM information_schema.columns WHERE table_name = '{TABLE}' AND column_name = '{COLUMN}';` |
| Column nullable | `SELECT is_nullable FROM information_schema.columns WHERE table_name = '{TABLE}' AND column_name = '{COLUMN}';` |
| API endpoint exists | `curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $AUTH_TOKEN" "$API_BASE_URL/{endpoint}"` |
| API response shape | `curl -s -H "Authorization: Bearer $AUTH_TOKEN" "$API_BASE_URL/{endpoint}" \| jq 'keys'` |
| Config value set | `grep '{CONFIG_KEY}' .env .env.local 2>/dev/null \|\| echo "NOT FOUND"` |
| File exists | `ls -la {filepath} 2>/dev/null \|\| echo "NOT FOUND"` |
| Dependency available | `npm list {package} 2>/dev/null \|\| pip show {package} 2>/dev/null \|\| echo "NOT FOUND"` |
| Service running | `curl -s -o /dev/null -w "%{http_code}" "$API_BASE_URL/health" \|\| echo "NOT REACHABLE"` |

**IMPORTANT:** Replace `{TABLE}`, `{COLUMN}`, `{endpoint}`, `$API_BASE_URL`, `$AUTH_TOKEN` with actual values from Phase 0.

### Interface Verification (MANDATORY before coding)

**NEVER write code against an assumed interface. ALWAYS inspect actual format first.**

This catches bugs like:
- Assuming JWT arrives raw when it's actually `Bearer <token>`
- Assuming column `reference_images` exists when it's `reference_image_url`
- Assuming API returns `{data: [...]}` when it returns `[...]` directly

| Interface | Inspection Command | What to Check |
|-----------|-------------------|---------------|
| **Database schema** | `\d tablename` or `SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'X';` | Exact column names, types, nullability |
| **HTTP request headers** | Log/print `request.headers` before parsing | Auth format (Bearer? Basic?), content-type |
| **HTTP request body** | Log/print `request.body` before parsing | Actual JSON structure, field names |
| **API response** | `curl ... \| jq .` raw output before deserializing | Actual structure, not assumed |
| **File/config** | `cat` or `head` before parsing | Actual format, encoding, field names |
| **Environment variable** | `echo $VAR_NAME` before using | Actual value, not assumed |

```
PROCEDURE:

STEP 1: IDENTIFY external interfaces your code will touch
        List: database tables, API endpoints, files, env vars

STEP 2: For EACH interface, INSPECT actual format
        Run the appropriate command from table above
        Capture output in verification log

STEP 3: WRITE code that matches OBSERVED format
        Not documented format. Not assumed format. OBSERVED.

STEP 4: If interface is inaccessible
        ASK human partner to run inspection command
        Do NOT guess and proceed
```

**Example failure this prevents:**

```
Task: Decode JWT from Authorization header

WITHOUT interface verification:
  Agent assumes: header contains raw JWT
  Agent writes:  jwt.decode(auth_header)
  Reality:       header is "Bearer eyJhbG..."
  Result:        Decode fails

WITH interface verification:
  Agent runs:    print(request.headers.get('Authorization'))
  Agent sees:    "Bearer eyJhbG..."
  Agent writes:  jwt.decode(auth_header.replace("Bearer ", ""))
  Result:        Works
```

### Database Query Execution

SQL commands above are queries only. To execute them, use the appropriate client based on DB_TYPE from Phase 0:

| DB_TYPE | Execution Command |
|---------|-------------------|
| postgresql | `psql "$DATABASE_URL" -c "YOUR_SQL_HERE"` |
| mysql | `mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASS $DB_NAME -e "YOUR_SQL_HERE"` |
| sqlite | `sqlite3 "$DATABASE_PATH" "YOUR_SQL_HERE"` |

**If DATABASE_URL not accessible:**

```
ASK human partner:
"I need to verify [assumption] against the database.
Please run this command and paste the output:

  psql $DATABASE_URL -c \"SELECT column_name FROM information_schema.columns WHERE table_name = 'users';\"

Or provide database connection details so I can run it."
```

**If database client not available:**
Run: `which psql mysql sqlite3 2>/dev/null`
If none found: ASK human partner to run query or install client.

### Example: Correct Execution

```
Task: Add user preferences feature

PHASE 0 - Discovery completed:
  DATABASE_URL: postgresql://localhost:5432/myapp_dev
  API_BASE_URL: http://localhost:3000/api
  AUTH_TOKEN: not required (local dev)

STEP 1 - Assumptions listed:
  1. users table exists
  2. users table has preferences column
  3. preferences column is JSONB type
  4. /api/users/:id endpoint returns user object

STEP 2 - Commands identified (with actual values):
  1. SELECT table_name FROM information_schema.tables WHERE table_name = 'users';
  2. SELECT column_name FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'preferences';
  3. SELECT data_type FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'preferences';
  4. curl -s http://localhost:3000/api/users/1 | jq 'keys'

STEP 3 & 4 - Execution and comparison:
  1. ✓ Returned: users (table exists)
  2. ✗ Returned: 0 rows (column does NOT exist) ← STOP
  3. (blocked by #2)
  4. ✓ Returned: ["id", "name", "email"] (endpoint works)

STEP 5 - Documentation:
  "Verified: users table exists, API endpoint works.
   BLOCKED: preferences column missing. Need migration before implementing."

GATE: Cannot proceed. Must create migration first.
```

---

## Phase 2: DURING - Handle Failure Modes

### Procedure (Execute These Steps)

```
STEP 1: For EACH operation in your code, LIST failure modes:
        - What if input is null/empty/invalid?
        - What if external call fails/times out?
        - What if data doesn't exist?
        - What if response shape is unexpected?

STEP 2: For EACH failure mode, ADD explicit handling:
        - Validate inputs at function entry
        - Check response status before using data
        - Throw descriptive errors (not silent returns)

STEP 3: DISCOVER source directory
        Run: ls -d src lib app components 2>/dev/null | head -1
        Result: SOURCE_DIR=[discovered directory]

        If no standard directory found:
        Run: find . -maxdepth 3 -name "*.ts" -o -name "*.js" -o -name "*.py" 2>/dev/null | head -1 | xargs dirname
        Result: SOURCE_DIR=[discovered directory]

        If still not found: ASK human partner for source directory location.

STEP 4: VERIFY no silent failures exist
        Replace [SOURCE_DIR] with discovered directory in these commands:

        # Find bare returns after conditionals (silent failures)
        grep -rn "if.*return;$" --include="*.ts" --include="*.js" --include="*.py" [SOURCE_DIR]/

        # Find ignored error variables (JS/TS pattern)
        grep -rn "{ data, error }.*=" --include="*.ts" --include="*.js" [SOURCE_DIR]/ | grep -v "if.*error"

        # Find swallowed exceptions
        grep -rn "catch.*{\|except.*:" --include="*.ts" --include="*.js" --include="*.py" [SOURCE_DIR]/ | grep -v "throw\|raise\|console\|log"

        # Find destructuring without error check (JS/TS pattern)
        grep -rn "const { data }" --include="*.ts" --include="*.js" [SOURCE_DIR]/

        If ANY command returns results: INVESTIGATE each match. Fix or justify.

GATE: Every operation must have explicit error handling. All search commands return 0 unjustified matches.
```

### Failure Mode Checklist (Apply to Each Operation)

| Operation Type | Failure Modes to Handle |
|---------------|------------------------|
| **Function input** | null, undefined, empty string, wrong type, out of range |
| **HTTP request** | Network error, timeout, 4xx status, 5xx status, malformed response |
| **Database query** | Connection error, query error, no rows returned, wrong types |
| **File operation** | File not found, permission denied, file locked, disk full |
| **JSON parsing** | Invalid JSON, missing expected fields, wrong field types |

### Error Handling Pattern (Language-Agnostic)

Every operation that can fail MUST follow this 5-step pattern. Implement in whatever language you're using:

```
STEP 1: VALIDATE
        Check input exists and has expected type.
        If invalid: Throw/raise with descriptive message.

STEP 2: CAPTURE
        Store BOTH success result AND error from operation.
        Never discard error information.

STEP 3: CHECK
        Examine error BEFORE using success value.
        Error takes priority - never use result if error exists.

STEP 4: FAIL LOUD
        Throw/raise with descriptive message including:
        - Function name
        - What failed
        - Input values (for debugging)

STEP 5: RETURN
        Only return validated data after all checks pass.
```

**If uncertain how to implement this pattern in a specific language: ASK human partner.**

### Forbidden Patterns (Search and Eliminate)

```
❌ FORBIDDEN: Silent failure - returns nothing on error
   Pattern: function ends with bare return (no value) after conditional

❌ FORBIDDEN: Swallowed exception - error disappears
   Pattern: catch/except block that doesn't throw/raise/log

❌ FORBIDDEN: Ignored error - error variable never checked
   Pattern: destructuring/unpacking result and error, but only using result

❌ FORBIDDEN: Bare return on failure - caller doesn't know why
   Pattern: if (condition) return;  with no error information
```

---

## Phase 3: AFTER - Test Against Reality

### Procedure (Execute These Steps)

```
STEP 1: IDENTIFY what must be tested
        List every behavior your code implements:
        - Happy path (normal operation)
        - Error paths (expected failures)
        - Edge cases (boundary conditions)

STEP 2: For EACH behavior, WRITE the test command
        Use actual values from Phase 0 (API_BASE_URL, AUTH_TOKEN, etc.)
        The command must hit REAL infrastructure, not mocks.

STEP 3: RUN each test command
        Execute against real database/API/service.
        Capture: stdout, stderr, exit code, HTTP status.

STEP 4: VERIFY output matches expected
        For each test:
        - What output did you expect?
        - What output did you get?
        - Do they match exactly?

STEP 5: Document results
        Record: Test → Command → Expected → Actual → Pass/Fail

GATE: All tests must pass against real infrastructure before claiming complete.
```

### Test Command Templates

| What to Test | Command Pattern |
|--------------|-----------------|
| **Record created** | `curl -X POST "$API_BASE_URL/resource" -H "Content-Type: application/json" -H "Authorization: Bearer $AUTH_TOKEN" -d '{"field":"value"}' -w "\n%{http_code}"` |
| **Record retrieved** | `curl -s "$API_BASE_URL/resource/{id}" -H "Authorization: Bearer $AUTH_TOKEN" \| jq .` |
| **Record updated** | `curl -X PATCH "$API_BASE_URL/resource/{id}" -H "Content-Type: application/json" -H "Authorization: Bearer $AUTH_TOKEN" -d '{"field":"newvalue"}' -w "\n%{http_code}"` |
| **Record deleted** | `curl -X DELETE "$API_BASE_URL/resource/{id}" -H "Authorization: Bearer $AUTH_TOKEN" -w "\n%{http_code}"` |
| **Error handling** | `curl -s "$API_BASE_URL/resource/nonexistent" -H "Authorization: Bearer $AUTH_TOKEN" -w "\n%{http_code}"` (expect 404) |
| **Constraint enforced** | Attempt duplicate/invalid, verify rejection with appropriate status code |
| **Data persists** | After create/update, query database directly: `SELECT * FROM table WHERE id = 'X';` |

### Destructive Command Safety

```
BEFORE running DELETE, DROP, or TRUNCATE verifications:

STEP 1: Confirm test environment
        Run: echo $DATABASE_URL | grep -i "prod" && echo "ABORT: Production"

STEP 2: Use SELECT first
        Before: DELETE FROM users WHERE id = 123;
        First:  SELECT * FROM users WHERE id = 123;  -- Verify what will be deleted

STEP 3: For irreversible operations, use transactions
        BEGIN;
        DELETE FROM users WHERE id = 123;
        SELECT * FROM users WHERE id = 123;  -- Verify deletion
        ROLLBACK;  -- Undo for safety, or COMMIT if intentional
```

### Example: Correct Execution

```
STEP 1 - Behaviors to test:
  1. Create user - should insert record
  2. Create duplicate - should reject with 409
  3. Get user - should return record
  4. Get missing user - should return 404
  5. Update user - should persist change

STEP 2 - Test commands (with actual values from Phase 0):
  1. curl -X POST "http://localhost:3000/api/users" -H "Content-Type: application/json" -d '{"email":"test@example.com"}' -w "\n%{http_code}"
  2. curl -X POST "http://localhost:3000/api/users" -H "Content-Type: application/json" -d '{"email":"test@example.com"}' -w "\n%{http_code}"
  3. curl -s "http://localhost:3000/api/users/1" | jq .
  4. curl -s "http://localhost:3000/api/users/99999" -w "\n%{http_code}"
  5. curl -X PATCH "http://localhost:3000/api/users/1" -H "Content-Type: application/json" -d '{"name":"Updated"}' -w "\n%{http_code}"

STEP 3 & 4 - Execution and verification:
  1. Expected: 201 + {"id":...}    Actual: 201 + {"id":1}         ✓ PASS
  2. Expected: 409 + error         Actual: 409 + "Email exists"   ✓ PASS
  3. Expected: 200 + user object   Actual: {"id":1,"email":...}   ✓ PASS
  4. Expected: 404                 Actual: 404 + "Not found"      ✓ PASS
  5. Expected: 200 + updated       Actual: 200 + {"name":"Updated"} ✓ PASS

STEP 5 - Documentation:
  "Reality tested: All 5 behaviors verified against http://localhost:3000.
   Happy path works. Error handling works. Constraints enforced."

GATE: All tests passed. Can proceed to completion.
```

---

## Phase 4: COMPLETION - Claim Verification

### The Gate Function (MANDATORY)

```
BEFORE claiming "done", "complete", "fixed", "working", or ANY success:

STEP 1: IDENTIFY the claim you want to make
        "Tests pass" / "Feature complete" / "Bug fixed" / etc.

STEP 2: IDENTIFY the command that PROVES this claim
        What single command demonstrates the claim is true?

STEP 3: RUN the command NOW (fresh, in this session)
        Not "I ran it earlier." Run it NOW.

        SAFETY CHECK for destructive commands:
        - If command modifies data: Ensure test environment
        - If command is DELETE/DROP: Use SELECT first to preview

STEP 4: READ the FULL output
        - Check exit code: echo $?
        - Count any failures/errors
        - Read actual messages, not just "success"

STEP 5: COMPARE output to claim
        Does the output PROVE the claim?
        - If YES: State claim WITH the evidence
        - If NO: State actual status with evidence

STEP 6: ONLY NOW make the claim
        Include the evidence in your statement.

SKIP ANY STEP = LYING, NOT VERIFYING
```

### Claim → Evidence Requirements

| Claim | Required Evidence | NOT Sufficient |
|-------|-------------------|----------------|
| "Tests pass" | Test command output showing 0 failures | "Should pass", previous run, partial run |
| "Build succeeds" | Build command with exit code 0 | Linter passing, "no errors visible" |
| "Feature complete" | Each requirement demonstrated working | "Code looks complete" |
| "Bug fixed" | Reproduction steps now produce correct behavior | "Changed the code" |
| "API works" | Actual HTTP request with expected response | "Endpoint exists" |
| "Data persists" | Query showing data exists after operation | "Insert succeeded" |

### Regression Test Verification (For Bug Fixes)

```
STEP 1: Write test that reproduces the bug

STEP 2: Run test → MUST FAIL (proves test catches the bug)
        If test passes: Test is wrong. Fix the test first.

STEP 3: Implement fix

STEP 4: Run test → MUST PASS (proves fix works)
        If test fails: Fix is wrong. Fix the code.

STEP 5: Revert fix temporarily using SAFE REVERT:
        $ git stash push -m "regression-test-$(date +%s)"
        $ git checkout HEAD -- path/to/fixed/file.ts

STEP 6: Run test → MUST FAIL (proves test still catches bug)
        If test passes: Test is wrong. It doesn't actually catch the bug.

STEP 7: Restore fix:
        $ git stash pop

STEP 8: Run test → MUST PASS (confirms fix is back)

FOR IRREVERSIBLE CHANGES (database migrations, etc.):
  Skip steps 5-7. Document: "Revert test skipped: migration cannot be reverted"
```

### Forbidden Completion Phrases (Without Evidence)

These phrases are LIES without fresh verification output:
- "Done!"
- "Fixed!"
- "Should work now"
- "That should do it"
- "All set"
- "Tests pass"
- "Everything works"
- "Ready for review"

**Only say these AFTER running verification and INCLUDING the evidence.**

### Example: Correct Completion

```
WRONG:
  "I've implemented the user CRUD operations. Should work now!"
  (No evidence. This is a guess, not a claim.)

RIGHT:
  "Implemented user CRUD. Verification results:

   $ npm test -- --grep 'user'
   ✓ creates user (52ms)
   ✓ rejects duplicate email (23ms)
   ✓ retrieves user by id (18ms)
   ✓ returns 404 for missing user (12ms)
   ✓ updates user (31ms)
   5 passing (136ms)
   $ echo $?
   0

   $ curl -X POST http://localhost:3000/api/users -H "Content-Type: application/json" -d '{"email":"verify@test.com"}'
   {"id": 5, "email": "verify@test.com", "created_at": "2024-01-15T10:30:00Z"}

   All 5 tests pass (exit code 0). API verified against running server."
```

---

## Documentation Requirements

### Bead CLI Reference

The `bd` command is the beads CLI for task tracking. Commands used in this workflow:

```bash
bd comment BD-XXX "message"   # Add comment to bead
bd show BD-XXX                # Show bead details
bd update BD-XXX --status X   # Update bead status
```

### Bead Verification Comment (Required Format)

Before marking bead complete, add comment with this EXACT structure:

```bash
bd comment BD-XXX "VERIFICATION:
Assumptions verified: [list what you checked before implementing]
Reality tested: [list what you tested against real infrastructure]
Evidence: [key outputs proving it works]
Remaining risks: [what you did NOT verify, potential issues]"
```

### Example

```bash
bd comment BD-042 "VERIFICATION:
Assumptions verified: users table exists (queried information_schema), email column is VARCHAR(255) (confirmed), unique constraint on email (confirmed)
Reality tested: CREATE user (201), duplicate rejection (409), GET user (200), GET missing (404), UPDATE user (200)
Evidence: All 5 curl commands returned expected status codes against localhost:3000, verified data in DB directly
Remaining risks: Not tested under concurrent load, not tested with special characters in email"
```

---

## Red Flags - STOP Immediately

When you notice yourself:

**Thinking vague thoughts:**
- "I assume..."
- "This should..."
- "Probably..."
- "I think..."
- "Should be fine..."

**Expressing premature success:**
- "Done!"
- "Fixed!"
- "That should work"
- "Perfect!"
- "Great!"

**Rationalizing:**
- "I'll verify later"
- "This is too simple to break"
- "Docs say it exists"
- "It worked in another project"

**ACTION: STOP. Return to the relevant Phase procedure. Execute it. Then continue.**

---

## Common Rationalizations (All Require Verification)

| Excuse | Required Action |
|--------|-----------------|
| "Docs say it exists" | Run: `SELECT ... FROM information_schema` or `curl` to prove existence |
| "Schema file shows the type" | Run: `SELECT data_type FROM information_schema.columns WHERE ...` |
| "Unit tests pass" | Run: Test against real infrastructure with `curl` or direct DB query |
| "I'm pretty sure" | Run: The specific command that proves your certainty |
| "It worked before" | Run: The test NOW, capture fresh output |
| "Too simple to verify" | Run: 30-second verification command anyway |
| "Orchestrator is waiting" | Run: Verification anyway (correct code > fast broken code) |

---

## Verification Checklist

Execute each phase. Check each box only when the procedure is COMPLETE with evidence.

**Proving Compliance:** After completing your work, run these commands to verify checklist completion:

```bash
# Verify PHASE 0 completed - look for discovery output
grep -c "DATABASE_URL\|API_BASE_URL\|AUTH_TOKEN" .verification_logs/{BEAD_ID}.md  # Should be > 0

# Verify BEFORE phase - assumptions were listed and checked
grep -c "Assumption:" .verification_logs/{BEAD_ID}.md    # Count of assumptions
grep -c "Command:" .verification_logs/{BEAD_ID}.md       # Must match assumption count
grep "Status: FAILED" .verification_logs/{BEAD_ID}.md    # Should return 0 results

# Verify DURING phase - forbidden patterns were searched
grep -c "grep.*silent\|grep.*swallowed\|grep.*ignored" .verification_logs/{BEAD_ID}.md  # > 0

# Verify AFTER phase - tests were run
grep -c "curl\|npm test\|pytest" .verification_logs/{BEAD_ID}.md  # > 0
grep -c "Expected:.*Actual:" .verification_logs/{BEAD_ID}.md      # > 0

# Verify COMPLETION - evidence was captured
grep -c "exit code\|http_code\|status" .verification_logs/{BEAD_ID}.md  # > 0
```

**No .verification_logs/{BEAD_ID}.md?** Create one. Document as you go, not after.

---

**PHASE 0 - Discovery:**
- [ ] Ran discovery commands for config files
- [ ] Extracted DATABASE_URL, API_BASE_URL, AUTH_TOKEN (or confirmed not needed)
- [ ] Verified NOT production environment
- [ ] Documented discovered values

**BEFORE Phase:**
- [ ] Listed ALL assumptions (numbered)
- [ ] Identified verification command for EACH assumption (with actual values, no placeholders)
- [ ] Ran EACH verification command
- [ ] Documented results (assumption → command → output → status)
- [ ] Zero contradicted assumptions remain

**DURING Phase:**
- [ ] Listed failure modes for EACH operation
- [ ] Added explicit error handling for EACH failure mode
- [ ] Ran forbidden pattern search commands
- [ ] Zero unjustified matches from search commands

**AFTER Phase:**
- [ ] Listed ALL behaviors to test
- [ ] Wrote test commands with actual URLs/credentials (no placeholders)
- [ ] Ran tests against REAL infrastructure
- [ ] Captured and compared outputs (expected vs actual)
- [ ] All tests produce expected results

**COMPLETION Phase:**
- [ ] Identified claim to make
- [ ] Ran verification command NOW (fresh, after last code change)
- [ ] Read FULL output including exit code
- [ ] Output proves claim
- [ ] Stated claim WITH evidence (command + output)
- [ ] Added verification comment to bead with required format

**Can't check all boxes? You're not done.**

---

## The Bottom Line

```
Assumption without verification → Bug
Claim without evidence → Lie
Procedure skipped → Failure guaranteed
Placeholder not replaced → Command fails
```

Your human partner would rather wait 3 extra minutes for verified code than spend 30 minutes debugging your assumptions.

**Execute the procedures. Replace the placeholders. Capture the evidence. Then claim done.**
