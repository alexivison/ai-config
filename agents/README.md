# Sub-Agents

Sub-agents preserve context by offloading investigation/verification tasks.

## debug-investigator
**Use when:** Complex bugs requiring systematic investigation.

**Methodology:** 4-phase debugging (Root Cause → Pattern Analysis → Hypothesis Testing → Specify Fix).

**Writes to:** `~/.claude/investigations/{issue-id}.md`

**Returns:** Brief summary with file path, verdict, hypotheses tested, one-line summary.

## project-researcher
**Use when:** Starting on a new project, need context on status/team/decisions, or finding design specs.

**Returns:** Structured overview with status, team, resources (Notion/Figma/Slack), recent activity, open questions.

**Note:** Searches Notion primarily. Figma/Slack only if MCP configured.

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
