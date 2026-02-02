---
name: task-workflow
description: Execute a task from TASK*.md with full workflow. Auto-invoked when implementing planned tasks.
user-invocable: false
---

# Task Workflow

Execute tasks from TASK*.md files with the full autonomous workflow.

## Pre-Implementation Gate

**STOP. Before writing ANY code:**

1. **Create worktree first** — `git worktree add ../repo-branch-name -b branch-name`
2. **Install dependencies** — If node_modules missing, run `npm install` (or yarn/pnpm)
3. **Does task require tests?** → invoke `/write-tests` FIRST
4. **Requirements unclear?** → Ask user for clarification
5. **Will this bloat into a large PR?** → Split into smaller tasks

State which items were checked before proceeding.

## Execution Flow

After passing the gate, execute continuously — **no stopping until PR is created**.

```
/write-tests (if needed) → implement → GREEN → checkboxes → /pre-pr-verification → commit → PR
```

### Step-by-Step

1. **Tests** — If task needs tests, invoke `/write-tests` first (RED phase via test-runner)
2. **Implement** — Write the code to make tests pass
3. **GREEN phase** — Run test-runner agent to verify tests pass
4. **Checkboxes** — Update both TASK*.md and PLAN.md: `- [ ]` → `- [x]`
5. **PR Verification** — Invoke `/pre-pr-verification` (runs reviews + all checks)
6. **Commit & PR** — Create commit and draft PR

**Note:** Code review and architecture review are now part of `/pre-pr-verification`, not separate steps.

**Important:** Always use test-runner agent for running tests, check-runner for lint/typecheck. This preserves context by isolating verbose output.

## Checkpoint Updates

After completing implementation, update checkboxes:
- In TASK*.md file (the specific task)
- In PLAN.md (the overall progress tracker)

Commit checkbox updates WITH implementation, not separately.

## Core Reference

See [execution-core.md](/Users/aleksituominen/.claude/rules/execution-core.md) for:
- Decision matrix (when to continue vs pause)
- Sub-agent behavior rules
- Verification requirements
- PR gate requirements
