# Task 7 — Absorb Tracker Runtime Into TUI Foundation

**Dependencies:** Task 5, Task 6 | **Issue:** TBD

---

## Goal

Turn the existing tracker into a reusable TUI foundation inside `party-cli`. This task builds the shared Bubble Tea shell, styling, polling cadence, and mode selection that later worker-sidebar and master-tracker views shall fill in.

## Scope Boundary (REQUIRED)

**In scope:**
- Create the shared Bubble Tea application shell in `internal/tui`
- Reuse `party-tracker` styling, polling cadence, and narrow-width rendering patterns
- Add auto-selection between worker/standalone sidebar mode and master tracker mode
- Support an explicit `--session` override for testability and local operator use

**Out of scope (handled by other tasks):**
- Final worker sidebar widgets such as Codex status and peek popup
- Final master tracker actions
- Session-launch integration in shell wrappers

**Cross-task consistency check:**
- The view-selection contract created here is what Task 9 will launch in pane `0`
- Task 12 and Task 13 must extend this model rather than creating separate TUI programs

## Reference

Files to study before implementing:

- `tools/party-tracker/main.go` — current model/update/view structure
- `tools/party-tracker/workers.go` — worker refresh pattern
- `tools/party-tracker/actions.go` — action wiring style

## Design References (REQUIRED for UI/component tasks)

- `../diagrams/end-state-architecture.svg`
- `../diagrams/session-layouts.svg`

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
| `tools/party-cli/internal/tui/app.go` | Create |
| `tools/party-cli/internal/tui/model.go` | Create |
| `tools/party-cli/internal/tui/style.go` | Create |
| `tools/party-cli/internal/tui/*_test.go` | Create |
| `tools/party-tracker/main.go` | Reference only, or modify later if a compatibility wrapper is needed |

## Requirements

**Functionality:**
- `party-cli` TUI can boot with a shared model and polling loop
- Width-adaptive rendering and styling reuse the tracker patterns rather than starting over
- The TUI can determine whether the current session should render a worker sidebar or a master tracker shell
- Tests can force a specific session id without requiring live auto-discovery

**Key gotchas:**
- This task should stop at the foundation. Placeholder or skeletal panels are acceptable; final widgets belong to later tasks
- Keep the TUI state model thin enough that CLI commands do not need to import UI concerns

## Tracker Migration Checklist

What carries over from `tools/party-tracker/` vs. what gets rebuilt:

| Pattern | Source | Action |
|---------|--------|--------|
| **Bubble Tea model/update/view cycle** | `main.go:45-57` (model struct), `:77-110` (Init/Update), `:252-359` (View) | **Reuse pattern** — same `model` → `Init` → `Update` → `View` architecture, but generalize for mode selection (tracker vs sidebar) |
| **Lip Gloss styles and ANSI palette** | `main.go:14-30` (color vars + style defs) | **Reuse directly** — copy palette constants and style vars into `internal/tui/style.go`; terminal-theme-inheriting ANSI colors are portable |
| **Width-adaptive rendering** | `main.go:244-250` (`innerWidth`), `:259` (`compact := width < 50`), `:287-299` (compact status variants), `:321-331` (snippet skip at `width < 30`) | **Reuse logic** — extract `innerWidth()` and `compact` threshold into shared helpers; later views reuse them |
| **Tick/polling mechanism** | `main.go:42-43` (msg types), `:71-75` (`tickCmd` at 3s), `:89-97` (tick handler refreshes workers) | **Reuse pattern** — same `tea.Tick` cadence; generalize the tick handler to refresh whichever view is active |
| **Key binding patterns** | `main.go:112-198` (normal mode nav: j/k/enter/q), `:200-229` (input mode: esc/enter), `:361-386` (manifest scroll) | **Reuse pattern** — extract shared nav keys (j/k/q/esc) into a base keymap; mode-specific bindings added by tracker/sidebar views |
| **Text input for relay/broadcast/spawn** | `main.go:34-40` (mode enum), `:200-229` (`updateInput`), `:340-351` (footer prompt) | **Rebuild in Task 13** — master tracker actions are out of scope for Task 7; the input infrastructure can wait |
| **Worker data loading** | `workers.go:13-18` (Worker struct), `:21-24` (manifest struct), `:26-36` (stateRoot/manifestPath), `:66-103` (fetchWorkers) | **Rebuild in Go** — the Worker struct and manifest reader move to `internal/state/` (Task 5); Task 7 consumes them via service interface, not direct file I/O |
| **Pane capture / snippet extraction** | `workers.go:106-153` (`captureSnippet` — tmux pane scraping) | **Rebuild in Go** — move to `internal/tmux/` (Task 6); Task 7 calls it through the tmux service |
| **Action wiring (attach/relay/spawn/stop/delete)** | `actions.go:23-70` (shell-out to `party.sh` / `party-relay.sh`) | **Rebuild in Task 13** — actions are out of scope for Task 7; lifecycle commands land in Task 10 |
| **Session script resolution** | `actions.go:12-20` (`sessionScript` via `PARTY_REPO_ROOT`) | **Rebuild in Task 6** — tmux service owns script/path resolution |
| **Manifest viewer (scroll overlay)** | `main.go:361-417` (`updateManifest`/`viewManifest`) | **Defer** — nice-to-have for master tracker (Task 13); not needed in foundation |

## Tests

Test cases:
- TUI boot path in no-arg mode
- Mode selection for master versus worker/standalone sessions
- Narrow-width rendering behavior
- Poll tick refresh without a live tmux server

## Acceptance Criteria

- [x] `party-cli` has a shared Bubble Tea foundation inside `internal/tui`
- [x] Existing tracker styling and width behavior are reused
- [x] TUI mode selection between worker and master exists
- [x] TUI foundation tests pass
