# Multi-Agent Planning Implementation Plan

> **Goal:** Make the party harness fully agent-agnostic — any CLI coding agent can fill the primary or companion role — and replace the two separate TUI modes with a unified party tracker showing master→worker hierarchy.
>
> **Architecture:** Introduce a Go `Agent` interface, role-based registry, user-global config, agent-agnostic session lifecycle, and unified party tracker TUI.
>
> **Tech Stack:** Go (agent package, session, state, tui, cmd), TOML (project config), Bash (hooks and existing transport wrappers, with `party-cli agent query` bridge)
>
> **Specification:** [SPEC.md](./SPEC.md) | **Design:** [DESIGN.md](./DESIGN.md)

## Prerequisites

- Current `main` branch. No dependency on PR #119 (shell-to-Go transport migration).
- Go 1.25+ (already in go.mod)
- TOML parser dependency added in Task 1

## Scope

This plan covers:
- Agent interface and provider implementations (Claude, Codex, stub)
- Role system and user-global config
- Agent-agnostic session lifecycle (start, continue, spawn, promote)
- Manifest schema evolution with backward compatibility
- Unified party tracker TUI with master→worker hierarchy
- Agent-agnostic messaging (relay, broadcast, read, report)
- Shell transport compatibility updates in the existing Bash layer (`party-lib.sh`, `party-relay.sh`, `tmux-codex.sh`, `tmux-claude.sh`)
- Hook generalization (companion-gate, companion-trace, companion-guard, primary-state)
- CLI flag updates and backward-compatible aliases

This plan does NOT cover:
- Shell transport script migration to Go (PR #119 scope)
- OpenSpec adapter (separate project)
- Non-tmux transports

## Feature Branch

All work is done on a feature branch: `feature/multi-agent-planning`. PRs from this branch are merged to `main` per-task or in phase batches.

## Task Granularity

- [x] **Standard** — ~200-400 lines of implementation (tests excluded), ≤5 files per task

## Tasks

- [x] [Task 1](./tasks/TASK1-agent-interface-and-registry.md) — Create Go `Agent` interface, registry, the initial config parser, Claude/Codex/stub providers, and `party-cli agent query` subcommand (deps: none)
- [x] [Task 2](./tasks/TASK2-agent-agnostic-session-lifecycle.md) — Refactor session start/continue/spawn to use agent registry; evolve manifest schema (deps: Task 1)
- [x] [Task 3](./tasks/TASK3-agent-agnostic-layouts.md) — Refactor layout functions to use role-based `@party_role` values and role→command maps (deps: Task 2)
- [x] [Task 4](./tasks/TASK4-agent-agnostic-messaging.md) — Refactor messaging and shell transport helpers/scripts to resolve panes by role (deps: Task 3)
- [x] [Task 5](./tasks/TASK5-unified-party-tracker.md) — Build the unified party tracker TUI replacing both worker sidebar and master tracker, with master→worker hierarchy (deps: Task 3, Task 4)
- [x] [Task 6](./tasks/TASK6-agent-agnostic-promote.md) — Refactor promote to use role-based pane resolution and agent-agnostic master mode (deps: Task 3)
- [x] [Task 7](./tasks/TASK7-generalize-hooks.md) — Rename and parameterize hooks; make pr-gate config-driven; add `party-cli agent query` consumption (deps: Task 1)
- [x] [Task 8](./tasks/TASK8-cli-flags-and-compat.md) — Update CLI flags (`--resume-agent`), backward-compatible aliases, settings.json hook paths, and install script (deps: Task 7)
- [x] [Task 9](./tasks/TASK9-update-docs-and-skills.md) — Update CLAUDE.md, AGENTS.md, execution-core.md, workflow skill prompts to role-based language (deps: Tasks 2-6)
- [x] [Task 10](./tasks/TASK10-tests-and-compat-verification.md) — Extend tests for multi-agent scenarios, verify zero-config backward compatibility, manifest migration (deps: all)
- [x] [Task 11](./tasks/TASK11-relocate-config-to-user-global.md) — Relocate agent config to `~/.config/party-cli/config.toml` and add `party-cli config` (deps: Tasks 1-10)

## Dependency Graph

```
Task 1 (foundation) ──────┬──> Task 2 (session) ──> Task 3 (layouts) ──┬──> Task 5 (tracker TUI)
                          │                                            │
                          │                                            ├──> Task 4 (messaging) ──> Task 5
                          │                                            │
                          │                                            ├──> Task 6 (promote)
                          │                                            │
                          ├──> Task 7 (hooks) ──> Task 8 (CLI/compat)  │
                          │                                            │
                          └────────────────────────────────────────────┴──> Task 9 (docs)
                                                                           │
                                                                           └──> Task 10 (tests)
```

Tasks 4, 5, 6 can progress in parallel after Task 3.
Task 7 can progress in parallel with Tasks 2-6 (only depends on Task 1).
Task 9 depends on the code changes being stable (Tasks 2-6).
Task 10 is the final verification gate.

## Task Handoff State

| After Task | State |
|------------|-------|
| Task 1 | `Agent` interface, registry, config parser, Claude/Codex/stub providers, `party-cli agent query` subcommand exist. Nothing uses them yet. All existing code unchanged. |
| Task 2 | `session/start.go` and `session/continue.go` use registry. `buildClaudeCmd()`/`buildCodexCmd()` deleted (logic in providers). Manifest has `Agents[]` with migration. Old manifests still work. |
| Task 3 | Layout functions accept role→command maps. `@party_role` values are `"primary"`/`"companion"`. Backward compat fallback in `ResolveRole()`. |
| Task 4 | All messaging functions and shell transport helpers resolve panes by role. `"claude"` no longer hardcoded in `message/message.go`; Bash transport wrappers honor `primary`/`companion` with legacy fallback. |
| Task 5 | Unified party tracker replaces `ViewWorker` and `ViewMaster`. Master→worker hierarchy displayed. Companion status and evidence inline. |
| Task 6 | `promote.go` uses role-based pane resolution. Master mode injects prompt via `agent.MasterPrompt()`. |
| Task 7 | Hooks renamed and parameterized. `pr-gate.sh` reads evidence requirements from config. |
| Task 8 | CLI flags updated. Old flags aliased. `settings.json` points to new hooks. Install is agent-aware. |
| Task 9 | All docs and skill prompts use role-based language. |
| Task 10 | All tests pass. Zero-config matches today's behavior. Manifest migration verified. |

## Definition of Done

- [x] All task checkboxes complete
- [x] Running `party.sh "test"` with NO user config file works exactly as today (Claude primary + Codex companion)
- [x] Running with user-global config setting Codex as primary routes correctly
- [x] Running with user-global config omitting companion starts primary-only session
- [x] `tmux-codex.sh` / `tmux-claude.sh` still route correctly after the role-tag migration
- [x] Unified party tracker shows master→worker hierarchy
- [x] All Go tests pass (existing + new)
- [x] All hook tests pass (renamed)
- [x] A stub agent exists demonstrating the interface
- [x] SPEC.md acceptance criteria satisfied
