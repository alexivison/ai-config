---
name: quick-fix-workflow
description: >-
  Fast workflow for small or straightforward changes. Routes the session into
  the `quick` execution-preset, which requires only code-critic plus the
  test/check verification for PR creation. Use when the user asks for a quick
  fix, small change, or invokes /quick-fix-workflow.
user-invocable: true
---

# Quick Fix Workflow

Lightweight workflow for small or straightforward changes. Invoking this skill selects the `quick` execution preset. That preset requires `code-critic` + `pr-verified` + `test-runner` + `check-runner` — no minimizer, no companion review.

## Enforcement

Invoking this skill selects the `quick` execution preset. Claude's hook implementation records that preset via `skill-marker.sh`, so `pr-gate.sh` enforces the quick evidence set. Agents without Claude's hook chain, including Codex and Pi, self-enforce the same sequence and evidence list from their current agent instructions.

## Scope Guidance

Use this workflow when speed matters and the requested change seems contained. There is no category whitelist or hard size rejection in this skill.

- Follow the quick preset checklist regardless of agent. Claude wires the evidence marker automatically when this skill is invoked; agents without that marker hook self-enforce the checklist manually.
- Satisfy the quick preset gate with `code-critic`, `test-runner`, and `check-runner` (plus `pr-verified`).
- If the work turns into deep debugging or broad planned implementation, switching to `bugfix-workflow` or `task-workflow` may still be the cleaner framing, but it is a judgment call rather than an enforced gate.

## Pre-Fix Gate

**Before writing ANY code:**

1. **Create worktree** — `git worktree add ../repo-branch-name -b branch-name`
2. **Understand scope** — Confirm what the user wants changed and whether behavior is likely to change
3. **Note verification needs** — Decide what tests and checks are needed for the requested change

State the scope assessment before proceeding, but do not reject the work merely because it touches logic, API surface, or a larger diff.

## Execution Flow

After passing the gate, execute continuously — **no stopping until PR is created**.

1. **Implement** the change
2. **Run code-critic** — Single pass. Triage any blocking findings before proceeding.
3. **Commit** — Create the commit that the verification evidence will apply to
4. **Run the full verification** — tests and checks, per `/pre-pr-verification`
5. **PR** — Create or update the PR

## What This Workflow Optimizes

- **Direct quick preset routing** — `code-critic + pr-verified + test-runner + check-runner` is sufficient for the PR gate
- **No companion review in quick preset** — quick preset intentionally skips companion review
- **No minimizer gate** — minimizer is not part of the quick preset evidence set
- **Manual workflow choice** — Use `task-workflow` or `bugfix-workflow` when you want the fuller pipeline, not because the gate requires it

## Core Reference

See `shared/reference/execution-core.md` for the evidence system and the preset-to-evidence mapping used by the PR gate.
