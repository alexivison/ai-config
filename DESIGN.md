# Ledger-Based Workflow Evidence Design

## Objective

Migrate workflow truth from ephemeral `/tmp` marker files to an append-only event ledger, while keeping marker compatibility during rollout.

## Goals

1. Make gate decisions reproducible from durable evidence.
2. Preserve current behavior during migration (shadow mode first).
3. Keep rollback simple with a runtime mode switch.

## Non-Goals

1. Rewriting tmux transport in this migration.
2. Changing reviewer policy semantics (only evidence storage and evaluation).
3. Building remote storage in v1 (local per-session ledger first).

## Existing Standards (REQUIRED)

| Pattern | Location | How It Applies |
|---------|----------|----------------|
| Hook-based enforcement in `PreToolUse` | `claude/settings.json:86-111` | Ledger evaluator is wired into existing hook chain, not a new runtime. |
| Marker creation from post-tool traces | `claude/hooks/agent-trace.sh:106-129`, `claude/hooks/codex-trace.sh:50-75`, `claude/hooks/skill-marker.sh:24-29` | Existing marker producers become dual-write producers (marker + ledger event). |
| Gate checks in dedicated scripts | `claude/hooks/pr-gate.sh:46-60`, `claude/hooks/codex-gate.sh:26-57` | Gate decision logic is centralized in one shared ledger evaluator library. |
| Edit invalidation behavior | `claude/hooks/marker-invalidate.sh:35-55` | Edit invalidation emits `code_changed` ledger events. |
| Session lifecycle cleanup | `claude/hooks/session-cleanup.sh:10-16` | Session start keeps cleanup, but extends to ledger retention/rotation policy. |
| Fail-open parsing pattern | `claude/hooks/agent-trace.sh:14-26`, `claude/hooks/codex-trace.sh:14-37` | Ledger write path follows the same defensive parse pattern. |

## Architecture Overview

```
PostToolUse hooks
  -> normalize hook outcome
  -> append immutable event to ledger (source of truth)
  -> optionally touch legacy marker (compatibility)

PreToolUse gates
  -> evaluate ledger state for current session/repo/branch/head
  -> deny/allow with explicit missing evidence list
  -> (during shadow mode) compare against legacy marker result and log mismatch
```

## File Structure

```
claude/
├── hooks/
│   ├── lib/
│   │   ├── ledger.sh               # New: append + schema validation helpers
│   │   └── ledger-eval.sh          # New: derive gate state from events
│   ├── agent-trace.sh              # Modify: dual-write markers + events
│   ├── codex-trace.sh              # Modify: dual-write markers + events
│   ├── skill-marker.sh             # Modify: dual-write markers + events
│   ├── marker-invalidate.sh        # Modify: append code_changed event
│   ├── pr-gate.sh                  # Modify: marker mode -> shadow -> ledger mode
│   ├── codex-gate.sh               # Modify: marker mode -> shadow -> ledger mode
│   ├── session-cleanup.sh          # Modify: ledger retention cleanup
│   └── tests/
│       ├── test-ledger-lib.sh      # New
│       ├── test-ledger-eval.sh     # New
│       └── test-ledger-gates.sh    # New
└── state/
    └── ledger/
        └── <session_id>.jsonl      # Runtime output (not committed)
```

Legend: `New` = create, `Modify` = edit existing

## Ledger Data Model (v1)

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `v` | integer | yes | Schema version (`1`) |
| `ts` | string | yes | UTC timestamp, ISO-8601 |
| `session` | string | yes | Claude session id |
| `repo` | string | yes | Absolute git root |
| `branch` | string | yes | Current branch |
| `head` | string | yes | Current `git rev-parse --short HEAD` |
| `event` | string | yes | One of canonical event types |
| `actor` | string | yes | hook/agent source (`test-runner`, `codex-trace`, etc.) |
| `meta` | object | no | Event-specific details |

### Canonical Event Types (v1)

1. `code_critic_approved`
2. `minimizer_approved`
3. `tests_passed`
4. `checks_passed`
5. `codex_review_completed`
6. `codex_approved`
7. `pre_pr_verified`
8. `code_changed`

## Data Flow

### Write Path

1. Hook receives tool payload.
2. Hook validates/normalizes outcome into canonical event type.
3. Hook appends one JSON line to `~/.claude/state/ledger/<session>.jsonl` atomically.
4. During compatibility phases, hook also writes legacy marker files.

### Read Path

1. Gate loads ledger entries for `session + repo + branch`.
2. Gate computes `latest_code_changed_boundary`.
3. Gate verifies required evidence events occur after boundary.
4. Gate returns:
   - `allow=true` when complete
   - `allow=false` + explicit missing list when incomplete

## Data Transformation Points (REQUIRED)

| Layer Boundary | Code Path | Function | Input -> Output | Location |
|----------------|-----------|----------|------------------|----------|
| Hook JSON -> typed fields | Shared | `jq` extraction per hook | Hook stdin JSON -> normalized shell vars | `claude/hooks/agent-trace.sh:23-49`, `claude/hooks/codex-trace.sh:19-48`, `claude/hooks/skill-marker.sh:8-10` |
| Verdict text -> evidence event | Agent path | verdict mapping | response text -> `*_approved` / `*_passed` | `claude/hooks/agent-trace.sh:56-75` |
| Command stdout -> codex events | Codex path | command/response mapping | bash tool response -> `codex_review_completed` / `codex_approved` | `claude/hooks/codex-trace.sh:50-75` |
| Skill invocation -> verification event | Skill path | skill case mapping | skill id -> `pre_pr_verified` | `claude/hooks/skill-marker.sh:24-29` |
| File edit signal -> invalidation event | Edit path | invalidate hook | file path -> `code_changed` | `claude/hooks/marker-invalidate.sh:19-55` |
| Event stream -> gate decision | Gate path | ledger evaluator | ledger jsonl -> `{allow, missing, boundary}` | New `claude/hooks/lib/ledger-eval.sh` |

## Integration Points (REQUIRED)

| Point | Existing Code | New Interaction |
|-------|---------------|-----------------|
| PR gate entry | `claude/hooks/pr-gate.sh:26-73` | Replace marker-only checks with `ledger-eval` in shadow then enforce mode. |
| Codex gate entry | `claude/hooks/codex-gate.sh:26-70` | Replace marker-only checks with `ledger-eval` for codex requirements. |
| Hook registration | `claude/settings.json:86-154` | Keep same hook triggers; only internals and helper sourcing change. |
| Marker invalidation | `claude/hooks/marker-invalidate.sh:35-55` | Emit `code_changed` event when invalidation happens. |

## Rollout and Modes

Use env-controlled mode:

1. `CLAUDE_LEDGER_MODE=off`  
   Marker-only behavior (current default at start).
2. `CLAUDE_LEDGER_MODE=shadow`  
   Markers still enforce; ledger evaluated in parallel; mismatches logged.
3. `CLAUDE_LEDGER_MODE=enforce`  
   Ledger enforces; markers are compatibility fallback only.

## Failure Handling

1. Ledger write failure:
   - In `off`: no effect.
   - In `shadow`: log mismatch risk but do not block.
   - In `enforce`: fail closed for gate evaluation only when required evidence cannot be computed.
2. Corrupt line in ledger:
   - Skip malformed line, continue evaluation, emit warning.
3. Session file missing:
   - Treat as no evidence, deny with explicit message.

## Verification Strategy

1. Unit-like shell tests for ledger writer and evaluator.
2. Gate simulation tests for:
   - complete happy path
   - stale evidence after `code_changed`
   - missing codex review completion
   - cross-session isolation
3. Existing hook suites remain green:
   - `tests/test-hooks.sh`
   - `tests/test-party-state.sh`
   - `tests/test-party-routing.sh`

## Backward Compatibility and Rollback

1. Keep marker writes until end of migration.
2. Rollback by setting `CLAUDE_LEDGER_MODE=off`.
3. No data migration needed; ledger is append-only and optional in `off`.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Ledger and marker verdict diverge in shadow mode | Confusing enforcement | Log diff with deterministic reason; block enforcement promotion until mismatch threshold is zero. |
| Event spam inflates session ledger | Slower gate eval | Filter by event type and by latest `code_changed` boundary; add retention in cleanup. |
| Shell JSON parsing edge cases | Incorrect events | Keep strict schema checks in `ledger.sh`; add malformed-input tests. |

## Design Decisions

| Decision | Rationale | Alternatives Considered |
|----------|-----------|-------------------------|
| JSONL append-only local ledger | Simple, auditable, shell-friendly | SQLite (stronger queries, more complexity) |
| Dual-write transition | Zero downtime and safe rollback | Big-bang marker removal (high risk) |
| Boundary-based invalidation (`code_changed`) | Mirrors existing invalidation semantics | Per-file dependency graph (overkill for v1) |
