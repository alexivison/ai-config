# Task 4 — Generalize Session Management and Manifest

**Dependencies:** Task 1

## Goal

Make session startup and manifest state companion-generic. `party.sh` creates companion windows dynamically from the registry. `party-lib.sh` resolves panes by companion name. The Go manifest supports N companions instead of Codex-specific fields.

## Scope Boundary

**In scope:**
- `party-lib.sh`: Replace `party_codex_pane_target()` with `party_companion_pane_target "$session" "$name"` and generalize `write_codex_status()` → `write_companion_status "$name"`
- `party.sh`: Iterate `companion_list` from registry during session startup; call `adapter_start` for each
- `manifest.go`: Add `Companions []CompanionState` struct; migrate `codex_thread_id` extra → companion entry
- `continue.go` (or equivalent resume path): Iterate companions for resumption instead of hardcoded `codex_thread_id`
- Runtime state files: `codex-status.json` → `companion-status-<name>.json`

**Out of scope:**
- Transport changes (Task 2)
- Hook changes (Task 3)
- settings.json / install.sh (Task 5)
- Workflow doc updates (Task 7)

**Design References:** N/A (non-UI task)

## Files to Create/Modify

| File | Action |
|------|--------|
| `session/party-lib.sh` | Modify — generic pane resolution and status writing |
| `session/party.sh` | Modify — dynamic companion window setup |
| `tools/party-cli/internal/state/manifest.go` | Modify — companions array |
| `tools/party-cli/cmd/continue.go` | Modify — multi-companion resume |

## Requirements

**Functionality:**
- `party_companion_pane_target "$session" "$name"`: Same logic as current `party_codex_pane_target` but parameterized by companion name. Sidebar layout uses `companion_pane_window "$name"` from registry. Classic layout uses `party_role_pane_target "$session" "$name"`.
- `write_companion_status "$name" "$state" "$mode" ...`: Same as `write_codex_status` but writes to `companion-status-<name>.json`.
- `party.sh` startup: Source registry, iterate `companion_list`, for each call `adapter_start "$name" "$session" "$window" "$cwd"`. Skip companions whose CLI isn't installed (warn, don't fail).
- Manifest `CompanionState`: `Name string`, `CLI string`, `Role string`, `Pane string`, `Window int`, `ThreadID string` (for session resumption).
- Resume path: Iterate `manifest.Companions` to find thread IDs for each companion, pass to `adapter_start`.
- Backward compatibility: If manifest has `codex_thread_id` in extras (old format), migrate it to a `Companions` entry on read.

**Key gotchas:**
- `party_codex_pane_target` is called from `tmux-codex.sh` — after Task 2 renames transport, calls will come from `tmux-companion.sh`. During transition, keep the old function as an alias.
- `write_codex_status` is called from both `tmux-codex.sh` and `tmux-claude.sh` — both need to use the new name after Tasks 2 and this task land.
- The Go manifest change requires rebuilding `party-cli`.

## Tests

- `party_companion_pane_target "$session" "wizard"` returns same result as old `party_codex_pane_target`
- Session startup with two companions in `.party.toml` creates two hidden windows
- Session startup with missing companion CLI warns but doesn't fail
- Manifest round-trip: write companions array → read back → fields preserved
- Old manifest with `codex_thread_id` extra → migrated to companions on read

## Acceptance Criteria

- [ ] `party_companion_pane_target` resolves panes by companion name
- [ ] `write_companion_status` writes to `companion-status-<name>.json`
- [ ] `party.sh` creates companion windows dynamically from registry
- [ ] Missing companion CLI produces warning, not failure
- [ ] Manifest `Companions` array stores per-companion state
- [ ] Resume path iterates companions, not hardcoded Codex
- [ ] Old manifests with `codex_thread_id` are backward-compatible
