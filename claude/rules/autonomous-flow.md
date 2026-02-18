# Autonomous Flow Reference

When executing a task from TASK*.md, **do not stop until PR is created** (or a valid pause condition is met).

## The Flow

**Code workflow:** `/write-tests → implement → checkboxes → [code-critic + minimizer] → wizard → /pre-pr-verification → commit → PR`

**Plan workflow:** `/brainstorm (if needed) → /plan-workflow → wizard → plan PR`

## Decision Matrix

See [execution-core.md](execution-core.md) for the complete matrix.

## Violation Patterns

| Pattern | Correct Action |
|---------|---------------|
| "Tests pass." [stop] | Continue to checkboxes/critics |
| "Code-critic approved." [stop] | Continue to minimizer (or wizard if both done) |
| "All checks pass." [stop] | Continue to commit/PR |
| "Ready to create PR." [stop] | Just create it |
| "Should I continue?" | Just continue |

## Enforcement

**Code PRs** require all markers: pre-pr-verification, code-critic, minimizer, wizard, test-runner, check-runner, security-scanner.

**Plan PRs** (branch suffix `-plan`) require: wizard marker only.

## Checkpoint Markers

Created by `agent-trace.sh`. See CLAUDE.md marker table for full list.

## Post-PR Changes

1. Make changes in same branch
2. Re-run `/pre-pr-verification` — MANDATORY
3. Amend commit, force-push with `--force-with-lease`

**Rule:** No post-PR changes without re-verification.
