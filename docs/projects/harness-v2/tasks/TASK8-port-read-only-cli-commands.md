# Task 8 — Port Read-Only CLI Commands

**Dependencies:** Task 5, Task 6 | **Issue:** TBD

---

## Goal

Port the safest operator commands first: `list`, `status`, and `prune`. These commands prove that the new state and tmux packages are useful in real work before any mutating path depends on them.

## Scope Boundary (REQUIRED)

**In scope:**
- Add `list`, `status`, and `prune` subcommands
- Format output for human use while keeping errors explicit and testable
- Reuse shared state/discovery and tmux query packages

**Out of scope (handled by other tasks):**
- Session creation, teardown, or promotion
- Messaging commands
- Picker integration

**Cross-task consistency check:**
- `list` and `status` show all party sessions (no companion filtering needed — hidden-window model means Codex lives within the session, not in a separate one)
- Output and errors here become the basis for later picker and wrapper reuse

## Reference

Files to study before implementing:

- `session/party.sh` — current `party_list()` and prune behavior
- `session/party-lib.sh` — discovery behavior
- `tools/party-cli/internal/state/*` — shared manifest/discovery layer
- `tools/party-cli/internal/tmux/*` — shared tmux query layer

## Design References (REQUIRED for UI/component tasks)

N/A (non-UI task)

## Data Transformation Checklist (REQUIRED for shape changes)

- [ ] Proto definition (N/A unless a typed file contract is introduced)
- [ ] Proto -> Domain converter (N/A unless a typed file contract is introduced)
- [ ] Domain model struct
- [ ] Params struct(s) — check ALL variants
- [ ] Params conversion functions
- [ ] Any adapters between param types

## Files to Create/Modify

| File | Action |
|------|--------|
| `tools/party-cli/cmd/list.go` | Create |
| `tools/party-cli/cmd/status.go` | Create |
| `tools/party-cli/cmd/prune.go` | Create |
| `tools/party-cli/cmd/*_test.go` | Create |

## Requirements

**Functionality:**
- `party-cli list` shows only visible user-facing sessions
- `party-cli status` reports manifest and tmux state clearly
- `party-cli prune` removes stale manifests with explicit output and exit behavior (no companion orphan sweep needed — hidden-window model means session death kills all windows automatically)
- Commands remain safe to run while the Bash harness still owns mutations

**Key gotchas:**
- No companion filtering needed — all sessions are user-facing under the hidden-window model
- Keep output stable enough for downstream scripts or wrapper tests

## Tests

Test cases:
- Session listing shows all party sessions (no filtering needed)
- Status output for active, stale, and missing sessions
- Prune behavior across active and stale manifest sets
- Prune removes stale manifests (no companion orphan sweep — hidden-window model auto-cleans)

## Acceptance Criteria

- [ ] `party-cli list`, `status`, and `prune` exist and are buildable
- [ ] Read-only commands use shared state and tmux packages
- [ ] All sessions shown are user-facing (no companion filtering needed)
- [ ] Read-only command tests pass
