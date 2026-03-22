# Task 9 — Launch Party CLI Pane And Sidebar Layouts

**Dependencies:** Task 6, Task 7, Task 8 | **Issue:** TBD

---

## Goal

Put the unified binary into live sessions. Window 1 (pane `0`) should now run `party-cli`, master sessions should show the tracker shell, worker and standalone sessions should support the sidebar shell as an opt-in layout (`PARTY_LAYOUT=sidebar`), Codex should move to a hidden window 0 within the same tmux session when sidebar mode is active, the tmux status bar should visually distinguish agent windows from workspace windows, and `PARTY_LAYOUT=classic` must remain the default until Task 10 proves sidebar-mode promotion works.

## Scope Boundary (REQUIRED)

**In scope:**
- Update shell launchers to create window 0 (Codex, hidden) and window 1 (workspace panes) in sidebar mode
- Start `party-cli` in window 1 pane `0`
- Direct master launches do NOT create window 0 (matching current behavior — masters have no Codex pane); promoted masters retain window 0 from their worker/standalone origin (handled by Task 10)
- Support sidebar layout (opt-in via `PARTY_LAYOUT=sidebar`) as sidebar | claude | shell (window 1) with Codex in hidden window 0
- Preserve `PARTY_LAYOUT=classic` as a first-class escape hatch (single window, no hidden Codex window)
- Update shell routing helpers so retained Codex transport targets window 0 (`${session}:0`) when sidebar mode is active
- Configure tmux status bar to visually distinguish agent windows (window 0 — dimmed/subtle, left side) from workspace windows (window 1+ — normal/bright, right side) via the existing theme in `tmux/tmux.conf`
- Set window 1 as the active window on session launch so the user sees the workspace, not the Codex window

**Out of scope (handled by other tasks):**
- Final worker sidebar widgets
- CLI lifecycle command ownership
- Final wrapper cutover

**Cross-task consistency check:**
- Window 0/1 conventions created here must match the window-management helpers from Task 6
- Task 12 assumes the sidebar shell launched here already exists and can read runtime status later
- Status bar theming must be configurable via existing `tmux/tmux.conf` and not require per-session manual setup

## Reference

Files to study before implementing:

- `session/party.sh` — current standard/worker launch flow
- `session/party-master.sh` — current master launch flow
- `session/party-lib.sh` — role routing and session discovery helpers
- `claude/skills/codex-transport/scripts/tmux-codex.sh` — retained shell caller that must target window 0 in sidebar mode
- `tmux/tmux.conf` — existing tmux theme where status bar styling should be configured

## Design References (REQUIRED for UI/component tasks)

- `../diagrams/session-layouts.svg`
- `../diagrams/before-after.svg`

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
| `session/party.sh` | Modify — create window 0 (Codex) + window 1 (workspace) in sidebar mode |
| `session/party-master.sh` | Modify — launch party-cli tracker in pane 0 (no window 0 for direct masters) |
| `session/party-lib.sh` | Modify — window-based routing helpers |
| `claude/skills/codex-transport/scripts/tmux-codex.sh` | Modify — target `${session}:0` in sidebar mode |
| `tmux/tmux.conf` | Modify — add status bar styling to distinguish agent vs. workspace windows |
| `tests/test-party-routing.sh` | Modify |
| `tests/test-party-master.sh` | Modify |
| `tests/test-party-sidebar-layout.sh` | Create |

## Requirements

**Functionality:**
- New sessions create window 0 (Codex, hidden) and window 1 (party-cli | Claude | Shell) in sidebar mode
- Window 1 is the active window on session launch
- Worker and standalone sessions support sidebar layout (opt-in via `PARTY_LAYOUT=sidebar`) with Codex in hidden window 0; `PARTY_LAYOUT=classic` remains the default until Task 10 proves promotion parity
- Direct master sessions use tracker layout with no window 0 (no Codex pane, matching current behavior); promoted masters retain window 0 from their worker/standalone origin
- `PARTY_LAYOUT=classic` preserves the existing visible-Codex behavior (single window, no hidden window 0)
- Retained Codex transport targets `${session}:0` in sidebar mode and the classic Codex pane in classic mode
- tmux status bar visually distinguishes agent windows (window 0, dimmed/subtle) from workspace windows (window 1+, bright), configurable via `tmux/tmux.conf`
- Session death automatically destroys all windows — no companion cleanup hooks or orphan sweeps needed

**Key gotchas:**
- Do not add a new persisted manifest field for Codex window location; window numbering convention is sufficient
- **Resume/continue layout:** The current manifest schema does not persist layout mode. `continue` should follow the current `PARTY_LAYOUT` env var or default, not promise to restore the original topology. If layout persistence is needed later, it can be added as a manifest field in a follow-up task.
- No orphan problem — session death kills all windows automatically, unlike companion sessions which could be orphaned
- **Promotion compatibility (deferred to Task 10):** The current shell promotion path (`session/party-master.sh:126-133`) resolves a visible `codex` role pane. Once sidebar mode removes it from the workspace window, promotion would break. Task 9 does NOT fix promotion — it defers to Task 10, which owns all lifecycle commands including `promote`. Task 9 MUST NOT break the classic promotion path: sidebar mode is additive, `PARTY_LAYOUT=classic` remains the default until Task 10 proves promotion works in sidebar mode. No independently shippable PR may leave classic promotion broken.

## Tests

Test cases:
- Sidebar opt-in launch creates window 0 (Codex, hidden) and window 1 (workspace, active) for standalone and worker sessions (`PARTY_LAYOUT=sidebar`)
- Classic default launch creates a single window with no hidden Codex window (no env var or `PARTY_LAYOUT=classic`)
- Direct master launch creates a single window (tracker | claude | shell) with no window 0
- Codex transport routing targets `${session}:0` when sidebar mode is active
- Session death destroys all windows (no orphan windows possible)
- tmux status bar shows agent windows dimmed and workspace windows bright
- Window 1 is the active window on launch (user sees workspace, not Codex)

## Acceptance Criteria

- [x] Window 0 (Codex, hidden) and window 1 (workspace, active) are created in sidebar mode
- [x] Pane `0` in window 1 launches `party-cli` in new sessions
- [x] Sidebar and classic layouts both work as designed
- [x] `tmux-codex.sh` targets window 0 in sidebar mode and classic Codex pane in classic mode
- [x] tmux status bar visually distinguishes agent windows (dimmed) from workspace windows (bright)
- [x] Shell promotion (`party.sh --promote`) continues to work in classic mode (sidebar promotion deferred to Task 10)
- [x] Session death destroys all windows — no orphan cleanup needed
- [x] Layout and routing tests pass
