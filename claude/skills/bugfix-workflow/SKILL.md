---
name: bugfix-workflow
description: Debug and fix bugs with investigation workflow. Auto-invoked for broken functionality or errors.
user-invocable: false
---

# Bugfix Workflow

Debug and fix bugs with investigation before implementation.

## Pre-Bugfix Gate

**STOP. Before writing ANY code:**

1. **Create worktree first** — `git worktree add ../repo-branch-name -b branch-name`
2. **Understand the bug** — Read relevant code, reproduce if possible
3. **Complex bug?** → Invoke `cli-orchestrator` for investigation → `[wait for user]`
4. **Logs relevant?** → Invoke `log-analyzer` agent → `[wait for user]`

`[wait]` = Show findings, use AskUserQuestion, wait for user input.

**cli-orchestrator investigation prompt:**
```
Investigate bug: {error/symptom description}.
Context: {relevant files, steps to reproduce}.
Apply four-phase methodology.
```

Investigation ALWAYS requires user review before proceeding.

State which items were checked before proceeding.

## Execution Flow

Execute continuously — **no stopping until PR is created**.

```
/write-tests (regression) → implement fix → GREEN → /pre-pr-verification → commit → PR
```

### Step-by-Step

1. **Regression Test** — Invoke `/write-tests` to write a test that reproduces the bug (RED phase via test-runner)
2. **Implement Fix** — Fix the bug to make the test pass
3. **GREEN phase** — Run test-runner agent to verify tests pass
4. **PR Verification** — Invoke `/pre-pr-verification` (runs reviews + all checks)
5. **Commit & PR** — Create commit and draft PR

**Note:** Code review and architecture review are now part of `/pre-pr-verification`, not separate steps.

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

## Core Reference

See [execution-core.md](/Users/aleksituominen/.claude/rules/execution-core.md) for:
- Decision matrix (when to continue vs pause)
- Sub-agent behavior rules
- Verification requirements
- PR gate requirements
