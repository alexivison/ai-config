---
name: review-team
description: >-
  Spawn an adversarial reviewer teammate via Agent Teams to stress-test code changes.
  Runs concurrently with Codex review after critics approve. Focuses on failure modes,
  edge cases, input validation gaps, race conditions, and security surface. Advisory
  only — produces no gating markers. Requires CLAUDE_TEAM_REVIEW=1 environment variable.
user-invocable: false
---

# Review Team — Adversarial Reviewer

Spawns one Agent Teams teammate that tries to break the code while Codex performs deep review. Both run concurrently; no code edits until both return (or timeout).

## Preflight

All checks must pass. If any fail, log the reason and proceed Codex-only (no blocking).

1. `CLAUDE_TEAM_REVIEW=1` environment variable is set
2. Claude Code version supports Agent Teams (`claude --version` >= 1.0.74)
3. Running in main Paladin context (not inside a sub-agent — no `subagent_type` in environment)

Skip silently if preflight fails. Log to evidence-trace.log:
```
timestamp | review-team | SKIP:reason | session_id
```

## When to Invoke

After critics APPROVE (both code-critic and minimizer), immediately after dispatching Codex review. Step 7b in task-workflow.

## Teammate Role — Adversarial Reviewer

The teammate's sole purpose is to try to break the code. Focus areas:

- Failure modes and error paths
- Edge cases the tests don't cover
- Input validation gaps
- Race conditions and state corruption
- "What's the worst that happens if X fails?"
- Security surface (injection, privilege escalation, data leakage)

## Display Mode

The adversarial reviewer is short-lived and read-only — it does not need its own pane.
**Always use `in-process` mode** to avoid spawning new tmux windows/panes.

Before creating the team, ensure the session uses in-process mode. Since `teammateMode`
cannot be set per-spawn, the Paladin must be running in a tmux session where `auto`
would default to split panes. Override by checking/setting the flag before `TeamCreate`:

```
# In the Agent tool spawn, no extra step needed — in-process is the default
# when not in tmux. But since we ARE in tmux, we must be explicit.
```

**Implementation:** When spawning the teammate via the `Agent` tool, there is no
per-spawn display mode parameter. The `teammateMode` setting applies session-wide.
If the current session defaults to split panes (tmux), accept this but note that
`in-process` is preferred for single short-lived reviewers.

## Spawn Prompt

Include in the teammate prompt:

1. The working tree diff against merge-base (`git diff "$(git merge-base HEAD main)"`) — this captures uncommitted changes since step 7b runs before commit
2. TASK scope boundaries (in-scope and out-of-scope files)
3. Instruction: produce concise findings (max 20 lines) with `file:line` references
4. Instruction: classify each finding as `[must]` (correctness/security) or `[should]` (robustness)
5. Instruction: if no issues found, return `**APPROVE**`

## Concurrency Rule

**BARRIER:** No code edits until BOTH Codex AND adversarial reviewer return (or 5-minute timeout).

The lead (Paladin) should toggle delegate mode during team review to avoid implementing instead of coordinating.

## Timeout

If the reviewer does not complete within 5 minutes, proceed with Codex findings only. Log timeout:
```
timestamp | review-team | TIMEOUT | session_id
```

## Synthesis

After both return, triage the UNION of Codex + reviewer findings using standard severity classification:
- **Blocking:** correctness bug, crash, security HIGH/CRITICAL → fix + re-run
- **Non-blocking:** robustness, style → note only
- **Out-of-scope:** pre-existing issues → reject

Reviewer findings are **advisory** — they create no gating markers and block no gates.

## Auditability

No marker file — Agent Teams lacks per-teammate hooks, and markers must be hook-created per `execution-core.md`. Completion is logged to `evidence-trace.log` via the skill's preflight/completion logging:
```
timestamp | review-team | COMPLETED | session_id
```

## Cleanup

After synthesis, shut down the teammate and clean up the team. Do not leave orphaned team sessions.
