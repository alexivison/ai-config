# Companion Abstraction Specification

## Problem Statement

- The party harness hardcodes Codex as the sole companion agent across transport, hooks, session management, manifest state, and workflow docs
- Adding or swapping a companion CLI (Gemini, Aider, OpenSpec agent, etc.) requires touching 20+ files in lock-step
- Per-project configuration is impossible — every repo gets the same companion, layout, and evidence requirements
- Planning/spec templates are internal-only; teams using external spec formats (e.g., OpenSpec) have no integration path

## Goal

Make the party harness companion-agnostic: any CLI tool that can review code, create plans, or answer prompts can slot in as a companion — with zero changes to the execution core, evidence system, or sub-agent architecture.

## User Experience

| Scenario | User Action | Expected Result |
|----------|-------------|-----------------|
| Current setup (no change) | Run `./session/party.sh "task"` with no `.party.toml` | Codex launches as "wizard" in hidden window, everything works as today |
| Swap companion | Set `companions.wizard.cli = "gemini-cli"` in `.party.toml` | Gemini CLI launches in the Wizard pane, transport routes to it |
| Add second companion | Add `[companions.oracle]` block to `.party.toml` | Second hidden window created, skills can address either by role |
| Say "ask the Wizard" | Type naturally in Claude session | Claude resolves "Wizard" → active analyzer companion via CLAUDE.md mapping |
| OpenSpec team repo | Set `specs.format = "openspec"` in `.party.toml` | Plan workflow imports/exports OpenSpec; execution core unchanged |
| No companion available | `.party.toml` has `companions = {}` or companion CLI not installed | Harness runs Claude-only; review gates skip companion evidence (quick-tier-like) |

## Acceptance Criteria

- [ ] A companion registry exists that maps role names to CLI tools, capabilities, and transport config
- [ ] Transport layer routes by role/capability, not by hardcoded tool name
- [ ] Hooks (gate, guard, trace) are parameterized by companion name — not Codex-specific
- [ ] `pr-gate.sh` reads required evidence types from config, not a hardcoded string
- [ ] Session startup creates companion windows dynamically from registry
- [ ] Manifest supports N companions (not just `codex_pane` / `codex_thread_id`)
- [ ] A `.party.toml` (or equivalent) config drives per-project companion and spec format choices
- [ ] Default behavior with no config file matches today's behavior exactly (Codex as wizard)
- [ ] Existing Codex adapter passes all current hook tests (backward compatibility)
- [ ] CLAUDE.md and workflow skills reference roles ("the analyzer", "The Wizard"), not tool names
- [ ] install.sh is companion-aware (iterates registered companions)
- [ ] At least one non-Codex adapter exists as a reference (can be a stub/example)

## Non-Goals

- Rewriting the execution core sequence (it's already agent-agnostic)
- Changing the sub-agent architecture (critic, minimizer, scribe, sentinel stay as-is)
- Adding OpenSpec parsing/generation (that's a separate project that builds on this)
- Supporting non-tmux transports (HTTP, pipe) in v1 — design for it, don't build it
- Multi-companion orchestration logic (who reviews when) — v1 uses explicit addressing

## Related Projects

- `source-agnostic-workflow` — Decouples execution from TASK file format. Complementary; this project decouples from Codex. Both should land.

## Technical Reference

For implementation details, see [DESIGN.md](./DESIGN.md).
