---
name: bugfix-workflow
description: Debug and fix bugs. INVOKE FIRST when user reports bugs/errors - workflow handles investigation internally.
user-invocable: false
---

# Bugfix Workflow

Debug and fix bugs with investigation before implementation.

## Pre-Bugfix Gate

**STOP. Before writing ANY code:**

1. **Create worktree first** — `git worktree add ../repo-branch-name -b branch-name`
2. **Understand the bug** — Read relevant code, reproduce if possible
3. **Complex bug?** → Invoke `codex` agent with debugging task → `[wait for user]`
4. **Logs relevant?** → Invoke `log-analyzer` agent → `[wait for user]`

`[wait]` = Show findings, use AskUserQuestion, wait for user input.

Investigation agents ALWAYS require user review before proceeding.

State which items were checked before proceeding.

## Execution Flow

Execute continuously — **no stopping until PR is created**.

```
/write-tests (regression) → implement fix → code-critic → codex → /pre-pr-verification → PR
```

### Step-by-Step

1. **Regression Test** — Invoke `/write-tests` to write a test that reproduces the bug (RED phase via test-runner)
2. **Implement Fix** — Fix the bug to make the test pass
3. **GREEN phase** — Run test-runner agent to verify tests pass
4. **code-critic** — MANDATORY after implementing. Fix issues until APPROVE
5. **codex** — Spawn codex agent for combined code + architecture review
6. **Re-run code-critic** — If Codex made changes, verify conventions
7. **PR Verification** — Invoke `/pre-pr-verification` (runs test-runner + check-runner internally)
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

## Codex Investigation Step

For complex bugs, spawn **codex** agent with debugging task:

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

## Codex Review Step

See [task-workflow/SKILL.md](../task-workflow/SKILL.md#codex-step) for the code + architecture review invocation details and iteration protocol.

## Core Reference

See [execution-core.md](/Users/aleksituominen/.claude/rules/execution-core.md) for:
- Decision matrix (when to continue vs pause)
- Sub-agent behavior rules
- Verification requirements
- PR gate requirements
