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
| Codex as primary (per-session) | Run `party.sh --primary codex "task"` | Codex launches in the primary pane for this session only |
| Codex as primary (per-repo) | Set `roles.primary.agent = "codex"` in `.party.toml` | All sessions in this repo use Codex as primary |
| Override repo default | `.party.toml` says Codex primary, run `party.sh --primary claude "task"` | This session uses Claude despite repo config |
| Gemini as primary | Add `[agents.gemini]` to `.party.toml` + `--primary gemini` | Gemini CLI launches; requires a Go adapter file |
| No companion | Run `party.sh --no-companion "task"` | Session runs primary-only; companion evidence skipped |
| TUI sidebar | Any session | Unified party tracker shows all sessions with master→worker hierarchy |
| Master session | Any primary agent | Master mode works — agent receives orchestration instructions via prompt |

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
- Making the review cascade agent-agnostic (hooks, sub-agents, evidence gates, PR gate are Claude Code-specific — see Known Limitations)
- Porting shell transport scripts to Go (that's PR #119's scope — orthogonal to this)
- Supporting non-tmux transports (HTTP, pipe) in v1
- Multi-companion orchestration logic (v1 uses explicit addressing; one companion per role)
- OpenSpec adapter implementation (separate project)

## Known Limitations

### Review cascade only works with Claude as primary

The review cascade (hooks → sub-agents → evidence → PR gate) is built on Claude Code-specific features:
- **Hooks** (PreToolUse, PostToolUse, SessionStart, etc.) — only Claude Code supports these
- **Sub-agents** (code-critic, minimizer, test-runner, check-runner, scribe, sentinel) — Claude Code sub-agent framework
- **Skills** (task-workflow, codex-transport, etc.) — Claude Code SKILL.md framework
- **Evidence system** (JSONL logs, diff-hash gating) — powered by hooks
- **PR gate** (blocks `gh pr create` without evidence) — PreToolUse hook on Bash

When a non-Claude agent is the primary (e.g., Codex), none of these mechanisms exist. The session runs in **autonomous mode** — no review cascade, no PR gating, no sub-agent critics. The companion (if configured) can still be dispatched for review via transport scripts, but nothing *enforces* the review workflow.

This is an accepted trade-off for v1. Moving the cascade into party-cli as an agent-agnostic enforcement layer is a potential future project.

## Technical Reference

For implementation details, see [DESIGN.md](./DESIGN.md).
For phased task breakdown, see [PLAN.md](./PLAN.md).
