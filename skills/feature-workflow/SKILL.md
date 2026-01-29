---
name: feature-workflow
description: Implement a new feature from requirements through PR. Auto-invoked for new functionality or user requests.
user-invocable: false
---

# Feature Workflow

Implement new features from requirements through to PR creation.

## Entry Phase

Before implementation, clarify and plan:

1. **Requirements unclear?** → Invoke `/brainstorm` → `[wait for user]`
2. **Substantial feature (3+ files)?** → Invoke `/plan-implementation` → `[wait for user]`

`[wait]` = Show findings, use AskUserQuestion, wait for user input.

## After Planning Approved

1. **Create worktree** — `git worktree add ../repo-branch-name -b branch-name`
2. **Proceed to execution flow**

## Execution Flow

Execute continuously — **no stopping until PR is created**.

```
/write-tests (if needed) → implement → code-critic → architecture-critic → verification → PR
```

### Step-by-Step

1. **Tests** — If feature needs tests, invoke `/write-tests` first (RED phase via test-runner)
2. **Implement** — Write the code to make tests pass
3. **GREEN phase** — Run test-runner agent to verify tests pass
4. **code-critic** — MANDATORY after implementing. Fix issues until APPROVE
5. **architecture-critic** — Run after code-critic passes
6. **Verification** — Run test-runner + check-runner + security-scanner (parallel)
7. **PR Verification** — Invoke `/pre-pr-verification`
8. **Commit & PR** — Create commit and draft PR

**Important:** Always use test-runner agent for running tests, check-runner for lint/typecheck. This preserves context by isolating verbose output.

## When to Use This Workflow

- User asks to "add", "create", "build", or "implement" something new
- User describes a new feature or capability
- Enhancing existing functionality with significant additions

## Core Reference

See [execution-core.md](/Users/aleksituominen/.claude/rules/execution-core.md) for:
- Decision matrix (when to continue vs pause)
- Sub-agent behavior rules
- Verification requirements
- PR gate requirements
