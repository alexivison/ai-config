# Research: Tmux Integration vs CLI Orchestration

## Context

This repo (`ai-config`) orchestrates two AI coding agents — **Claude Code** (Paladin) and **Codex CLI** (Wizard) — using a CLI-based approach. This document evaluates converting to a **tmux-based** orchestration model and compares the two approaches.

## Current Architecture: CLI-Based Orchestration

### How It Works Today

Claude and Codex communicate via **synchronous CLI subprocess calls**:

- **Claude → Codex**: `call_codex.sh` invokes `codex exec` or `codex exec review` as a blocking subprocess. Claude's Bash tool runs the script, waits for completion, and reads stdout.
- **Codex → Claude**: `call_claude.sh` invokes `claude -p` (one-shot/piped mode) as a blocking subprocess.

Both scripts are thin wrappers that:
1. Validate arguments and build the CLI command
2. Run the target agent in non-interactive, one-shot mode
3. Capture and return the output as plain text

### Orchestration Enforcement

A hook-based governance system enforces workflow ordering:

| Hook | Trigger | Purpose |
|------|---------|---------|
| `codex-gate.sh` | PreToolUse (Bash) | Blocks `call_codex.sh --review` until both critic APPROVE markers exist |
| `codex-trace.sh` | PostToolUse (Bash) | Creates evidence markers when codex review completes and verdict is issued |
| `agent-trace.sh` | PostToolUse (Task) | Logs sub-agent invocations, creates markers for critic/test/check approvals |
| `marker-invalidate.sh` | PostToolUse (Edit/Write) | Deletes all review markers when implementation files are edited |
| `pr-gate.sh` | PreToolUse (Bash) | Blocks `gh pr create` unless all 7 required markers exist |

The full pipeline is: `/write-tests → implement → checkboxes → self-review → [code-critic + minimizer] → codex → /pre-pr-verification → commit → PR`

### Key Properties of Current Approach

- **Synchronous, blocking calls** — the calling agent waits for the result
- **Non-interactive mode** — both agents run in one-shot/piped mode (`codex exec`, `claude -p`)
- **Text-in, text-out** — communication is via stdin/stdout of the subprocess
- **Hook-enforced ordering** — Claude Code's hook system gates workflow progression
- **Marker-based evidence** — `/tmp/claude-*` files prove each step completed

---

## Tmux-Based Orchestration: What It Would Look Like

### The Core Pattern

Instead of one agent spawning the other as a subprocess, both agents run **simultaneously in separate tmux panes**. An orchestrator script (or a lead agent) coordinates them by sending keys and reading pane output.

```bash
# Create session with two panes
tmux new-session -d -s party -n work
tmux split-window -h -t party:work

# Launch agents
tmux send-keys -t party:work.0 "claude --dangerously-skip-permissions" C-m
tmux send-keys -t party:work.1 "codex --full-auto" C-m

# Send a task to Claude
tmux send-keys -t party:work.0 "Implement the auth middleware" C-m

# Poll for completion, then capture output
wait_for_idle party:work.0
OUTPUT=$(tmux capture-pane -t party:work.0 -p -S -200)

# Send that output to Codex for review
tmux send-keys -t party:work.1 -l "Review this: $OUTPUT" C-m
```

### Key tmux Primitives

| Command | Purpose |
|---------|---------|
| `tmux send-keys -t <target> "text" C-m` | Send input to a pane |
| `tmux capture-pane -t <target> -p -S -N` | Read last N lines from a pane |
| `tmux split-window -P -F "#{pane_id}"` | Create pane and capture its ID |
| `tmux list-panes -F "#{pane_id} #{pane_current_command}"` | List panes and their processes |

### Existing Ecosystem

Several tools have emerged for tmux-based AI agent orchestration:

| Project | Description |
|---------|-------------|
| **Claude Code Agent Teams** (first-party) | Built-in experimental feature (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`). Lead spawns teammates as tmux split panes. Shared task list, inbox messaging, delegate mode. |
| **NTM** | Go CLI for mixed agent swarms. `ntm spawn myproject --cc=4 --cod=4 --gmi=2`. Type-aware broadcasting, session analytics. |
| **AWS CLI Agent Orchestrator** | Enterprise-grade. Isolated tmux sessions, MCP-based communication, FastAPI HTTP API, provider abstraction. |
| **Multi-Agent Shogun** | YAML-based hierarchy (Shogun → Karo → Ashigaru). Detects agent status via CLI prompt patterns. |
| **Agent Conductor** | Supervisor/worker topology, inbox messaging, approval gates, SQLite persistence. |
| **tmux-mcp** | MCP server giving AI agents programmatic tmux control (list, create, send-keys, capture). |

### What "Converting" Would Mean

Conversion would involve replacing the current `call_codex.sh`/`call_claude.sh` subprocess model with:

1. A **session manager** that creates/maintains tmux sessions with agent panes
2. **Send-keys dispatchers** that inject prompts into the target pane
3. **Output capture/polling** to read results back from panes
4. Either keeping or replacing the hook-based governance with tmux-native coordination

---

## Comparison: CLI vs Tmux

### Pros of Current CLI Approach

| Advantage | Detail |
|-----------|--------|
| **Simplicity** | Two shell scripts (~160 lines each). Easy to understand, debug, and modify. |
| **Deterministic control flow** | Synchronous calls mean the calling agent always knows when the other is done. No polling, no race conditions. |
| **Structured output** | `codex exec --json` returns parseable JSON. `claude -p` returns clean text. No TUI artifacts to strip. |
| **Hook integration** | Claude Code's PreToolUse/PostToolUse hooks naturally intercept Bash calls. The gate/trace/invalidation system works because calls flow through the Bash tool. |
| **No persistent state** | Each invocation is fresh — no leaked context, no session management, no stale panes. |
| **No TTY complexity** | One-shot mode doesn't need a pseudo-terminal. Scripts work in any environment (CI, containers, headless servers). |
| **Cost efficiency** | Agents only run (and bill) when actively needed. No idle agents consuming resources. |
| **Testability** | Scripts can be tested in isolation with mocked inputs/outputs. |

### Cons of Current CLI Approach

| Disadvantage | Detail |
|--------------|--------|
| **No parallelism between Claude and Codex** | Claude blocks entirely while Codex runs (up to 15 minutes for reviews). Can't work on anything else. |
| **No persistent Codex context** | Every `codex exec` call starts fresh. Codex can't remember previous interactions or build up project understanding across calls. |
| **No observability during execution** | While Codex runs, Claude (and the user) see nothing until the full output returns. No streaming, no progress indication. |
| **One-shot limitations** | Some tasks benefit from interactive, multi-turn exchanges between agents that the current model can't support. |
| **Codex can't use tools** | `codex exec` in read-only sandbox is very constrained. A full interactive Codex session can browse files, run commands, etc. |

### Pros of Tmux Approach

| Advantage | Detail |
|-----------|--------|
| **True parallelism** | Both agents work simultaneously. Claude can implement while Codex reviews a previous change. |
| **Persistent agent sessions** | Codex retains context across interactions. Can build up project understanding over the session. |
| **Real-time observability** | User can watch both agents working in split panes. Can see progress, intervene, or redirect. |
| **Interactive multi-turn** | Agents can have back-and-forth exchanges. Codex can ask clarifying questions mid-review. |
| **Full agent capabilities** | Agents run in interactive mode with full tool access, not constrained one-shot mode. |
| **Session persistence** | tmux sessions survive terminal disconnects. Long-running workflows continue in the background. |
| **Visual debugging** | When something goes wrong, you can see exactly what each agent is doing in its pane. |
| **Ecosystem momentum** | Claude Code Agent Teams, NTM, AWS CAO, and others are building in this direction. The ecosystem is moving toward tmux. |

### Cons of Tmux Approach

| Disadvantage | Detail |
|--------------|--------|
| **Completion detection is fragile** | No reliable way to know when an agent is "done." Must poll `capture-pane` and match text patterns. Different agents have different idle indicators. |
| **Output parsing is messy** | `capture-pane` returns raw terminal content with ANSI codes, line wrapping, TUI artifacts. Extracting structured data is unreliable. |
| **Race conditions** | Sending keys while an agent is mid-response can corrupt input. Polling intervals create timing windows. |
| **Hook system incompatibility** | The current hook system intercepts Claude Code's tool calls. If Claude runs in one pane and Codex in another, hooks on Claude's side can't gate Codex's behavior. The governance model breaks. |
| **State management complexity** | Must track which panes exist, which agents are idle vs. busy, handle agent crashes, manage session lifecycle. |
| **Cost** | Agents running in persistent sessions consume tokens/compute even when idle (depending on billing model). |
| **Environment dependency** | Requires tmux installed and a terminal environment. Doesn't work in pure CI, containers, or headless contexts without additional setup. |
| **Harder to test** | Integration tests need a real tmux session. Can't easily mock pane interactions. |
| **Security surface** | Interactive agents with full tool access are harder to sandbox. Current read-only `codex exec` is inherently safe. |
| **Marker/gate system redesign** | The entire PreToolUse/PostToolUse hook chain would need to be redesigned. Markers created by hooks on one agent's tool calls can't enforce gates on another agent's actions in a separate pane. |

---

## Critical Analysis: Should This Repo Convert?

### The Core Tension

The current CLI model is **simple, deterministic, and governance-enforced**. The tmux model offers **parallelism, persistence, and observability** but at the cost of reliability and the hook-based governance system that is the heart of this repo's workflow enforcement.

### What Would Break

1. **The entire hook chain** — `codex-gate.sh`, `codex-trace.sh`, `pr-gate.sh`, `marker-invalidate.sh` all depend on Codex being invoked via Claude's Bash tool. In a tmux model, Codex runs independently and these hooks never fire.

2. **Evidence markers** — The marker system (`/tmp/claude-*`) works because hooks create markers as side effects of tool calls. In a tmux model, you'd need an entirely different evidence mechanism.

3. **Read-only sandbox enforcement** — `call_codex.sh` forces `--sandbox read-only`. In a tmux session, Codex has full interactive capabilities.

4. **Timeout control** — The current model has explicit timeout wrappers. In tmux, there's no built-in timeout for an interactive agent session.

### Where Tmux Makes Sense

- **Parallel independent tasks** — If Claude and Codex need to work on different files or different aspects of a task simultaneously.
- **Long-running sessions with context** — If Codex's lack of cross-call memory is a real bottleneck.
- **User observability** — If watching both agents work in real-time is a priority.

### Where CLI Is Better Suited

- **Sequential pipeline workflows** — The current `critics → codex → verification → PR` pipeline is inherently sequential. Parallelism doesn't help.
- **Governance enforcement** — Any workflow that requires "X must happen before Y" is easier to enforce with synchronous calls + hooks.
- **Structured output** — Any time you need parseable, clean output from an agent.

---

## Recommendation

### Don't fully convert; consider a hybrid approach.

The current CLI model is well-suited to this repo's primary use case: a **sequential, governance-enforced review pipeline**. Converting entirely to tmux would require rebuilding the hook system and sacrificing the determinism that makes the workflow reliable.

However, tmux could complement the current system for specific use cases:

### Hybrid Architecture

```
┌─────────────────────────────────────────────────────┐
│ tmux session: "party"                               │
│                                                     │
│ ┌─────────────────────┐ ┌─────────────────────────┐ │
│ │ Pane 0: Claude Code │ │ Pane 1: User/Dashboard  │ │
│ │ (main orchestrator) │ │ (status, logs, observe) │ │
│ │                     │ │                         │ │
│ │ Uses call_codex.sh  │ │ Watches agent-trace.jsonl│
│ │ for review pipeline │ │ Shows marker status     │ │
│ │ (unchanged)         │ │                         │ │
│ └─────────────────────┘ └─────────────────────────┘ │
│                                                     │
│ ┌─────────────────────────────────────────────────┐ │
│ │ Pane 2: Optional — persistent Codex session     │ │
│ │ (for interactive debugging, architecture Q&A)   │ │
│ │ NOT used for the review pipeline                │ │
│ └─────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

1. **Keep CLI for the review pipeline** — The `critics → codex review → verdict → PR` flow stays as-is. Hooks, markers, and gates remain intact.

2. **Add tmux for observability** — Run Claude Code inside a tmux session. Add a dashboard pane that tails `agent-trace.jsonl` and shows marker status in real time.

3. **Add tmux for parallel independent work** — Use Claude Code Agent Teams (experimental) for tasks that are genuinely parallelizable (e.g., implementing multiple unrelated files simultaneously).

4. **Add tmux for interactive Codex sessions** — A persistent Codex pane for ad-hoc architecture discussions, debugging, or research that doesn't go through the review pipeline.

### If Full Tmux Conversion Is Still Desired

The following would need to be built:

1. **Tmux-aware governance layer** — Replace hook-based gates with a coordinator process that monitors all panes and enforces ordering via a state machine.
2. **Output extraction API** — Reliable parsing of `capture-pane` output, stripping ANSI codes and TUI artifacts.
3. **Completion detection** — Agent-specific idle detection (different for Claude Code vs. Codex CLI vs. other agents).
4. **Evidence system** — Replace `/tmp` markers with a centralized state store that both agents report to.
5. **Sandbox enforcement** — Mechanism to constrain what Codex can do in its tmux pane during review phases.

This is a non-trivial engineering effort. The existing tools (NTM, AWS CAO, Agent Conductor) provide building blocks but none of them replicate this repo's specific governance model.

---

## References

| Resource | URL |
|----------|-----|
| Claude Code Agent Teams | `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var |
| NTM (Named Tmux Manager) | github.com/Dicklesworthstone/ntm |
| AWS CLI Agent Orchestrator | github.com/awslabs/cli-agent-orchestrator |
| Multi-Agent Shogun | github.com/yohey-w/multi-agent-shogun |
| Agent Conductor | github.com/gaurav-yadav/agent-conductor |
| Agent Deck | github.com/asheshgoplani/agent-deck |
| Tmux-Orchestrator | github.com/Jedward23/Tmux-Orchestrator |
| Agent of Empires | github.com/njbrake/agent-of-empires |
| tmux-mcp | github.com/jonrad/tmux-mcp |
