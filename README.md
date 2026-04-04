# ai-party

<p align="center">
  <img src="assets/the-adventuring-party.png" alt="The Adventuring Party — Claude the Warforged Paladin, the Mastermind Rogue, and The Wizard (High Elf)" width="700">
</p>

<p align="center"><em>"Evidence before claims. Tests before implementation."</em></p>

Shared configuration and orchestration for an adventuring party of AI coding assistants. Each member brings unique strengths; this repo equips them through symlink-based installation and launches them side by side in a tmux party session.

## The Party

| Member | Class | Role |
|--------|-------|------|
| **The User** | Mastermind Rogue | Commander and final authority. Leads the party. |
| **Claude** | Warforged Paladin | Living construct of steel and divine fire. Implementation, testing, orchestration. |
| **The Wizard** | High Elf Wizard | Ancient arcanist of deep intellect. Deep reasoning, analysis, review. |

## Structure

```
ai-party/
├── assets/          # Static assets (banner image)
├── claude/          # Claude Code configuration (hooks, skills, agents, rules)
├── codex/           # OpenAI Codex CLI configuration
├── docs/            # Project documentation
├── nvim/            # Neovim (LazyVim) configuration
├── shared/          # Skills shared by both platforms
├── session/         # Shell wrappers and retained routing library
│   ├── party.sh              # Thin wrapper — delegates to party-cli
│   ├── party-lib.sh          # State helpers, locking, routing (retained for tmux-codex.sh)
│   ├── party-relay.sh        # Thin wrapper — delegates to party-cli
│   ├── party-picker.sh       # Thin wrapper — delegates to party-cli picker
│   ├── party-preview.sh      # Thin wrapper — delegates to party-cli picker preview
│   └── party-master-jump.sh  # tmux keybinding: jump from worker to master
├── tools/
│   ├── party-cli/         # Unified Go binary: TUI + CLI (primary implementation)
│   └── (party-tracker removed — functionality absorbed into party-cli)
├── tmux/            # tmux configuration
├── tests/           # Test suite
├── install.sh       # Install CLIs, create symlinks
├── uninstall.sh     # Remove symlinks
└── README.md
```

## Installation

```bash
# Clone the repo
git clone git@github.com:alexivison/ai-party.git ~/Code/ai-party

# Full install (symlinks + CLI installation + auth)
cd ~/Code/ai-party
./install.sh

# Or symlinks only (install CLIs yourself)
./install.sh --symlinks-only
```

The installer will:
1. Create config symlinks (`~/.claude`, `~/.codex`, `~/.config/nvim`, `~/.tmux.conf`)
2. Offer to install missing CLI tools (optional)
3. Offer to run authentication for each tool (optional)

### CLI Installation Methods

| Dependency | Install Command |
|------------|-----------------|
| Claude | `curl -fsSL https://cli.anthropic.com/install.sh \| sh` |
| Codex | `brew install --cask codex` |
| tmux | `brew install tmux` |
| fzf | `brew install fzf` |
| Go | `brew install go` *(required — for building party-cli)* |

> **Note:** tmux and fzf are required for party sessions. Go is required to build party-cli, the unified binary that powers all session operations.

## Uninstallation

```bash
cd ~/Code/ai-party
./uninstall.sh
```

Removes symlinks but keeps the repository.

## Usage

Launch a party session to run Claude and The Wizard side by side in a three-pane tmux layout:

```bash
./session/party.sh "my task"
```

### Standard Session

Each party is a standalone tmux session with three panes:

| Pane | Role | Agent |
|------|------|-------|
| 0 | `codex` | The Wizard (Codex CLI) |
| 1 | `claude` | The Paladin (Claude Code) |
| 2 | `shell` | Operator terminal |

### Master Session

A master session replaces the Wizard pane with an interactive tracker TUI. The master Claude acts as an orchestrator, dispatching work to worker sessions instead of implementing directly.

```bash
./session/party.sh --master "Project Alpha"
```

| Pane | Role | Agent |
|------|------|-------|
| 0 | `tracker` | Party Tracker (Bubble Tea TUI) |
| 1 | `claude` | The Paladin (orchestrator) |
| 2 | `shell` | Operator terminal |

Workers are separate sessions registered under the master:

```bash
./session/party.sh --detached --master-id <master-id> "ENG-456 fix auth"
```

The tracker shows live status of all workers with vim-style navigation. Press `Enter` to jump to a worker, `r` to relay a message, `b` to broadcast, `s` to spawn, `x` to stop.

Any standalone session can be promoted to master mid-flight:

```bash
./session/party.sh --promote
```

### Flags

| Flag | Description |
|------|-------------|
| *(none)* | Start a new party session |
| `--master` | Start a master session (tracker + orchestrator) |
| `--master-id <id>` | Start a worker session registered under a master |
| `--promote [party-id]` | Promote a standalone session to master |
| `--switch` | Interactive session switcher |
| `--continue [party-id]` | Resume a session; opens interactive fzf picker if no ID given |
| `--list` | List active and resumable party sessions |
| `--stop [name]` | Stop one or all party sessions |
| `--detached` | Launch without attaching |
| `--prompt "text"` | Send an initial prompt to Claude |
| `--install-tpm` | Install tmux Plugin Manager |

### Session Picker

The interactive picker (requires [fzf](https://github.com/junegunn/fzf)) groups sessions hierarchically:

```
party-1741230000  active       solo task          ~/Code/project-a
party-1741234567  master (2)   Project Alpha      ~/Code/project-b
  party-1741234568  worker     ENG-456 fix auth   ~/Code/project-b
  party-1741234569  worker     ENG-789 dark mode  ~/Code/project-b
── resumable ──────────────────────────────
party-1741200000  03/10        old-task           ~/Code/project-c
```

Supports **Enter** to switch/resume, **Ctrl-D** to delete, and **Esc** to cancel.

### State

Party metadata is persisted under `~/.party-state/<party-id>.json`. Runtime handoff files in `/tmp/<party-id>/` are rebuilt on demand. Manifests older than 7 days are auto-pruned on start (configurable via `PARTY_PRUNE_DAYS`).

Transport scripts (`tmux-codex.sh`, `tmux-claude.sh`) route messages by `@party_role` metadata and scan all windows in a session, so routing works regardless of pane layout.

## Documentation

- **Claude Code**: See [claude/CLAUDE.md](claude/CLAUDE.md) for the Paladin's full configuration
- **Codex**: See [codex/AGENTS.md](codex/AGENTS.md) for the Wizard's configuration
