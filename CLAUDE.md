# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

Centralized configuration for Claude Code, Gemini CLI, and Codex CLI. Deployed via symlinks:

- `~/.claude` → `claude/`
- `~/.gemini` → `gemini/`
- `~/.codex` → `codex/`

Configuration only — no build/test/lint. Files are Markdown, JSON, and shell scripts.

## Installation

```bash
./install.sh                  # Symlinks + optional CLI install + auth (prompts for each)
./install.sh --symlinks-only  # Symlinks only
./uninstall.sh                # Remove symlinks (keeps repo)
```

## Architecture

Claude configuration (`claude/`) is organized into five layers:

```
Hooks (observe Claude Code events)
  ↓ suggest/enforce
Skills (orchestrate multi-step workflows)
  ↓ spawn
Agents (execute specialized tasks in isolation)
  ↓ reference
Rules (domain standards and constraints)
  ↓ governed by
Global Instructions (claude/CLAUDE.md — loaded in every session)
```

Gemini and Codex are minimal sub-agent configs. See `gemini/GEMINI.md` and `codex/AGENTS.md`.

### Global Instructions (`claude/CLAUDE.md`)

**Warning:** Loaded in every Claude Code session across all projects via the `~/.claude` symlink. Treat edits with the same care as a shared library API.

Contains workflow dispatch tables, sub-agent routing, skill invocation rules (MUST vs SHOULD), and the autonomous execution contract.

### Agents (`claude/agents/*.md`)

Declarative definitions specifying model, tools, and preloaded skills. Spawned via Task tool for context isolation.

| Agent | Purpose | Model |
|-------|---------|-------|
| code-critic | Code review, iterates to APPROVE | sonnet |
| codex | Deep reasoning via Codex CLI | haiku wrapper |
| gemini | Log analysis + web research via Gemini CLI | haiku wrapper |
| test-runner | Run tests, return failures only | haiku |
| check-runner | Typecheck/lint, return errors only | haiku |
| security-scanner | Vulnerability + secret scanning | haiku |

### Skills (`claude/skills/*/SKILL.md`)

Procedural workflows invoked via Skill tool:

- **Orchestrators** (auto-suggested by `hooks/skill-eval.sh`; invoked explicitly): `task-workflow`, `design-workflow`, `plan-workflow`, `bugfix-workflow`
- **User-invocable**: `brainstorm`, `minimize`, `address-pr`, `autoskill`, `write-tests`, `code-review`, `pre-pr-verification`
- **Reference** (preloaded by agents): `codex-cli`, `gemini-cli`

### Rules (`claude/rules/*.md`)

Reference documents loaded on-demand. `execution-core.md` and `autonomous-flow.md` define the workflow contract. Language rules in `rules/backend/` and `rules/frontend/`.

### Hooks (`claude/hooks/*.sh`)

Event-driven shell scripts that enforce workflow rules and create checkpoint markers.

| Hook | Event | Purpose |
|------|-------|---------|
| session-cleanup.sh | SessionStart | Clean stale markers (>24h) |
| skill-eval.sh | UserPromptSubmit | Detect keywords, suggest skills |
| worktree-guard.sh | PreToolUse(Bash) | Block `git checkout/switch` in shared repos |
| pr-gate.sh | PreToolUse(Bash) | Block `gh pr create` without markers |
| agent-trace.sh | PostToolUse(Task) | Log + create agent markers (`/tmp/claude-{agent}-*`) |
| skill-marker.sh | PostToolUse(Skill) | Log + create skill markers (`/tmp/claude-pr-verified-*`) |

### Marker System

Workflow enforcement relies on session-scoped marker files. Two hooks create them; `pr-gate.sh` validates them before allowing PR creation.

| Marker | Created by hook | Required for |
|--------|----------------|-------------|
| `/tmp/claude-tests-passed-{sid}` | agent-trace.sh (test-runner PASS) | Code PRs |
| `/tmp/claude-checks-passed-{sid}` | agent-trace.sh (check-runner PASS/CLEAN) | Code PRs |
| `/tmp/claude-code-critic-{sid}` | agent-trace.sh (code-critic APPROVE) | Code PRs |
| `/tmp/claude-codex-{sid}` | agent-trace.sh (codex "CODEX APPROVED") | Code PRs + Plan PRs |
| `/tmp/claude-security-scanned-{sid}` | agent-trace.sh (security-scanner any) | Code PRs |
| `/tmp/claude-pr-verified-{sid}` | skill-marker.sh (pre-pr-verification) | Code PRs |

Plan PRs (branch suffix `-plan`) need only the codex marker. Code PRs need all.

**Cleanup caveat:** `session-cleanup.sh` cleans most markers after 24h but does not clean `claude-codex-*`. Codex markers persist until manual deletion or reboot.

## Editing Guidelines

| Component | Key constraint |
|-----------|---------------|
| `claude/CLAUDE.md` | Global impact — test in a separate repo after editing |
| `claude/settings.json` | Hook wiring + permissions; takes effect next session |
| `claude/hooks/*.sh` | Must be idempotent, fast (5–30s timeout). `agent-trace.sh` → `pr-gate.sh` dependency |
| `claude/skills/*/SKILL.md` | Frontmatter: `name`, `description`, `user-invocable`. Auto-suggested skills also need a trigger pattern in `skill-eval.sh` |
| `claude/agents/*.md` | Keep concise; procedural logic belongs in skills |
| `claude/rules/*.md` | One domain per file |

## Testing Configuration Changes

**Global instructions or rules:**
```bash
# Start a session in a different repo to verify behavior
cd ~/some-other-project && claude
```

**Hooks:**
1. Edit `claude/hooks/*.sh`
2. Run `./install.sh --symlinks-only` (re-links if needed)
3. Start a new session and run through a workflow
4. Verify markers: `ls /tmp/claude-*`

**Skills or agents:**
1. Edit the definition file
2. Invoke in a session (`/skill-name` or trigger the agent via workflow)
3. Verify output matches expectations

## Troubleshooting

**Symlinks broken:** `ls -la ~/.claude ~/.gemini ~/.codex` to verify, then `./install.sh --symlinks-only` to re-create.

**PR gate blocking unexpectedly:** `ls /tmp/claude-*` to check markers. Common causes: skipped workflow step, or markers expired (most cleaned after 24h by `session-cleanup.sh`; codex markers persist longer).

**Hook timeout:** Check `timeout` field in `settings.json` hook entries. Look for network calls or blocking I/O in the script.

**Skill not suggested:** Check keyword patterns in `hooks/skill-eval.sh`.
