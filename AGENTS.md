# AGENTS.md

Multi-agent configuration for AI-assisted development.

## Architecture

```
Claude Code (Orchestrator — Claude Opus)
    ├── Internal agents (via Task tool)
    │   ├── code-critic, minimizer, security-scanner  (sonnet)
    │   └── test-runner, check-runner                  (haiku)
    ├── Codex CLI wrapper (sonnet → GPT-5.3 xhigh reasoning)
    └── Gemini CLI wrapper (sonnet → Gemini Pro/Flash)
```

## Installation

```bash
./install.sh                  # Symlinks + optional CLI install + auth
./install.sh --symlinks-only  # Symlinks only
```

Symlinks: `~/.claude` → `claude/`, `~/.gemini` → `gemini/`, `~/.codex` → `codex/`

## Configuration

| Agent | Config root | Key files |
|-------|-------------|-----------|
| Claude Code | `claude/` | `CLAUDE.md`, `settings.json`, `agents/*.md`, `skills/*/SKILL.md`, `rules/*.md`, `hooks/*.sh` |
| Codex CLI | `codex/` | `config.toml`, `AGENTS.md`, `skills/planning/SKILL.md` |
| Gemini CLI | `gemini/` | `GEMINI.md`, `settings.json` |

## Workflow

```
/write-tests → implement → [code-critic + minimizer] → codex → /pre-pr-verification → commit → PR
```

PR gate (`hooks/pr-gate.sh`) blocks until all required markers exist in `/tmp/claude-*-{session_id}`.

## Troubleshooting

- **Symlinks:** `ls -la ~/.claude ~/.gemini ~/.codex` — fix with `./install.sh --symlinks-only`
- **PR gate:** `ls /tmp/claude-*` to check markers
- **Codex errors:** `~/.codex/log/codex-tui.log`
- **Gemini errors:** `~/.gemini/tmp/*/logs.json`
