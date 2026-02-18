# AGENTS.md

Multi-agent configuration for AI-assisted development.

## Architecture

```
Claude Code (Orchestrator — Claude Opus)
    ├── Internal agents (via Task tool)
    │   ├── code-critic, minimizer, security-scanner  (sonnet)
    │   └── test-runner, check-runner                  (haiku)
    └── Wizard — Codex CLI wrapper (sonnet → GPT-5.3 xhigh reasoning)
```

## Installation

```bash
./install.sh                  # Symlinks + optional CLI install + auth
./install.sh --symlinks-only  # Symlinks only
```

Symlinks: `~/.claude` → `claude/`, `~/.codex` → `codex/`

## Configuration

| Agent | Config root | Key files |
|-------|-------------|-----------|
| Claude Code | `claude/` | `CLAUDE.md`, `settings.json`, `agents/*.md`, `skills/*/SKILL.md`, `rules/*.md`, `hooks/*.sh` |
| Codex CLI | `codex/` | `config.toml`, `AGENTS.md`, `skills/planning/SKILL.md` |

## Workflow

```
/write-tests → implement → [code-critic + minimizer] → wizard → /pre-pr-verification → commit → PR
```

PR gate (`hooks/pr-gate.sh`) blocks until all required markers exist in `/tmp/claude-*-{session_id}`.

## Troubleshooting

- **Symlinks:** `ls -la ~/.claude ~/.codex` — fix with `./install.sh --symlinks-only`
- **PR gate:** `ls /tmp/claude-*` to check markers
- **Codex errors:** `~/.codex/log/codex-tui.log`
