# Task 8 — CLI Flags, Settings, and Install

**Dependencies:** Task 7
**Branch:** `feature/multi-agent-planning`

## Goal

Update CLI flags (`--resume-claude`/`--resume-codex` → `--resume-agent`), update `settings.json` hook paths to point to new hook files, and make the install script agent-aware.

## Scope Boundary

**In scope:**
- `tools/party-cli/cmd/start.go` — New `--primary`, `--companion`, `--no-companion`, `--resume-agent` flags; keep old flags as hidden aliases
- `tools/party-cli/cmd/spawn.go` — Same flag changes
- `claude/settings.json` — Update hook paths from old names to new names
- `session/party.sh` — Forward new flags, keep old flag aliases
- `install.sh` — Agent-aware CLI detection

**Out of scope:**
- Session lifecycle changes (already done in Task 2)
- TUI changes (Task 5)
- Hook logic (Task 7 — already done)

## Reference Files

### CLI flags

- `tools/party-cli/cmd/start.go` — Lines 19-20, 66-73: `--resume-claude` and `--resume-codex` flags. These map to `StartOpts.ClaudeResumeID` and `StartOpts.CodexResumeID`.
- `tools/party-cli/cmd/spawn.go` — Lines 15, 64-70: Same flags for spawn.

### Settings

- `claude/settings.json` — **Read the entire file (212 lines).** Key sections:
  - Lines 88-90: `codex-gate.sh` reference → `companion-gate.sh`
  - Lines 92-94: `codex-gate.sh` log path → `companion-gate.sh`
  - Lines 96-100: `pr-gate.sh` — unchanged (already generic)
  - Lines 101-103: `wizard-guard.sh` reference → `companion-guard.sh`
  - Lines 107-114: `claude-state.sh` references → `primary-state.sh`
  - Lines 180-188: PostToolUse `codex-trace.sh` → `companion-trace.sh`
  - Line 42: Permission for `tmux-codex.sh` — keep (backward compat via symlinks)

### Shell wrapper

- `session/party.sh` — Lines 166-171: `--resume-claude` and `--resume-codex` flag parsing.

### Install script

- `install.sh` — Lines 1-60: Has `setup_claude()` and `setup_codex()` functions (not shown but inferred from structure). Should detect agents from `.party.toml` or defaults.

## Files to Create/Modify

| File | Action | Key Changes |
|------|--------|-------------|
| `tools/party-cli/cmd/start.go` | Modify | Add `--resume-agent` flag; keep old flags as hidden aliases |
| `tools/party-cli/cmd/spawn.go` | Modify | Same flag changes |
| `claude/settings.json` | Modify | Update hook paths to new names |
| `session/party.sh` | Modify | Update flag names with backward compat |
| `install.sh` | Modify | Agent-aware CLI detection |

## Requirements

### New CLI Flags: `--primary`, `--companion`, `--no-companion`

These flags override `.party.toml` agent selection per-session:

```go
var primaryAgent, companionAgent string
var noCompanion bool
cmd.Flags().StringVar(&primaryAgent, "primary", "", "agent to use as primary (e.g. codex, claude)")
cmd.Flags().StringVar(&companionAgent, "companion", "", "agent to use as companion (e.g. claude, codex)")
cmd.Flags().BoolVar(&noCompanion, "no-companion", false, "run without a companion agent")
```

In `RunE`, pass to registry via `ConfigOverrides`:
```go
overrides := &agent.ConfigOverrides{
    Primary:     primaryAgent,
    Companion:   companionAgent,
    NoCompanion: noCompanion,
}
registry, err := agent.NewRegistry(agent.LoadConfig(cwd, overrides))
```

These flags go on both `start` and `spawn` commands.

### New CLI Flag: `--resume-agent`

New syntax: `--resume-agent primary=<id>` or `--resume-agent companion=<id>`. Can be specified multiple times.

```go
var resumeAgents []string
cmd.Flags().StringArrayVar(&resumeAgents, "resume-agent", nil, "resume agent: ROLE=ID (e.g. primary=abc123)")
```

Parse in `RunE`:
```go
resumeMap := parseResumeFlags(resumeAgents)
// Also check old flags for backward compat
if opts.resumeClaude != "" { resumeMap["claude"] = opts.resumeClaude }
if opts.resumeCodex != ""  { resumeMap["codex"] = opts.resumeCodex }
```

Old flags kept but marked hidden:
```go
cmd.Flags().StringVar(&opts.resumeClaude, "resume-claude", "", "Claude session ID to resume (deprecated: use --resume-agent primary=ID)")
cmd.Flags().StringVar(&opts.resumeCodex, "resume-codex", "", "Codex thread ID to resume (deprecated: use --resume-agent companion=ID)")
cmd.Flags().MarkHidden("resume-claude")
cmd.Flags().MarkHidden("resume-codex")
```

### settings.json Updates

Replace hook command paths (keep log file paths consistent with new names):

```json
"command": "~/.claude/hooks/companion-gate.sh 2>>~/.claude/logs/hook-debug-companion-gate.log"
"command": "~/.claude/hooks/companion-guard.sh"
"command": "~/.claude/hooks/primary-state.sh"
"command": "~/.claude/hooks/companion-trace.sh"
```

The symlinks from Task 7 mean the old paths also work, but settings.json should use the canonical new names.

### party.sh Flag Updates

Add `--primary`, `--companion`, `--no-companion`, and `--resume-agent` flag forwarding. Keep `--resume-claude` and `--resume-codex` as aliases:

```bash
--primary) _party_primary="${2:?--primary requires an agent name}"; shift 2 ;;
--companion) _party_companion="${2:?--companion requires an agent name}"; shift 2 ;;
--no-companion) _party_no_companion=1; shift ;;
```

Then pass to party-cli:
```bash
[[ -n "$_party_primary" ]]       && start_args+=(--primary "$_party_primary")
[[ -n "$_party_companion" ]]     && start_args+=(--companion "$_party_companion")
[[ "$_party_no_companion" -eq 1 ]] && start_args+=(--no-companion)
```

For resume flags:

```bash
--resume-agent) _party_resume_agents+=("${2:?--resume-agent requires ROLE=ID}"); shift 2 ;;
--resume-claude) _party_resume_agents+=("primary=${2:?--resume-claude requires a session ID}"); shift 2 ;;
--resume-codex)  _party_resume_agents+=("companion=${2:?--resume-codex requires a session ID}"); shift 2 ;;
```

Then pass to party-cli:
```bash
for ra in "${_party_resume_agents[@]}"; do
  start_args+=(--resume-agent "$ra")
done
```

### install.sh Changes

The install script currently has hardcoded Claude and Codex setup. Make it agent-aware:

1. Read `.party.toml` if present (simple grep for `cli = "..."` lines, or call `party-cli agent query names` if party-cli is built)
2. For each configured agent: check if CLI is installed, offer to install if missing
3. Default behavior (no `.party.toml`): check for Claude and Codex (same as today)

## Tests

- `--primary codex` overrides `.party.toml` → session starts with Codex as primary
- `--companion claude` overrides `.party.toml` → session starts with Claude as companion
- `--no-companion` → session starts with no companion (single-agent mode)
- `--primary codex --no-companion` → Codex solo session
- `--resume-agent primary=abc` correctly maps to primary agent resume
- `--resume-claude abc` (old flag) still works, maps to resume for Claude
- Both old and new flags in same command → both applied
- settings.json has no references to old hook names (except in log paths if desired)

## Acceptance Criteria

- [x] `--resume-agent` flag works on `start` and `spawn` commands
- [x] Old `--resume-claude`/`--resume-codex` flags still work (hidden)
- [x] `settings.json` points to new hook file names
- [x] `party.sh` forwards new flag format
- [x] `install.sh` handles agent-aware CLI detection
