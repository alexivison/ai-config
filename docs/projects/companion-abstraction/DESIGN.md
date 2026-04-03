# Companion Abstraction Design

> **Specification:** [SPEC.md](./SPEC.md)

## Architecture Overview

The design introduces three new concepts:

1. **Companion Registry** — A config-driven list of companion agents, each with a role, CLI binary, capabilities, and transport settings
2. **Adapter Interface** — A shell contract (start/send/receive/health) that each companion CLI must implement via a thin wrapper script
3. **Project Config** (`.party.toml`) — Per-repo overrides for companion selection, layout, spec format, and execution tier

The execution core, sub-agents, and evidence system are untouched. Only the plumbing between Claude and external companions changes.

```
┌─────────────────────────────────────────────────┐
│                  Execution Core                  │
│  (sequence, evidence, critics, dispute — NO      │
│   changes)                                       │
└────────────────────┬────────────────────────────┘
                     │ "send to analyzer"
                     ▼
┌─────────────────────────────────────────────────┐
│            Companion Transport Router            │
│  resolve role/capability → adapter → dispatch    │
└───────┬─────────────┬───────────────┬───────────┘
        ▼             ▼               ▼
   ┌─────────┐  ┌──────────┐  ┌────────────┐
   │  Codex   │  │  Gemini  │  │   Stub/    │
   │ Adapter  │  │ Adapter  │  │  Example   │
   └─────────┘  └──────────┘  └────────────┘
```

## Existing Standards

| Pattern | Location | How It Applies |
|---------|----------|----------------|
| Transport dispatch modes | `claude/skills/codex-transport/scripts/tmux-codex.sh:1-200` | Adapter interface mirrors these modes (review, plan-review, prompt, etc.) |
| Pane role metadata | `session/party-lib.sh` (`party_codex_pane_target()`) | Generalize to `party_companion_pane_target "$session" "$role"` |
| Evidence recording | `claude/hooks/lib/evidence.sh` (`append_evidence()`) | Already accepts agent type as string — no change needed |
| Manifest extras | `tools/party-cli/internal/state/manifest.go` (`ExtraString()`) | Use extras pattern for per-companion state (thread IDs, etc.) |
| TOON findings format | `shared/references/agent-transport/scripts/toon-transport.sh` | Already companion-agnostic — no change needed |
| Hook PreToolUse pattern | `claude/settings.json:84-115` | Generalized hook names, same matcher structure |

## File Structure

```
shared/
├── companions/
│   ├── registry.sh               # Create — resolve role→adapter, list, validate
│   └── adapters/
│       ├── interface.md          # Create — adapter contract documentation
│       ├── codex.sh              # Create — wraps existing tmux-codex.sh logic
│       └── example-stub.sh       # Create — reference adapter for new CLIs
claude/
├── skills/
│   ├── companion-transport/      # Rename from codex-transport/
│   │   ├── SKILL.md              # Modify — role-based dispatch
│   │   └── scripts/
│   │       └── tmux-companion.sh # Rename from tmux-codex.sh — routes via registry
├── hooks/
│   ├── companion-gate.sh         # Rename from codex-gate.sh — parameterized
│   ├── companion-guard.sh        # Rename from wizard-guard.sh — parameterized
│   ├── companion-trace.sh        # Rename from codex-trace.sh — parameterized
│   ├── pr-gate.sh                # Modify — read evidence requirements from config
│   └── tests/
│       ├── test-companion-gate.sh    # Rename + update
│       ├── test-companion-trace.sh   # Rename + update
│       └── test-pr-gate.sh           # Modify
session/
├── party-lib.sh                  # Modify — companion-generic pane resolution
├── party.sh                      # Modify — dynamic companion window setup
tools/party-cli/
├── internal/state/manifest.go    # Modify — companions array
├── cmd/continue.go               # Modify — multi-companion resume
.party.toml                       # Create — project config (repo root, optional)
```

**Legend:** `Create` = new file, `Modify` = edit existing, `Rename` = move + modify

## Companion Registry

The registry is a shell library sourced by transport and session scripts. It reads companion definitions from `.party.toml` (project-level) with a hardcoded default fallback (Codex as wizard).

```bash
# registry.sh API
companion_list                          # → "wizard oracle" (space-separated names)
companion_cli "$name"                   # → "codex" (CLI binary)
companion_role "$name"                  # → "analyzer"
companion_capabilities "$name"          # → "review plan prompt"
companion_has_capability "$name" "$cap" # → exit 0/1
companion_adapter "$name"              # → path to adapter script
companion_for_capability "$capability"  # → first companion with that capability
companion_pane_window "$name"          # → tmux window index
```

**Defaults** (when no `.party.toml` exists):

```toml
[companions.wizard]
cli = "codex"
role = "analyzer"
capabilities = ["review", "plan", "prompt"]
pane_window = 0
```

## Adapter Interface

Each adapter is a shell script implementing four functions:

```bash
# $1 = companion name (from registry)
# All functions read companion config via registry.sh

adapter_start "$name" "$session" "$window" "$cwd"
# Launch the companion CLI in the given tmux window.
# Set @party_role metadata on the pane.
# Handle thread resumption if state file exists.

adapter_send "$name" "$session" "$mode" "$payload" "$work_dir"
# Dispatch work to the companion. Modes: review, plan-review, prompt,
# review-complete, needs-discussion, triage-override.
# Write companion status file. Return immediately (non-blocking).

adapter_receive "$name" "$session"
# Check for completed work. Return findings file path if ready,
# empty string if still working. Called by polling or tmux hooks.

adapter_health "$name" "$session"
# Check if companion pane is alive and responsive.
# Exit 0 = healthy, 1 = dead/unresponsive.
```

The **Codex adapter** (`codex.sh`) wraps the existing `tmux-codex.sh` logic — it's a refactor, not a rewrite. The mode dispatch, TOON handling, and status file writing move into the adapter.

## Project Config (`.party.toml`)

```toml
# .party.toml — optional, lives in repo root
# Absence = defaults (Codex as wizard, classic layout, full tier)

[party]
layout = "classic"                 # classic | sidebar

[companions.wizard]
cli = "codex"                      # CLI binary name
role = "analyzer"                  # semantic role
capabilities = ["review", "plan", "prompt"]
pane_window = 0                    # tmux window index (0 = hidden)

# Example second companion (commented out):
# [companions.oracle]
# cli = "gemini-cli"
# role = "researcher"
# capabilities = ["prompt", "research"]
# pane_window = 2

[specs]
format = "internal"                # internal | openspec (future adapter)

[evidence]
# Override required evidence types for pr-gate
# Default: ["pr-verified", "code-critic", "minimizer", "companion", "test-runner", "check-runner"]
# Quick-tier: ["quick-tier", "code-critic", "test-runner", "check-runner"]
# Set to skip companion review (e.g. solo mode):
# required = ["pr-verified", "code-critic", "minimizer", "test-runner", "check-runner"]
```

**Resolution order:** `.party.toml` in CWD → walk up to git root → global defaults.

## Data Flow (Transport Routing)

```
Claude skill invokes:
  /companion-transport --to wizard --review <work_dir>
       │
       ▼
  tmux-companion.sh
       │
       ├── source registry.sh
       ├── resolve: companion_adapter "wizard" → adapters/codex.sh
       ├── source adapters/codex.sh
       └── call: adapter_send "wizard" "$session" "review" "$work_dir"
              │
              ├── resolve pane: party_companion_pane_target "$session" "wizard"
              ├── write status: companion-status-wizard.json
              └── tmux send-keys to codex pane (existing mechanism)
```

Return path (Codex → Claude) is unchanged in v1 — `tmux-claude.sh` already uses `@party_role` for routing.

## Integration Points

| Point | Existing Code | New Code Interaction |
|-------|---------------|----------------------|
| Transport dispatch | `tmux-codex.sh` (all 6 modes) | Logic moves into `codex.sh` adapter; `tmux-companion.sh` is the router |
| PreToolUse gate | `codex-gate.sh` (blocks `--approve`) | `companion-gate.sh` blocks `--approve` for ANY companion adapter |
| PreToolUse guard | `wizard-guard.sh` (blocks direct tmux to Codex) | `companion-guard.sh` blocks direct tmux to ANY companion pane |
| PostToolUse trace | `codex-trace.sh` (records evidence) | `companion-trace.sh` records evidence with companion name as type |
| PR gate | `pr-gate.sh` hardcodes `REQUIRED="... codex ..."` | Reads required list from `.party.toml` or defaults; replaces `codex` with active companion name(s) |
| Session startup | `party.sh` creates Codex window at index 0 | Iterates `companion_list`, calls `adapter_start` for each |
| Pane resolution | `party_codex_pane_target()` | `party_companion_pane_target "$session" "$name"` — same logic, parameterized |
| Manifest state | `codex_thread_id` in extras | `companion_<name>_thread_id` pattern in extras |
| install.sh | `setup_codex()` hardcoded | Iterates registered companions, calls per-adapter install hints |
| settings.json | Hook paths reference `codex-gate.sh`, etc. | Updated paths: `companion-gate.sh`, `companion-guard.sh`, `companion-trace.sh` |

## Design Decisions

| Decision | Rationale | Alternatives Considered |
|----------|-----------|-------------------------|
| Shell adapter interface (not Go) | Adapters are thin wrappers (~50 lines); shell keeps them accessible and matches existing transport scripts | Go plugin system (rejected: overkill, rebuild required for new adapter) |
| `.party.toml` not `.party.json` | TOML is human-editable, supports comments, matches modern CLI conventions | JSON (no comments), YAML (whitespace fragile) |
| Registry as shell library (not daemon) | Sourced by scripts that need it; no long-running process; matches `party-lib.sh` pattern | Registry service (rejected: complexity for no benefit) |
| Rename files (not add wrappers) | Clean break avoids dual-path bugs; git tracks renames for blame history | Keep codex-* names and add aliases (rejected: confusing, maintenance burden) |
| Default to Codex when no config | Zero-config backward compatibility; existing users don't need `.party.toml` | Require `.party.toml` (rejected: breaking change) |
| `--to <name>` addressing (not capability-first in v1) | Explicit routing is simpler and debuggable; capability routing can layer on top | Capability-only routing (rejected: ambiguous when multiple companions share a capability) |
| Evidence type = companion name | `append_evidence()` already accepts arbitrary type strings; `"wizard"` instead of `"codex"` | Separate evidence namespace (rejected: unnecessary indirection) |

## External Dependencies

- **TOML parser for shell:** `tomlq` (via `yq` with TOML support) or a minimal Go helper in party-cli. If neither available, fall back to simple `grep`/`sed` parsing of the flat TOML structure.
- **No new CLI tools required for v1.** Only the adapter scripts are new; the companion CLIs themselves are user-provided.
