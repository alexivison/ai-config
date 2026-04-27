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

## Enforcement

On Claude, invoking this skill writes the `bugfix` execution-preset via `skill-marker.sh`, so `pr-gate.sh` enforces the bugfix evidence set. On Codex, there is no local preset hook, so the same sequence and evidence list are self-enforced from `codex/AGENTS.md`.

## Deltas from Task Workflow

- **No PLAN.md checkboxes** — bugfixes aren't planned work
- **Investigation gate** — complex bugs go to the companion before implementation
- **Regression test first** — write a test that reproduces the bug before fixing
- **Research note location** — write investigation findings to `~/.ai-party/docs/research/YYYY-MM-DD-investigation-<slug>.md` with frontmatter `type: investigation`

## Pre-Bugfix Gate

**STOP. Before writing ANY code:**

1. **Create worktree first** — `git worktree add ../repo-branch-name -b branch-name`
2. **Understand the bug** — Read relevant code, reproduce if possible
3. **Complex bug?** → Dispatch the companion via the default transport script `tmux-companion.sh --prompt` → `[wait for user]`

Investigation agents ALWAYS require user review before proceeding.

## Execution Flow

Invoking this skill selects the `bugfix` execution preset. That preset requires `code-critic + minimizer + companion review + pre-pr-verification` evidence (no requirements-auditor, unlike the task preset).

Use the canonical sequence in `shared/execution-core.md` (section "Core Sequence"), then apply these bugfix deltas from `shared/skills/task-workflow/SKILL.md`:
- Step 1: Regression test (not feature test) — must FAIL first (RED), then PASS after fix (GREEN)
- Fix must address root cause (not just mask symptoms)
- No checkbox step

## Regression Test First

1. Write a test that reproduces the bug → invoke `/write-tests`
2. Run via your verification mechanism — it should FAIL (RED)
3. Fix the bug
4. Run the verification again — it should PASS (GREEN)

## Companion Investigation

For complex bugs, dispatch the companion with a debugging task:

```
Analyze this bug and identify the root cause.
**Bug description:** {symptom/error message}
**Relevant files:** {files where bug manifests}
Trace data/control flow, identify root cause with file:line, specify fix (don't implement).
Write findings to `~/.ai-party/docs/research/YYYY-MM-DD-investigation-<slug>.md`.
```

**On APPROVE:** Show findings, ask user before fixing.
**On REQUEST_CHANGES:** Gather requested info, re-invoke.
**On NEEDS_DISCUSSION:** Present options, ask user.

## Core Reference

See `shared/execution-core.md` for review governance, decision matrix, and verification requirements.
