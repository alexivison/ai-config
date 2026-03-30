# Task 8 — Cut Over Shims And Retire Shell Libraries

**Dependencies:** Task 5, Task 6, Task 7 | **Issue:** TBD

---

## Goal

Finish the migration by leaving shell only at the Claude-facing edge. After this task, the libraries under `claude/hooks/lib/` and the metrics script are wrappers or removed; the real implementation lives in `party-cli`.

## Scope Boundary (REQUIRED)

**In scope:**
- Convert `claude/hooks/lib/evidence.sh`, `claude/hooks/lib/session-id-helper.sh`, `claude/hooks/lib/review-metrics.sh`, `claude/hooks/lib/oscillation.sh`, and `claude/hooks/scripts/review-metrics.sh` into wrappers or remove them where no caller remains
- Ensure every migrated hook entrypoint in `claude/settings.json` still points at a shell shim
- Add consolidated Go regression coverage for the migrated packages and keep shell smoke coverage where it still buys confidence
- Update comments and docs that still describe the shell libraries as the source of truth

**Out of scope (handled elsewhere):**
- Excluded shell scripts from the project brief
- `tmux-codex.sh` and `tmux-claude.sh`
- New workflow-policy changes

**Cross-task consistency check:**
- After this task there is exactly one implementation of evidence, metrics, oscillation, and gate logic in Go
- Shell files that remain must be compatibility edges only; they may not own business rules

## Reference

Files to study before implementing:

- `claude/settings.json:84` — hook registrations that must continue to point at `.sh` files
- `claude/hooks/tests/run-all.sh:11` — current shell regression runner
- `claude/hooks/lib/evidence.sh:1` — current library shell surface to retire
- `claude/hooks/lib/session-id-helper.sh:1` — current helper shell surface to retire
- `claude/hooks/lib/review-metrics.sh:1` — current metrics shell surface to retire
- `claude/hooks/lib/oscillation.sh:1` — current oscillation shell surface to retire
- `claude/rules/execution-core.md:44` — docs that describe the runtime contract

## Design References (REQUIRED for UI/component tasks)

N/A (non-UI task)

## Data Transformation Checklist (REQUIRED for shape changes)

- [ ] Proto definition (N/A)
- [ ] Proto -> Domain converter (N/A)
- [ ] Domain model struct(s) already exist; no new persisted shape should be introduced here
- [ ] Params struct(s) for any remaining wrapper entrypoints
- [ ] Params conversion functions from shell shim args/stdin to `party-cli`
- [ ] Any adapters between retained shell smoke tests and Go-owned commands

## Files to Create/Modify

| File | Action |
|------|--------|
| `claude/hooks/lib/evidence.sh` | Modify or Delete |
| `claude/hooks/lib/session-id-helper.sh` | Modify or Delete |
| `claude/hooks/lib/review-metrics.sh` | Modify or Delete |
| `claude/hooks/lib/oscillation.sh` | Modify or Delete |
| `claude/hooks/scripts/review-metrics.sh` | Modify |
| `claude/hooks/tests/run-all.sh` | Modify |
| `tools/party-cli/internal/*/*_test.go` | Modify |
| `tools/party-cli/cmd/*_test.go` | Modify |
| `claude/rules/execution-core.md` | Modify |

## Requirements

**Functionality:**
- Shell entrypoints remain valid for Claude because the settings file still executes `.sh` files
- Legacy shell libraries no longer own evidence, metrics, oscillation, or gate behavior
- Go tests become the primary parity suite for migrated behavior
- Retained shell tests become smoke tests and compatibility checks, not the only oracle

**Key gotchas:**
- Do not delete a shell file that is still referenced by settings, docs, or operator workflows before a wrapper replacement exists
- Keep `/tmp` paths, environment variable names, and stdout/stderr conventions stable during the wrapper cleanup

## Tests

Test cases:
- Full Go regression run across evidence, resolver, metrics, oscillation, trace, and gate packages
- Shell smoke run through the retained hook entrypoints
- Wrapper scripts preserve exit codes and hook JSON output shapes
- Legacy evidence and metrics files remain readable after the cleanup

Verification commands:
- `go test ./...`
- `bash claude/hooks/tests/run-all.sh`

## Acceptance Criteria

- [ ] One Go implementation owns the migrated hook and harness behavior
- [ ] Remaining shell files are shims or wrappers only
- [ ] Go regression coverage is the primary oracle for migrated behavior
- [ ] Shell smoke tests and wrapper compatibility checks pass
