# Task 5 — Update settings.json and install.sh

**Dependencies:** Task 2, Task 3

## Goal

Wire the renamed hooks and transport scripts into `settings.json` (permissions + hook paths) and make `install.sh` / `uninstall.sh` companion-aware.

## Scope Boundary

**In scope:**
- `claude/settings.json`: Update hook command paths from `codex-*` to `companion-*`; update Bash permissions for `tmux-companion.sh`
- `install.sh`: Replace `setup_codex()` with a companion-aware loop that reads the registry (or defaults to Codex)
- `uninstall.sh`: Remove companion symlinks generically

**Out of scope:**
- Hook logic changes (already done in Task 3)
- Transport logic changes (already done in Task 2)
- Workflow / CLAUDE.md updates (Task 7)

**Design References:** N/A (non-UI task)

## Files to Create/Modify

| File | Action |
|------|--------|
| `claude/settings.json` | Modify — hook paths, permissions |
| `install.sh` | Modify — companion-aware setup |
| `uninstall.sh` | Modify — companion-aware cleanup |

## Requirements

**Functionality:**
- `settings.json` hooks section: Replace all `codex-gate.sh` → `companion-gate.sh`, `wizard-guard.sh` → `companion-guard.sh`, `codex-trace.sh` → `companion-trace.sh` in command paths
- `settings.json` permissions: Replace `tmux-codex.sh` path with `tmux-companion.sh` path in the allow list
- `install.sh`: The `setup_codex()` function becomes `setup_companions()` which:
  - Always sets up the `codex/` symlink (it's still the default companion config directory)
  - Reads `.party.toml` if present for additional companions
  - Prompts for each companion CLI installation and auth
  - Keeps the same interactive prompt UX
- `uninstall.sh`: Remove `~/.codex` and any other companion config symlinks

**Key gotchas:**
- The transition stubs from Task 3 (old hook names → new) can be removed once settings.json points to new names
- `settings.json` is the file that actually wires hooks to Claude Code — this task is what makes the renames "live"
- Codex config directory (`~/.codex`) stays as a symlink regardless — it's Codex's own config, not ours to rename

## Tests

- `settings.json` contains no references to `codex-gate.sh`, `wizard-guard.sh`, or `codex-trace.sh`
- `settings.json` permissions reference `tmux-companion.sh`
- `install.sh --symlinks-only` creates companion symlinks
- `uninstall.sh` removes companion symlinks

## Acceptance Criteria

- [ ] `settings.json` hook paths all point to `companion-*` named hooks
- [ ] `settings.json` permissions allow `tmux-companion.sh`
- [ ] `install.sh` sets up companions from registry/defaults
- [ ] `uninstall.sh` cleans up companion symlinks
- [ ] Codex config symlink (`~/.codex`) still created (backward compatible)
