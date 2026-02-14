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
5. **Locate PLAN.md** — Find the project's PLAN.md for checkbox updates later

State which items were checked before proceeding.

## Execution Flow

After passing the gate, execute continuously — **never stop until PR is created. No exceptions.**

```
/write-tests (if needed) → implement → checkboxes → code-critic → codex → /pre-pr-verification → commit → PR
```

### No-Pause Rule

This workflow **never pauses for user input** during execution. Unlike bugfix-workflow, there are no valid pause conditions. Handle escalations inline:

| Situation | Action (do NOT pause) |
|-----------|----------------------|
| code-critic → NEEDS_DISCUSSION | Attempt the suggested fix. If genuinely ambiguous, pick the simpler option and note the tradeoff in a code comment. |
| code-critic → repeated failures on same issue | Try a different approach entirely. If still failing, revert the problematic change and proceed without it. |
| codex → NEEDS_DISCUSSION | Apply best-judgment fix. Document the concern as a TODO comment for human review. |
| security-scanner → HIGH/CRITICAL | Apply the recommended remediation. If no clear fix, add a `// SECURITY: <description>` comment and continue. |

The PR description is the right place to flag unresolved concerns — not a mid-workflow pause.

### Step-by-Step

1. **Tests** — If task needs tests, invoke `/write-tests` first (RED phase via test-runner)
2. **Implement** — Write the code to make tests pass
3. **GREEN phase** — Run test-runner agent to verify tests pass
4. **Checkboxes** — Update both TASK*.md AND PLAN.md: `- [ ]` → `- [x]` (MANDATORY — both files)
5. **code-critic** — MANDATORY after implementing. Fix issues until APPROVE
6. **codex** — Spawn codex agent for combined code + architecture review
7. **Re-run code-critic** — If Codex made changes, verify conventions
8. **PR Verification** — Invoke `/pre-pr-verification` (runs test-runner + check-runner internally)
9. **Commit & PR** — Create commit and draft PR

**Note:** Step 5 (Checkboxes) MUST include PLAN.md. Forgetting PLAN.md is a common violation.

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
**Iteration:** {N}
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
- If stuck on the same issue after multiple attempts, try a different approach entirely.
- Do NOT re-run codex after code-critic convention fixes

## Core Reference

See [execution-core.md](~/.claude/rules/execution-core.md) for:
- Decision matrix (base rules — this workflow overrides all pause conditions)
- Sub-agent behavior rules
- Verification requirements
- PR gate requirements
