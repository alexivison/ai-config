# AGENTS.md

Multi-agent configuration for AI-assisted development. Three CLI agents orchestrated through a shared workflow.

## Overview

```
Claude Code (Orchestrator — Claude Opus)
    ├── Internal agents (spawned via Task tool)
    │   ├── code-critic      Code review, iterates to APPROVE
    │   ├── minimizer        Bloat/complexity review
    │   ├── test-runner       Run tests, return failures
    │   ├── check-runner      Typecheck/lint, return errors
    │   └── security-scanner  Vulnerability + secret scanning
    │
    ├── Codex CLI (GPT-5.3 — deep reasoning)
    │   ├── Code + architecture review
    │   ├── Plan + design review
    │   ├── Debugging analysis
    │   └── Trade-off evaluation
    │
    └── Gemini CLI (Gemini Pro/Flash — research)
        ├── Log analysis (2M token context)
        └── Web search synthesis
```

Claude Code orchestrates all work. Internal agents run as isolated sub-processes. Codex and Gemini are external CLIs invoked through sonnet-model wrapper agents that relay output verbatim.

## Installation

```bash
./install.sh                  # Symlinks + optional CLI install + auth (prompts for each)
./install.sh --symlinks-only  # Symlinks only
./uninstall.sh                # Remove symlinks (keeps repo)
```

Creates symlinks:
- `~/.claude` → `claude/`
- `~/.gemini` → `gemini/`
- `~/.codex` → `codex/`

## Agent Configurations

### Claude Code (`claude/`)

Primary orchestrator. Handles implementation, git operations, and workflow coordination. Configuration organized in five layers:

```
Hooks (observe events, enforce rules)
  ↓ suggest/enforce
Skills (orchestrate multi-step workflows)
  ↓ spawn
Agents (execute specialized tasks in isolation)
  ↓ reference
Rules (domain standards and constraints)
  ↓ governed by
Global Instructions (claude/CLAUDE.md)
```

| Component | Location | Purpose |
|-----------|----------|---------|
| Global instructions | `claude/CLAUDE.md` | Loaded every session. Workflow dispatch, agent routing, execution contract |
| Settings | `claude/settings.json` | Permissions, hook wiring, model selection |
| Agents | `claude/agents/*.md` | Declarative definitions (model, tools, preloaded skills) |
| Skills | `claude/skills/*/SKILL.md` | Procedural workflows invoked via Skill tool |
| Rules | `claude/rules/*.md` | Domain standards, one domain per file |
| Hooks | `claude/hooks/*.sh` | Event-driven scripts for enforcement and markers |

### Codex CLI (`codex/`)

Deep reasoning engine. Called by Claude Code for tasks requiring extended thinking.

| Component | Location | Purpose |
|-----------|----------|---------|
| Config | `codex/config.toml` | Model (GPT-5.3), reasoning effort (xhigh), sandbox (read-only) |
| Agent instructions | `codex/AGENTS.md` | Task types, output format, verdict conventions |
| Context loader | `codex/skills/context-loader/SKILL.md` | Loads project rules at task start |

### Gemini CLI (`gemini/`)

Research and large-scale analysis. Called by Claude Code for log analysis and web research.

| Component | Location | Purpose |
|-----------|----------|---------|
| Settings | `gemini/settings.json` | Auth, preview features |
| Agent instructions | `gemini/GEMINI.md` | Output contract, task types, format templates |

## Internal Agents

Spawned by Claude Code via Task tool for context isolation. Each runs as a sub-process with its own model and toolset.

| Agent | Model | Purpose | Verdict |
|-------|-------|---------|---------|
| code-critic | sonnet | Code review, iterates to APPROVE | APPROVE / REQUEST_CHANGES |
| minimizer | sonnet | Bloat/complexity review | APPROVE / REQUEST_CHANGES |
| codex | sonnet (wrapper) | Invokes Codex CLI, relays output verbatim | CODEX APPROVED / REQUEST_CHANGES |
| gemini | sonnet (wrapper) | Invokes Gemini CLI, relays output verbatim | N/A (investigation) |
| test-runner | haiku | Run tests, return failures only | PASS / FAIL |
| check-runner | haiku | Typecheck/lint, return errors only | PASS / CLEAN / FAIL |
| security-scanner | sonnet | Vulnerability + secret scanning | ISSUES_FOUND / CLEAN |

**Wrapper agents** (codex, gemini) exist to bridge external CLIs into Claude Code's Task tool pipeline. The sonnet model ensures high-fidelity passthrough of CLI output without summarization loss.

## Workflow

### Core Sequence

```
/write-tests → implement → checkboxes → [code-critic + minimizer] → codex → /pre-pr-verification → commit → PR
```

### Skills

| Type | Skills |
|------|--------|
| Orchestrators | `task-workflow`, `design-workflow`, `plan-workflow`, `bugfix-workflow` |
| User-invocable | `brainstorm`, `address-pr`, `autoskill`, `write-tests`, `code-review`, `pre-pr-verification` |
| Reference (preloaded by wrapper agents) | `codex-cli`, `gemini-cli` |

### Hooks

| Hook | Event | Purpose |
|------|-------|---------|
| session-cleanup.sh | SessionStart | Clean stale markers (>24h) |
| skill-eval.sh | UserPromptSubmit | Detect keywords, suggest skills |
| worktree-guard.sh | PreToolUse(Bash) | Block `git checkout/switch` in shared repos |
| pr-gate.sh | PreToolUse(Bash) | Block `gh pr create` without markers |
| agent-trace.sh | PostToolUse(Task) | Log agent runs + create markers |
| skill-marker.sh | PostToolUse(Skill) | Log skill runs + create markers |

### Marker System

Workflow enforcement via session-scoped marker files. Hooks create them; `pr-gate.sh` validates before PR creation.

| Marker | Created by | Required for |
|--------|-----------|-------------|
| `claude-tests-passed-{sid}` | agent-trace.sh (test-runner PASS) | Code PRs |
| `claude-checks-passed-{sid}` | agent-trace.sh (check-runner PASS/CLEAN) | Code PRs |
| `claude-code-critic-{sid}` | agent-trace.sh (code-critic APPROVE) | Code PRs |
| `claude-minimizer-{sid}` | agent-trace.sh (minimizer APPROVE) | Code PRs |
| `claude-codex-{sid}` | agent-trace.sh (codex "CODEX APPROVED") | Code PRs + Plan PRs |
| `claude-security-scanned-{sid}` | agent-trace.sh (security-scanner any) | Code PRs |
| `claude-pr-verified-{sid}` | skill-marker.sh (pre-pr-verification) | Code PRs |

All markers stored in `/tmp/`. Plan PRs (branch suffix `-plan`) need only the codex marker. Code PRs need all.

## Editing Guidelines

| Component | Key constraint |
|-----------|---------------|
| `claude/CLAUDE.md` | Global impact — test in a separate repo after editing |
| `claude/settings.json` | Hook wiring + permissions; takes effect next session |
| `claude/hooks/*.sh` | Must be idempotent, fast (5-30s timeout) |
| `claude/skills/*/SKILL.md` | Frontmatter: `name`, `description`, `user-invocable` |
| `claude/agents/*.md` | Keep concise; procedural logic belongs in skills |
| `claude/rules/*.md` | One domain per file |
| `codex/AGENTS.md` | Loaded by Codex CLI. Output format must match marker detection in agent-trace.sh |
| `codex/config.toml` | Model, reasoning effort, sandbox policy |
| `gemini/GEMINI.md` | Loaded by Gemini CLI. Output contract for wrapper agent |

## Testing Changes

**Claude global instructions or rules:**
```bash
cd ~/some-other-project && claude
```

**Hooks:**
1. Edit `claude/hooks/*.sh`
2. Run `./install.sh --symlinks-only`
3. Start a new session and trigger the workflow
4. Verify markers: `ls /tmp/claude-*`

**Skills or agents:**
1. Edit the definition file
2. Invoke in a session (`/skill-name` or trigger via workflow)
3. Verify output matches expectations

**Codex or Gemini config:**
1. Edit the config file
2. Test directly: `codex exec -s read-only "test prompt"` or `gemini "test prompt"`
3. Then test through Claude Code's wrapper agent to verify end-to-end

## Troubleshooting

**Symlinks broken:** `ls -la ~/.claude ~/.gemini ~/.codex` — then `./install.sh --symlinks-only`.

**PR gate blocking:** `ls /tmp/claude-*` to check markers. Common causes: skipped workflow step, or markers expired (cleaned after 24h; codex markers persist longer).

**Hook timeout:** Check `timeout` in `claude/settings.json` hook entries.

**Skill not suggested:** Check keyword patterns in `claude/hooks/skill-eval.sh`.

**Codex CLI errors:** Check `~/.codex/log/codex-tui.log` for model selection and error messages.

**Gemini CLI errors:** Check `~/.gemini/tmp/*/logs.json` for session logs.
