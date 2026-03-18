---
name: quick-fix-workflow
description: Fast workflow for non-behavioral changes (config, deps, typos, CI). Skips critics, codex, and adversarial review. Use when the change is small and doesn't affect runtime logic.
user-invocable: true
---

# Quick Fix Workflow

Lightweight workflow for non-behavioral changes. Tiered PR gate requires only test-runner + check-runner evidence.

## Scope Constraints (Enforced)

**ONLY for non-behavioral changes:**
- Config file edits
- Dependency bumps (package.json, go.mod, etc.)
- Typo/comment fixes
- CI/build tweaks
- Docs-with-code changes

**If the change modifies ANY of these → REJECT and suggest task-workflow or bugfix-workflow:**
- Runtime logic or control flow
- API surface (new/changed endpoints, exports, signatures)
- Security-relevant code
- Feature flags or gates

**Size guardrail:**
- >30 changed lines (additions + deletions) → reject
- >3 changed files → reject
- Any new files → reject

## Execution Flow

1. **Pre-gate:** Working tree must be clean (or use --worktree)
2. **Scope check:** Verify change is non-behavioral. If not → reject with explanation
3. **Implement** the change
4. **Size guardrail:** Compute diff stats. If over threshold → reject, suggest task-workflow
5. **Run test-runner** sub-agent
6. **Run check-runner** sub-agent (parallel with test-runner)
7. **Commit and create PR** (tiered gate allows with just test-runner + check-runner)

## Non-Goals

- No RED phase (not applicable — non-behavioral changes)
- No code-critic or minimizer
- No codex review
- No adversarial review
- No /pre-pr-verification skill (test-runner + check-runner cover it)
