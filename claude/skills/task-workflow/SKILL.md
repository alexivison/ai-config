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
2. **Does task require tests?** → invoke `/write-tests` FIRST
3. **Requirements unclear?** → `/brainstorm` or ask user
4. **Will this bloat into a large PR?** → Split into smaller tasks

State which items were checked before proceeding.

## Execution Flow

After passing the gate, execute continuously — **no stopping until PR is created**.

```
/write-tests (if needed) → implement → checkboxes → code-critic → codex → /pre-pr-verification → commit → PR
```

### Step-by-Step

1. **Tests** — If task needs tests, invoke `/write-tests` first (RED phase via test-runner)
2. **Implement** — Write the code to make tests pass
3. **GREEN phase** — Run test-runner agent to verify tests pass
4. **Checkboxes** — Update both TASK*.md and PLAN.md: `- [ ]` → `- [x]`
5. **code-critic** — MANDATORY after implementing. Fix issues until APPROVE
6. **codex** — Spawn codex agent for combined code + architecture review
7. **Re-run code-critic** — If Codex made changes, verify conventions
8. **PR Verification** — Invoke `/pre-pr-verification` (runs test-runner + check-runner internally)
9. **Commit & PR** — Create commit and draft PR

**Important:** Always use test-runner agent for running tests, check-runner for lint/typecheck. This preserves context by isolating verbose output.

## Checkpoint Updates

After completing implementation, update checkboxes:
- In TASK*.md file (the specific task)
- In PLAN.md (the overall progress tracker)

Commit checkbox updates WITH implementation, not separately.

## Codex Step

After code-critic APPROVE, spawn **codex** agent for deep review:

**Prompt template:**
```
Review uncommitted changes for bugs, security, and architectural fit.

**Task:** Code + Architecture Review
**Iteration:** {N} of 3
**Previous feedback:** {summary if iteration > 1}

Check imports, callers, and related files. Return verdict with file:line issues.
```

The codex agent will:
1. Read domain rules from `claude/rules/` or `.claude/rules/`
2. Run `codex exec -s read-only` for deep analysis
3. Return structured verdict (APPROVE/REQUEST_CHANGES/NEEDS_DISCUSSION)

**On APPROVE:** Agent returns "CODEX APPROVED" and marker is created automatically.

**On REQUEST_CHANGES:** Fix issues and re-invoke codex agent.

**Iteration protocol:**
- Max 3 iterations, then NEEDS_DISCUSSION
- Do NOT re-run codex after code-critic convention fixes

## Core Reference

See [execution-core.md](/Users/aleksituominen/.claude/rules/execution-core.md) for:
- Decision matrix (when to continue vs pause)
- Sub-agent behavior rules
- Verification requirements
- PR gate requirements
