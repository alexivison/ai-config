---
name: bugfix-workflow
description: >-
  Debug and fix bugs with full autonomous workflow. INVOKE FIRST when the user
  reports a bug, error, crash, test failure, unexpected behavior, broken feature,
  or anything that looks wrong. Handles investigation (optionally via the
  companion, default: Codex, for complex bugs), regression test writing, root
  cause analysis, and fix implementation.
  Follows execution-core rules without PLAN.md checkboxes.
user-invocable: true
---

# Bugfix Workflow

Debug and fix bugs. Follows the same execution flow as task-workflow with these deltas.

## Deltas from Task Workflow

- **No PLAN.md checkboxes** — bugfixes aren't planned work
- **Investigation gate** — complex bugs go to the companion before implementation
- **Regression test first** — write a test that reproduces the bug before fixing

## Pre-Bugfix Gate

**STOP. Before writing ANY code:**

1. **Create worktree first** — `git worktree add ../repo-branch-name -b branch-name`
2. **Understand the bug** — Read relevant code, reproduce if possible
3. **Complex bug?** → Dispatch the companion via the default transport script `tmux-codex.sh --prompt` → `[wait for user]`

Investigation agents ALWAYS require user review before proceeding.

## Execution Flow

Use the canonical sequence in [execution-core.md](~/.claude/rules/execution-core.md#core-sequence),
then apply these bugfix deltas from [task-workflow/SKILL.md](../task-workflow/SKILL.md):
- Step 1: Regression test (not feature test) — must FAIL first (RED), then PASS after fix (GREEN)
- Fix must address root cause (not just mask symptoms)
- No checkbox step

## Regression Test First

1. Write a test that reproduces the bug → invoke `/write-tests`
2. Run via test-runner — it should FAIL (RED)
3. Fix the bug
4. Run test-runner again — it should PASS (GREEN)

## Companion Investigation

For complex bugs, dispatch the companion with a debugging task:

```
Analyze this bug and identify the root cause.
**Bug description:** {symptom/error message}
**Relevant files:** {files where bug manifests}
Trace data/control flow, identify root cause with file:line, specify fix (don't implement).
```

**On APPROVE:** Show findings, ask user before fixing.
**On REQUEST_CHANGES:** Gather requested info, re-invoke.
**On NEEDS_DISCUSSION:** Present options, ask user.

## Core Reference

See [execution-core.md](~/.claude/rules/execution-core.md) for review governance, decision matrix, and verification requirements.
