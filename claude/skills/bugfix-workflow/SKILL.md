---
name: bugfix-workflow
description: Debug and fix bugs. INVOKE FIRST when user reports bugs/errors - workflow handles investigation internally.
user-invocable: true
---

# Bugfix Workflow

Debug and fix bugs with investigation before implementation.

## Pre-Bugfix Gate

**STOP. Before writing ANY code:**

1. **Create worktree first** — `git worktree add ../repo-branch-name -b branch-name`
2. **Understand the bug** — Read relevant code, reproduce if possible
3. **Complex bug?** → Invoke `~/.claude/skills/codex-cli/scripts/tmux-codex.sh --prompt` with debugging task → `[wait for user]`

`[wait]` = Show findings, use AskUserQuestion, wait for user input.

Investigation agents ALWAYS require user review before proceeding.

State which items were checked before proceeding.

## Execution Flow

Execute continuously — **no stopping until PR is created**.

```
/write-tests (regression) → implement fix → self-review → [code-critic + minimizer] → codex → /pre-pr-verification → commit → PR
```

**Note:** Bugfixes typically don't have PLAN.md checkbox updates (they're not part of planned work).

### Step-by-Step

1. **Regression Test** — Invoke `/write-tests` to write a test that reproduces the bug (RED phase via test-runner)
2. **Implement Fix** — Fix the bug to make the test pass
3. **GREEN phase** — Run test-runner agent to verify tests pass
4. **Self-Review** — Before invoking critics, verify your own work (see [execution-core.md](~/.claude/rules/execution-core.md#self-review)):
   - Bug root cause addressed? (not just symptom masked)
   - Regression test covers the exact failure mode?
   - No debug artifacts?
   - Diff matches intent? (`git diff`)
   - No obvious secondary bugs introduced?
   Fix any failures before proceeding.
5. **code-critic + minimizer** — Run in parallel with diff focus. Triage findings by severity (see [Review Governance](../task-workflow/SKILL.md#review-governance)). Fix only blocking issues. Proceed to codex when no blocking findings remain.
6. **codex** — Request codex review via tmux (non-blocking):
   ```bash
   ~/.claude/skills/codex-cli/scripts/tmux-codex.sh --review main "{Bug fix summary}"
   ```
   Continue with non-edit work while Codex reviews. Include bug context in scope boundaries.
7. **Triage codex findings** — When `[CODEX] Review complete` arrives: read findings, record evidence (`--review-complete`), triage by severity, signal verdict (`--approve`/`--re-review`/`--needs-discussion`).
8. **PR Verification** — Invoke `/pre-pr-verification` (runs test-runner + check-runner internally)
9. **Commit & PR** — Create commit and draft PR

**Important:** Always use test-runner agent for running tests, check-runner for lint/typecheck. This preserves context by isolating verbose output.

## Regression Test First

For bug fixes, ALWAYS write a regression test first:
1. Write a test that reproduces the bug
2. Run via test-runner — it should FAIL (RED)
3. Fix the bug
4. Run test-runner again — it should PASS (GREEN)

This ensures the bug is actually fixed and won't regress.

## When to Use This Workflow

- User mentions "bug", "fix", "broken", "error", "not working"
- Something that worked before stopped working
- Unexpected behavior that needs investigation

## Codex Investigation Step

For complex bugs, invoke Codex directly with debugging task:

**Prompt template:**
```
Analyze this bug and identify the root cause.

**Task:** Debugging
**Bug description:** {symptom/error message}
**Relevant files:** {files where bug manifests}

Investigation steps:
1. Trace the data/control flow to find where it breaks
2. Compare with similar working code patterns
3. Identify the root cause with file:line reference
4. Specify the fix (don't implement)

Return structured findings with verdict:
- APPROVE = Root cause confirmed, ready to fix
- REQUEST_CHANGES = Need more investigation (specify what)
- NEEDS_DISCUSSION = Multiple possible causes or unclear path forward
```

**On APPROVE:** Show findings, ask user before proceeding to fix.

**On REQUEST_CHANGES:** Gather the requested information and re-invoke.

**On NEEDS_DISCUSSION:** Present options, ask user for guidance.

## Review Governance

Bugfix workflows follow the same review governance as task workflows:
- **Scope context** in all sub-agent prompts (bug description + affected files = scope)
- **Finding triage** by severity (blocking vs non-blocking vs out-of-scope)
- **Issue ledger** to prevent oscillation and re-raising of closed findings
- **Tiered re-review** after codex fixes

See [task-workflow/SKILL.md](../task-workflow/SKILL.md#review-governance) for full review governance rules.

## Codex Review Step

See [task-workflow/SKILL.md](../task-workflow/SKILL.md#codex-step) for the code + architecture review invocation details and iteration protocol.

## Core Reference

See [execution-core.md](~/.claude/rules/execution-core.md) for:
- Review governance (severity tiers, iteration caps, tiered re-review)
- Decision matrix (when to continue vs pause)
- Sub-agent behavior rules
- Verification requirements
- PR gate requirements
