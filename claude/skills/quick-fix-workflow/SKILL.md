---
name: quick-fix-workflow
description: >-
  Fast workflow for small or straightforward changes. Routes the session
  through the quick tier via explicit quick-tier evidence and requires only
  code-critic + test-runner + check-runner before PR creation. Use when the
  user asks for a quick fix, small change, or invokes /quick-fix-workflow.
user-invocable: true
---

# Quick Fix Workflow

Lightweight workflow for small or straightforward changes. It routes the
session through the quick tier when this skill writes explicit `quick-tier`
evidence. The gate no longer imposes category or size restrictions once that
evidence exists.

## Scope Guidance

Use this workflow when speed matters and the requested change seems
contained. There is no category whitelist or hard size rejection in this skill.
Instead:

- Record `quick-tier` evidence for work explicitly routed through this workflow.
- Satisfy the quick-tier gate with `code-critic`, `test-runner`, and `check-runner`.
- If the work turns into deep debugging or broad planned implementation,
  switching to `bugfix-workflow` or `task-workflow` may still be the cleaner
  framing, but it is a judgment call rather than an enforced gate.

## Pre-Fix Gate

**Before writing ANY code:**

1. **Create worktree** — `git worktree add ../repo-branch-name -b branch-name`
2. **Understand scope** — Confirm what the user wants changed and whether behavior is likely to change
3. **Note verification needs** — Decide what tests and checks are needed for the requested change

State the scope assessment before proceeding, but do not reject the work merely
because it touches logic, API surface, or a larger diff.

## Execution Flow

After passing the gate, execute continuously — **no stopping until PR is created**.

1. **Implement** the change
2. **Write quick-tier evidence** — Append `quick-tier` evidence to the session log:
   ```bash
   source ~/.claude/hooks/lib/evidence.sh
   append_evidence "$SESSION_ID" "quick-tier" "AUTHORIZED" "$CWD"
   ```
   This signals to the PR gate that this change was explicitly routed through the quick-fix workflow.
3. **Run code-critic** — Single pass. Triage any blocking findings before proceeding.
4. **Run test-runner + check-runner** — Launch both sub-agents in parallel
5. **Commit & PR** — Create commit and draft PR

## What This Workflow Optimizes

- **Direct quick tier routing** — `quick-tier + code-critic + test-runner + check-runner` is sufficient for the PR gate
- **No companion review in quick tier** — the quick-tier evidence chain replaces the default companion review requirement for this path
- **No category guardrails** — Runtime logic, API edits, and larger diffs are no longer auto-rejected here
- **Manual workflow choice** — Use `task-workflow` or `bugfix-workflow` when you want the fuller pipeline, not because the gate requires it

The safety net is deliberate workflow choice plus the quick-tier evidence chain.

## Core Reference

See [execution-core.md](~/.claude/rules/execution-core.md) for the evidence system and PR gate requirements.
