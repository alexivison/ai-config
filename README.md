# ai-config

<p align="center">
  <img src="assets/the-adventuring-party.png" alt="The Adventuring Party — Claude the Adventurer, Codex the Wizard, Gemini the Sage" width="700">
</p>

<p align="center"><em>"Evidence before claims. Tests before implementation."</em></p>

Shared configuration for an adventuring party of AI coding assistants. Each member brings unique strengths; this repo equips them all through symlink-based installation.

## The Party

| Member | Role | Strength |
|--------|------|----------|
| **Claude** | The Adventurer | Blade and code alike — handles all implementation. Companion and tactician of the party. |
| **Codex** | The Wizard | Dispatched for deep reasoning and arcane logic. Sees truths hidden from lesser minds. |
| **Gemini** | The Sage | Keeper of lore and seeker of knowledge. Consulted for research and ancient wisdom. |

## Structure

```
ai-config/
├── claude/          # Claude Code configuration
├── gemini/          # Google Gemini CLI configuration
├── codex/           # OpenAI Codex CLI configuration
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
1. Create config symlinks (`~/.claude`, `~/.gemini`, `~/.codex`)
2. Offer to install missing CLI tools (optional)
3. Offer to run authentication for each tool (optional)

### CLI Installation Methods

| Member | Install Command |
|--------|-----------------|
| Claude | `curl -fsSL https://cli.anthropic.com/install.sh \| sh` |
| Gemini | `npm install -g @google/gemini-cli` |
| Codex | `brew install --cask codex` |

## Uninstallation

```bash
cd ~/Code/ai-config
./uninstall.sh
```

Removes symlinks but keeps the repository.

## Recruiting a New Member

1. Create a directory for the tool: `mkdir -p newtool`
2. Add a `setup_newtool()` function in `install.sh`
3. Add the tool to `uninstall.sh`
4. Run `./install.sh` to create the symlink

## Documentation

- **Claude Code**: See [claude/README.md](claude/README.md) for the Adventurer's full configuration
- **Gemini**: Google Gemini CLI settings and credentials
- **Codex**: OpenAI Codex CLI settings, skills, and agents
