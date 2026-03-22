# Task 15 — Cut Over Wrappers And Retire Duplicate Bash

**Dependencies:** Task 12, Task 13, Task 14 | **Issue:** TBD

---

## Goal

Complete the migration without lying about the remaining shell dependency. The duplicate Bash entrypoints should now become thin wrappers or disappear, while `session/party-lib.sh` is explicitly retained as the routing library for `tmux-codex.sh` and classic shell paths.

## Scope Boundary (REQUIRED)

**In scope:**
- Reduce `party.sh`, `party-master.sh`, `party-relay.sh`, and `party-picker.sh` to thin wrappers or retire them
- Update docs and help text so `party-cli` is the primary implementation surface
- Keep `party-lib.sh` as a declared supported dependency for `tmux-codex.sh`
- Remove or freeze legacy duplicate logic once parity is proved

**Out of scope (handled by other tasks):**
- Porting Codex transport away from shell
- New TUI features beyond parity
- Additional manifest or workflow redesign

**Cross-task consistency check:**
- Wrapper cutover is only valid if all lifecycle, messaging, sidebar, tracker, and picker paths already call the shared Go services
- `party-lib.sh` must remain available for retained Codex transport and classic routing after wrapper retirement

## Reference

Files to study before implementing:

- `session/party.sh` — duplicate lifecycle entrypoint
- `session/party-master.sh` — duplicate master entrypoint
- `session/party-relay.sh` — duplicate messaging entrypoint
- `session/party-picker.sh` — duplicate picker entrypoint
- `claude/skills/codex-transport/scripts/tmux-codex.sh` — retained shell dependency boundary

## Design References (REQUIRED for UI/component tasks)

N/A (non-UI task)

## Data Transformation Checklist (REQUIRED for shape changes)

N/A (no new public or persisted shape; this is a cutover task)

## Files to Create/Modify

| File | Action |
|------|--------|
| `session/party.sh` | Modify or retire |
| `session/party-master.sh` | Modify or retire |
| `session/party-relay.sh` | Modify or retire |
| `session/party-picker.sh` | Modify or retire |
| `session/party-preview.sh` | Modify or retire if obsolete |
| `session/party-lib.sh` | Modify only as needed; retain |
| `docs/projects/harness-v2/*` | Modify if completion notes are needed |
| `tests/*` | Modify |

## Requirements

**Functionality:**
- `party-cli` becomes the primary operator and script surface
- Remaining shell wrappers delegate cleanly without duplicating business logic
- `party-lib.sh` remains supported for `tmux-codex.sh` and classic layout routing
- Legacy duplicate logic is deleted only after parity is demonstrated

**Key gotchas:**
- Do not remove `party-lib.sh`; this plan expressly keeps that dependency
- Wrapper docs and help text must not claim Codex transport has moved into Go when it hath not

## Tests

Test cases:
- Wrapper delegation for lifecycle, messaging, and picker commands
- `tmux-codex.sh` still functions after wrapper cutover
- Classic layout paths still route correctly
- Full regression suite across shell, hooks, and Go packages

## Acceptance Criteria

- [x] `party-cli` is the primary implementation surface
- [x] Legacy Bash entrypoints are removed or reduced to thin wrappers
- [x] `party-lib.sh` remains available for retained Codex transport
- [x] Classic mode (`PARTY_LAYOUT=classic`) works correctly AFTER wrappers are thinned — full lifecycle, messaging, and layout
- [x] Sidebar mode works correctly after cutover — all views, hidden-window handling, and Codex status
- [x] `tmux-codex.sh` continues to function through `party-lib.sh` after wrapper retirement
- [x] Rollback path documented: if sidebar mode has issues, `PARTY_LAYOUT=classic` restores full pre-migration behavior without code changes
- [x] End-to-end regression suites pass after cutover (both layout modes)
