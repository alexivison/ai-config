# Harness V2 — Simplification And Evolution Specification

## Problem Statement

- The harness still splits its real control surface across Bash launchers, tmux routing helpers, relay scripts, hooks, a standalone Go tracker, and a separate sidebar project. The heaviest operator path remaineth rooted in `session/party.sh:86-158`, `session/party.sh:169-303`, `session/party-master.sh:5-84`, and `session/party-relay.sh:45-218`.
- The present shell layer fails soft where it ought to fail loud. Manifest mutation silently does nothing when `jq` is missing in `session/party-lib.sh:76` and `session/party-lib.sh:151`, while `tmux_send()` may drop work with little ceremony in `session/party-lib.sh:347-390`.
- The Go surface already exists, but it is isolated. `tools/party-tracker/` hath a usable Bubble Tea model, width-adaptive rendering, and tmux capture helpers, yet it still shells back out through `exec.Command` for core behavior in `tools/party-tracker/actions.go:24-66` and `tools/party-tracker/workers.go:74-127`.
- The former CLI-first migration plan left the sidebar and tracker as separate concerns, which preserved three parallel implementation tracks instead of converging them.
- Codex transport still belongs to `tmux-codex.sh`, which explicitly sources `session/party-lib.sh` and resolves sessions/panes there (`claude/skills/codex-transport/scripts/tmux-codex.sh:9`, `claude/skills/codex-transport/scripts/tmux-codex.sh:31`, `claude/skills/codex-transport/scripts/tmux-codex.sh:37`). Any new architecture that pretends Bash vanisheth outright is lying.

## Goal

Reduce complexity first, then converge the surviving harness into one Go binary, `party-cli`, that runs as:

- a Bubble Tea TUI when launched with no subcommand
- a scriptable CLI when launched with a subcommand

The same packages must power both modes. Standard and worker sessions should support a sidebar TUI in pane `0` (opt-in via `PARTY_LAYOUT=sidebar` initially, flipped to default once promotion and Codex status parity are proven); master sessions should use a tracker TUI in pane `0`; and `PARTY_LAYOUT=classic` must preserve the current visible-Codex layout for the folk who desire the old ways.

## User Experience

| Scenario | User Action | Expected Result |
|----------|-------------|-----------------|
| Default worker or standalone launch | Run `session/party.sh` without `PARTY_LAYOUT=classic` | Session opens as `party-cli sidebar | claude | shell` in window 1; Codex runs in a hidden window 0 within the same tmux session and is summarized by the sidebar instead of consuming a full pane |
| Default master launch | Run `session/party.sh --master` | Session opens as `party-cli tracker | claude | shell`; the tracker is part of the same binary as the CLI |
| Classic escape hatch | Run `PARTY_LAYOUT=classic session/party.sh` | Existing visible Codex pane layout remains available |
| Local operator TUI | Run `party-cli` inside a party tmux session | `party-cli` auto-detects the current session and opens the correct TUI mode, or fails clearly if no party session is discoverable |
| Read-only scripting | Run `party-cli list`, `party-cli status`, or `party-cli prune` | Commands return structured, testable output backed by the same state and tmux services used by the TUI |
| Lifecycle scripting | Run `party-cli start|continue|stop|delete|promote` | Commands preserve current master/worker semantics and coexist with shell wrappers during migration |
| Worker report-back | A worker or helper runs `party-cli report "done: ..."` | The master receives the report through the shared messaging layer; the old `party-relay.sh --report` contract remains representable during coexistence |
| Sidebar inspection | Use the worker sidebar in TUI mode | Sidebar shows Codex status, last verdict summary, session metadata, and a guarded peek popup backed by tmux capture and `codex-status.json` |
| Tracker inspection | Use the master tracker in TUI mode | Tracker shows workers, snippets, attach/relay/spawn actions, and manifest inspection from the same binary |

## Acceptance Criteria

- [ ] Phase 1 removes the dead compatibility and cleanup paths called out in research and turns silent failures into explicit operator-visible errors.
- [ ] `party-cli` launches Bubble Tea TUI mode when invoked with no subcommand and CLI mode when invoked with a subcommand.
- [ ] Standard and worker sessions support the TUI sidebar layout in pane `0` (opt-in via `PARTY_LAYOUT=sidebar` until promotion and status parity are proven, then flipped to default), while master sessions default to the TUI tracker layout in pane `0`.
- [ ] `PARTY_LAYOUT=classic` preserves the current visible-Codex layout for standard and worker sessions.
- [ ] The sidebar-tui project is absorbed into Harness V2 rather than evaluated or built as a separate track.
- [ ] `tools/party-tracker/` patterns are reused and migrated into `party-cli` rather than rewritten from scratch.
- [ ] State, discovery, tmux queries, delivery results, and pane capture live in shared Go packages used by both TUI and CLI modes.
- [ ] The read-only CLI commands land before mutating commands become authoritative.
- [ ] The lifecycle, relay, read, report-back, tracker, and picker flows are all represented in the migration plan; no current worker workflow is silently dropped.
- [ ] `tmux-codex.sh` keeps working through retained `session/party-lib.sh` helpers; Codex transport is not ported in this plan.
- [ ] Bash entrypoints continue to work during migration and are only retired or thinned after parity and regression proof.
- [ ] The completed phase-simplification changes remain intact; only the explicitly requested cleanup and extraction work is carried forward.

## Non-Goals

- Porting `tmux-codex.sh` away from `session/party-lib.sh` in this plan.
- Replacing tmux with another process supervisor or UI host.
- Reworking the simplified evidence model from `docs/projects/phase-simplification/PLAN.md`.
- Performing an early manifest-schema rewrite merely to suit the Go port.
- Reopening workflow consolidations that research already rejected.

## Technical Reference

Implementation details, package seams, diagrams, and migration sequencing live in [DESIGN.md](./DESIGN.md).
