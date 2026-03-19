---
name: quick-fix-workflow
description: >-
  Fast workflow for non-behavioral changes: config edits, dependency bumps,
  typo/comment fixes, CI/build tweaks, docs-with-code. Skips critics, codex,
  and adversarial review — requires only test-runner + check-runner. Use when
  the user asks for a small config change, dependency update, typo fix, CI tweak,
  or any change that doesn't touch runtime logic. Also use when the user says
  "quick fix", "small change", or invokes /quick-fix-workflow. REJECT and suggest
  task-workflow or bugfix-workflow if the change modifies runtime logic, control
  flow, API surface, or security-relevant code.
user-invocable: true
---

# Quick Fix Workflow

Lightweight workflow for non-behavioral changes. Skips the full review cascade
(critics, codex, adversarial review) because the change doesn't affect runtime
behavior. The tiered PR gate requires only test-runner + check-runner evidence
plus explicit quick-tier authorization from this skill.

## Scope Constraints (Enforced)

These constraints exist because the quick tier skips code review. Behavioral
changes without review are a safety hole — the constraints prevent this.

**Allowed changes:**
- Config file edits (non-runtime: CI, linting, formatting, editor config)
- Dependency bumps (package.json, go.mod, Cargo.toml — version only, not new deps)
- Typo/comment fixes in code or docs
- CI/build pipeline tweaks
- Docs-with-code changes (README, CHANGELOG alongside a non-behavioral code edit)

**REJECT if the change touches ANY of these — suggest task-workflow or bugfix-workflow:**
- Runtime logic or control flow
- API surface (new/changed endpoints, exports, function signatures)
- Security-relevant code (auth, crypto, permissions, input validation)
- Feature flags or gates
- New dependencies (adding, not bumping)
- Database schemas or migrations

**Size guardrail (hard limit):**
- More than 30 changed lines (additions + deletions) → reject
- More than 3 changed files → reject
- Any new files → reject

If any guardrail trips, explain why and suggest the appropriate full workflow.

## Pre-Fix Gate

**Before writing ANY code:**

1. **Create worktree** — `git worktree add ../repo-branch-name -b branch-name`
2. **Scope check** — Verify the change is non-behavioral per the constraints above
3. **If uncertain** — Ask the user. When in doubt, use task-workflow instead

State the scope assessment before proceeding.

## Execution Flow

After passing the gate, execute continuously — **no stopping until PR is created**.

1. **Implement** the change
2. **Size guardrail** — Check diff stats. If over threshold, stop and suggest task-workflow
3. **Write quick-tier evidence** — Append `quick-tier` evidence to the session log:
   ```bash
   source ~/.claude/hooks/lib/evidence.sh
   append_evidence "$SESSION_ID" "quick-tier" "AUTHORIZED" "$CWD"
   ```
   This signals to the PR gate that this change was explicitly routed through the quick-fix workflow. The gate will not apply the quick tier without this evidence — size alone is insufficient.
4. **Run code-critic** — Single pass. Triage any blocking findings before proceeding.
5. **Run test-runner + check-runner** — Launch both sub-agents in parallel
6. **Commit & PR** — Create commit and draft PR

## What This Workflow Skips (and Why That's OK)

- **No RED phase** — Non-behavioral changes don't need failing-then-passing tests
- **No minimizer** — The change is already size-gated; minimality is inherent
- **No codex review** — The code-critic catches quality issues; codex deep-review is overkill for config/typo changes
- **No adversarial review** — No security or correctness surface to probe
- **No /pre-pr-verification** — test-runner + check-runner cover the same ground

The safety net is the code-critic plus the test suite. The critic catches anything a non-behavioral change shouldn't be doing; tests catch regressions.

## Core Reference

See [execution-core.md](~/.claude/rules/execution-core.md) for the evidence system and PR gate requirements.
