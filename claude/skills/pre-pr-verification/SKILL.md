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

## Process

### Step 1: Identify Verification Commands

Check project's package.json or CI config for the exact commands. Common patterns:

| Check | Common Commands |
|-------|-----------------|
| Types | `pnpm typecheck`, `tsc --noEmit` |
| Lint | `pnpm lint`, `eslint src` |
| Tests | `pnpm test`, `vitest` |

### Step 2: Run All Checks

Delegate to sub-agents **in parallel** for efficiency:

1. Launch **test-runner** and **check-runner** simultaneously using Task tool
2. Wait for both to complete
3. Review their summaries

**Why sub-agents?**
- Parallel execution is faster
- Summaries show what failed (test name, file:line, error message)
- Isolates verbose output from main context

**If you need more detail:** Re-run the specific failing test/check in main context to see full output.

### Step 3: Handle Failures

**If checks fail on NEW code you wrote:**
1. Fix the issue
2. Re-run ALL checks (not just the failing one)
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

After all checks pass, capture the output for the PR description:

```markdown
## Verification

| Check | Result |
|-------|--------|
| Typecheck | ✓ No errors |
| Lint | ✓ No errors (X warnings) |
| Tests | ✓ X passed, 0 failed |

Run at: [timestamp]
```

Include this in the PR description so reviewers know verification was done.

## Red Flags — STOP

If you catch yourself thinking:
- "Should pass" (without fresh evidence)
- "I'll fix that after the PR"
- "That failure is unrelated"
- "It's a small change, no need to verify"

**STOP.** Run verification. Show evidence.

## Only After Passing

Create PR: `gh pr create --draft`
