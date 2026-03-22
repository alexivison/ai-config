# Task 12 — Build Worker Sidebar View

**Dependencies:** Task 7, Task 9, Task 11 | **Issue:** TBD

---

## Goal

Finish the worker and standalone sidebar experience inside `party-cli`: Codex status, evidence summary, session information, offline handling, and a guarded peek popup. This task also defines the runtime bridge from retained shell Codex transport into the Go sidebar.

## Scope Boundary (REQUIRED)

**In scope:**
- Define the `codex-status.json` schema and file-location contract (see sub-scope below)
- Implement write calls in `tmux-codex.sh` (dispatch/in-progress) and `tmux-claude.sh` (completion/idle)
- Implement the final worker/standalone sidebar rendering that reads `codex-status.json`
- Summarize recent evidence state and session metadata
- Add guarded Codex peek popup behavior
- Handle offline or stale Codex window states without crashing or lying

**`codex-status.json` sub-scope (blocking — must land before sidebar read side):**
- **Schema definition:** `{ "state": "idle"|"working"|"error", "target": "<file-or-description>", "mode": "review"|"plan-review"|"prompt"|null, "verdict": "APPROVE"|"REQUEST_CHANGES"|"NEEDS_DISCUSSION"|null, "started_at": "<ISO-8601>", "finished_at": "<ISO-8601>"|null, "error": "<message>"|null }`
- **File location:** `party_runtime_dir($session)/codex-status.json` (i.e., `/tmp/<session>/codex-status.json` — consistent with the existing transient-state model in `party-lib.sh:14-17`)
- **Write side — `tmux-codex.sh`:** On dispatch, write `{state: "working", target, mode, started_at}`. On transport error, write `{state: "error", error}`.
- **Write side — `tmux-claude.sh`:** On completion callback, write `{state: "idle", verdict, finished_at}`. On timeout/error, write `{state: "error", error, finished_at}`.
- **Atomicity:** Write to a `.tmp` file and `mv` to final path to prevent partial reads by the Go sidebar.

**Out of scope (handled by other tasks):**
- Master tracker interactions
- Final shell-wrapper retirement
- Codex transport migration away from `tmux-codex.sh`

**Cross-task consistency check:**
- The status-file contract introduced here must be written by retained shell transport and consumed by the Go sidebar
- Sidebar actions should reuse tmux/message services from earlier tasks rather than spawning fresh shell calls

## Reference

Files to study before implementing:

- `docs/projects/sidebar-tui/PLAN.md` — absorbed sidebar behaviors worth keeping
- `claude/skills/codex-transport/scripts/tmux-codex.sh` — retained transport and status-writer location
- `claude/hooks/lib/evidence.sh` — evidence source model
- `tools/party-tracker/main.go` — existing narrow-width rendering patterns
- `tools/party-tracker/workers.go` — capture and snippet precedent

## Design References (REQUIRED for UI/component tasks)

- `../diagrams/session-layouts.svg`
- `../diagrams/data-flow.svg`

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
| `tools/party-cli/internal/tui/sidebar.go` | Create |
| `tools/party-cli/internal/tui/sidebar_status.go` | Create |
| `tools/party-cli/internal/tui/sidebar_popup.go` | Create |
| `tools/party-cli/internal/tui/*_test.go` | Modify or create |
| `claude/skills/codex-transport/scripts/tmux-codex.sh` | Modify (write dispatch/in-progress status) |
| `codex/skills/claude-transport/scripts/tmux-claude.sh` | Modify (write completion/idle status, last verdict) |

## Requirements

**Functionality:**
- Sidebar shows Codex state, target, last verdict summary, and session context
- Sidebar reads a structured runtime status file instead of scraping raw pane output alone
- Sidebar can open a guarded read-only peek popup for Codex
- Offline or stale Codex window/session states render safely and clearly
- Evidence summaries remain faithful to the simplified evidence model

**Key gotchas:**
- Keep the status-file format small and explicit; this is a bridge contract, not a dumping ground
- Do not let a missing status file or unavailable Codex window crash the TUI
- **Two-script status contract (blocking):** `tmux-codex.sh` only owns Claude→Codex dispatch (`tmux-codex.sh:30-40`, `:97-104`). Completion notifications come back through `tmux-claude.sh` (`codex/skills/claude-transport/scripts/tmux-claude.sh:6-28`). Both scripts must write to the same status file: dispatch writes `{state: "working", target: "...", started_at: "..."}`, completion writes `{state: "idle", verdict: "...", finished_at: "..."}`.

## Tests

Test cases:
- **Write side — `tmux-codex.sh`:** dispatch writes well-formed `codex-status.json` with `state=working`, correct `target`/`mode`/`started_at`; transport error writes `state=error`
- **Write side — `tmux-claude.sh`:** completion writes `state=idle` with `verdict`/`finished_at`; timeout writes `state=error`
- **Write side — atomicity:** concurrent reads never see partial JSON (verify `.tmp` + `mv` pattern)
- **Read side — parse and render:** sidebar correctly renders each state (`working`, `idle`, `error`)
- **Read side — missing or stale status file:** renders offline state without crash
- Evidence summary render for recent approval/dispute states
- Peek popup command construction and unavailable-Codex guard behavior

## Acceptance Criteria

- [ ] Worker/standalone sidebar view is fully rendered in `party-cli`
- [ ] `tmux-codex.sh` writes dispatch/in-progress status to `codex-status.json`
- [ ] `tmux-claude.sh` writes completion/idle status with last verdict to `codex-status.json`
- [ ] Offline and unavailable Codex states are handled gracefully
- [ ] Sidebar tests pass
