# Sub-Agents

Sub-agents preserve context by offloading investigation/verification tasks.

## debug-investigator (DEPRECATED)

**Note:** Replaced by codex agent for debugging/investigation tasks. The codex agent provides deeper reasoning via Codex CLI.

**Migration:** Use codex agent with debugging task prompt instead. See `bugfix-workflow` skill for the updated flow.

## test-runner
**Use when:** Running test suites that produce verbose output.

**Returns:** Brief summary with pass/fail count and failure details only.

**Note:** Uses Haiku. Isolates verbose test output from main context.

## check-runner
**Use when:** Running typechecks or linting.

**Returns:** Brief summary with error/warning counts and issue details only.

**Note:** Uses Haiku. Auto-detects project stack and package manager.

## gemini
**Use when:** ALL log analysis tasks (replaces log-analyzer), or research queries requiring web search and synthesis.

**Modes:**
| Mode | Model | Trigger |
|------|-------|---------|
| Log analysis (small) | gemini-2.0-flash | Logs < 400K tokens (~1.6MB) |
| Log analysis (large) | gemini-2.5-pro | Logs >= 400K tokens |
| Web search | gemini-2.0-flash | Research queries with explicit external intent |

**Writes to:** `~/.claude/logs/{identifier}.md` (log analysis) or returns inline (web search)

**Returns:** Structured findings with sources cited.

**Security:** Displays pre-flight warning before sending logs to Gemini API. Checks for sensitive patterns.

**Note:** Uses Haiku (wrapper) + Gemini CLI. 2M token context for massive log files.

## log-analyzer (⛔ DEPRECATED — DO NOT USE)

> **DO NOT USE this agent.** Use `gemini` agent for ALL log analysis.

| Feature | log-analyzer | gemini |
|---------|--------------|--------|
| Context | ~100K tokens | **2M tokens** |
| Compressed logs | No | Yes |
| Smart model selection | No | Yes |

This agent will be removed in a future version.

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

## codex

**Use when:** Deep reasoning tasks — code review, architecture analysis, plan review, design decisions, debugging, trade-off evaluation.

**Pattern:** Dedicated agent that invokes Codex CLI (`codex exec -s read-only`). Isolates Codex output from main context.

**Supported tasks:**
- Code + architecture review (pre-code-PR, after code-critic)
- Plan review (pre-plan-PR, sole reviewer)
- Design decisions and trade-off analysis
- Complex debugging analysis
- Architectural pattern evaluation

**Iteration:** Main agent controls loop. Max 3 iterations for reviews.

**Marker:** agent-trace.sh creates `/tmp/claude-codex-{session}` when output contains "CODEX APPROVED" token.

**Returns:** Structured verdict (APPROVE | REQUEST_CHANGES | NEEDS_DISCUSSION) with file:line references.

**Important:** Main agent must NOT run `codex exec` directly — always spawn this agent via Task tool. Once approved, codex step is complete (no redundant background analysis).

**Escalates to user:** Only on NEEDS_DISCUSSION or after 3 failed iterations.

**Note:** Uses Haiku (wrapper) + GPT5.2 High (via Codex CLI). Replaces architecture-critic. Always uses read-only sandbox.

## architecture-critic (DEPRECATED)

**Note:** Replaced by codex agent. Files preserved for reference.

**Use when:** After code-critic passes, before tests.

**Pattern:** Quick metrics scan first → deep analysis only when thresholds exceeded.

**Returns:** Verdict (SKIP | APPROVE | REQUEST_CHANGES | NEEDS_DISCUSSION) with architectural analysis.

**On REQUEST_CHANGES:** Main agent asks user about creating follow-up refactor task, PR proceeds (advisory, not blocking).

**Escalates to user:** Only on NEEDS_DISCUSSION.

**Note:** Uses Opus. Preloads `architecture-review` skill. Guidelines at `~/.claude/skills/architecture-review/reference/`:
- `architecture-guidelines-common.md` (always loaded)
- `architecture-guidelines-frontend.md` (React/TypeScript)
- `architecture-guidelines-backend.md` (Go/Python/Node.js)

## plan-reviewer (DEPRECATED)

**Note:** Replaced by codex agent for plan reviews. The codex agent provides deeper reasoning for architectural soundness and feasibility.

**Previously used for:** Document structure validation after creating planning documents.

**Migration:** Use codex agent with plan review prompt instead. See `plan-workflow` skill for the updated flow.
