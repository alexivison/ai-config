# Multi-Agent Planning Specification

## Problem Statement

- The party harness hardcodes Claude as the primary agent and Codex as the companion across session management, manifest state, TUI, messaging, hooks, and transport scripts
- Swapping either agent (e.g., running Codex as primary with Claude as companion, or Gemini as primary with no companion) requires touching Go session lifecycle, manifest schema, TUI code, hooks, shell scripts, and all workflow docs in lock-step
- The TUI has two distinct view modes (worker sidebar + master tracker) that are deeply coupled to the Claude+Codex pairing, doubling the maintenance surface for every agent abstraction change
- Per-project agent configuration is impossible — every repo gets the same agent pairing

## Goal

Make the party harness fully agent-agnostic: any CLI coding agent can fill any role (primary, companion, or both). A unified party tracker replaces the two separate TUI modes, showing all sessions with master-worker hierarchy and enabling switching between them.

## Relationship to Existing Projects

### companion-abstraction

The existing `companion-abstraction` project (in this `docs/projects/` directory) abstracts only the companion (secondary) agent while keeping Claude as the fixed primary. It also depends on PR #119 (shell-to-Go migration of transport layer), which is open with merge conflicts and hasn't landed.

**This project subsumes `companion-abstraction`.** Rather than abstracting the companion first and then re-abstracting the primary (touching the same files twice), we do both in one coherent refactor. The design decisions from `companion-abstraction/DESIGN.md` (Go interface, `.party.toml`, `party-cli agent query` bridge) carry forward and are extended to cover both roles.

**This project does NOT depend on PR #119.** It builds on the current `main` branch. The shell transport scripts (`tmux-codex.sh`, `tmux-claude.sh`) remain functional. If PR #119 lands later, the transport layer can adopt the agent registry as a follow-up.

### source-agnostic-workflow

Complementary project. That decouples execution from TASK file format; this decouples from specific agent CLIs. Both can land in any order.

## User Experience

| Scenario | User Action | Expected Result |
|----------|-------------|-----------------|
| Current setup (no change) | Run `party.sh "task"` with no `.party.toml` | Claude launches as primary, Codex as companion — identical to today |
| Codex as primary | Set `roles.primary.agent = "codex"` in `.party.toml` | Codex launches in the primary pane, Claude (or nothing) as companion |
| Gemini as primary | Add `[agents.gemini]` + set `roles.primary.agent = "gemini"` | Gemini CLI launches as primary; requires a Go adapter file for Gemini |
| No companion | Omit `[roles.companion]` from `.party.toml` | Session runs primary-only; companion evidence requirements skipped in gates |
| TUI sidebar | Any session | Unified party tracker shows all sessions with master→worker hierarchy, companion status inline |
| Master session | Any primary agent | Master mode works — agent receives orchestration instructions via prompt injection or initial prompt |

## Acceptance Criteria

- [ ] A Go `Agent` interface and registry exist that map names to CLI tools, command builders, and resume metadata
- [ ] A `Role` system (`primary`, `companion`) maps roles to agent providers via `.party.toml` or defaults
- [ ] Session startup creates agent panes dynamically from registry — no hardcoded `buildClaudeCmd()` or `buildCodexCmd()`
- [ ] Manifest supports N agents (not just `ClaudeBin` / `codex_thread_id`)
- [ ] `@party_role` pane tags use role names (`primary`, `companion`) not agent names (`claude`, `codex`)
- [ ] All messaging (`Relay`, `Broadcast`, `Read`, `Report`) resolves panes by role, not by hardcoded `"claude"`
- [ ] A unified party tracker TUI replaces both the worker sidebar and master tracker
- [ ] The unified tracker shows master→worker hierarchy (workers indented/nested under their master)
- [ ] The unified tracker shows companion status and evidence inline per-session
- [ ] Master mode is agent-agnostic — any primary agent can orchestrate if given the right prompt
- [ ] Hooks are parameterized by role/companion name — not Codex-specific
- [ ] A `.party.toml` config drives per-project agent and role choices
- [ ] Default behavior with no config file matches today's behavior exactly (Claude as primary, Codex as companion)
- [ ] Existing Go tests pass with agent abstraction (backward compatibility)
- [ ] At least one non-Codex, non-Claude adapter exists as a reference (can be a stub)
- [ ] Graceful degradation when a companion is unavailable: missing CLI detected at startup, session runs primary-only
- [ ] A `party-cli agent query` subcommand exists as a bridge for shell hooks to read registry/config state
- [ ] `party-cli install` is agent-aware — detects configured agents and offers to install missing CLIs
- [ ] All workflow skill prompts reference roles ("the companion"), not hardcoded agent names ("Codex")

## Non-Goals

- Rewriting the execution core sequence (it's already agent-agnostic in its own terms)
- Changing the sub-agent architecture (critic, minimizer, scribe, sentinel stay as Claude sub-agents)
- Porting shell transport scripts to Go (that's PR #119's scope — orthogonal to this)
- Supporting non-tmux transports (HTTP, pipe) in v1
- Multi-companion orchestration logic (v1 uses explicit addressing; one companion per role)
- OpenSpec adapter implementation (separate project)

## Technical Reference

For implementation details, see [DESIGN.md](./DESIGN.md).
For phased task breakdown, see [PLAN.md](./PLAN.md).
