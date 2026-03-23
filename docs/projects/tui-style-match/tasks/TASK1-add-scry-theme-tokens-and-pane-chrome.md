# Task 1 — Add scry Theme Tokens And Pane Chrome

**Dependencies:** none | **Issue:** TBD

---

## Goal

Create the shared render primitives that make the rest of the project coherent: scry-aligned theme tokens, local bordered-pane helpers, explicit height budgeting, and shared style tiers for worker labels, values, help text, and tracker titles. This task should not restyle worker or tracker views yet; it should only make the chrome reusable and testable.

## Scope Boundary (REQUIRED)

**In scope:**
- Rename and expand `tools/party-cli/internal/tui/style.go` to use the scry token vocabulary and exact ANSI values
- Add `compactHeightThreshold = 14` and helper rules for footer-only vs pane+status-bar height budgeting
- Keep `gold = lipgloss.Color("#ffd700")` as a local exception for master identity text
- Add a readable inactive worker-title style derived from `StatusFg`
- Add explicit worker sidebar semantic tiers: `sidebarLabelStyle`, default metadata value style, and help-text style
- Add a local bordered pane helper that mirrors `scry`'s rounded corners, embedded title/footer, active/inactive border colors, and optional right-edge scroll indicator
- Add shared footer/status helpers where full-width status bars are transient-only, not universal
- Add helper-level tests for pane rendering, ANSI-aware title handling, and status/footer formatting

**Out of scope (handled by other tasks):**
- Worker sidebar render changes
- Tracker row, manifest, or composer restyles
- Picker RGB-to-ANSI cleanup
- Any session/message/tmux behavior changes

**Cross-task consistency check:**
- Task 2 and Task 3 must consume the exact helper layer created here; they should not reintroduce view-local footer or border logic
- The `gold` token created here must remain text-only so later tasks keep blue active borders
- The height-budget rules created here must be the only source of truth for whether a separate status bar is allowed
- The worker label/value/help styles created here must be the shared source of truth for Task 2, not redefined ad hoc inside `sidebar.go`

## Reference

Files to study before implementing:

- `~/Code/scry/internal/ui/theme/theme.go` — semantic token names and values
- `~/Code/scry/internal/ui/panes/border.go` — rounded bordered pane semantics
- `~/Code/scry/internal/ui/statusbar.go` — full-width status-bar behavior
- `~/Code/scry/internal/ui/idle.go` — key badge styling and dim note treatment
- `tools/party-cli/internal/tui/style.go` — current palette and compact threshold
- `tools/party-cli/internal/tui/model.go` — current worker shell with no explicit height budgeting
- `tools/party-cli/internal/tui/sidebar.go` — current worker labels/values collapsed toward one dim tier
- `tools/party-cli/internal/tui/tracker.go` — current tracker shell with no explicit height budgeting

## Design References (REQUIRED for UI/component tasks)

- `../mockups/sidebar-wide.svg`
- `../mockups/tracker-wide.svg`

## Data Transformation Checklist (REQUIRED for shape changes)

N/A (non-UI-data-shape task; render primitives only)

## Files to Create/Modify

| File | Action |
|------|--------|
| `tools/party-cli/internal/tui/style.go` | Modify |
| `tools/party-cli/internal/tui/pane.go` | Create |
| `tools/party-cli/internal/tui/pane_test.go` | Create |

## Requirements

**Functionality:**
- Expose the scry token set locally with exact ANSI values
- Expose a readable inactive worker-title style that is brighter than snippets/footer
- Expose worker sidebar semantic tiers: bright labels, default muted metadata values, and dim/faint help text
- Define `compactHeightThreshold = 14`
- Provide `borderedPane(...)`, `borderedPaneWithScroll(...)`, and `contentDimensions(...)`
- Provide a shared `chromeLayout(...)` or equivalent helper that decides footer-only vs pane+status-bar states and yields correct body height
- Provide a shared `renderStatusBar(...)` or equivalent helper for transient-only status bars
- Support nested styled title text so later tasks can keep a gold `Master` token inside a blue-accent border line

**Key gotchas:**
- Do not import Go code from the `scry` repo; copy the contract, not the dependency
- Keep helper behavior ANSI-safe so embedded styled title strings do not wreck width calculations
- Make the body-height formulas explicit: `outerHeight - 2` for footer-only panes, `outerHeight - 3` when a separate status bar is active
- Resist the temptation to hide the border helper inside one view; it must be shared or the worker/tracker surfaces will diverge immediately
- Do not make worker sidebar labels and inactive tracker titles share a vague generic style name; the semantic role must stay obvious in `style.go`

## Tests

Test cases:
- Rounded corners render as `╭╮╰╯`
- Title text is embedded in the top border
- Footer text is embedded in the bottom border
- Active and inactive borders use different colors/styles
- Scroll indicator renders as `┃` on the right edge when requested
- Footer/status helper respects `compactHeightThreshold`
- Styled title width calculation remains correct when a gold `Master` token appears inside a blue border line
- ANSI-aware truncation preserves border alignment for long styled titles
- Status bar renders key badges and muted labels without truncation glitches
- Shared sidebar label/value/help styles resolve to distinct semantic tiers

## Verification Commands

- `cd tools/party-cli && go test ./internal/tui -run 'TestPane|TestStatusBar|TestStyledTitle|TestChromeLayout'`
- `cd tools/party-cli && go test ./internal/tui/...`

## Acceptance Criteria

- [ ] `style.go` uses the scry semantic token set and keeps only `gold` as a local exception
- [ ] `style.go` defines `compactHeightThreshold = 14`, a readable inactive worker-title style, and explicit sidebar label/value/help styles
- [ ] A local pane helper exists for bordered panes with optional scroll indicator
- [ ] Shared chrome helpers define footer-only vs pane+status-bar body budgets
- [ ] A shared transient-only status-bar/key-badge helper exists
- [ ] Helper tests cover border/title/footer/scroll/status-bar behavior, styled-title width, ANSI-aware title truncation, and shared semantic style tiers
