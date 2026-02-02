---
name: pre-pr-verification
description: Run full verification before creating PR. Enforces evidence-based completion. Use before any PR creation or when asked to verify changes.
user-invocable: false
allowed-tools: Bash, Task
---

# Pre-PR Verification

Run all checks locally before creating a PR. No PR without passing verification.

## Core Principle

**"Evidence before PR, always."** — If you haven't run verification fresh and seen it pass, you cannot create a PR.

## CRITICAL: Do NOT Load Review Skills Directly

**Do NOT invoke `/code-review` or `/architecture-review` skills.** Reviews are done by cli-orchestrator agent, not the main agent.

## Process

### Step 1: Code Review via cli-orchestrator Agent (Iterative)

**Spawn cli-orchestrator agent** using Task tool:

```
Task(subagent_type="cli-orchestrator", prompt="Review the uncommitted changes in {worktree_path}. Context: {task description}")
```

- If **APPROVE** → continue immediately (no pause)
- If **REQUEST_CHANGES** → fix and re-run (max 3 iterations)
- If **NEEDS_DISCUSSION** → pause and ask user

Code review must pass before proceeding. Iterate until APPROVE.

### Step 2: Run All Checks in Parallel (Including Arch Review)

After code review passes, launch **all four** simultaneously in ONE message block:

```
Task(subagent_type="cli-orchestrator", prompt="Architecture review of changed files in {worktree_path}. Context: {task description}")
Task(subagent_type="test-runner", ...)
Task(subagent_type="check-runner", ...)
Task(subagent_type="security-scanner", ...)
```

**Why arch review runs here:**
- Arch review is advisory (doesn't block PR on REQUEST_CHANGES)
- Running parallel with checks saves ~3 minutes
- Code review already passed, so arch sees final code

**Handling arch review results:**
- **APPROVE** or **SKIP** → continue
- **REQUEST_CHANGES** → note for future task, continue (doesn't block PR)
- **NEEDS_DISCUSSION** → pause and ask user

### Step 3: Handle Failures

**If checks fail on NEW code you wrote:**
1. Fix the issue
2. Re-run code review first, then parallel checks again
3. Repeat until all pass

**If checks fail on UNRELATED code:**
1. Don't rationalize "it's not my change"
2. Either fix it (if simple) or ask user how to proceed
3. Never ship a PR with known failures

**If a test is flaky** (passes/fails randomly):
1. A flaky test is a broken test — don't ignore it
2. If you can't fix it: file an issue, skip the test explicitly with a comment, document in PR
3. Never ship with unskipped flaky tests

### Step 4: Capture Evidence

After all checks pass, capture verification summary for PR description:

```markdown
## Verification

| Check | Result |
|-------|--------|
| Code Review | ✓ APPROVE |
| Architecture | ✓ SKIP / APPROVE |
| Typecheck | ✓ No errors |
| Lint | ✓ No errors |
| Tests | ✓ X passed |
| Security | ✓ No CRITICAL/HIGH |

Run at: [timestamp]
```

## Autonomous Flow Reminder

**Do NOT pause between steps.** Continue immediately after each step unless:
- NEEDS_DISCUSSION verdict
- 3 failed fix attempts
- HIGH/CRITICAL security issues

**Violation patterns** (do not do these):
- "Code review complete." [stop] — Continue to parallel checks
- "All checks pass." [stop] — Continue to commit/PR
- "Would you like me to..." — Just do it
- "Should I continue?" — Just continue

## No Remote? Just Note It

If `git remote -v` shows no remote configured:
- Note "No remote configured" in summary
- **Do NOT ask** "Would you like me to add a remote?"
- The task is complete when commit exists locally

## Only After All Pass

Create PR: `gh pr create --draft` (if remote exists)
