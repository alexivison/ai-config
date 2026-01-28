# Sub-Agents

Sub-agents preserve context by offloading investigation/verification tasks.

## debug-investigator
**Use when:** Complex bugs requiring systematic investigation.

**Methodology:** 4-phase debugging (Root Cause → Pattern Analysis → Hypothesis Testing → Specify Fix).

**Writes to:** `~/.claude/investigations/{issue-id}.md`

**Returns:** Brief summary with file path, verdict, hypotheses tested, one-line summary.

## test-runner
**Use when:** Running test suites that produce verbose output.

**Returns:** Brief summary with pass/fail count and failure details only.

**Note:** Uses Haiku. Isolates verbose test output from main context.

## check-runner
**Use when:** Running typechecks or linting.

**Returns:** Brief summary with error/warning counts and issue details only.

**Note:** Uses Haiku. Auto-detects project stack and package manager.

## log-analyzer
**Use when:** Analyzing application/server logs.

**Writes to:** `~/.claude/logs/{identifier}.md`

**Returns:** Brief summary with file path, error/warning counts, timeline.

**Note:** Uses Haiku. Handles JSON, syslog, Apache/Nginx, plain text.

## security-scanner
**Use when:** Before commits/PRs, auditing security posture, or after dependency updates.

**Checks:** Secrets detection, dependency vulnerabilities, OWASP Top 10 patterns, config issues.

**Returns:** Structured findings with severity (CRITICAL/HIGH/MEDIUM/LOW), exact locations, and remediation.

**Note:** Uses Haiku. Runs available tools (npm audit, pip-audit, etc.) and grep patterns.

## code-critic
**Use when:** After writing code, before commit.

**Pattern:** Single-pass review. Main agent controls iteration loop (write → critic → fix → critic → ... → APPROVED).

**Returns:** Verdict (APPROVE | REQUEST_CHANGES | NEEDS_DISCUSSION) with `[must]`/`[q]`/`[nit]` feedback.

**Escalates to user:** Only on NEEDS_DISCUSSION or after 3 failed iterations.

**Note:** Uses Sonnet. Preloads `/code-review` skill. Include iteration number and previous feedback when re-invoking.

## architecture-critic
**Use when:** After code-critic passes, before tests.

**Pattern:** Quick metrics scan first → deep analysis only when thresholds exceeded.

**Returns:** Verdict (SKIP | APPROVE | REQUEST_CHANGES | NEEDS_DISCUSSION) with architectural analysis.

**On REQUEST_CHANGES:** Main agent creates follow-up refactor task, PR proceeds (advisory, not blocking).

**Escalates to user:** Only on NEEDS_DISCUSSION.

**Note:** Uses Opus. Reference guidelines split by type:
- `reference/architecture-guidelines-common.md` (always loaded)
- `reference/architecture-guidelines-frontend.md` (React/TypeScript)
- `reference/architecture-guidelines-backend.md` (Go/Python/Node.js)
