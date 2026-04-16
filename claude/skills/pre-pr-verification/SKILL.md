---
name: pre-pr-verification
description: >-
  Run full verification (typecheck, lint, tests) before creating a PR. Enforces
  evidence-based completion with parallel sub-agent execution (test-runner +
  check-runner). Use before any PR creation, when asked to verify changes, check
  everything passes, or as the final gate before committing. Captures verification
  evidence for the PR description.
user-invocable: false
allowed-tools: Bash, Task
---

# Pre-PR Verification

Run all checks locally before creating a PR. No PR without passing verification.

## Core Principle

**"Evidence before PR, always."** — If you haven't run verification fresh and seen it pass, you cannot create a PR.

## Ordering — Run AFTER Commit

The PR gate checks evidence against the current **committed** `diff_hash`. Re-running verification on an uncommitted diff and then committing invalidates the evidence the gate will check, and you'll have to re-run anyway. Sequence:

```
… → commit → /pre-pr-verification → gh pr create
```

Any edit (even a comment fix) after verification passes also invalidates evidence — re-run before pushing. Verification does not replace any required companion-review evidence; it only refreshes the test/check half of the PR gate.

## Process

### Step 1 — DO THIS NOW: Dispatch Sub-Agents in Parallel

Launch **test-runner** and **check-runner** in the **same message** using the Task tool — not sequentially. This is the primary action of this skill; everything else supports it.

```
Task(test-runner, …)  ←┐  same message, parallel dispatch
Task(check-runner, …) ←┘
```

Wait for both to complete, then review their summaries. Sub-agents auto-discover the project's test/lint/typecheck commands — no need to pre-identify them.

**If you need more detail:** re-run the specific failing test/check in main context to see full output.

### Step 2: Handle Failures

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

### Step 3: Capture Evidence

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
