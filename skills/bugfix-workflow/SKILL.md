---
name: bugfix-workflow
description: Debug and fix bugs with investigation workflow. Auto-invoked for broken functionality or errors.
user-invocable: false
---

# Bugfix Workflow

Debug and fix bugs with investigation before implementation.

## Entry Phase (Investigation)

Before fixing, understand the problem:

1. **Complex bug?** → Invoke `debug-investigator` agent → `[wait for user]`
2. **Logs relevant?** → Invoke `log-analyzer` agent → `[wait for user]`

`[wait]` = Show findings, use AskUserQuestion, wait for user input.

Investigation agents ALWAYS require user review before proceeding.

## After Investigation Approved

1. **Create worktree** — `git worktree add ../repo-branch-name -b branch-name`
2. **Proceed to execution flow**

## Execution Flow

Execute continuously — **no stopping until PR is created**.

```
/write-tests (regression) → implement fix → code-critic → architecture-critic → verification → PR
```

### Step-by-Step

1. **Regression Test** — Invoke `/write-tests` to write a test that reproduces the bug (RED phase via test-runner)
2. **Implement Fix** — Fix the bug to make the test pass
3. **GREEN phase** — Run test-runner agent to verify tests pass
4. **code-critic** — MANDATORY after implementing. Fix issues until APPROVE
5. **architecture-critic** — Run after code-critic passes
6. **Verification** — Run test-runner + check-runner + security-scanner (parallel)
7. **PR Verification** — Invoke `/pre-pr-verification`
8. **Commit & PR** — Create commit and draft PR

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
