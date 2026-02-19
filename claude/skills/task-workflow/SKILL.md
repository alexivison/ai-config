---
name: task-workflow
description: Execute a task from TASK*.md with full workflow. Auto-invoked when implementing planned tasks.
user-invocable: true
---

# Task Workflow

Execute tasks from TASK*.md files with the full autonomous workflow.

## Pre-Implementation Gate

**STOP. Before writing ANY code:**

1. **Create worktree first** — `git worktree add ../repo-branch-name -b branch-name`
2. **Does task require tests?** → invoke `/write-tests` FIRST
3. **Requirements unclear?** → Ask user
4. **Will this bloat into a large PR?** → Split into smaller tasks
5. **Locate PLAN.md** — Find the project's PLAN.md for checkbox updates later
6. **Extract scope boundaries** — Read the TASK file's "In Scope" and "Out of Scope" sections for use in all sub-agent prompts

State which items were checked before proceeding.

## Execution Flow

After passing the gate, execute continuously — **no stopping until PR is created**.

```
/write-tests (if needed) → implement → checkboxes → [code-critic + minimizer] → wizard → /pre-pr-verification → commit → PR
```

### Step-by-Step

1. **Tests** — If task needs tests, invoke `/write-tests` first (RED phase via test-runner)
2. **Implement** — Write the code to make tests pass
3. **GREEN phase** — Run test-runner agent to verify tests pass
4. **Checkboxes** — Update both TASK*.md AND PLAN.md: `- [ ]` → `- [x]` (MANDATORY — both files)
5. **code-critic + minimizer** — Run in parallel with scope context and diff focus (see [Review Governance](#review-governance)). Triage findings by severity. Fix only blocking issues. Proceed to wizard when no blocking findings remain.
6. **wizard** — Invoke wizard for code + architecture review with scope context
7. **Handle wizard verdict** — Triage findings (see [Finding Triage](#finding-triage)). Classify fix impact for tiered re-review.
8. **PR Verification** — Invoke `/pre-pr-verification` (runs test-runner + check-runner internally)
9. **Commit & PR** — Create commit and draft PR

**Note:** Step 4 (Checkboxes) MUST include PLAN.md. Forgetting PLAN.md is a common violation.

**Important:** Always use test-runner agent for running tests, check-runner for lint/typecheck. This preserves context by isolating verbose output.

## Review Governance

The review loop is the most expensive part of the workflow. These rules prevent waste.

### Scope Context in Sub-Agent Prompts

**Every** code-critic, minimizer, and wizard prompt MUST include:

```
SCOPE BOUNDARIES:
- IN SCOPE: {copied from TASK file's "In scope" section}
- OUT OF SCOPE: {copied from TASK file's "Out of scope" section}
Findings on out-of-scope or pre-existing (untouched) code are automatically rejected.
Review the DIFF, not the entire codebase. Read context files for understanding only.
```

### Diff-Scoped Reviews

Instruct critics to run `git diff` and review only changed code. Pre-existing code not touched by the diff is non-blocking unless the change creates a new security-relevant interaction with it.

### Finding Triage

After receiving any critic or wizard verdict, the main agent classifies each finding BEFORE acting:

| Severity | Examples | Action |
|----------|---------|--------|
| **Blocking** | Correctness bug, crash path, wrong output, security HIGH/CRITICAL | Fix → re-run per tiered re-review |
| **Non-blocking** | Style nit, "could be simpler", defensive edge case, consistency | Note and optionally fix — do NOT re-run loop |
| **Out-of-scope** | Pre-existing code, requirements not in TASK file, hallucinated requirements | Reject — note as backlog if useful |

**Only blocking findings continue the review loop.**

### Issue Ledger

Track all findings mentally across iterations:
- A closed/fixed finding cannot be re-raised without new evidence (new code added since closure).
- If a critic re-raises a closed finding, reject it and proceed.
- If a critic reverses its own prior feedback (e.g., "remove X" → "add X back"), that is **oscillation** — the main agent uses its own judgment and proceeds. Do not chase the cycle.

### Iteration Caps

| Finding Tier | Max Critic Rounds | Max Wizard Rounds | Then |
|-------------|------------------|------------------|------|
| Blocking | 3 | 3 | NEEDS_DISCUSSION |
| Non-blocking | 1 | 1 | Accept or drop |

### Tiered Re-Review After Wizard Fixes

| Fix Impact | Example | Re-Review Required |
|-----------|---------|-------------------|
| Targeted swap | `in` → `Object.hasOwn`, typo | test-runner only |
| Logic change within function | Restructured control flow | test-runner + critics (diff-scoped) |
| New export, changed signature, security path | Added public API | Full cascade |

## Plan Conformance (Checkbox Enforcement)

When PLAN.md exists, enforce:

1. **Both files updated:** TASK*.md AND PLAN.md checkboxes must change `- [ ]` → `- [x]` after implementation.
2. **Dependency/order changes:** If task execution reveals the need to reorder or add tasks, update PLAN.md explicitly before proceeding.
3. **Commit together:** Checkbox updates go WITH implementation, not as separate commits.

Forgetting PLAN.md is the most common violation. Verify both files are updated before proceeding to code-critic.

## Wizard Step

After critics have no remaining blocking findings, invoke **wizard** for deep review:

**Prompt template:**
```
Review uncommitted changes for bugs, security, and architectural fit.

**Task:** Code + Architecture Review
**Iteration:** {N} of 3
**Previous feedback:** {summary of findings and resolutions from issue ledger}

SCOPE BOUNDARIES:
- IN SCOPE: {from TASK file}
- OUT OF SCOPE: {from TASK file}
Findings on out-of-scope code are automatically rejected.

Check imports, callers, and related files. Return verdict with file:line issues.
Each finding must include: severity (blocking/non-blocking), file:line, evidence.
```

The wizard agent will:
1. Read domain rules from `claude/rules/` or `.claude/rules/`
2. Run `codex exec -s read-only` for deep analysis
3. Return structured verdict (APPROVE/REQUEST_CHANGES/NEEDS_DISCUSSION)

On APPROVE, the "CODEX APPROVED" marker is created automatically.

**Iteration protocol:**
- Max 3 iterations for blocking findings, then NEEDS_DISCUSSION
- Non-blocking wizard findings do not trigger re-review — note and proceed
- Do NOT re-run wizard after convention/style fixes — only after logic or structural changes

## Core Reference

See [execution-core.md](~/.claude/rules/execution-core.md) for:
- Review governance (severity tiers, iteration caps, tiered re-review)
- Decision matrix (when to continue vs pause)
- Sub-agent behavior rules
- Verification requirements
- PR gate requirements
