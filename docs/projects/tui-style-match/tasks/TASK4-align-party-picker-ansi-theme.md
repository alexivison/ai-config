# Task 4 — Align Party Picker ANSI Theme

**Dependencies:** Task 1 | **Issue:** TBD

---

## Goal

Align the `fzf`-based party picker with the same terminal-theme-safe token vocabulary as the rest of the restyle by replacing hardcoded RGB escape strings with ANSI 4/2/8/240 usage. The picker should still look and behave like the same lightweight `fzf` surface; this task changes color semantics, not picker behavior.

## Scope Boundary (REQUIRED)

**In scope:**
- Replace hardcoded RGB ANSI strings in `tools/party-cli/internal/picker/fzf.go`
- Align picker list separators, resumable divider row, preview headers, and preview status lines to the scry token vocabulary
- Inspect `tools/party-cli/internal/picker/picker.go` for related formatting and keep it unchanged unless extracting tiny shared ANSI constants/helpers is materially cleaner
- Add or update picker tests that prove the formatted output uses ANSI token-aligned colors

**Out of scope (handled by other tasks):**
- Bubble Tea / Lip Gloss TUI surfaces
- Picker ordering, preview content, or selection behavior
- Rewriting the picker around Lip Gloss or a custom UI
- Codex peek popup styling

**Cross-task consistency check:**
- Task 4 should align to the same token meanings defined in Task 1, even though the picker remains raw ANSI text
- The picker must preserve its existing fixed-width formatting contract; color changes must not mangle columns or worker indentation
- `picker.go` should not grow new behavior merely because `fzf.go` is being cleaned up

## Reference

Files to study before implementing:

- `tools/party-cli/internal/picker/fzf.go` — current hardcoded RGB ANSI strings in list and preview formatting
- `tools/party-cli/internal/picker/picker.go` — picker entry and preview data shaping
- `tools/party-cli/internal/picker/picker_test.go` — existing picker tests and best place to add format assertions
- `~/Code/scry/internal/ui/theme/theme.go` — canonical token meanings and ANSI values

## Design References (REQUIRED for UI/component tasks)

- `../DESIGN.md`

## Data Transformation Checklist (REQUIRED for shape changes)

N/A (render-only formatting task; no data shape changes)

## Files to Create/Modify

| File | Action |
|------|--------|
| `tools/party-cli/internal/picker/fzf.go` | Modify |
| `tools/party-cli/internal/picker/picker.go` | Inspect / optional tiny cleanup |
| `tools/party-cli/internal/picker/picker_test.go` | Modify |

## Requirements

**Functionality:**
- Replace picker RGB blue with ANSI 4 (`Accent`)
- Replace picker RGB green with ANSI 2 (`Clean` / `Added`)
- Replace dim separator and resumable divider colors with ANSI 240 (`DividerFg`) or ANSI 8 (`Muted`) as appropriate
- Replace dim column separators with ANSI 8 (`Muted`)
- Render preview section headers such as `--- Paladin ---` with ANSI 4 (`Accent`)
- Preserve existing fixed-width row formatting and existing preview content
- Keep the picker inheriting the user's terminal theme rather than introducing new RGB values

**Key gotchas:**
- `FormatEntries()` relies on fixed widths because `column(1)` was abandoned to avoid ANSI mangling; keep that contract intact
- Do not break the two-space worker indentation under master sessions
- Do not change selection/cancel behavior in `RunFzf()`
- Do not broaden this into a picker rewrite; it is a string-constant cleanup with token alignment

## Tests

Test cases:
- `FormatEntries()` uses ANSI 8 for column separators
- `FormatEntries()` uses ANSI 240 or ANSI 8 for the resumable divider row
- `FormatPreview()` uses ANSI 4 for master/header text and `--- Paladin ---`
- `FormatPreview()` uses ANSI 2 for active/prompt lines
- `FormatPreview()` uses ANSI 8 for resumable/cwd/timestamp/id text
- Existing picker entry ordering and preview data tests still pass unchanged

## Verification Commands

- `cd tools/party-cli && go test ./internal/picker -run 'TestFormatEntries|TestFormatPreview|TestBuildEntries|TestBuildPreview'`
- `cd tools/party-cli && go test ./internal/picker/...`

## Acceptance Criteria

- [ ] `fzf.go` no longer contains hardcoded RGB ANSI escape strings for list or preview colors
- [ ] Picker ANSI colors align to Accent/Clean/Muted/DividerFg token meanings
- [ ] `picker.go` remains unchanged unless a tiny constant/helper extraction is materially cleaner
- [ ] Picker format tests assert the ANSI token-aligned output
- [ ] Existing picker behavior and fixed-width formatting remain intact
