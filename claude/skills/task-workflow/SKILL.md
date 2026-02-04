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
/write-tests (if needed) → implement → checkboxes → code-critic → codex-review → /pre-pr-verification → commit → PR
```

### Step-by-Step

1. **Tests** — If task needs tests, invoke `/write-tests` first (RED phase via test-runner)
2. **Implement** — Write the code to make tests pass
3. **GREEN phase** — Run test-runner agent to verify tests pass
4. **Checkboxes** — Update both TASK*.md and PLAN.md: `- [ ]` → `- [x]`
5. **code-critic** — MANDATORY after implementing. Fix issues until APPROVE
6. **codex-review** — Spawn general-purpose subagent for combined code + arch review
7. **Re-run code-critic** — If Codex made changes, verify conventions
8. **PR Verification** — Invoke `/pre-pr-verification` (runs test-runner + check-runner internally)
9. **Commit & PR** — Create commit and draft PR

**Important:** Always use test-runner agent for running tests, check-runner for lint/typecheck. This preserves context by isolating verbose output.

## Checkpoint Updates

After completing implementation, update checkboxes:
- In TASK*.md file (the specific task)
- In PLAN.md (the overall progress tracker)

Commit checkbox updates WITH implementation, not separately.

## Codex Review Step

After code-critic APPROVE, spawn general-purpose subagent for Codex review:

**Prompt template:**
```
Run Codex CLI for combined code + architecture review.

**Iteration:** {N} of 3
**Previous feedback:** {summary if iteration > 1}

**Steps:**
1. First, detect config root and read domain rules:
   - Check for `claude/rules/`, `.claude/rules/`, or `./rules/`
   - Read `development.md` and any `backend/*.md` or `frontend/*.md` files
   - Note key conventions for the review

2. Run: `codex exec -s read-only "Review uncommitted changes for bugs and architectural fit. Check imports/callers. Return verdict: **APPROVE** or **REQUEST_CHANGES** with file:line issues."`

3. Parse the output and return summary to main agent:
   - Verdict (**APPROVE** or **REQUEST_CHANGES**)
   - Key issues with file:line references
   - Architectural concerns

**IMPORTANT:** On APPROVE, your response MUST include the exact text "CODEX APPROVED" so the marker is created.
```

**On APPROVE:** Include "CODEX APPROVED" in response (agent-trace.sh creates marker automatically)

**On REQUEST_CHANGES:** Return findings for main agent to fix.

**Key capabilities:**
- Codex uses `read-only` sandbox — can explore entire codebase
- GPT5.2 High with detailed reasoning (configured in codex/config.toml)
- Reviews code quality AND architectural fit

**Iteration protocol:**
- Main agent fixes issues and re-spawns subagent
- Max 3 iterations, then NEEDS_DISCUSSION
- Do NOT re-run Codex after code-critic convention fixes

## Core Reference

See [execution-core.md](/Users/aleksituominen/.claude/rules/execution-core.md) for:
- Decision matrix (when to continue vs pause)
- Sub-agent behavior rules
- Verification requirements
- PR gate requirements
