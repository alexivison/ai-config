---
name: task-workflow
description: >-
  Execute planned work with full autonomous workflow including tests,
  implementation, critic review, companion review, and PR creation. Works with
  any planning source that provides scope, requirements, and a goal — TASK
  files, external planning tools, or direct user instructions. Covers the
  entire cycle from worktree creation to draft PR.
user-invocable: true
---

# Task Workflow

Execute planned work using the full autonomous pipeline defined in [execution-core.md](~/.claude/rules/execution-core.md).

## When to Use

Use task-workflow for **planned work** from any source that provides scope, requirements, and a goal:
- TASK*.md files from a project plan
- External planning tool artifacts (Linear, Notion, etc.)
- Direct user instructions with clear scope

For bug fixes → use `bugfix-workflow`. For non-behavioral small changes → use `quick-fix-workflow`.

## What This Skill Adds

Task-workflow is a thin shim over execution-core. It triggers the full pipeline and ensures:

1. **Scope extraction** — Read the planning source and extract scope boundaries, requirements, and goal per [Pre-Implementation Gate](~/.claude/rules/execution-core.md#pre-implementation-gate).
2. **Requirements audit** — Because planned work has requirements, the requirements-auditor runs alongside critics per [Requirements-Auditor Contract](~/.claude/rules/execution-core.md#requirements-auditor-contract).
3. **Source-file updates** — Tracking files are updated per [Source-File Updates](~/.claude/rules/execution-core.md#source-file-updates).

## Execution

Follow [execution-core.md](~/.claude/rules/execution-core.md) end-to-end — pre-implementation gate, RED evidence, implementation, source-file updates, critics (with requirements-auditor), companion review, deep-reviewer, commit, pre-pr-verification, PR. No stopping until PR is created.

See the [Core Sequence](~/.claude/rules/execution-core.md#core-sequence), [Decision Matrix](~/.claude/rules/execution-core.md#decision-matrix), and [Review Governance](~/.claude/rules/execution-core.md#review-governance) for the full rules.
