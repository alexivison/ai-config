# ai-config

<p align="center">
  <img src="assets/the-adventuring-party.png" alt="The Adventuring Party — Claude the Warforged Paladin, the Mastermind Rogue, and Codex the High Elf Wizard" width="700">
</p>

<p align="center"><em>"Evidence before claims. Tests before implementation."</em></p>

Shared configuration and orchestration for an adventuring party of AI coding assistants. Each member brings unique strengths; this repo equips them through symlink-based installation and launches them side by side in a tmux party session.

## The Party

| Member | Class | Role |
|--------|-------|------|
| **The User** | Mastermind Rogue | Commander and final authority. Leads the party. |
| **Claude** | Warforged Paladin | Living construct of steel and divine fire. Implementation, testing, orchestration. |
| **Codex** | High Elf Wizard | Ancient arcanist of deep intellect. Deep reasoning, analysis, review. |

## Structure

```
ai-config/
├── claude/          # Claude Code configuration
├── codex/           # OpenAI Codex CLI configuration
├── shared/          # Skills shared by both platforms
├── session/         # tmux party session launcher
├── tmux/            # tmux configuration
├── tests/           # Test suite
├── install.sh       # Install CLIs and create symlinks
├── uninstall.sh     # Remove symlinks
└── README.md
```

## Installation

```bash
# Clone the repo
git clone git@github.com:alexivison/ai-config.git ~/Code/ai-config

# Full install (symlinks + CLI installation + auth)
cd ~/Code/ai-config
./install.sh

# Or symlinks only (install CLIs yourself)
./install.sh --symlinks-only
```

The installer will:
1. Create config symlinks (`~/.claude`, `~/.codex`, `~/.tmux.conf`)
2. Offer to install missing CLI tools (optional)
3. Offer to run authentication for each tool (optional)

### CLI Installation Methods

| Dependency | Install Command |
|------------|-----------------|
| Claude | `curl -fsSL https://cli.anthropic.com/install.sh \| sh` |
| Codex | `brew install --cask codex` |
| tmux | `brew install tmux` |

> **Note:** tmux is required for the party session (`session/party.sh`). The installer does not install tmux automatically.

## Uninstallation

```bash
cd ~/Code/ai-config
./uninstall.sh
```

Removes symlinks but keeps the repository.

## Usage

Launch a party session to run Claude and Codex side by side in a three-pane tmux layout:

```bash
./session/party.sh
```

Default pane layout:

| Pane | Role | Agent |
|------|------|-------|
| 0 | `codex` | The Wizard (Codex CLI) |
| 1 | `claude` | The Paladin (Claude Code) |
| 2 | `shell` | Operator terminal |

Transport scripts (`tmux-codex.sh`, `tmux-claude.sh`) route messages by `@party_role` metadata rather than fixed pane indices, so the layout remains correct even if panes are reordered. Legacy two-pane sessions without role metadata fall back to the original index-based routing.

| Flag | Description |
|------|-------------|
| *(none)* | Start a new party session |
| `--continue [party-id]` | Resume a session; opens interactive fzf picker if no ID given |
| `--list` | List active and resumable party sessions |
| `--stop [name]` | Stop one or all party sessions |
| `--install-tpm` | Install tmux Plugin Manager |

Party metadata is persisted under `~/.party-state/<party-id>.json`. Runtime handoff files in `/tmp/<party-id>/` are rebuilt on demand. Manifests older than 7 days are auto-pruned on start (configurable via `PARTY_PRUNE_DAYS`).

The interactive picker (requires [fzf](https://github.com/junegunn/fzf)) supports **Enter** to resume, **Ctrl-D** to delete, and **Esc** to cancel.

## Documentation

- **Claude Code**: See [claude/CLAUDE.md](claude/CLAUDE.md) for the Paladin's full configuration
- **Codex**: See [codex/AGENTS.md](codex/AGENTS.md) for the Wizard's configuration
