# Task 3 — Restyle Master Tracker, Manifest, And Composer

**Dependencies:** Task 1 | **Issue:** TBD

---

## Goal

Bring the master tracker into the same visual family as scry by applying bordered pane chrome, full-row reverse selection, readable inactive worker titles, bordered manifest view, and a bordered tracker composer where space allows. This task should finish the visible restyle across all master-only surfaces without changing tracker behavior.

## Scope Boundary (REQUIRED)

**In scope:**
- Restyle `TrackerModel.viewWorkers()` with bordered pane chrome and footer-first steady-state hints
- Change selected worker rows from "blue bold title + cursor" to "reverse entire selected row + cursor"
- Restyle inactive worker titles so they are brighter than snippets/footer
- Restyle snippets with muted/faint typography
- Give `TrackerModel.viewManifest()` bordered treatment and a right-edge scroll indicator
- Restyle tracker input mode (`relay`, `broadcast`, `spawn`) with a bordered composer in standard sizes and a compact inline fallback below the agreed size threshold
- Use a separate full-width status bar only for active input or transient errors when height >= `compactHeightThreshold`
- Preserve gold master identity text only inside the title token

**Out of scope (handled by other tasks):**
- Worker sidebar shell
- Shared border/status helper implementation
- Tracker action semantics or backend services

**Cross-task consistency check:**
- Reverse selection must consume the shared style primitives from Task 1 so the worker and master surfaces still share one token system
- The manifest view and composer should not invent separate border logic; they must reuse the same pane helper as the main tracker shell
- The inactive-title style must remain distinct from snippet/footer styling or the tracker will regress back into an unreadable gray wall

## Reference

Files to study before implementing:

- `tools/party-cli/internal/tui/tracker.go` — current tracker, manifest, and input-mode rendering
- `tools/party-cli/internal/tui/tracker_test.go` — current compact/footer/manifest expectations
- `~/Code/scry/internal/ui/panes/filelist.go` — reverse-row selection model
- `~/Code/scry/internal/ui/panes/dashboard.go` — selected dashboard row treatment
- `~/Code/scry/internal/ui/panes/border.go` — bordered panes and scroll indicator

## Design References (REQUIRED for UI/component tasks)

- `../mockups/tracker-wide.svg`
- `../mockups/tracker-compact.svg`

## Data Transformation Checklist (REQUIRED for shape changes)

N/A (render-only task)

## Files to Create/Modify

| File | Action |
|------|--------|
| `tools/party-cli/internal/tui/tracker.go` | Modify |
| `tools/party-cli/internal/tui/tracker_test.go` | Modify |

## Requirements

**Functionality:**
- Main tracker shell renders inside a bordered pane with embedded title/footer
- Selected worker row uses full-row reverse highlight and still shows `▸`
- Inactive worker titles use a readable style derived from `StatusFg`
- Status text and snippets use the new semantic/faint styles
- Manifest inspection uses a bordered pane with a scroll indicator when content overflows
- Relay/broadcast/spawn input mode uses a bordered composer when `width >= 40` and `height >= 14`, with inline fallback below that
- Steady-state hints live in the pane footer; active input or transient errors may claim a separate status bar only when height allows

**Key gotchas:**
- Keep the master border blue; gold belongs only in the master title token
- Do not regress compact behavior that hides snippets in narrow panes
- Manifest scrolling uses `height`-dependent logic already; account for the pane border and the optional extra status-bar line when computing viewable rows
- Do not let inactive worker titles share the same `Muted` + `Faint` tier as snippets and footer text

## Tests

Test cases:
- Wide tracker view renders bordered pane chrome and worker count footer
- Compact or short-height tracker view preserves reverse selection and footer-folded hints
- Selected worker row includes reverse styling semantics, not just cursor presence
- Inactive worker titles remain readable above dim/faint snippets and footer text
- Manifest view renders with bordered title/footer and scroll indicator when long
- Input mode renders bordered composer in standard sizes and inline fallback in cramped sizes
- Styled title width and truncation stay aligned when the gold `Master` token sits inside a blue border line
- Error messages surface through the transient status bar in tall panes and the footer in short panes

## Verification Commands

- `cd tools/party-cli && go test ./internal/tui -run 'TestTracker_View|TestTracker_Update|TestTracker_Manifest|TestSelectedRow|TestStyledTitle'`
- `cd tools/party-cli && go test ./internal/tui/...`

## Acceptance Criteria

- [ ] Tracker shell uses bordered pane chrome and footer-first steady-state hints
- [ ] Selected row uses full-row reverse highlight while retaining `▸`
- [ ] Tracker tests assert reverse-selected row styling beyond cursor presence
- [ ] Inactive worker titles use a readable tier above muted/faint snippets and footer text
- [ ] Manifest view uses bordered chrome and scroll indicator
- [ ] Input mode uses bordered composer chrome with compact fallback and height-aware status/footer behavior
- [ ] Tracker tests cover wide, compact, short-height, manifest, and composer chrome behavior
