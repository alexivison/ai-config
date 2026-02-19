# Autonomous Flow Reference

When executing a task from TASK*.md, **do not stop until PR is created** (or a valid pause condition is met).

## The Flow

**Code workflow:** `/write-tests → implement → checkboxes → [code-critic + minimizer] → codex → /pre-pr-verification → commit → PR`


## Decision Matrix

See [execution-core.md](execution-core.md) for the complete matrix.

## Violation Patterns

| Pattern | Correct Action |
|---------|---------------|
| "Tests pass." [stop] | Continue to checkboxes/critics |
| "Code-critic approved." [stop] | Continue to minimizer (or codex if both done) |
| "All checks pass." [stop] | Continue to commit/PR |
| "Ready to create PR." [stop] | Just create it |
| "Should I continue?" | Just continue |
| Chasing non-blocking critic nits for 2+ iterations | Triage by severity, note and move on (cap is 1 round) |
| Implementing every codex finding without triage | Classify as blocking/non-blocking/out-of-scope first |
| Re-running full cascade after one-line codex fix | Use tiered re-review (test-runner only for targeted swaps) |
| Critic oscillating (reverse own prior feedback) | Main agent decides, proceed |

## Enforcement

**Code PRs** require all markers: pre-pr-verification, code-critic, minimizer, codex, test-runner, check-runner, security-scanner.

## Checkpoint Markers

Created by `agent-trace.sh` (sub-agents) and `codex-trace.sh` (codex verdict via Bash hook). The `/tmp/claude-codex-{session_id}` marker is created by `codex-trace.sh` when `codex-verdict.sh approve` is run.

## Post-PR Changes

1. Make changes in same branch
2. Re-run `/pre-pr-verification` — MANDATORY
3. Amend commit, force-push with `--force-with-lease`

**Rule:** No post-PR changes without re-verification.
