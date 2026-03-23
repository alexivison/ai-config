# party-cli TUI Style Match Specification

## Problem Statement

- `party-cli` currently renders its worker sidebar and master tracker as flat text with dim horizontal rules, using the style set in `tools/party-cli/internal/tui/style.go:7-30`, the worker shell in `tools/party-cli/internal/tui/model.go:219-276`, the worker status body in `tools/party-cli/internal/tui/sidebar.go:11-67`, and the tracker shell in `tools/party-cli/internal/tui/tracker.go:257-390`.
- `scry` already defines the visual language this tool family wants: semantic theme tokens in `~/Code/scry/internal/ui/theme/theme.go:8-25`, rounded bordered panes in `~/Code/scry/internal/ui/panes/border.go:11-119`, full-row reverse selection in `~/Code/scry/internal/ui/panes/filelist.go:16-35` and `~/Code/scry/internal/ui/panes/filelist.go:148-211`, and status-bar / key-badge treatment in `~/Code/scry/internal/ui/statusbar.go:14-20`, `~/Code/scry/internal/ui/statusbar.go:48-95`, and `~/Code/scry/internal/ui/idle.go:126-133`.
- The current `party-cli` palette only partially overlaps with scry, and it uses ad hoc names (`blue`, `green`, `yellow`, `dim`) instead of the scry token vocabulary; see `tools/party-cli/internal/tui/style.go:7-27`.
- The current worker sidebar has weak visual hierarchy: section labels, metadata values, and help-ish copy all collapse toward the same dim treatment in `tools/party-cli/internal/tui/sidebar.go:19-96`, which makes scanning slower than it needs to be.
- The current tracker selection model relies on a `▸` cursor plus blue bold text only, rather than a reversed full-row highlight; see `tools/party-cli/internal/tui/tracker.go:278-316`.
- The current worker and tracker views do not own vertical space explicitly once extra chrome is added, so adding borders and separate footer/status treatment without a height policy would steal rows unpredictably from body content; see `tools/party-cli/internal/tui/model.go:219-276` and `tools/party-cli/internal/tui/tracker.go:257-361`.
- The current tracker also has a readability problem: non-selected worker titles, snippets, and footer hints all sit on the same dim tier, creating a low-contrast gray wall.
- The current party picker uses hardcoded RGB ANSI escape codes in `tools/party-cli/internal/picker/fzf.go:13-72`, so it does not inherit the terminal theme the way scry-aligned ANSI tokens do.

## Goal

Make the `party-cli` worker sidebar, master tracker, and party picker feel like first-party siblings of `scry` by adopting the same pane chrome, token vocabulary, selection treatment, footer/status patterns, worker/sidebar typography tiers, and ANSI theme alignment while preserving `party-cli`'s gold master identity accent and staying readable in short tmux panes.

## User Experience

| Scenario | User Action | Expected Result |
|----------|-------------|-----------------|
| Worker sidebar, wide tmux pane | Open `party-cli` in worker mode at width >= 50 and height >= 14 | The sidebar renders inside a rounded bordered pane with an embedded title/footer, footer-based passive metadata and steady-state key hints, and a clear three-tier hierarchy: bright labels, muted or semantic values, and dimmest help text; a separate status bar is reserved for transient errors only |
| Worker sidebar, short tmux pane | Open `party-cli` in worker mode below `compactHeightThreshold` | The sidebar keeps the bordered pane, folds hints and transient messages into the pane footer, budgets body rows explicitly, preserves the label/value/help hierarchy, and remains readable without a separate status-bar line |
| Master tracker, wide tmux pane | Open `party-cli` in master mode at width >= 50 and height >= 14 | The tracker renders inside scry-style bordered chrome, uses full-row reverse selection while keeping the `▸` cursor, shows inactive worker titles in a readable mid-bright style above muted/faint snippets, and keeps worker count plus steady-state hints in the pane footer |
| Master tracker, compact or short tmux pane | Open `party-cli` in master mode at width < 50 or height < 14 | The tracker keeps bordered chrome, preserves the reverse-selected row, keeps inactive worker titles readable, and folds hints into the pane footer instead of paying for a separate status bar |
| Manifest inspection | Open worker or master manifest view | The manifest renders inside its own bordered pane with an embedded title/footer and a right-edge scroll indicator when content overflows |
| Input mode | Enter relay, broadcast, or spawn mode in the tracker | The composer uses bordered treatment in standard widths; when height >= 14 it may also use a separate status bar for send/cancel prompts, and when height is below that threshold it folds those prompts into the pane footer |
| Party picker | Open the fzf-based picker flow | Session rows, separators, preview headers, and preview statuses use ANSI colors aligned to the scry token vocabulary instead of hardcoded RGB values, so the picker inherits the terminal theme and looks like part of the same tool family |

## Acceptance Criteria

- [ ] `tools/party-cli/internal/tui/style.go` adopts scry-aligned token names and values for `Added`, `Deleted`, `HunkHeader`, `Clean`, `Dirty`, `Error`, `Accent`, `Muted`, `StatusBg`, `StatusFg`, `DividerFg`, and `BrightText`, while retaining `gold = lipgloss.Color("#ffd700")` only for master identity text and adding both a readable inactive worker-title style and a `sidebarLabelStyle` derived from `StatusFg`.
- [ ] `party-cli` gains a local rounded-pane helper that matches `scry`'s border semantics from `~/Code/scry/internal/ui/panes/border.go:11-119`: rounded corners, embedded title, embedded footer, active/inactive border colors, and optional right-edge scroll indicator.
- [ ] The helper layer defines `compactHeightThreshold = 14` and explicit body-row budgets: footer-only pane states render body content in `outerHeight - 2` rows, and tall transient-error / active-input states that append a separate status bar render body content in `outerHeight - 3` rows.
- [ ] Worker-mode rendering in `tools/party-cli/internal/tui/model.go` and `tools/party-cli/internal/tui/sidebar.go` uses bordered pane chrome plus embedded footer hints/metadata in steady state; worker labels render in a bright label tier, metadata values default to `Muted`, semantic status values use `Clean`/`Dirty`/`Error` as appropriate, and help text remains `Muted` + `Faint`.
- [ ] Tracker-mode rendering in `tools/party-cli/internal/tui/tracker.go` uses full-row reverse selection, bordered pane chrome, readable inactive worker titles, muted/faint snippet typography, and a footer-first hint model; a full-width status bar is used only for active input or transient errors when height allows.
- [ ] The tracker manifest view uses bordered treatment and a scroll indicator instead of plain rule-delimited JSON output.
- [ ] Relay, broadcast, and spawn input modes gain bordered composer chrome in standard widths, with an explicit compact fallback rule for very narrow or short panes and footer-folded send/cancel hints below `compactHeightThreshold`.
- [ ] Compact-width rendering remains functional at the current `compactThreshold` of `50` because the new border helper removes the old fixed left/right gutters (`tools/party-cli/internal/tui/model.go:293-300`, `tools/party-cli/internal/tui/tracker.go:249-255`) instead of adding net width loss.
- [ ] `tools/party-cli/internal/picker/fzf.go` replaces hardcoded RGB escape strings with ANSI color usage aligned to scry's token vocabulary: Accent = ANSI 4, Clean = ANSI 2, Muted = ANSI 8, DividerFg = ANSI 240, with preview headers such as `--- Paladin ---` using Accent and resumable separators using DividerFg or Muted.
- [ ] `tools/party-cli/internal/picker/picker.go` is inspected for related formatting and remains unchanged unless shared ANSI constants or helpers make a materially cleaner implementation possible.
- [ ] `tools/party-cli/internal/tui/model_test.go`, `tools/party-cli/internal/tui/sidebar_test.go`, `tools/party-cli/internal/tui/tracker_test.go`, new helper tests, and picker formatting tests in `tools/party-cli/internal/picker/picker_test.go` cover wide and short-height chrome behavior, bordered manifest rendering, ANSI-aware title width/truncation, reverse-selected row styling, worker label/value/help hierarchy, and picker ANSI formatting.

## Non-Goals

- Changing `party-cli` session, tmux, message, manifest, or picker ordering behavior; this project is styling and layout only.
- Importing Go packages directly from the `scry` repository; `party-cli` should copy the visual contract locally, not add a cross-repo runtime dependency.
- Rebuilding the tracker into a new multi-pane IA merely because `scry` has split layouts elsewhere.
- Removing the `▸` cursor or the gold master identity accent; both remain as `party-cli`-specific affordances.
- Restyling the Codex peek popup launched via `tools/party-cli/internal/tui/sidebar_popup.go`; that remains a future enhancement, not part of this project.
- Adding a feature flag for the restyle; the change should replace the current chrome directly.

## Technical Reference

Implementation details, style mappings, exact Lip Gloss snippets, ANSI picker mappings, row-budget rules, and task breakdown live in [DESIGN.md](./DESIGN.md) and [PLAN.md](./PLAN.md).
