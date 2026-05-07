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

Execute planned work using the full autonomous pipeline defined in the shared execution-core rules at `shared/reference/execution-core.md` (or an agent-local shim when one is installed).

## Enforcement

Invoking this skill selects the `task` execution preset. Claude's hook implementation records that preset via `skill-marker.sh`, so `pr-gate.sh` requires the full task-preset evidence set. Agents without Claude's hook chain, including Codex and Pi, self-enforce the same sequence and evidence list from their current agent instructions.

## When to Use

Use task-workflow for **planned work** from any source that provides scope, requirements, and a goal:
- TASK*.md files from a project plan
- External planning tool artifacts (Linear, Notion, etc.)
- Direct user instructions with clear scope

For bug fixes → use `bugfix-workflow`. For non-behavioral small changes → use `quick-fix-workflow`.

## What This Skill Adds

Task-workflow is a thin shim over execution-core. It triggers the full pipeline and ensures:

1. **Scope extraction** — Read the planning source and extract scope boundaries, requirements, and goal per the pre-implementation gate in `shared/reference/execution-core.md`.
2. **Requirements audit** — Because planned work has requirements, the critics stage is `code-critic + minimizer + requirements-auditor`.
3. **Source-file updates** — Tracking files (TASK/PLAN/external checkboxes) are updated alongside the implementation commit.
4. **Task-plan location** — If you create a separate task plan doc, write it to `~/.ai-party/docs/research/YYYY-MM-DD-task-<slug>.md` with frontmatter `type: plan`.

## Execution

Follow `shared/reference/execution-core.md` end-to-end — pre-implementation gate, RED evidence, implementation, source-file updates, critics (`code-critic + minimizer + requirements-auditor`), companion review, commit, pre-pr-verification, PR. No stopping until PR is created.

Concrete stage mechanisms come from your current agent's instructions (for example `claude/CLAUDE.md`, `codex/AGENTS.md`, or `pi/agent/AGENTS.md`). This recipe describes the stages; the agent instructions describe how to execute them.
