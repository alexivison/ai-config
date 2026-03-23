# Task 2 — Restyle Worker Sidebar Shell

**Dependencies:** Task 1 | **Issue:** TBD

---

## Goal

Apply the new chrome system to the worker and standalone sidebar so it feels like scry immediately: bordered pane shell, footer-first hints, and a flat-list interior that matches the tracker's flow instead of presenting a rigid inner form layout.

## Scope Boundary (REQUIRED)

**In scope:**
- Restyle worker-mode `Model.View()` and `viewError()` around the new bordered pane helper
- Remove the current flat header/footer rules and plain dim footer text
- Replace the worker's rigid key-value form layout with a flat list body: direct value lines, section headers, and indented detail lines
- Restyle `RenderSidebar()` and `RenderEvidence()` to use semantic typography with explicit worker tiers: bright section headers, muted or semantic detail lines, and dimmest help text
- Put steady-state `quit` / `peek` hints in the pane footer
- Use a separate full-width status bar only for transient worker errors when height >= `compactHeightThreshold`
- Preserve compact and wide behavior at the existing width threshold and adopt the new short-height behavior

**Out of scope (handled by other tasks):**
- Master tracker row selection and manifest/composer chrome
- New pane helper implementation itself
- Picker ANSI formatting
- Session discovery or peek behavior changes

**Cross-task consistency check:**
- Worker view must use the shared border/status helpers from Task 1, not a custom worker-only variant
- Worker section headers must consume the shared `sidebarLabelStyle` from Task 1 rather than invent a local color choice
- The worker pane body should read like the tracker's list flow, not a two-column form hidden inside a border
- Compact mode must still be keyed off `compactThreshold`, not a worker-specific magic number
- Short panes must obey `compactHeightThreshold` and collapse any transient status text into the pane footer

## Reference

Files to study before implementing:

- `tools/party-cli/internal/tui/model.go` — current worker shell and error shell
- `tools/party-cli/internal/tui/sidebar.go` — current Codex/evidence formatting
- `tools/party-cli/internal/tui/sidebar_test.go` — existing compact/offline coverage
- `~/Code/scry/internal/ui/idle.go` — badge treatment and muted note styling
- `~/Code/scry/internal/ui/statusbar.go` — status-bar structure

## Design References (REQUIRED for UI/component tasks)

- `../mockups/sidebar-wide.svg`
- `../mockups/sidebar-compact.svg`

## Data Transformation Checklist (REQUIRED for shape changes)

N/A (non-API render task)

## Files to Create/Modify

| File | Action |
|------|--------|
| `tools/party-cli/internal/tui/model.go` | Modify |
| `tools/party-cli/internal/tui/sidebar.go` | Modify |
| `tools/party-cli/internal/tui/model_test.go` | Modify |
| `tools/party-cli/internal/tui/sidebar_test.go` | Modify |

## Requirements

**Functionality:**
- The worker sidebar renders inside a rounded bordered pane with embedded title/footer
- The worker error state also uses the new bordered chrome rather than flat rules
- The pane body uses a flat list layout rather than a rigid label:value grid
- Title and cwd render as direct value lines because the pane title already identifies the session
- `Codex` renders as a bright section header with inline semantic status, followed by an indented muted detail line that compacts secondary information with `·` separators where useful
- `Evidence` renders as a bright section header with an indented sub-list of semantic result lines
- Default detail lines use `Muted`; semantic status values use `Clean`, `Dirty`, `Error`, or a deliberately dim offline state as appropriate
- Help text and steady-state footer hints use the dimmest tier: `Muted` + `Faint`
- `CodexWorking` uses accent-colored spinner/dot treatment
- `CodexIdle`, warnings, and errors map to the new semantic token set
- Low-priority notes such as offline/unavailable/no-status copy use muted and italic/faint styling where appropriate
- Steady-state controls and counts render in the pane footer
- If height is below `compactHeightThreshold`, the worker view never appends a separate status-bar line

**Key gotchas:**
- The current worker view hard-codes `"  "` prefixes in both shell and body; remove those or the bordered pane will waste width
- Keep `peek` behavior untouched; only the shell chrome changes
- Compact output should abbreviate or drop low-priority detail lines before it regresses back into a form layout
- Worker body height must follow the helper budget: `outerHeight - 2` in steady state, `outerHeight - 3` only if a tall transient error state explicitly enables a status bar
- Do not preserve fake alignment by padding labels into columns; that is precisely the layout smell this task exists to remove

## Tests

Test cases:
- Wide worker steady state renders bordered pane chrome with footer hints and no mandatory status-bar line
- Wide worker body uses direct value lines plus section headers and indented detail lines, not a rigid label:value grid
- Short-height worker view still contains session identity and bounded/truncated content without a separate status bar
- Error view renders inside bordered chrome
- Offline and stale Codex states remain readable
- Evidence lines render as an indented semantic sub-list

## Verification Commands

- `cd tools/party-cli && go test ./internal/tui -run 'TestModel_View|TestRenderSidebar|TestReadCodexStatus'`
- `cd tools/party-cli && go test ./internal/tui/...`

## Acceptance Criteria

- [x] Worker mode uses bordered pane chrome instead of flat rules
- [x] Worker steady-state hints render in the pane footer
- [x] Worker body uses the same flat-list interior feel as the tracker instead of a rigid form layout
- [x] Title and cwd render as direct value lines, not label:value rows
- [x] `Codex` and `Evidence` render as bright section headers with indented detail content beneath them
- [x] Short worker panes render without a separate status bar line
- [x] Tall transient worker errors may use the shared status bar without violating the height budget
- [x] Wide and compact worker tests cover the new chrome and flat-list layout contract
