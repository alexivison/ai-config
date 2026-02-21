# Current System vs Full Tmux Replacement

Architectural comparison: the existing subprocess/hook/marker orchestration versus replacing it entirely with tmux-based agent coordination. Both approaches are evaluated as complete, self-contained systems — this is not a hybrid proposal.

---

## Part 1: The Current System (As-Is)

### Architecture Overview

Two AI agents — Claude Code (Opus 4.6) and Codex CLI (GPT-5.3-Codex) — coordinate through **synchronous subprocess invocation**. Claude is the orchestrator; Codex is invoked as a blocking child process via shell scripts.

```
┌──────────────────────────────────────────────────┐
│                  Claude Code                      │
│             (interactive session)                 │
│                                                   │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐   │
│  │ Task tool │  │Bash tool │  │Edit/Write tool│   │
│  │(sub-agents)│ │(scripts) │  │  (code edits) │   │
│  └─────┬─────┘  └────┬─────┘  └──────┬───────┘   │
│        │              │               │            │
│   PostToolUse    PreToolUse      PostToolUse       │
│   agent-trace    codex-gate      marker-invalidate │
│                  pr-gate                           │
│                  PostToolUse                       │
│                  codex-trace                       │
└──────────────────────────────────────────────────┘
         │              │
    ┌────┘         ┌────┘
    ▼              ▼
Sub-agents     call_codex.sh ──▶ codex exec (blocking, one-shot)
(in-process)   call_claude.sh ◀── (Codex can call Claude back)
```

### Communication Model

| Direction | Mechanism | Mode | Output |
|-----------|-----------|------|--------|
| Claude → Codex | `call_codex.sh` → `codex exec` | Blocking subprocess, read-only sandbox | JSON piped through jq, final agent message extracted |
| Claude → Codex (review) | `call_codex.sh --review` → `codex exec review` | Blocking subprocess, inherent read-only | Review findings as plain text |
| Codex → Claude | `call_claude.sh` → `claude -p` | Blocking subprocess, one-shot piped mode | Plain text |
| Claude → Sub-agents | Task tool (code-critic, minimizer, test-runner, check-runner, security-scanner) | In-process sub-agents via Claude Code SDK | Structured text with verdict keywords |

**Key property:** Every inter-agent call is synchronous. The caller blocks until the callee returns. No polling, no race conditions, no completion detection.

### Governance: The Hook/Marker System

The system enforces a strict review pipeline through Claude Code's hook system. Hooks fire on tool use events and create/check/delete marker files in `/tmp/`.

#### The Pipeline

```
/write-tests → implement → checkboxes → self-review
    → [code-critic + minimizer] (parallel sub-agents)
    → codex review (blocked until critics approve)
    → /pre-pr-verification
    → commit → PR (blocked until all 7 markers exist)
```

#### Hook Inventory

| Hook | Event | What It Does |
|------|-------|-------------|
| `session-cleanup.sh` | SessionStart | Deletes stale markers (>24h) from `/tmp/` |
| `skill-eval.sh` | UserPromptSubmit | Pattern-matches user prompt, injects skill suggestions |
| `worktree-guard.sh` | PreToolUse (Bash) | Blocks `git checkout`/`switch` in main worktree |
| `codex-gate.sh` | PreToolUse (Bash) | **Blocks** `call_codex.sh --review` unless both critic APPROVE markers exist |
| `pr-gate.sh` | PreToolUse (Bash) | **Blocks** `gh pr create` unless all 7 required markers exist |
| `codex-trace.sh` | PostToolUse (Bash) | Creates `codex-ran` marker when review completes; creates `codex` approval marker when `codex-verdict.sh approve` runs (only if `codex-ran` exists) |
| `agent-trace.sh` | PostToolUse (Task) | Logs all sub-agent invocations to JSONL; creates markers for critic/test/check/security approvals based on verdict keywords |
| `marker-invalidate.sh` | PostToolUse (Edit/Write) | **Deletes all 8 review markers** when any implementation file is edited (skips .md, /tmp/, .log, .jsonl) |
| `skill-marker.sh` | PostToolUse (Skill) | Creates markers when critical skills complete (pre-pr-verification, write-tests, code-review) |

#### Marker Inventory

| Marker | Created By | Required For |
|--------|-----------|-------------|
| `/tmp/claude-code-critic-{sid}` | agent-trace.sh (verdict=APPROVED) | codex-gate, pr-gate |
| `/tmp/claude-minimizer-{sid}` | agent-trace.sh (verdict=APPROVED) | codex-gate, pr-gate |
| `/tmp/claude-codex-ran-{sid}` | codex-trace.sh (review completed) | codex approval (evidence gate) |
| `/tmp/claude-codex-{sid}` | codex-trace.sh (verdict approve + ran evidence) | pr-gate |
| `/tmp/claude-tests-passed-{sid}` | agent-trace.sh (verdict=PASS) | pr-gate |
| `/tmp/claude-checks-passed-{sid}` | agent-trace.sh (verdict=PASS/CLEAN) | pr-gate |
| `/tmp/claude-security-scanned-{sid}` | agent-trace.sh (any completion) | pr-gate |
| `/tmp/claude-pr-verified-{sid}` | skill-marker.sh (pre-pr-verification) | pr-gate |

#### How Governance Actually Works

The system creates a **directed acyclic graph** of dependencies enforced at runtime:

```
implement ──Edit/Write──▶ marker-invalidate (deletes ALL markers)
                              │
                              ▼
                    code-critic ──APPROVE──▶ marker created
                    minimizer  ──APPROVE──▶ marker created
                              │
                         codex-gate checks both markers
                              │
                              ▼
                    call_codex.sh --review ──▶ codex-ran marker
                    codex-verdict.sh approve ──▶ codex marker (only if ran exists)
                              │
                    test-runner ──PASS──▶ marker
                    check-runner ──PASS──▶ marker
                    security-scanner ──▶ marker
                    /pre-pr-verification ──▶ marker
                              │
                         pr-gate checks all 7 markers
                              │
                              ▼
                         gh pr create (allowed)
```

**The key invariant:** Any code edit wipes all markers. You cannot reach `gh pr create` without every review step having run *after* the last code edit. This is what makes the system tamper-resistant — even the agent itself can't skip steps.

#### Anti-Forgery Properties

The marker system has layered defenses:

1. **Markers are created by hooks, not agents.** The agent never runs `touch /tmp/claude-*`. Hooks create markers as side effects of tool calls.
2. **Codex approval requires evidence.** `codex-trace.sh` only creates the approval marker if `codex-ran` exists — you can't self-declare codex approval without actually running codex.
3. **Command pattern matching.** `codex-trace.sh` matches `call_codex.sh` at command position with anchored regex — you can't forge it by echoing the sentinel string.
4. **Marker invalidation on edit.** Any implementation edit wipes everything — you can't approve first and edit after.
5. **Agent-trace verdict detection.** Sub-agent markers depend on keyword matching in the response (APPROVED, PASS, etc.) — the sub-agent must actually return the verdict.

### Sub-Agent Architecture

| Agent | Model | Tools | Purpose | Verdict |
|-------|-------|-------|---------|---------|
| code-critic | Sonnet | Bash, Read, Grep, Glob | Code review against standards | APPROVE / REQUEST_CHANGES / NEEDS_DISCUSSION |
| minimizer | Sonnet | Bash, Read, Grep, Glob (no Write/Edit) | Bloat/complexity review | APPROVE / REQUEST_CHANGES / NEEDS_DISCUSSION |
| test-runner | Haiku | Bash, Read, Grep, Glob | Run test suite | PASS / FAIL |
| check-runner | Haiku | Bash, Read, Grep, Glob | Run typecheck + lint | PASS / FAIL |
| security-scanner | Sonnet | Bash, Glob, Grep, Read (no Write/Edit) | OWASP scan, secret detection | CRITICAL / HIGH / MEDIUM / CLEAN |

All sub-agents are **read-only** — none can modify files. They run in-process via Claude Code's Task tool, which means `agent-trace.sh` fires on PostToolUse and can capture their verdicts.

### Strengths of This System

1. **Deterministic.** No polling, no race conditions, no timing issues. The calling agent blocks until the callee finishes.
2. **Tamper-resistant.** The hook chain creates an enforcement mechanism the agent itself cannot circumvent. Even prompt injection in sub-agent output can't forge markers (hooks match specific tool call patterns, not raw text).
3. **Simple.** Two ~160-line shell scripts for cross-agent communication. Hooks are each <60 lines. Total governance code: ~500 lines of bash.
4. **Testable.** Scripts can be tested with mocked stdin/stdout. Hooks can be tested by feeding them JSON payloads.
5. **Environment-agnostic.** Works in CI, containers, headless servers, SSH sessions — anywhere Claude Code runs.
6. **Cost-efficient.** Codex only runs when invoked. No idle agent consuming tokens.

### Weaknesses of This System

1. **Sequential bottleneck.** Claude blocks for up to 15 minutes during Codex review. Can't do anything else during that time.
2. **No persistent Codex context.** Every `codex exec` starts fresh. Codex can't build project understanding across calls.
3. **No observability during execution.** While Codex runs, the user sees nothing. No streaming, no progress.
4. **One-shot limitations.** Can't have multi-turn dialogues between Claude and Codex. Review is fire-and-forget.
5. **Constrained Codex.** `codex exec` in read-only sandbox is very limited compared to interactive Codex with full tool access.
6. **No parallelism between agents.** Claude and Codex can never work simultaneously.

---

## Part 2: The Tmux Replacement (Proposed)

### Architecture Overview

Both agents run as **persistent interactive sessions** in separate tmux panes. A **coordinator process** (shell script or small daemon) manages communication, governance, and evidence collection.

```
┌─────────────────────────────────────────────────────────────────┐
│ tmux session: "party"                                           │
│                                                                 │
│ ┌───────────────────┐ ┌───────────────────┐ ┌────────────────┐ │
│ │ Pane 0: Claude    │ │ Pane 1: Codex     │ │ Pane 2: Coord  │ │
│ │ (interactive)     │ │ (interactive)     │ │ (coordinator)  │ │
│ │                   │ │                   │ │                │ │
│ │ claude --dangerou │ │ codex --full-auto │ │ party-coord.sh │ │
│ │ sly-skip-permissi │ │                   │ │ (state machine │ │
│ │ ons               │ │                   │ │  + governance) │ │
│ └───────────────────┘ └───────────────────┘ └────────────────┘ │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Pane 3: Dashboard (tail -f state.json, marker status, logs)│ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Communication Model

Instead of subprocess calls, agents communicate through the coordinator:

| Direction | Mechanism | How |
|-----------|-----------|-----|
| Coordinator → Claude | `tmux send-keys -t party:work.0` | Injects prompt text into Claude's pane |
| Coordinator → Codex | `tmux send-keys -t party:work.1` | Injects prompt text into Codex's pane |
| Claude → Coordinator | `tmux capture-pane -t party:work.0 -p` | Coordinator polls and reads Claude's output |
| Codex → Coordinator | `tmux capture-pane -t party:work.1 -p` | Coordinator polls and reads Codex's output |
| Claude ↔ Codex | Mediated by coordinator | Coordinator captures from one, sends to other |

**No direct agent-to-agent communication.** The coordinator mediates all exchanges. This is critical for governance.

### The Coordinator: Replacing Hooks with a State Machine

The current system uses hooks (event-driven, per-tool-call enforcement). In tmux, hooks don't fire because agents run independently. The coordinator replaces them with an **explicit state machine**.

#### State Machine

```
┌──────────────┐
│  IMPLEMENT   │◄─────────────────────────────────────┐
│              │                                       │
└──────┬───────┘                                       │
       │ Claude signals "done implementing"            │
       ▼                                               │
┌──────────────┐                                       │
│  SELF_REVIEW │                                       │
│              │                                       │
└──────┬───────┘                                       │
       │ Claude signals "self-review PASS"             │
       ▼                                               │
┌──────────────┐                                       │
│   CRITICS    │ (code-critic + minimizer in parallel) │
│              │                                       │
└──────┬───────┘                                       │
       │ Both APPROVE                                  │
       │ REQUEST_CHANGES ──▶ back to IMPLEMENT ────────┘
       ▼
┌──────────────┐
│ CODEX_REVIEW │ Coordinator sends diff to Codex pane
│              │
└──────┬───────┘
       │ Coordinator captures Codex output, extracts verdict
       │ REQUEST_CHANGES ──▶ back to IMPLEMENT
       ▼
┌──────────────┐
│  VERIFY      │ (tests, checks, security scan)
│              │
└──────┬───────┘
       │ All pass
       ▼
┌──────────────┐
│   PR_READY   │ Coordinator allows PR creation
│              │
└──────┴───────┘
```

#### Evidence Collection (Replacing Markers)

Instead of `/tmp/` marker files created by hooks, the coordinator maintains a **state file**:

```json
{
  "session_id": "abc123",
  "state": "CODEX_REVIEW",
  "evidence": {
    "code_critic": { "verdict": "APPROVED", "timestamp": "2026-02-20T10:30:00Z", "iteration": 2 },
    "minimizer": { "verdict": "APPROVED", "timestamp": "2026-02-20T10:30:15Z", "iteration": 1 },
    "codex_review": null,
    "tests": { "verdict": "PASS", "timestamp": "2026-02-20T10:28:00Z" },
    "checks": { "verdict": "PASS", "timestamp": "2026-02-20T10:28:30Z" },
    "security": { "verdict": "CLEAN", "timestamp": "2026-02-20T10:29:00Z" },
    "pr_verified": false
  },
  "last_code_edit": "2026-02-20T10:25:00Z",
  "invalidation_count": 3
}
```

**Invalidation rule:** If `last_code_edit` is newer than any evidence timestamp, that evidence is stale and the coordinator treats it as missing. This replaces `marker-invalidate.sh`.

#### Governance Enforcement

| Current Hook | Tmux Replacement |
|-------------|-----------------|
| `codex-gate.sh` (blocks codex until critics approve) | Coordinator state machine: won't enter CODEX_REVIEW state until both critics APPROVED |
| `pr-gate.sh` (blocks PR until all markers) | Coordinator state machine: won't enter PR_READY until all evidence present and non-stale |
| `marker-invalidate.sh` (deletes markers on edit) | Coordinator watches `last_code_edit` timestamp; stale evidence auto-invalidated |
| `codex-trace.sh` (creates codex evidence) | Coordinator parses Codex pane output directly, records evidence |
| `agent-trace.sh` (creates sub-agent evidence) | Sub-agents still run via Claude's Task tool (unchanged), but coordinator also monitors Claude's pane for verdict signals |
| `skill-eval.sh` (suggests skills) | Coordinator intercepts user input before forwarding to Claude pane |
| `worktree-guard.sh` (blocks checkout) | Coordinator can intercept or delegate to Claude's own hooks (still works in-pane) |

#### Completion Detection

The hardest problem in tmux orchestration. Three strategies, used together:

**1. Sentinel-based (most reliable)**

The coordinator injects prompts that end with a unique sentinel:

```bash
tmux send-keys -t party:work.1 "Review this diff. When done, end your response with SENTINEL_$(date +%s)" C-m
```

Then polls for the sentinel:

```bash
while ! tmux capture-pane -t party:work.1 -p | grep -q "SENTINEL_1740000000"; do
  sleep 2
done
```

**2. Idle detection (fallback)**

Monitor the pane's cursor position. If it hasn't moved for N seconds and the prompt character is visible, the agent is idle:

```bash
prev=""
idle_count=0
while true; do
  curr=$(tmux capture-pane -t party:work.1 -p | tail -1)
  if [[ "$curr" == "$prev" ]]; then
    ((idle_count++))
    [[ $idle_count -ge 5 ]] && break  # 10 seconds idle
  else
    idle_count=0
  fi
  prev="$curr"
  sleep 2
done
```

**3. Process monitoring**

Check if the agent's child processes are still running:

```bash
pane_pid=$(tmux display-message -t party:work.1 -p '#{pane_pid}')
while pgrep -P "$pane_pid" > /dev/null; do
  sleep 1
done
```

#### Output Extraction

Raw `capture-pane` output contains ANSI escape codes, line wrapping artifacts, and TUI elements. The coordinator must clean this:

```bash
# Capture and strip ANSI codes
OUTPUT=$(tmux capture-pane -t party:work.1 -p -S -200 | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g')

# Extract content between sentinels
RESPONSE=$(echo "$OUTPUT" | sed -n '/BEGIN_RESPONSE/,/END_RESPONSE/p' | sed '1d;$d')
```

More robust: have agents write structured output to a shared file:

```bash
# Claude writes review results to a known path
tmux send-keys -t party:work.0 "Write your review findings to /tmp/party-review-output.json" C-m
# Coordinator reads the file instead of parsing pane output
```

### The Codex Review Flow (Tmux Version)

Here's how the current Codex review would work in the tmux model:

**Current (subprocess):**
```
Claude runs call_codex.sh --review → blocks → gets output → calls codex-verdict.sh → hook creates marker
```

**Tmux replacement:**
```
1. Coordinator detects Claude reached CODEX_REVIEW state
2. Coordinator generates diff: git diff main...HEAD
3. Coordinator sends to Codex pane:
   tmux send-keys -t codex "Review this diff against main. Focus on bugs, security, architecture. End with VERDICT: APPROVE or VERDICT: REQUEST_CHANGES followed by findings. SENTINEL_xxx" C-m
4. Coordinator polls for SENTINEL_xxx
5. Coordinator captures output, extracts verdict
6. Coordinator updates state file with codex evidence
7. If APPROVE → advance to VERIFY state
8. If REQUEST_CHANGES → send findings to Claude pane, return to IMPLEMENT state
```

**What changes:**
- Codex runs in **interactive mode** with full capabilities (not `codex exec` sandbox)
- Codex has **persistent context** — it remembers previous reviews in this session
- The review can be **multi-turn** — Codex asks clarifying questions, coordinator mediates
- The user can **watch** Codex working in real time

**What's lost:**
- The read-only sandbox guarantee (Codex can now write files)
- Deterministic completion (must poll instead of blocking)
- Structured JSON output (must parse pane text)
- Hook-based evidence chain (replaced by coordinator logic)

### Sub-Agents in the Tmux Model

Two options:

**Option A: Keep sub-agents as-is (in-process via Task tool)**

Claude's internal sub-agents (code-critic, minimizer, test-runner, etc.) continue running via the Task tool inside Claude's pane. The coordinator doesn't need to manage them — Claude handles them internally, and Claude's own hooks (`agent-trace.sh`) still fire within Claude's process.

The coordinator only needs to detect when Claude has finished the critic phase (by monitoring Claude's pane output for verdict keywords or sentinels).

**Pros:** Minimal change. Sub-agent governance still works. Claude's hook system still enforces internal ordering.
**Cons:** No parallelism between Claude's sub-agents and Codex. Claude still blocks during sub-agent execution.

**Option B: Promote sub-agents to their own tmux panes**

Each sub-agent gets its own pane. The coordinator dispatches work to each:

```
┌─────────┐ ┌─────────┐ ┌──────────┐ ┌───────────┐ ┌──────────┐ ┌──────────┐
│ Claude  │ │ Codex   │ │ Critic   │ │ Minimizer │ │ Tester   │ │ Checker  │
│ (impl)  │ │ (review)│ │ (claude) │ │ (claude)  │ │ (claude) │ │ (claude) │
└─────────┘ └─────────┘ └──────────┘ └───────────┘ └──────────┘ └──────────┘
```

**Pros:** True parallelism everywhere. All agents work simultaneously on different tasks.
**Cons:** 6+ panes to manage. Each "sub-agent" pane is a full Claude Code session (expensive). Coordinator complexity increases significantly. The in-process Task tool is much cheaper and simpler.

**Recommendation for full tmux conversion:** Option A. Keep sub-agents in-process. Only Claude and Codex get tmux panes. This limits the coordinator's scope to the inter-agent boundary where the current system's weaknesses actually are.

### Session Management

The coordinator handles lifecycle:

```bash
# Startup
party_start() {
  tmux new-session -d -s party -n work
  tmux split-window -h -t party:work
  tmux split-window -v -t party:work.0  # dashboard below Claude

  # Launch agents
  tmux send-keys -t party:work.0 "claude --dangerously-skip-permissions" C-m
  tmux send-keys -t party:work.1 "codex --full-auto" C-m

  # Initialize state
  echo '{"state":"IDLE","evidence":{}}' > /tmp/party-state.json
}

# Teardown
party_stop() {
  tmux kill-session -t party 2>/dev/null
  rm -f /tmp/party-state.json
}

# Crash recovery
party_health() {
  for pane in 0 1; do
    pid=$(tmux display-message -t party:work.$pane -p '#{pane_pid}')
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "Agent in pane $pane crashed. Respawning..."
      # Respawn logic
    fi
  done
}
```

### Parallelism Model

The primary benefit. Here's what becomes possible:

```
Timeline (current system — sequential):
├── Claude implements ──────────────────────────┤
├── Critics review ─────────┤
├── Claude fixes ───────────┤
├── Critics approve ─┤
├── Codex reviews ──────────────────────────────┤ (15 min blocking)
├── Claude fixes ───┤
├── Codex approves ─┤
├── Verify + PR ────┤
Total: ~45 minutes

Timeline (tmux system — parallel where possible):
├── Claude implements ──────────────────────────┤
├── Critics review ─────────┤
├── Claude fixes ───────────┤
├── Critics approve ─┤
├── Codex reviews ──────────────────────────────┤
├── Claude works on next task ──────────────────┤ (NOT blocked)
├── Codex approves ─┤
├── Verify + PR ────┤
Total: ~30 minutes (Codex review overlaps with next task)
```

The real win isn't in a single PR cycle — it's that Claude can **start the next task** while Codex reviews. Over a session with multiple PRs, the throughput improvement compounds.

### Sandbox and Security

The current system enforces a read-only sandbox on Codex via `call_codex.sh`. In tmux, Codex runs interactively with full access. Options:

**1. Trust-based (simplest)**

Codex runs in `--full-auto` with its own `AGENTS.md` instructions that say "don't write files during review." This is the weakest option — relies on prompt compliance.

**2. Codex's own sandbox modes**

Codex CLI supports `--sandbox read-only` even in interactive mode. Launch Codex with:
```bash
tmux send-keys -t party:work.1 "codex --full-auto --sandbox read-only" C-m
```

This gives OS-level sandboxing (filesystem read-only) while still allowing interactive use.

**3. Coordinator-enforced**

The coordinator monitors Codex's pane for write operations (watching for file edit tool calls in Codex's output). If detected during review phase, coordinator kills and restarts Codex.

**Recommendation:** Option 2. Codex's built-in sandbox works in interactive mode and provides OS-level enforcement without coordinator complexity.

---

## Part 3: Head-to-Head Comparison

### Complexity

| Aspect | Current System | Tmux Replacement |
|--------|---------------|-----------------|
| Core communication | 2 shell scripts (~320 lines total) | Coordinator script (~500-800 lines) |
| Governance | 8 hook scripts (~400 lines total) | State machine in coordinator (~300 lines) |
| Evidence | File-based markers (touch/check/delete) | JSON state file (read/write/timestamp) |
| Completion detection | N/A (synchronous) | Polling + sentinels + idle detection (~100 lines) |
| Output parsing | jq on JSON / clean text | ANSI stripping + sentinel extraction (~50 lines) |
| Session management | N/A (stateless) | Startup/teardown/health check (~100 lines) |
| **Total governance code** | **~720 lines** | **~1050-1350 lines** |

The tmux system is roughly **50-80% more code**, but the increase is concentrated in two areas: completion detection and session management. The governance logic itself (state machine) is actually simpler than the distributed hook chain.

### Reliability

| Property | Current System | Tmux Replacement |
|----------|---------------|-----------------|
| Completion detection | **Perfect** (synchronous) | Fragile (polling + heuristics) |
| Race conditions | **None** | Possible (send-keys during agent activity) |
| Output fidelity | **Perfect** (structured JSON/text) | Lossy (ANSI artifacts, line wrapping) |
| Governance enforcement | **Strong** (hooks fire automatically) | Strong if coordinator is sole interface |
| Crash recovery | **Automatic** (subprocess dies = error) | Requires health monitoring |
| Idempotency | **Natural** (each call fresh) | Requires explicit state management |

The current system is more reliable at the mechanical level. The tmux system requires more defensive engineering.

### Governance Strength

| Property | Current System | Tmux Replacement |
|----------|---------------|-----------------|
| Can agent bypass governance? | **No** — hooks fire on tool calls, agent can't suppress them | **Depends** — if agent can access tmux directly, it could send-keys to other panes |
| Evidence tamper resistance | **Strong** — agents don't create markers, hooks do | **Moderate** — coordinator creates evidence, but agents could write to state file |
| Invalidation on edit | **Automatic** — PostToolUse hook fires on every Edit/Write | **Requires monitoring** — coordinator must detect edits (via file watcher or Claude's output) |
| Ordering enforcement | **Automatic** — PreToolUse hooks block out-of-order calls | **Explicit** — state machine must be correctly implemented |

**Key difference:** The current system's governance is **passive** — hooks fire automatically and the agent cannot prevent them. The tmux system's governance is **active** — the coordinator must explicitly enforce rules, and there are more ways to circumvent it.

**Mitigation:** If the coordinator is the **sole interface** between the user and the agents (user types into coordinator, not directly into agent panes), then governance is equally strong. The coordinator can refuse to forward commands that violate the state machine.

### Performance

| Metric | Current System | Tmux Replacement |
|--------|---------------|-----------------|
| Single PR cycle | ~45 min (sequential) | ~35 min (some parallelism) |
| Multi-PR session | N × 45 min | ~N × 30 min (pipeline overlap) |
| Codex review latency | 5-15 min (blocking) | 5-15 min (non-blocking) |
| Codex context quality | Cold start each time | Warm context across reviews |
| Sub-agent overhead | Minimal (in-process) | Same (kept in-process) |
| Idle cost | Zero (agents only run when needed) | Non-zero (persistent sessions) |

**Where tmux wins:** Multi-PR sessions where pipeline overlap matters. A 5-PR session might take 3.75 hours today vs. 2.5 hours with tmux.

**Where current system wins:** Single-task sessions where there's nothing to parallelize. The overhead of the coordinator and session management is pure cost.

### Observability

| Capability | Current System | Tmux Replacement |
|-----------|---------------|-----------------|
| Watch agents work | No (Codex runs in background subprocess) | **Yes** (both panes visible) |
| Intervene mid-task | No (must wait for subprocess to finish) | **Yes** (type into any pane) |
| Progress during Codex review | None (blocking call) | **Real-time** (watch Codex's pane) |
| Audit trail | JSONL logs (agent-trace, skill-trace) | JSONL logs + state file history + pane scrollback |
| Dashboard | status-line.sh (single line) | Full pane with live state, markers, logs |

This is a clear tmux win. The current system is opaque during Codex execution.

### Developer Experience

| Aspect | Current System | Tmux Replacement |
|--------|---------------|-----------------|
| Setup complexity | `install.sh` (symlinks + hook config) | `install.sh` + tmux + coordinator setup |
| Debugging | Read hook scripts, check marker files | Read coordinator, check state file, check pane history |
| Extending | Add a hook script, wire it in settings.json | Modify coordinator state machine |
| Testing | Feed JSON to hook scripts | Feed JSON to coordinator + mock tmux commands |
| CI compatibility | **Works** (no tmux needed, hooks fire normally) | **Partial** (need virtual tmux or fallback to subprocess mode) |
| Remote/SSH | Works everywhere | **Excellent** (tmux attach from anywhere) |

### What Each System Is Better At

| Use Case | Better System | Why |
|----------|--------------|-----|
| Single-task PR workflow | Current | No parallelism needed, sequential pipeline is natural |
| Multi-task sessions | **Tmux** | Pipeline overlap saves 30%+ time |
| Governance enforcement | Current | Passive hooks are harder to circumvent than active coordinator |
| Observability | **Tmux** | Watch both agents, intervene, see progress |
| Persistent Codex context | **Tmux** | Codex remembers previous reviews in session |
| CI/headless environments | Current | No tmux dependency |
| Interactive debugging with Codex | **Tmux** | Multi-turn dialogue, full tool access |
| Simplicity | Current | Fewer moving parts, no session management |
| Cost efficiency (single task) | Current | No idle agent cost |
| Throughput (long sessions) | **Tmux** | More work done per hour |

---

## Part 4: What the Full Conversion Requires

### New Components to Build

| Component | Effort | Description |
|-----------|--------|-------------|
| `party-coord.sh` | Large | State machine, message routing, evidence collection, health monitoring |
| Completion detection library | Medium | Sentinel injection, idle detection, process monitoring |
| Output extraction library | Medium | ANSI stripping, sentinel parsing, structured extraction |
| Session manager | Small | Startup, teardown, health checks, crash recovery |
| Dashboard pane script | Small | Live state file display, marker status, log tailing |
| Migration of settings.json | Small | Remove hook-based governance, add coordinator config |

### Components to Remove

| Component | Why |
|-----------|-----|
| `codex-gate.sh` | Replaced by coordinator state machine |
| `codex-trace.sh` | Replaced by coordinator evidence collection |
| `pr-gate.sh` | Replaced by coordinator state machine |
| `marker-invalidate.sh` | Replaced by timestamp-based staleness |
| `agent-trace.sh` | Partially kept (sub-agents still use Task tool), but marker creation moves to coordinator |
| `call_codex.sh` | Replaced by coordinator's send-keys to Codex pane |
| `codex-verdict.sh` | Verdict extracted from Codex pane output by coordinator |

### Components to Keep (Unchanged or Minimal Changes)

| Component | Why |
|-----------|-----|
| `call_claude.sh` | Still needed for Codex → Claude (if Codex initiates) |
| `skill-eval.sh` | Still fires on UserPromptSubmit (works within Claude's pane) |
| `skill-marker.sh` | Still fires on Skill tool use (works within Claude's pane) |
| `worktree-guard.sh` | Still fires within Claude's pane |
| Sub-agent definitions | Unchanged — still run via Task tool inside Claude |
| `session-cleanup.sh` | Adapted to clean state files instead of marker files |
| CLAUDE.md | Updated to reflect new workflow (no more call_codex.sh instructions) |
| Rules (execution-core, autonomous-flow) | Updated to reference coordinator states instead of markers |

### Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Completion detection fails silently | High | Timeout fallback: if sentinel not seen in 20 minutes, coordinator kills and retries |
| Race condition: send-keys during agent output | Medium | Coordinator waits for idle detection before sending |
| Agent crashes mid-session, state file stale | Medium | Health check + automatic state recovery |
| Codex writes files during review (sandbox bypass) | Low | Launch with `--sandbox read-only` flag |
| User types directly into agent pane, bypassing coordinator | Low | Document that coordinator pane is the input interface |
| ANSI parsing misses content | Medium | Use file-based output handoff as primary, pane capture as fallback |

---

## Part 5: Verdict

### When to convert

The tmux replacement makes sense if:

1. **Multi-PR sessions are the norm.** If most sessions involve 3+ PRs, the 30% throughput gain from pipeline overlap compounds significantly.
2. **Codex review quality matters and is limited by cold starts.** If Codex gives noticeably better reviews when it has session context, persistent sessions pay off.
3. **Observability is a pain point.** If the 15-minute Codex blackout is regularly frustrating and leads to wasted time.
4. **Interactive Codex dialogues are desired.** If multi-turn architecture discussions or debugging sessions with Codex would be valuable beyond the review pipeline.

### When to stay

The current system makes sense if:

1. **Single-task sessions are the norm.** If most sessions are one PR, the tmux overhead has no payoff.
2. **Governance tamper-resistance is paramount.** If the passive hook enforcement is valued over the active coordinator model.
3. **CI/headless usage is important.** If the workflow runs in environments without tmux.
4. **Simplicity is valued.** If maintaining ~700 lines of bash hooks is preferred over ~1200 lines of coordinator + libraries.

### The honest assessment

The current system is overengineered for a subprocess model — its governance layer is genuinely sophisticated. Converting to tmux trades that sophistication for capabilities the subprocess model simply cannot provide (parallelism, persistence, observability, interactivity). The conversion is non-trivial (~2-3 days of focused engineering) but the resulting system would be strictly more capable, at the cost of more complex failure modes.

The biggest risk isn't building it — it's that completion detection and output parsing in tmux are fundamentally heuristic. The current system's deterministic "call and wait" model will always be more reliable than "send-keys and poll." The question is whether the capabilities gained justify living with that uncertainty.

---

## Part 6: CLI vs Tmux — Does Invocation Method Affect Review Quality?

### The Core Question

When Codex reviews code, does it matter whether it was invoked as a blocking subprocess (`codex exec review`) or as a persistent interactive session in a tmux pane? The answer is nuanced — the invocation method itself doesn't change the model, but it changes the **context, capabilities, and interaction pattern** that shape review quality.

### How CLI Reviews Work Today

```
codex exec review --prompt "Review this diff..." --file /tmp/diff.patch
```

1. **Cold start.** Every invocation creates a fresh context. Codex has zero memory of prior reviews, prior code changes, or the codebase's history in this session.
2. **One-shot output.** Codex produces a single review response. If it misunderstands something or makes an error, there's no recourse — the review is final.
3. **Structured input.** The diff and instructions are passed as clean arguments. No ANSI artifacts, no pane noise. Input is deterministic.
4. **Read-only sandbox.** `codex exec` runs with `--sandbox read-only` implicitly. Codex can't run `grep` over the codebase to check whether a pattern exists elsewhere. It reviews only what's in front of it.
5. **Token-limited context.** The prompt + diff + system instructions must fit in a single context window. Large diffs get truncated or summarized by `call_codex.sh`.

### How Tmux Reviews Would Work

```
tmux send-keys -t codex "Review this diff against main. [diff content]. SENTINEL_xxx" C-m
```

1. **Warm context.** If Codex has reviewed earlier code in this session, it retains that context. It knows what the developer's patterns look like, what was changed before, and what the overall direction of the work is.
2. **Multi-turn possible.** The coordinator can mediate clarification: Codex asks "Is this intentional?" → coordinator relays to Claude → Claude responds → coordinator sends back to Codex. Review becomes a dialogue, not a verdict.
3. **Noisy input.** Pane capture includes potential ANSI codes, line-wrap artifacts, and TUI formatting. Diff content must be cleaned before Codex can parse it reliably.
4. **Full tool access.** Interactive Codex can run `grep`, `cat`, `find` — it can investigate the codebase during review. A review of "is this function used elsewhere?" can be answered by actually searching, not guessing.
5. **Larger effective context.** Multi-turn exchange means Codex can request specific files, ask for function definitions, or request the full test suite. Context is built incrementally rather than front-loaded.

### Quality Dimensions Compared

| Dimension | CLI (`codex exec`) | Tmux (interactive) | Winner |
|-----------|--------------------|--------------------|--------|
| **Input fidelity** | Clean structured JSON/text | Pane capture with potential noise | CLI |
| **Codebase awareness** | Only what's in the prompt | Can investigate via tools | Tmux |
| **Cross-review context** | None (cold start) | Remembers prior reviews | Tmux |
| **Consistency** | Same input → same review | Context-dependent, variable | CLI |
| **Depth of analysis** | Limited to provided diff | Can explore related code | Tmux |
| **False positive rate** | Higher (can't verify assumptions) | Lower (can check assumptions) | Tmux |
| **Latency to first finding** | Fast (direct inference) | Slower (may run tools first) | CLI |
| **Nuance in edge cases** | Low (no dialogue) | High (can ask clarifications) | Tmux |
| **Reproducibility** | High (deterministic input) | Low (depends on session state) | CLI |
| **Cost per review** | Lower (single inference) | Higher (multi-turn + tool use) | CLI |

### The Persistent Context Effect

The most significant quality difference is **persistent context**. In a typical session:

- **Review 1:** Codex sees a new utility function. In CLI mode, it evaluates it in isolation. In tmux mode, same behavior — no difference yet.
- **Review 2:** Codex sees the same pattern again. CLI mode treats it as novel. Tmux mode recognizes the pattern from Review 1 and can note consistency or flag divergence.
- **Review 3:** A refactor touches code reviewed in Review 1. CLI mode has no memory of what it said before. Tmux mode can verify its earlier suggestions were addressed.

This matters for **multi-PR sessions** where reviews build on each other. For single-PR sessions, the context advantage is minimal.

### The Tool Access Effect

CLI mode Codex is effectively blind — it can only analyze the exact text provided. Interactive Codex can investigate:

- "This function calls `parseConfig()` — let me check what that does" → `grep -rn parseConfig`
- "The test file should cover this edge case — let me verify" → `cat tests/parser_test.go`
- "Is this import used elsewhere in the project?" → `grep -rn 'import.*moduleName'`

This makes tmux reviews **more thorough** for architectural and integration concerns, where understanding context beyond the diff matters. For purely syntactic or local logic issues, the advantage is negligible.

### The Noise Problem

Tmux reviews face an input quality challenge that CLI reviews don't:

1. **ANSI escape codes** in captured pane output can corrupt diff content
2. **Line wrapping** in narrow panes can break code indentation, making it look wrong when it isn't
3. **TUI elements** (status bars, progress indicators) can appear in captured output
4. **Timing issues** — capturing too early gets incomplete output, capturing too late may miss scrolled content

Mitigation strategies exist (sentinel-based extraction, file-based output handoff, ANSI stripping), but they add complexity and failure modes that CLI reviews simply don't have. A corrupted diff leads to a corrupted review.

### When CLI Reviews Are Better

1. **Automated/CI pipelines** where consistency and reproducibility matter more than depth
2. **Small, focused diffs** (< 200 lines) where the full context is in the diff itself
3. **Security-critical reviews** where the read-only sandbox is a feature, not a limitation
4. **Cost-sensitive environments** where single-inference reviews are significantly cheaper

### When Tmux Reviews Are Better

1. **Large refactors** where understanding the broader codebase is essential
2. **Multi-PR sessions** where review context accumulates meaningfully
3. **Architectural reviews** where the reviewer needs to investigate beyond the diff
4. **Iterative development** where multi-turn dialogue catches issues a one-shot review misses
5. **Complex codebases** where a cold-start reviewer lacks necessary project knowledge

### Verdict on Review Quality

**For the current use case (single-reviewer, governance-gated pipeline):** CLI reviews are *adequate* and *more reliable*. The structured input and deterministic behavior are valuable properties for an enforcement gate. The reviews miss some depth, but the system compensates with multiple reviewers (code-critic + minimizer + codex).

**For a more capable system:** Tmux reviews would be *qualitatively better* — deeper, more contextual, more nuanced. The trade-off is reliability and cost. If the coordinator can solve the input fidelity problem (via file-based handoff rather than pane capture), the quality advantage becomes compelling.

**Net assessment:** Review quality is not the primary driver for or against tmux. The CLI model produces good-enough reviews for governance purposes. Tmux would produce better reviews, but the improvement is incremental, not transformative. The real arguments for tmux are parallelism and persistent context — review quality is a secondary benefit.

---

## Part 7: CLI-Only Capabilities — What Tmux Cannot Replicate

### Capabilities Exclusive to the CLI Subprocess Model

Several properties of the current system are **structurally impossible** to replicate in a tmux-based architecture. These aren't limitations that can be engineered around — they're fundamental to the invocation model.

#### 1. Deterministic Blocking

**CLI:** `call_codex.sh` invokes `codex exec` and blocks. When the script returns, the review is done. There is zero ambiguity about completion.

**Tmux:** Completion detection is heuristic. Sentinel polling, idle detection, and process monitoring are all probabilistic. There is always a nonzero chance of:
- False completion (sentinel appears in quoted text)
- Missed completion (sentinel scrolls off pane buffer)
- Zombie state (agent hangs but doesn't crash)

**Impact:** The governance system's tamper-resistance depends on deterministic state transitions. Heuristic completion detection introduces a class of failures that doesn't exist in the CLI model.

#### 2. Structured JSON Output

**CLI:** `codex exec` returns structured output. `call_codex.sh` pipes through `jq` to extract the final message:
```bash
codex exec review ... 2>/dev/null | jq -r '.choices[0].message.content'
```

**Tmux:** Output is extracted from a terminal emulator buffer. Even with ANSI stripping and sentinel framing, the output is **plain text with no guaranteed structure**. Parsing verdicts requires regex matching against free-form text, which is inherently fragile.

**Impact:** The evidence chain currently relies on exact string matching (`CODEX_REVIEW_RAN`, `CODEX APPROVED`). In tmux, these strings must be extracted from pane capture, where formatting artifacts, line wrapping, or model output variation could cause false negatives.

#### 3. Process-Level Isolation

**CLI:** `codex exec` runs in an isolated subprocess with its own environment. It cannot access Claude's runtime state, memory, or tools. The read-only sandbox is enforced at the OS level.

**Tmux:** Both agents run as persistent processes on the same machine. While Codex can be launched with `--sandbox read-only`, the isolation is weaker:
- Shared filesystem (same `/tmp/`, same working directory)
- Shared environment variables (unless explicitly scrubbed)
- Both processes visible to each other via `ps`
- Coordinator must mediate all access, but agents could theoretically bypass it

**Impact:** For governance purposes, the CLI's process isolation is a stronger security boundary. In tmux, the coordinator is a trust boundary that must be maintained by convention rather than enforcement.

#### 4. Hook-Based Evidence Chain

**CLI:** Claude Code's hook system fires on every tool call. Hooks are **passive observers** — they cannot be bypassed by the agent because they run outside the agent's process. The evidence chain is:
```
Agent uses tool → Hook fires automatically → Hook creates/checks markers
```

**Tmux:** There are no hooks. The coordinator is an **active participant** that must explicitly perform governance checks. The evidence chain becomes:
```
Agent produces output → Coordinator polls and detects → Coordinator updates state
```

**Impact:** The hook model is inherently more tamper-resistant because it's event-driven and mandatory. The coordinator model requires polling (can miss events), explicit checks (can have bugs), and is itself a single point of failure.

#### 5. Cost-Efficient Invocation

**CLI:** Codex is only instantiated when needed. `codex exec` spins up, does its work, and exits. Token cost is exactly one inference pass per invocation. No idle costs.

**Tmux:** Codex runs persistently. Even when idle, it consumes:
- System resources (RAM, process slots)
- The interactive session itself (Codex's context window accumulates)
- Potential keep-alive costs (if the provider charges for session duration)

For sessions where Codex is invoked once or twice, the persistent session overhead is pure waste.

**Impact:** Cost scales differently. CLI cost is O(invocations). Tmux cost is O(session_duration) with a minimum floor regardless of usage.

#### 6. Environment Portability

**CLI:** Works anywhere Claude Code runs — CI pipelines, Docker containers, SSH sessions, headless servers. No display, no terminal emulator, no multiplexer required.

**Tmux:** Requires tmux to be installed and running. Doesn't work in:
- Most CI/CD environments (no tmux)
- Minimal Docker containers (no tmux)
- Windows without WSL
- Environments where tmux is disallowed by policy

**Impact:** The CLI model is universally portable. Tmux introduces an environmental dependency that limits where the system can run.

#### 7. Atomic Tool-Call Semantics

**CLI:** Each `codex exec` call is a single tool invocation from Claude's perspective. It appears as one Bash tool call in Claude's context, with one input and one output. This means:
- Claude's context window isn't polluted by intermediate Codex output
- The hook system sees one clean event to gate and trace
- Retry logic is simple (re-invoke the tool)

**Tmux:** Communication is streamed. The coordinator sends multiple messages to Codex and captures multiple responses. From Claude's perspective, the review is opaque — Claude doesn't see Codex working. Claude's context stays clean, but the coordinator must manage all intermediate state externally.

**Impact:** Atomic semantics simplify everything — governance, debugging, logging, retry logic. Streamed communication is more capable but more complex.

### Capabilities Tmux Gains That CLI Cannot Provide

For completeness, here's what tmux provides that CLI structurally cannot:

| Capability | Why CLI Can't Do This |
|------------|----------------------|
| **Parallel agent execution** | `codex exec` blocks the calling process |
| **Persistent agent memory** | Each `codex exec` starts from scratch |
| **Multi-turn agent dialogue** | `codex exec` is fire-and-forget |
| **Real-time observability** | Subprocess output is captured only after exit |
| **Incremental context building** | No way to add context to a running `codex exec` |
| **Agent-to-agent negotiation** | Requires multiple round trips, each a new subprocess |
| **Shared workspace awareness** | Codex can't watch Claude work in real time |

### Summary: The CLI Advantage is Reliability

The CLI model's exclusive capabilities cluster around one theme: **reliability and determinism**. Every CLI-only property — blocking execution, structured output, process isolation, hook-based evidence, atomic semantics — serves the same goal: making the system predictable and tamper-resistant.

The tmux model's exclusive capabilities cluster around a different theme: **flexibility and capability**. Parallelism, persistence, dialogue, observability — these make the system more powerful but less predictable.

This is the fundamental trade-off. It's not about which is "better" — it's about which properties matter more for the use case. For a governance-gated review pipeline, reliability matters more. For a collaborative multi-agent workspace, capability matters more.

---

## Part 8: Feasibility Assessment — New Repo vs In-Place Modification

### The Question

Should the tmux-based coordinator be built as a modification to this repository (`ai-config`), or as a new separate repository? This section assesses both approaches based on a thorough analysis of the current codebase's structure, coupling, and complexity.

### Current Codebase Coupling Analysis

#### Files Directly Referencing Codex CLI Invocation

17 files reference `call_codex.sh`, `codex-verdict.sh`, or `codex exec`:

| Category | Files | Coupling Type |
|----------|-------|---------------|
| **Executable scripts** | `call_codex.sh` (164 lines), `codex-verdict.sh` (11 lines), `call_claude.sh` (147 lines) | Hard — replaced entirely |
| **Gate hooks** | `codex-gate.sh` (47 lines), `codex-trace.sh` (61 lines) | Hard — regex matches `call_codex.sh` literally |
| **Enforcement rules** | `execution-core.md`, `autonomous-flow.md` | Hard — prescribe specific script invocations |
| **Settings** | `settings.json` (2 permission lines) | Hard — grants Bash permission for specific paths |
| **Skill definitions** | `codex-cli/SKILL.md`, `task-workflow/SKILL.md`, `bugfix-workflow/SKILL.md` | Soft — documentation of workflow, not executable logic |
| **Agent guidelines** | `CLAUDE.md` (3 references) | Soft — prescriptive but not enforced by code |
| **Codex config** | `AGENTS.md`, `config.toml` | Independent — Codex's own configuration |

#### Critical Dependency Chain

```
execution-core.md (rules)
        │
        ├──▶ codex-gate.sh (PreToolUse hook)
        │     └── regex: call_codex\.sh +--review
        │
        ├──▶ codex-trace.sh (PostToolUse hook)
        │     └── regex: call_codex\.sh
        │     └── sentinel: CODEX_REVIEW_RAN
        │
        ├──▶ pr-gate.sh (PreToolUse hook)
        │     └── checks /tmp/claude-codex-{sid} marker
        │
        └──▶ marker-invalidate.sh (PostToolUse hook)
              └── deletes all 8 markers including codex-specific ones
```

Every hook uses **regex pattern matching** on exact script names. In a tmux model, these scripts aren't invoked via Bash tool, so the hooks can't fire and the regex can't match. This isn't something you can adapt incrementally — the detection mechanism is fundamentally incompatible.

#### What Survives Unchanged

| Component | Lines | Reusable? | Notes |
|-----------|-------|-----------|-------|
| Marker naming/semantics | N/A | Yes | Names, meanings, invalidation logic all transfer |
| Sub-agent infrastructure | ~500 | Yes | code-critic, minimizer, test-runner, check-runner, security-scanner — all run via Task tool, unaffected by Codex invocation method |
| `agent-trace.sh` | 126 | Yes | Sub-agent verdict capture stays identical |
| `skill-marker.sh` | 65 | Yes | Skill completion markers unaffected |
| `marker-invalidate.sh` | 60 | Yes | Edit-time invalidation logic is orthogonal |
| `session-cleanup.sh` | 25 | Yes | Marker cleanup is independent |
| `worktree-guard.sh` | 53 | Yes | Git protection is independent |
| `skill-eval.sh` | 123 | Yes | Skill suggestion is independent |
| Agent personas/style | ~200 | Yes | "Paladin"/"Wizard" identities, communication rules |
| Decision matrices | ~200 | Yes | Triage, severity, iteration caps — all orthogonal |
| Technology rules | ~300 | Yes | Go, Python, React, TypeScript rules unchanged |

**Summary:** ~75% of the codebase (by line count) is reusable without modification. The remaining ~25% is tightly coupled to the subprocess model.

### Option A: In-Place Modification

#### Scope of Changes

| Change | Effort | Risk |
|--------|--------|------|
| Rewrite `codex-gate.sh` (47 lines → coordinator logic) | Medium | HIGH — enforcement logic |
| Rewrite `codex-trace.sh` (61 lines → coordinator logic) | Medium | HIGH — evidence chain |
| Delete `call_codex.sh`, `codex-verdict.sh` | Trivial | None |
| Write coordinator script (~400-500 lines) | Large | HIGH — new complex system |
| Update `settings.json` (remove 2 permissions) | Trivial | Low |
| Rewrite `execution-core.md` (4+ sections) | Medium | Medium — documentation |
| Update `CLAUDE.md` (3 references) | Small | Medium — documentation |
| Rewrite `codex-cli/SKILL.md` (105 lines) | Medium | Medium — documentation |
| Update `task-workflow/SKILL.md`, `bugfix-workflow/SKILL.md` | Small | Low — documentation |
| Build test infrastructure from scratch | Large | HIGH — no existing tests |

#### Risks

1. **No test suite exists.** The repository has zero automated tests. Modifying governance code without tests means changes can't be validated except by manual testing in live sessions.
2. **Active development conflict.** The codebase sees 2-3 commits per day with ongoing enforcement hardening (commits #19, #20). In-place modification risks merge conflicts with this active work.
3. **Dual-mode transition period.** During migration, both subprocess and tmux paths would need to coexist. The hooks expect `call_codex.sh` invocations; the coordinator expects tmux panes. Running both creates confusing state.
4. **No rollback.** Once hooks are rewritten, reverting requires restoring the exact regex patterns, permissions, and scripts. Git revert works in theory but is messy in practice when 17+ files change.
5. **Enforcement gaps.** During the transition, there may be windows where neither hooks nor coordinator properly enforce governance. For a security-critical review pipeline, gaps are unacceptable.

#### Benefits

1. Single repository — no fork maintenance
2. Existing developers stay on one branch
3. Git history shows the evolution from subprocess → tmux

### Option B: New Repository

#### Scope of Changes

| Action | Effort | Risk |
|--------|--------|------|
| Create new repo, copy shared infrastructure | Small | None — isolated |
| Write coordinator (~400-500 lines) | Large | MEDIUM — isolated, testable |
| Port governance rules to coordinator state machine | Medium | MEDIUM — contained |
| Adapt workflow documentation | Small | Low — documentation |
| Build test infrastructure (mock agents, harness) | Medium | Low — greenfield |

#### Risks

1. **Fork maintenance.** If the original repo continues evolving (new rules, new skills), the new repo must be kept in sync.
2. **User confusion.** Two repos serving similar purposes creates a "which one do I use?" problem.
3. **Integration cost.** If the tmux system proves itself, merging it back into the main repo is non-trivial.

#### Benefits

1. **Complete isolation.** Can't break the existing system. Current governance continues working while the tmux system is developed.
2. **Proper testing.** Can build a test harness from day one without retrofitting it into an existing codebase.
3. **Clean rollback.** If it fails, delete the repo. The original system is untouched.
4. **Parallel development.** Original repo continues hardening while tmux system is built.
5. **Honest comparison.** Both systems can be run side-by-side to compare behavior.

### Quantitative Comparison

| Criterion | In-Place | New Repo |
|-----------|----------|----------|
| **Files modified** | 17+ | 0 (in original) |
| **New code** | ~500 lines + 300 test | ~500 lines + 300 test |
| **Existing code deleted** | ~280 lines | 0 |
| **Documentation rewrites** | ~500 lines across 6-8 files | Fresh docs only |
| **Risk to production system** | HIGH | NONE |
| **Test infrastructure** | Must retrofit | Built from scratch |
| **Rollback difficulty** | Medium-Hard | Trivial |
| **Time to first working prototype** | Longer (must maintain compatibility) | Shorter (no constraints) |

### Recommendation

**New repository is significantly more feasible** for three primary reasons:

1. **The hook coupling is architectural, not incidental.** The `codex-gate.sh` and `codex-trace.sh` hooks use regex matching on exact script names at the Bash tool call level. This isn't a matter of updating a few strings — the detection mechanism is structurally incompatible with tmux-based orchestration. In a new repo, you design the evidence system from scratch instead of retrofitting it.

2. **No test suite means no safety net.** Modifying governance code in a live system with zero automated tests is high-risk. A new repo lets you build validation infrastructure first, then implement against it.

3. **The shared infrastructure is copy-friendly.** The ~75% of reusable code (agent definitions, rules, skills, markers, style) is documentation and configuration — easy to copy and maintain in sync. The ~25% that must change is the exact code that would be rewritten anyway.

**Suggested approach:** Create `ai-config-tmux`, copy the shared infrastructure, build the coordinator with tests, validate with mock agents, then evaluate whether to merge back or run in parallel. The original repo continues working throughout.

### If In-Place Is Chosen Anyway

If the decision is made to modify this repository:

1. **Create a long-lived feature branch** — never modify `main` directly during transition
2. **Write tests first** — build a shell test harness before touching any hooks
3. **Feature-flag the coordinator** — environment variable toggles between subprocess and tmux mode
4. **Migrate one hook at a time** — start with `codex-trace.sh` (evidence collection), keep `codex-gate.sh` (enforcement) until last
5. **Maintain backward compatibility** — keep `call_codex.sh` working alongside the coordinator until the tmux path is proven

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
| tmux-mcp (jonrad) | github.com/jonrad/tmux-mcp |
| tmux-mcp (lox) | github.com/lox/tmux-mcp-server |
