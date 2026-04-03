# Companion Abstraction Implementation Plan

> **Goal:** Make the party harness companion-agnostic so any CLI tool can slot into a named role — without changing the execution core, evidence system, or sub-agent architecture.
>
> **Architecture:** Introduce a companion registry (shell library + `.party.toml` config), an adapter interface (start/send/receive/health per companion), and a transport router that dispatches by role name instead of hardcoded tool name. Existing Codex logic becomes the first adapter.
>
> **Tech Stack:** Bash (registry, adapters, transport, hooks), Go (manifest schema in party-cli), TOML (project config)
>
> **Specification:** [SPEC.md](./SPEC.md) | **Design:** [DESIGN.md](./DESIGN.md)

## Scope

This plan covers the full abstraction from Codex-specific plumbing to companion-agnostic plumbing. It does NOT cover:
- OpenSpec adapter implementation (separate project, builds on this)
- Non-tmux transport backends (designed for, not built)
- Multi-companion orchestration logic (v1 uses explicit `--to <name>` addressing)

**Relationship to `source-agnostic-workflow`:** That project decouples execution from TASK file format. This project decouples from Codex. Both are complementary and can land in any order, but Task 7 below should wait for `source-agnostic-workflow` Task 3 if it lands first (to avoid merge conflicts in CLAUDE.md and execution-core.md).

## Task Granularity

- [x] **Standard** — ~200 lines of implementation (tests excluded), split if >5 files

## Tasks

- [ ] [Task 1](./tasks/TASK1-companion-registry-and-config.md) — Create companion registry, adapter interface, `.party.toml` parser, and Codex adapter (deps: none)
- [ ] [Task 2](./tasks/TASK2-generalize-transport.md) — Rename codex-transport to companion-transport, build routing layer that dispatches via registry (deps: Task 1)
- [ ] [Task 3](./tasks/TASK3-generalize-hooks.md) — Rename and parameterize codex-gate, wizard-guard, codex-trace; make pr-gate config-driven (deps: Task 1)
- [ ] [Task 4](./tasks/TASK4-generalize-session-and-manifest.md) — Dynamic companion window setup in party.sh, companion-generic pane resolution in party-lib.sh, companions array in manifest (deps: Task 1)
- [ ] [Task 5](./tasks/TASK5-update-settings-and-install.md) — Update settings.json hook paths, permissions; make install.sh companion-aware (deps: Task 2, Task 3)
- [ ] [Task 6](./tasks/TASK6-update-hook-tests.md) — Update all hook tests for renamed/generalized hooks (deps: Task 3)
- [ ] [Task 7](./tasks/TASK7-update-docs-and-workflow-skills.md) — Update CLAUDE.md, execution-core.md, and workflow skill prompts to role-based language (deps: Task 2, Task 3, Task 4)
- [ ] [Task 8](./tasks/TASK8-example-stub-adapter.md) — Create a documented example/stub adapter as a reference for writing new companion adapters (deps: Task 1)

## Dependency Graph

```
Task 1 ───┬───> Task 2 ───┬───> Task 5
          │               │
          ├───> Task 3 ───┤───> Task 6
          │               │
          ├───> Task 4 ───┼───> Task 7
          │               │
          └───> Task 8    └───> Task 7
```

## Task Handoff State

| After Task | State |
|------------|-------|
| Task 1 | Registry + adapter interface + Codex adapter exist, but nothing uses them yet. Existing codex-transport still works. |
| Task 2 | Transport routes through registry. `companion-transport` skill replaces `codex-transport`. |
| Task 3 | Hooks are companion-generic. Evidence records companion name instead of "codex". |
| Task 4 | Sessions create companion windows dynamically. Manifest tracks N companions. |
| Task 5 | settings.json and install.sh reference new paths. System is fully wired. |
| Task 6 | All hook tests pass with new names. |
| Task 7 | All docs and skill prompts use role-based language. "Ask the Wizard" still works. |
| Task 8 | A reference adapter exists for anyone writing a new companion integration. |

## Coverage Matrix

| New Concept | Added In | Code Paths Affected | Handled By |
|-------------|----------|---------------------|------------|
| `companion_list` / `companion_cli` | Task 1 (registry) | Transport dispatch, session startup, install | Task 2 (transport), Task 4 (session), Task 5 (install) |
| `adapter_send` / `adapter_start` | Task 1 (interface) | Transport modes, session launch | Task 2 (transport), Task 4 (session) |
| `.party.toml` config | Task 1 (parser) | Evidence requirements, companion selection | Task 3 (pr-gate), Task 4 (session), Task 5 (install) |
| `companion-gate.sh` | Task 3 (hook) | PreToolUse blocking | Task 5 (settings.json), Task 6 (tests) |
| `companion-trace.sh` | Task 3 (hook) | PostToolUse evidence | Task 5 (settings.json), Task 6 (tests) |
| `Companions[]` in manifest | Task 4 (Go) | Session continue/resume | Task 4 (continue.go) |

## Definition of Done

- [ ] All task checkboxes complete
- [ ] Running `./session/party.sh "test"` with NO `.party.toml` works exactly as today (Codex as wizard)
- [ ] Running with `.party.toml` setting a different `companions.wizard.cli` routes to that adapter
- [ ] All existing hook tests pass (renamed)
- [ ] `pr-gate.sh` reads evidence requirements from config
- [ ] CLAUDE.md never mentions "Codex" in plumbing instructions (only as default companion persona)
- [ ] A stub adapter exists demonstrating the interface
- [ ] SPEC.md acceptance criteria satisfied
