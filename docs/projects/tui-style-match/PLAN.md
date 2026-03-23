# party-cli TUI Style Match Implementation Plan

> **Goal:** Make `party-cli`'s worker sidebar, master tracker, and adjacent party picker feel like `scry` siblings by porting scry's pane chrome, theme tokens, flat-list interior rhythm, height-aware footer/status handling, and terminal-theme-safe ANSI color usage into the existing `party-cli` render surfaces.
>
> **Architecture:** Introduce a local bordered-pane helper layer in `tools/party-cli/internal/tui/` that owns both width and height budgeting, plus a shared token vocabulary that reaches the raw ANSI formatting seam in `tools/party-cli/internal/picker/`. Steady-state TUI views render as bordered panes with embedded footers and flat-list interiors; the worker sidebar stops using a form-like inner grid and instead follows the same list flow as the tracker. A full-width status bar is reserved for transient errors or active input modes only when height allows. The picker remains raw ANSI text for `fzf`, but its colors align to the same scry token system.
>
> **Tech Stack:** Go, Bubble Tea, Lip Gloss, `fzf`, ANSI escape strings, Markdown, SVG
>
> **Specification:** [SPEC.md](./SPEC.md) | **Design:** [DESIGN.md](./DESIGN.md)

## Scope

This plan covers `tools/party-cli/internal/tui/` and the picker formatting seam in `tools/party-cli/internal/picker/`: shared styles, pane chrome, worker sidebar, tracker list, manifest viewer, tracker composer, height-aware footer/status behavior, worker/tracker inner layout consistency, picker list/preview ANSI formatting, and corresponding tests. It does not change `party-cli` session/message/tmux behavior, picker ordering, or introduce a cross-repo dependency on `scry`.

## Task Granularity

- [x] **Standard** — each task owns one coherent render surface or shared primitive layer
- [ ] **Atomic** — not needed; the risk is chrome consistency, row budgeting, and token drift, not minute-by-minute execution

## Tasks

- [x] [Task 1](./tasks/TASK1-add-scry-theme-tokens-and-pane-chrome.md) — Add scry-aligned theme tokens, shared TUI styles, a local bordered-pane helper, height-aware footer/status primitives, and ANSI-aware helper tests in `tools/party-cli/internal/tui/` (deps: none)
- [ ] [Task 2](./tasks/TASK2-restyle-worker-sidebar-shell.md) — Apply the new chrome and flat-list interior layout to the worker sidebar and error shell, including short-pane footer fallback, bright section headers, muted detail lines, and tall-pane transient status behavior (deps: Task 1)
- [ ] [Task 3](./tasks/TASK3-restyle-master-tracker-manifest-and-composer.md) — Apply the new chrome to the master tracker, manifest viewer, and relay/broadcast/spawn composer, including reverse-row selection, readable inactive titles, ANSI-aware selection tests, and compact height fallback rules (deps: Task 1)
- [ ] [Task 4](./tasks/TASK4-align-party-picker-ansi-theme.md) — Replace the picker's hardcoded RGB escape strings with scry-aligned ANSI color usage in `tools/party-cli/internal/picker/`, while preserving the existing fixed-width `fzf` formatting model (deps: Task 1)

## Coverage Matrix

No persisted fields or endpoints are added in this project. The matrix therefore tracks render contracts that must be carried through every affected surface.

| Style Contract | Added In | Views Affected | Handled By | Helper / Render Functions |
|----------------|----------|----------------|------------|---------------------------|
| Scry token vocabulary (`Accent`, `Muted`, `StatusBg`, `BrightText`, etc.) | Task 1 | Worker shell, tracker shell, manifest viewer, picker list/preview, tests | Task 2, Task 3, Task 4 | `style.go` token set; shared style vars; picker ANSI aliases |
| Rounded bordered pane chrome with embedded title/footer | Task 1 | Worker shell, tracker shell, manifest viewer | Task 2, Task 3 | `borderedPane(...)`, `borderedPaneWithScroll(...)`, `contentDimensions(...)` |
| Height-aware chrome policy (`compactHeightThreshold = 14`) | Task 1 | Worker shell, tracker shell, manifest viewer, error/input states | Task 2, Task 3 | `compactHeightThreshold`, `chromeLayout(...)`, footer-only body budget = `outerHeight - 2`, pane+status body budget = `outerHeight - 3` |
| Footer-first hints and transient-only status bar | Task 1 | Worker shell, tracker shell, manifest viewer, error/input states | Task 2, Task 3 | embedded pane footer for steady-state metadata/hints; `renderStatusBar(...)` only for transient errors or active input when height allows |
| Flat-list inner layout consistency between worker and tracker panes | Task 2 | Worker shell, evidence block, worker tests | Task 2 | direct title/cwd lines; `Codex` header + indented detail line; `Evidence` header + indented sub-list |
| Worker sidebar section-header/detail/help hierarchy | Task 1 | Worker shell, evidence block, tests | Task 2 | `sidebarLabelStyle = StatusFg`; detail lines default to `Muted`; help/footer text stays `Muted` + `Faint` |
| Full-row reverse selection while keeping `▸` | Task 3 | Master tracker worker list | Task 3 | `selectedRowStyle`, `selectedRowTitleStyle`, `TrackerModel.viewWorkers()` |
| Readable inactive tracker titles above dim snippets/footer | Task 1 | Master tracker worker list | Task 3 | `inactiveWorkerTitleStyle = StatusFg`; snippets/footer remain `Muted` + `Faint` |
| Picker ANSI alignment to terminal theme | Task 4 | Picker list rows, preview pane, picker tests | Task 4 | `FormatEntries()`, `FormatPreview()`, ANSI 4/2/8/240 escape strings |
| ANSI-aware title and selection verification | Task 1 | helper tests, tracker tests, picker format tests | Task 1, Task 3, Task 4 | styled-title width/truncation tests; reverse-selection tests beyond `▸` presence; picker ANSI-format assertions |

**Validation:** Every row above is intentionally shared or fan-out. Task 1 creates the primitives and vocabulary; Task 2 and Task 3 consume them inside Bubble Tea surfaces; Task 2 also aligns the worker's inner rhythm to the tracker so the panes feel like siblings instead of cousins; Task 4 applies the same token contract at the raw ANSI picker seam so the family resemblance does not stop at the `fzf` boundary.

## Dependency Graph

```text
Task 1 ───┬───> Task 2
          ├───> Task 3
          └───> Task 4
```

## Task Handoff State

| After Task | State |
|------------|-------|
| Task 1 | `party-cli` has scry-aligned token names, bordered pane helpers, a `compactHeightThreshold` policy, sidebar section-header/detail/help styles, footer-vs-status-bar rules, and helper tests for ANSI-aware title rendering |
| Task 2 | Worker mode and the error shell render with bordered chrome, a flat-list interior that mirrors the tracker, bright section headers, muted detail lines, steady-state footer hints, and short-pane fallback rules |
| Task 3 | Master tracker rows, manifest viewer, and tracker composer all use the same chrome system, including reverse-row selection, readable inactive titles, ANSI-aware selection coverage, and compact fallback rules |
| Task 4 | The `fzf` picker list and preview use scry-aligned ANSI colors instead of hardcoded RGB values, while keeping the existing fixed-width layout and preview content intact |

## External Dependencies

| Dependency | Status | Blocking |
|------------|--------|----------|
| `~/Code/scry/` as source-of-truth reference | Available locally | Task 1, Task 2, Task 3, Task 4 |
| Existing Bubble Tea + Lip Gloss packages in `tools/party-cli/` | Already present | Task 1, Task 2, Task 3 |
| Existing picker formatting/tests in `tools/party-cli/internal/picker/` | Already present, but expectations will change | Task 4 |
| `fzf` interactive picker runtime | Already required by the picker flow; not required for unit-format tests | Task 4 |

## Future Enhancements

- Codex peek currently launches a plain tmux popup via `tools/party-cli/internal/tui/sidebar_popup.go:9-19`, piping `tmux capture-pane` into `less -R`. That surface has no custom chrome or token-aware styling. It is a sensible follow-up once the main TUI surfaces and picker are aligned, but it is not worth a dedicated task in this plan.

## Plan Evaluation Record

PLAN_EVALUATION_VERDICT: PASS

Evidence:
- [x] Existing standards referenced with concrete paths
- [x] Data transformation points mapped
- [x] Tasks have explicit scope boundaries
- [x] Dependencies and verification commands listed per task
- [x] Requirements reconciled against source inputs
- [x] Whole-architecture coherence evaluated
- [x] UI/component tasks include design references

Source reconciliation:
- `scry` is the visual source of truth for tokens, borders, selection, and status bars: `~/Code/scry/internal/ui/theme/theme.go:8-25`, `~/Code/scry/internal/ui/panes/border.go:11-119`, `~/Code/scry/internal/ui/panes/filelist.go:16-35`, `~/Code/scry/internal/ui/statusbar.go:14-20`, `~/Code/scry/internal/ui/statusbar.go:48-95`, `~/Code/scry/internal/ui/idle.go:126-133`.
- Current `party-cli` seams and compact-width assumptions are explicit in `tools/party-cli/internal/tui/style.go:7-30`, `tools/party-cli/internal/tui/model.go:219-300`, `tools/party-cli/internal/tui/sidebar.go:11-96`, and `tools/party-cli/internal/tui/tracker.go:249-392`.
- The revised plan explicitly addresses the missing height budget called out in review: current worker and tracker views consume rows opportunistically and do not own vertical space once extra chrome is added (`tools/party-cli/internal/tui/model.go:219-276`, `tools/party-cli/internal/tui/tracker.go:257-361`).
- The worker sidebar currently feels structurally unlike the tracker because it presents a rigid label/value form layout inside the pane; the requested revision corrects that by switching the worker to direct value lines, section headers, and indented detail sub-lines rather than a faux inner table.
- The picker currently breaks terminal-theme inheritance by hardcoding RGB escape codes in `tools/party-cli/internal/picker/fzf.go:13-72`. `tools/party-cli/internal/picker/picker.go:40-218` shapes picker data, but does not add more color formatting; it only needs inspection unless Task 4 extracts shared ANSI constants.
- The plan intentionally ports chrome and token alignment, not IA. It does not force `scry`'s dashboard split layout into `party-cli` because worker sidebars are narrow tmux panes, tracker behavior already lives in a coherent single-column list, and the picker already has an appropriate `fzf` interaction model.
- The gold master accent from `tools/party-cli/internal/tui/style.go:13` is retained, but constrained to title text so the active border stays scry blue.

## Definition of Done

- [ ] All task checkboxes complete
- [ ] Worker sidebar, tracker, manifest/composer surfaces, and picker output all align to the same scry token vocabulary
- [ ] Worker sidebar uses the same flat-list interior feel as the tracker instead of a rigid inner form layout
- [ ] Compact and wide render paths stay readable at the current width and height thresholds
- [ ] Steady-state metadata and key hints live in pane footers; full-width status bars appear only for transient errors or active input when height allows
- [ ] Short panes below `compactHeightThreshold` render without a separate status bar line
- [ ] Worker section headers render brighter than detail lines and help text
- [ ] Tracker selection uses full-row reverse highlight while retaining `▸`
- [ ] Inactive worker titles remain readable above dim snippets and footer text
- [ ] Picker list and preview replace hardcoded RGB colors with ANSI 4/2/8/240-aligned theme usage
- [ ] ANSI-aware title, selection, and picker-format tests pass
- [ ] Helper, surface, and picker tests pass
- [ ] SPEC acceptance criteria are satisfied
