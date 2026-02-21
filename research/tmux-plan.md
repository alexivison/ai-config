# Tmux Coordinator — Implementation Plan

Implementation plan for replacing the subprocess-based Claude/Codex orchestration with tmux-based coordination. Built for iTerm2 on macOS.

---

## Context

### Why tmux

The current system invokes Codex as a blocking subprocess (`codex exec`). Each invocation is a cold start — fresh context, one-shot output, 15-minute block on Claude. The user's workflow involves 3-7 Codex reviews per task and bidirectional Claude↔Codex planning dialogues. At 7 reviews per task, that's ~105 minutes of dead blocking time. Tmux replaces this with persistent interactive sessions where both agents retain context across reviews and Claude isn't blocked during Codex work.

### What stays the same

- Sub-agents (code-critic, minimizer, test-runner, check-runner, security-scanner) remain in-process via Claude's Task tool
- The marker system's names, semantics, and invalidation logic survive intact
- All workflow skills (task-workflow, bugfix-workflow, pre-pr-verification) keep their structure — only the Codex invocation step changes
- Agent personas (Paladin/Wizard), rules, decision matrices are reused
- The review governance model (severity triage, iteration caps, tiered re-review) is unchanged

### What changes

- `call_codex.sh` / `codex-verdict.sh` → replaced by coordinator-mediated tmux communication
- `codex-gate.sh` / `codex-trace.sh` → replaced by coordinator state machine
- `settings.json` → updated permissions, hook config gains coordinator hooks
- Workflow skill docs → updated Codex invocation instructions
- `CLAUDE.md`, `execution-core.md`, `autonomous-flow.md` → updated references

### iTerm2 integration

iTerm2 supports `tmux -CC` (control mode), which maps tmux panes to native iTerm2 splits/tabs. The user gets native scrollback, selection, and search in each pane — no raw tmux pane capture needed for human observability. The coordinator still uses `tmux capture-pane` and `tmux send-keys` programmatically, but the user sees native iTerm2 windows.

---

## New Repo: `ai-config-tmux`

This is built as a **new repository** alongside the existing `ai-config`. Reasoning:

1. Current system works and is used daily — can't break it during development
2. The 2 critical hooks (`codex-gate.sh`, `codex-trace.sh`) are structurally incompatible with tmux — they regex-match `call_codex.sh` at the Bash tool call level, which doesn't exist in tmux
3. Zero test infrastructure exists — new repo builds validation from day one
4. Can evaluate side-by-side before committing to migration

### Repo structure

```
ai-config-tmux/
├── coordinator/
│   ├── party.sh                    # Main entry point — session launcher
│   ├── state-machine.sh            # Core state machine logic
│   ├── evidence.sh                 # Evidence collection, staleness, invalidation
│   ├── pane-io.sh                  # Send/capture/parse pane output
│   ├── codex-review.sh             # Codex review flow (replaces call_codex.sh)
│   ├── codex-dialogue.sh           # Multi-turn Codex dialogue for planning
│   └── health.sh                   # Agent health check, crash recovery
│
├── claude/                         # Copied + adapted from ai-config
│   ├── CLAUDE.md                   # Updated: coordinator references replace call_codex.sh
│   ├── settings.json               # Updated: new hooks, remove codex script permissions
│   ├── hooks/
│   │   ├── session-cleanup.sh      # Unchanged
│   │   ├── skill-eval.sh           # Unchanged
│   │   ├── worktree-guard.sh       # Unchanged
│   │   ├── agent-trace.sh          # Unchanged (sub-agents still in-process)
│   │   ├── marker-invalidate.sh    # Unchanged
│   │   ├── skill-marker.sh         # Unchanged
│   │   ├── pr-gate.sh              # Unchanged (still checks same markers)
│   │   ├── coordinator-gate.sh     # NEW: replaces codex-gate.sh — signals coordinator
│   │   └── coordinator-trace.sh    # NEW: replaces codex-trace.sh — reads coordinator state
│   ├── rules/
│   │   ├── execution-core.md       # Updated: coordinator references
│   │   ├── autonomous-flow.md      # Updated: coordinator references
│   │   └── (backend/, frontend/)   # Unchanged
│   ├── skills/
│   │   ├── codex-cli/              # Rewritten: tmux-based invocation
│   │   │   ├── SKILL.md            # Updated: coordinator-mediated patterns
│   │   │   └── scripts/
│   │   │       └── request-codex.sh  # NEW: signals coordinator to dispatch to Codex
│   │   ├── task-workflow/SKILL.md  # Updated: step 7 uses coordinator
│   │   ├── bugfix-workflow/SKILL.md # Updated: codex step uses coordinator
│   │   ├── pre-pr-verification/    # Unchanged
│   │   └── (other skills/)         # Unchanged
│   ├── agents/                     # Unchanged
│   └── scripts/                    # Unchanged
│
├── codex/                          # Copied + adapted from ai-config
│   ├── AGENTS.md                   # Updated: "you're in a tmux pane" context
│   ├── config.toml                 # Updated: sandbox mode per use case
│   ├── rules/                      # Unchanged
│   └── skills/
│       └── claude-cli/             # Rewritten: coordinator-mediated
│           ├── SKILL.md
│           └── scripts/
│               └── request-claude.sh  # NEW: signals coordinator to dispatch to Claude
│
├── shared/                         # Copied from ai-config
│   └── skills/                     # Unchanged
│
├── tests/
│   ├── test-state-machine.sh       # State transition tests
│   ├── test-evidence.sh            # Evidence staleness, invalidation tests
│   ├── test-pane-io.sh             # Pane capture/parse tests
│   ├── test-hooks.sh               # Hook integration tests
│   ├── mock-claude.sh              # Mock Claude agent for testing
│   ├── mock-codex.sh               # Mock Codex agent for testing
│   └── run-tests.sh                # Test runner
│
├── install.sh                      # Adapted from ai-config
└── README.md
```

---

## Phase 1: Coordinator Core

### 1.1 Session Launcher (`party.sh`)

The main entry point. Starts a tmux session with panes for Claude, Codex, the coordinator, and a dashboard.

**iTerm2 integration:** Launch with `tmux -CC` to get native iTerm2 panes:

```bash
# Launch in iTerm2 control mode
party.sh                # Default: uses tmux -CC if TERM_PROGRAM=iTerm.app
party.sh --raw          # Force raw tmux (for SSH, non-iTerm terminals)
```

**Pane layout:**

```
┌─────────────────────────────┬──────────────────────────────┐
│ Pane 0: Claude              │ Pane 1: Codex                │
│ claude --dangerously-skip-  │ codex --full-auto             │
│ permissions                 │ --sandbox read-only           │
│                             │                               │
│                             │                               │
├─────────────────────────────┴──────────────────────────────┤
│ Pane 2: Dashboard                                          │
│ State: IMPLEMENT | Evidence: critic✓ mini✓ codex… tests✓   │
│ Codex reviews: 2/7 | Last edit: 10:30:00 | Session: abc123 │
└────────────────────────────────────────────────────────────┘
```

The coordinator runs as a background process (not in a pane) — it's a daemon that monitors and controls the panes. The dashboard pane tails the state file.

**Implementation details:**

```bash
party_start() {
  SESSION="party-$(date +%s)"
  STATE_DIR="/tmp/party-$SESSION"
  mkdir -p "$STATE_DIR"

  # Detect iTerm2 and use control mode
  TMUX_CMD="tmux"
  if [[ "${TERM_PROGRAM:-}" == "iTerm.app" && "${PARTY_RAW:-}" != "1" ]]; then
    TMUX_CMD="tmux -CC"
  fi

  # Create session
  $TMUX_CMD new-session -d -s "$SESSION" -n work -x 200 -y 50

  # Split into panes
  tmux split-window -h -t "$SESSION:work"        # Pane 1: Codex (right)
  tmux split-window -v -t "$SESSION:work.0"       # Pane 2: Dashboard (below Claude)

  # Launch agents
  tmux send-keys -t "$SESSION:work.0" \
    "claude --dangerously-skip-permissions" C-m
  tmux send-keys -t "$SESSION:work.1" \
    "codex --full-auto --sandbox read-only" C-m

  # Launch dashboard
  tmux send-keys -t "$SESSION:work.2" \
    "watch -n 1 cat $STATE_DIR/state.json | jq -C ." C-m

  # Initialize state
  cat > "$STATE_DIR/state.json" << 'INIT'
  {
    "state": "IDLE",
    "session_id": "",
    "evidence": {},
    "codex_reviews": 0,
    "last_code_edit": null
  }
  INIT

  # Start coordinator daemon
  nohup coordinator/state-machine.sh "$SESSION" "$STATE_DIR" \
    > "$STATE_DIR/coordinator.log" 2>&1 &
  echo $! > "$STATE_DIR/coordinator.pid"

  # Attach (iTerm2 control mode auto-attaches)
  if [[ "$TMUX_CMD" == "tmux" ]]; then
    tmux attach -t "$SESSION"
  fi
}
```

**Teardown:**

```bash
party_stop() {
  kill "$(cat "$STATE_DIR/coordinator.pid")" 2>/dev/null
  tmux kill-session -t "$SESSION" 2>/dev/null
  rm -rf "$STATE_DIR"
}
```

**Deliverables:**
- [ ] `coordinator/party.sh` — session launcher with iTerm2 detection
- [ ] iTerm2 control mode (`tmux -CC`) integration tested
- [ ] `--raw` fallback for non-iTerm terminals
- [ ] Clean teardown on SIGTERM/SIGINT

### 1.2 State Machine (`state-machine.sh`)

The coordinator's core loop. Replaces the hook-based governance with an explicit state machine.

**States:**

```
IDLE → IMPLEMENT → SELF_REVIEW → CRITICS → CODEX_REVIEW → VERIFY → PR_READY
                ↑                                    │
                └────────────────────────────────────┘
                         (REQUEST_CHANGES)
```

Additional states for non-review flows:

```
IDLE → PLANNING → CODEX_DIALOGUE → PLANNING
                                       │
                                       └→ IMPLEMENT (when plan is accepted)
```

**State transitions:**

| From | To | Trigger |
|------|----|---------|
| IDLE | IMPLEMENT | User sends task to Claude pane |
| IDLE | PLANNING | User asks Codex for planning |
| IMPLEMENT | SELF_REVIEW | Claude signals "self-review" in output |
| SELF_REVIEW | CRITICS | Claude signals "PASS — proceeding to critics" |
| CRITICS | CODEX_REVIEW | Both critic APPROVE markers exist |
| CODEX_REVIEW | IMPLEMENT | Codex verdict: REQUEST_CHANGES |
| CODEX_REVIEW | VERIFY | Codex verdict: APPROVE |
| VERIFY | PR_READY | All verification markers present |
| PR_READY | IDLE | PR created |
| PLANNING | CODEX_DIALOGUE | Codex needs Claude's input |
| CODEX_DIALOGUE | PLANNING | Claude responds, coordinator relays to Codex |
| Any | IMPLEMENT | Code edit detected (marker invalidation) |

**Core loop:**

```bash
while true; do
  state=$(jq -r '.state' "$STATE_DIR/state.json")

  case "$state" in
    IDLE)
      monitor_for_task_start
      ;;
    IMPLEMENT)
      monitor_claude_pane_for_signal "self-review"
      watch_for_code_edits  # marker invalidation
      ;;
    SELF_REVIEW)
      monitor_claude_pane_for_signal "PASS — proceeding to critics"
      ;;
    CRITICS)
      wait_for_critic_markers
      ;;
    CODEX_REVIEW)
      dispatch_codex_review
      capture_codex_verdict
      ;;
    VERIFY)
      wait_for_verification_markers
      ;;
    PR_READY)
      # pr-gate.sh still enforces markers — coordinator just tracks state
      monitor_for_pr_creation
      ;;
    PLANNING)
      monitor_codex_pane_for_planning_output
      ;;
    CODEX_DIALOGUE)
      mediate_dialogue
      ;;
  esac

  sleep 1
done
```

**Deliverables:**
- [ ] `coordinator/state-machine.sh` — main loop with all state transitions
- [ ] State persistence in `$STATE_DIR/state.json`
- [ ] State transition logging to `$STATE_DIR/transitions.log`
- [ ] Signal detection from pane output (see 1.3)

### 1.3 Pane I/O (`pane-io.sh`)

Library of functions for communicating with agent panes. This is the hardest technical challenge — reliable output capture from terminal emulators.

**Send to pane:**

```bash
# Send a prompt to an agent pane
pane_send() {
  local pane="$1"
  local message="$2"
  local sentinel="SENTINEL_$(date +%s%N)"

  # Append sentinel request to message
  local full_message="$message

When you are completely done, output exactly this line on its own: $sentinel"

  # Write message to temp file to avoid send-keys escaping issues
  local msg_file="$STATE_DIR/msg-$(date +%s%N).txt"
  printf '%s' "$full_message" > "$msg_file"

  # Use bracketed paste mode for clean multi-line input
  tmux send-keys -t "$SESSION:work.$pane" \
    "$(cat "$msg_file")" C-m

  rm -f "$msg_file"
  echo "$sentinel"
}
```

**Capture from pane:**

Two strategies, used together. The primary strategy avoids pane capture entirely:

**Strategy A: File-based handoff (primary)**

Instead of parsing pane output, instruct agents to write results to a known file:

```bash
# For Codex review — instruct Codex to write verdict to file
pane_send_with_file_output() {
  local pane="$1"
  local message="$2"
  local output_file="$STATE_DIR/output-$(date +%s%N).json"

  local full_message="$message

IMPORTANT: When done, write your complete response to this file:
$output_file

Use this exact JSON format:
{\"verdict\": \"APPROVE|REQUEST_CHANGES|NEEDS_DISCUSSION\", \"findings\": \"...\", \"summary\": \"...\"}

After writing the file, output: FILE_WRITTEN"

  tmux send-keys -t "$SESSION:work.$pane" "$full_message" C-m

  # Wait for file to appear
  local timeout=900
  local elapsed=0
  while [[ ! -f "$output_file" ]] && (( elapsed < timeout )); do
    sleep 2
    ((elapsed += 2))
  done

  if [[ -f "$output_file" ]]; then
    cat "$output_file"
  else
    echo '{"verdict": "ERROR", "findings": "Timeout waiting for agent output"}'
  fi
}
```

**Strategy B: Pane capture with sentinel (fallback)**

```bash
# Capture pane output between sentinels
pane_capture() {
  local pane="$1"
  local sentinel="$2"
  local timeout="${3:-900}"
  local elapsed=0

  while (( elapsed < timeout )); do
    local output
    output=$(tmux capture-pane -t "$SESSION:work.$pane" -p -S -500 \
      | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g')

    if echo "$output" | grep -qF "$sentinel"; then
      # Extract content between the prompt and sentinel
      echo "$output" | sed -n "/$sentinel/q;p" | tail -n +2
      return 0
    fi

    sleep 2
    ((elapsed += 2))
  done

  return 1  # timeout
}
```

**Strategy C: Idle detection (health check)**

```bash
pane_is_idle() {
  local pane="$1"
  local prev_hash=""
  local idle_count=0

  for i in $(seq 1 5); do
    local curr_hash
    curr_hash=$(tmux capture-pane -t "$SESSION:work.$pane" -p | md5sum | cut -d' ' -f1)

    if [[ "$curr_hash" == "$prev_hash" ]]; then
      ((idle_count++))
      [[ $idle_count -ge 3 ]] && return 0  # idle
    else
      idle_count=0
    fi

    prev_hash="$curr_hash"
    sleep 2
  done

  return 1  # not idle
}
```

**Deliverables:**
- [ ] `coordinator/pane-io.sh` — send, capture, idle detection functions
- [ ] File-based handoff as primary output mechanism
- [ ] Pane capture with ANSI stripping as fallback
- [ ] Sentinel-based completion detection
- [ ] Idle detection for health checks

### 1.4 Evidence Collection (`evidence.sh`)

Manages the evidence/marker system. Works alongside the existing hooks that survive unchanged (`agent-trace.sh`, `skill-marker.sh`, `marker-invalidate.sh`).

**What this replaces:** `codex-trace.sh` — the hook that creates codex evidence markers. In tmux, the coordinator creates these markers directly after capturing Codex output.

**What this doesn't replace:** All other marker creation stays with existing hooks. The coordinator only manages Codex-related evidence.

```bash
# Create codex evidence after successful review
create_codex_evidence() {
  local session_id="$1"
  local verdict="$2"
  local review_number="$3"

  # Always create ran marker (proves review happened)
  touch "/tmp/claude-codex-ran-$session_id"

  # Create approval marker only on APPROVE
  if [[ "$verdict" == "APPROVE" ]]; then
    touch "/tmp/claude-codex-$session_id"
  fi

  # Update state file
  jq --arg v "$verdict" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg n "$review_number" \
    '.evidence.codex_review = {verdict: $v, timestamp: $t, iteration: ($n | tonumber)}
     | .codex_reviews = (.codex_reviews + 1)' \
    "$STATE_DIR/state.json" > "$STATE_DIR/state.json.tmp" \
    && mv "$STATE_DIR/state.json.tmp" "$STATE_DIR/state.json"
}

# Check if all evidence is present and non-stale
evidence_complete() {
  local session_id="$1"
  local last_edit
  last_edit=$(jq -r '.last_code_edit // "1970-01-01T00:00:00Z"' "$STATE_DIR/state.json")

  # Check each required marker exists
  local markers=(
    "/tmp/claude-code-critic-$session_id"
    "/tmp/claude-minimizer-$session_id"
    "/tmp/claude-codex-$session_id"
    "/tmp/claude-tests-passed-$session_id"
    "/tmp/claude-checks-passed-$session_id"
    "/tmp/claude-security-scanned-$session_id"
    "/tmp/claude-pr-verified-$session_id"
  )

  for marker in "${markers[@]}"; do
    if [[ ! -f "$marker" ]]; then
      return 1
    fi
    # Check staleness: marker must be newer than last code edit
    if [[ "$(stat -f %m "$marker" 2>/dev/null || stat -c %Y "$marker")" -lt \
          "$(date -d "$last_edit" +%s 2>/dev/null || date -j -f %Y-%m-%dT%H:%M:%SZ "$last_edit" +%s)" ]]; then
      return 1  # stale
    fi
  done

  return 0
}
```

**Deliverables:**
- [ ] `coordinator/evidence.sh` — evidence creation, staleness check
- [ ] Codex evidence markers created by coordinator (not hooks)
- [ ] Staleness detection based on `last_code_edit` timestamp
- [ ] State file updated with evidence metadata

### 1.5 Health Check (`health.sh`)

Detects crashed agents and handles recovery.

```bash
agent_health_check() {
  for pane in 0 1; do
    local pid
    pid=$(tmux display-message -t "$SESSION:work.$pane" -p '#{pane_pid}')

    if ! kill -0 "$pid" 2>/dev/null; then
      local agent_name
      [[ "$pane" == "0" ]] && agent_name="Claude" || agent_name="Codex"
      log "WARN" "$agent_name crashed in pane $pane. Respawning..."

      case "$pane" in
        0) tmux send-keys -t "$SESSION:work.0" \
             "claude --dangerously-skip-permissions" C-m ;;
        1) tmux send-keys -t "$SESSION:work.1" \
             "codex --full-auto --sandbox read-only" C-m ;;
      esac

      # Wait for agent to start
      sleep 5
    fi
  done
}
```

**Deliverables:**
- [ ] `coordinator/health.sh` — crash detection and respawn
- [ ] Periodic health check (every 30 seconds)
- [ ] Log crash/respawn events

---

## Phase 2: Codex Review Flow

### 2.1 Review Dispatch (`codex-review.sh`)

Replaces `call_codex.sh --review`. Instead of a blocking subprocess, the coordinator sends the review task to Codex's tmux pane and monitors the output.

**The flow:**

```
1. Claude reaches review step → signals coordinator (via request-codex.sh)
2. Coordinator verifies critic markers exist (replaces codex-gate.sh)
3. Coordinator generates diff: git diff $(git merge-base HEAD main)..HEAD
4. Coordinator sends diff + instructions to Codex pane
5. Codex reviews (Claude is NOT blocked — can continue other work)
6. Coordinator captures Codex output (file-based handoff)
7. Coordinator extracts verdict, creates evidence markers
8. Coordinator sends findings to Claude pane if REQUEST_CHANGES
9. Claude fixes, cycle repeats
```

**Review dispatch:**

```bash
dispatch_codex_review() {
  local session_id="$1"
  local iteration="$2"
  local base="${3:-main}"
  local title="${4:-}"

  # Gate check (replaces codex-gate.sh)
  if [[ ! -f "/tmp/claude-code-critic-$session_id" ]] || \
     [[ ! -f "/tmp/claude-minimizer-$session_id" ]]; then
    log "BLOCKED" "Codex review gate — critic markers missing"
    return 1
  fi

  # Generate diff
  local diff_file="$STATE_DIR/review-diff-$iteration.patch"
  local merge_base
  merge_base=$(git merge-base HEAD "$base")
  git diff "$merge_base"..HEAD > "$diff_file"

  # Build review prompt
  local output_file="$STATE_DIR/codex-review-$iteration.json"
  local prompt="Review this code change against the $base branch.

TITLE: ${title:-Code review}
ITERATION: $iteration
$(if [[ $iteration -gt 1 ]]; then
    echo "PREVIOUS FINDINGS: $(jq -r '.evidence.codex_review.findings // "none"' "$STATE_DIR/state.json")"
    echo "Focus on verifying previous issues were addressed and flag only new issues."
  fi)

DIFF:
$(cat "$diff_file")

Write your complete review to: $output_file
JSON format: {\"verdict\": \"APPROVE|REQUEST_CHANGES|NEEDS_DISCUSSION\", \"findings\": [...], \"summary\": \"...\"}

After writing the file, say: REVIEW_COMPLETE"

  # Send to Codex pane
  tmux send-keys -t "$SESSION:work.1" "$prompt" C-m

  # Wait for output file (non-blocking to Claude)
  local timeout=900
  local elapsed=0
  while [[ ! -f "$output_file" ]] && (( elapsed < timeout )); do
    sleep 5
    ((elapsed += 5))
  done

  if [[ -f "$output_file" ]]; then
    local verdict
    verdict=$(jq -r '.verdict' "$output_file")

    # Create evidence
    create_codex_evidence "$session_id" "$verdict" "$iteration"

    # If REQUEST_CHANGES, relay findings to Claude
    if [[ "$verdict" == "REQUEST_CHANGES" ]]; then
      local findings
      findings=$(jq -r '.summary' "$output_file")
      pane_send 0 "Codex review (iteration $iteration) returned REQUEST_CHANGES:

$findings

Fix blocking issues and signal when ready for re-review."
      transition_state "IMPLEMENT"
    else
      transition_state "VERIFY"
    fi
  else
    log "ERROR" "Codex review timed out after ${timeout}s"
    pane_send 0 "Codex review timed out. Check Codex pane for status."
  fi
}
```

**Key difference from current system:** Claude is NOT blocked. While Codex reviews, the coordinator can allow Claude to:
- Run tests in parallel
- Start preparing the next task
- Fix documentation
- Any non-code-edit work (code edits would invalidate markers)

**Deliverables:**
- [ ] `coordinator/codex-review.sh` — review dispatch and verdict capture
- [ ] Gate check (critic markers) built into coordinator
- [ ] File-based verdict capture (primary) with pane capture fallback
- [ ] Findings relay to Claude on REQUEST_CHANGES
- [ ] Iteration tracking in state file

### 2.2 Claude-Side Request Script (`request-codex.sh`)

Replaces `call_codex.sh` from Claude's perspective. Instead of invoking a subprocess, Claude runs this script which signals the coordinator to dispatch the review.

```bash
#!/usr/bin/env bash
# request-codex.sh — Signal coordinator to dispatch Codex review/task
# This is what Claude invokes instead of call_codex.sh
set -euo pipefail

MODE="${1:?Usage: request-codex.sh --review|--prompt <text>}"

STATE_DIR=$(find /tmp -maxdepth 1 -name 'party-*' -type d | head -1)
if [[ -z "$STATE_DIR" ]]; then
  echo "Error: No active party session found" >&2
  exit 1
fi

case "$MODE" in
  --review)
    BASE="${2:-main}"
    TITLE="${3:-}"
    # Write request to coordinator's inbox
    cat > "$STATE_DIR/codex-request.json" << EOF
{"type": "review", "base": "$BASE", "title": "$TITLE", "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF
    echo "CODEX_REVIEW_REQUESTED — coordinator will dispatch. Claude is free to continue non-edit work."
    echo "Monitor progress in the dashboard pane."
    ;;
  --prompt)
    PROMPT="${2:?Missing prompt text}"
    cat > "$STATE_DIR/codex-request.json" << EOF
{"type": "prompt", "prompt": "$PROMPT", "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF
    echo "CODEX_TASK_REQUESTED — coordinator will dispatch."
    ;;
esac
```

**Critical design decision:** This script returns immediately. Claude is unblocked. The coordinator handles the review asynchronously. Claude's hooks still work normally for everything else (sub-agents, marker invalidation, skill markers).

**Deliverables:**
- [ ] `claude/skills/codex-cli/scripts/request-codex.sh` — non-blocking coordinator signal
- [ ] Coordinator watches `$STATE_DIR/codex-request.json` for incoming requests
- [ ] Claude receives immediate acknowledgment (not blocked)

### 2.3 New Hooks (`coordinator-gate.sh`, `coordinator-trace.sh`)

These replace `codex-gate.sh` and `codex-trace.sh` but work with the coordinator instead of matching `call_codex.sh` regex.

**`coordinator-gate.sh`** — PreToolUse on Bash, blocks `request-codex.sh --review` unless critic markers exist:

```bash
#!/usr/bin/env bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

[[ -z "$SESSION_ID" || -z "$COMMAND" ]] && { echo '{}'; exit 0; }

# Only gate review requests (not --prompt for planning/debugging)
echo "$COMMAND" | grep -qE '(^|[;&|] *)([^ ]*/)request-codex\.sh +--review' || { echo '{}'; exit 0; }

# Check critic markers (same logic as original codex-gate.sh)
MISSING=""
[ ! -f "/tmp/claude-code-critic-$SESSION_ID" ] && MISSING="$MISSING code-critic"
[ ! -f "/tmp/claude-minimizer-$SESSION_ID" ] && MISSING="$MISSING minimizer"

if [ -n "$MISSING" ]; then
  cat << EOF
{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"BLOCKED: Codex review gate — critic APPROVE markers missing:$MISSING"}}
EOF
  exit 0
fi

echo '{}'
```

**`coordinator-trace.sh`** — PostToolUse on Bash, creates evidence when coordinator completes Codex review:

```bash
#!/usr/bin/env bash
hook_input=$(cat)
command=$(echo "$hook_input" | jq -r '.tool_input.command // ""' 2>/dev/null)
session_id=$(echo "$hook_input" | jq -r '.session_id // "unknown"' 2>/dev/null)

[[ -z "$session_id" || "$session_id" == "unknown" ]] && exit 0

# Detect request-codex.sh completion
echo "$command" | grep -qE '(^|[;&|] *)([^ ]*/)request-codex\.sh' || exit 0

response=$(echo "$hook_input" | jq -r '.tool_response // ""' 2>/dev/null)

# Coordinator handles evidence creation directly — this hook just logs
if echo "$response" | grep -qF "CODEX_REVIEW_REQUESTED"; then
  echo "Codex review dispatched to coordinator" >> "$HOME/.claude/logs/coordinator-trace.log"
fi

exit 0
```

**Note:** In the tmux model, evidence creation happens in the coordinator (`evidence.sh`), not in hooks. The `coordinator-trace.sh` hook is primarily for logging. The actual markers (`/tmp/claude-codex-*`) are created by `evidence.sh` when the coordinator captures Codex's verdict. This is architecturally different from the current system where hooks create markers — but the end result is the same: `pr-gate.sh` checks the same markers in the same locations.

**Deliverables:**
- [ ] `claude/hooks/coordinator-gate.sh` — gate for `request-codex.sh --review`
- [ ] `claude/hooks/coordinator-trace.sh` — logging trace for coordinator requests
- [ ] `pr-gate.sh` unchanged (checks same marker files)

---

## Phase 3: Planning Dialogue

### 3.1 Multi-Turn Codex Dialogue (`codex-dialogue.sh`)

This is the new capability the current system can't provide. Enables the bidirectional planning conversations between Claude and Codex that the user does daily.

**Current pain point:** Each Codex↔Claude exchange is a blocking subprocess with a fresh context. In a planning session with 5 back-and-forths, that's 5 cold starts on each side.

**Tmux solution:** The coordinator mediates a conversation between persistent sessions:

```bash
mediate_dialogue() {
  local source_pane="$1"  # Who initiated (0=Claude, 1=Codex)
  local target_pane="$2"  # Who to send to

  # Capture what the source said
  local message_file="$STATE_DIR/dialogue-$(date +%s%N).txt"
  pane_send_with_file_output "$source_pane" \
    "Write the question/message you want to send to $(pane_name $target_pane) to: $message_file"

  # Wait for message
  wait_for_file "$message_file" 120

  # Relay to target
  local response_file="$STATE_DIR/dialogue-response-$(date +%s%N).txt"
  local source_name=$(pane_name $source_pane)
  pane_send_with_file_output "$target_pane" \
    "Message from $source_name:
$(cat "$message_file")

Write your response to: $response_file"

  # Wait for response
  wait_for_file "$response_file" 300

  # Relay response back to source
  local target_name=$(pane_name $target_pane)
  pane_send "$source_pane" "Response from $target_name:
$(cat "$response_file")"

  # Log the exchange
  jq -n \
    --arg from "$(pane_name $source_pane)" \
    --arg to "$(pane_name $target_pane)" \
    --arg msg "$(cat "$message_file")" \
    --arg resp "$(cat "$response_file")" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{timestamp: $ts, from: $from, to: $to, message: $msg, response: $resp}' \
    >> "$STATE_DIR/dialogue.jsonl"
}
```

**Planning flow:**

```
User → Codex pane: "Design the authentication module for service X"
Codex works on plan...
Codex: "I need to know how the database connection pool works — asking Claude"
  → Coordinator detects request, enters CODEX_DIALOGUE state
  → Coordinator relays question to Claude pane
  → Claude investigates codebase, responds
  → Coordinator relays answer to Codex pane
Codex incorporates answer, continues planning...
Codex: "Plan complete. Writing to PLAN.md"
  → Coordinator detects completion, transitions to IDLE or IMPLEMENT
```

**Deliverables:**
- [ ] `coordinator/codex-dialogue.sh` — multi-turn dialogue mediation
- [ ] Dialogue logging to `$STATE_DIR/dialogue.jsonl`
- [ ] Request detection (Codex says "asking Claude" or writes to request file)
- [ ] Timeout handling for unresponsive agents

---

## Phase 4: Documentation Updates

### 4.1 Updated Workflow Skills

**`task-workflow/SKILL.md` — Step 7 changes:**

Current:
```
7. **codex** — Invoke `~/.claude/skills/codex-cli/scripts/call_codex.sh` for combined code + architecture review
```

New:
```
7. **codex** — Request codex review via the coordinator:
   ```bash
   ~/.claude/skills/codex-cli/scripts/request-codex.sh --review main "{PR title}"
   ```
   This dispatches the review to the coordinator. You are NOT blocked — continue with non-edit work while Codex reviews. The coordinator will relay findings when Codex completes.
   If REQUEST_CHANGES: the coordinator sends findings to your pane. Fix blocking issues and signal ready for re-review.
   If APPROVE: the coordinator creates evidence markers and advances to verification.
```

**`bugfix-workflow/SKILL.md` — Steps 3, 6, 7 change similarly.**

**`codex-cli/SKILL.md` — Full rewrite:**

Replace all `call_codex.sh` invocation patterns with `request-codex.sh` patterns. Update the explanation to describe coordinator-mediated flow instead of blocking subprocess.

### 4.2 Updated Rules

**`execution-core.md`:**
- Codex Review Gate section: describe coordinator gate instead of `codex-gate.sh` regex
- Enforcement chain: coordinator mediates instead of hooks
- Decision matrix: same logic, different mechanism description

**`autonomous-flow.md`:**
- Violation patterns: update `call_codex.sh` references to `request-codex.sh`
- Checkpoint markers: note that codex markers are created by coordinator, not hooks

**`CLAUDE.md`:**
- Sub-agents table: replace `call_codex.sh` with `request-codex.sh`
- Note that Codex review is non-blocking

### 4.3 Updated Settings

**`settings.json`:**

```diff
- "Bash(~/.claude/skills/codex-cli/scripts/call_codex.sh:*)",
- "Bash(~/.claude/skills/codex-cli/scripts/codex-verdict.sh:*)",
+ "Bash(~/.claude/skills/codex-cli/scripts/request-codex.sh:*)",
```

**Hook config:**

```diff
  "PreToolUse": [{
    "matcher": "Bash",
    "hooks": [
      { "type": "command", "command": "~/.claude/hooks/worktree-guard.sh", "timeout": 10 },
-     { "type": "command", "command": "~/.claude/hooks/codex-gate.sh", "timeout": 10 },
+     { "type": "command", "command": "~/.claude/hooks/coordinator-gate.sh", "timeout": 10 },
      { "type": "command", "command": "~/.claude/hooks/pr-gate.sh", "timeout": 30 }
    ]
  }],
  "PostToolUse": [
-   { "matcher": "Bash", "hooks": [{ "type": "command", "command": "~/.claude/hooks/codex-trace.sh", "timeout": 5 }] },
+   { "matcher": "Bash", "hooks": [{ "type": "command", "command": "~/.claude/hooks/coordinator-trace.sh", "timeout": 5 }] },
```

**Deliverables:**
- [ ] Updated `task-workflow/SKILL.md`
- [ ] Updated `bugfix-workflow/SKILL.md`
- [ ] Rewritten `codex-cli/SKILL.md`
- [ ] Updated `execution-core.md`
- [ ] Updated `autonomous-flow.md`
- [ ] Updated `CLAUDE.md`
- [ ] Updated `settings.json`

---

## Phase 5: Testing

### 5.1 Test Infrastructure

Shell-based test harness. Mock agents simulate Claude and Codex behavior.

**`mock-claude.sh`:**
```bash
# Simulates Claude Code responses
# Reads from stdin, pattern-matches, writes expected output
while IFS= read -r line; do
  case "$line" in
    *"self-review"*)
      echo "PASS — proceeding to critics"
      ;;
    *"REQUEST_CHANGES"*)
      echo "Fixing issues..."
      sleep 2
      echo "Fixed. Ready for re-review."
      ;;
    *)
      echo "Acknowledged: $line"
      ;;
  esac
done
```

**`mock-codex.sh`:**
```bash
# Simulates Codex responses
# Supports configurable review count before approval
REVIEWS_BEFORE_APPROVE="${MOCK_REVIEWS:-3}"
review_count=0

while IFS= read -r line; do
  case "$line" in
    *"Review this"*)
      ((review_count++))
      local output_file=$(echo "$line" | grep -oP '(?<=Write your complete review to: )\S+')
      if (( review_count >= REVIEWS_BEFORE_APPROVE )); then
        echo '{"verdict":"APPROVE","findings":[],"summary":"All issues addressed."}' > "$output_file"
      else
        echo '{"verdict":"REQUEST_CHANGES","findings":["Issue found"],"summary":"Fix X in file.ts:42"}' > "$output_file"
      fi
      echo "REVIEW_COMPLETE"
      ;;
  esac
done
```

### 5.2 Test Cases

**State machine tests (`test-state-machine.sh`):**
- [ ] IDLE → IMPLEMENT on task detection
- [ ] IMPLEMENT → SELF_REVIEW on self-review signal
- [ ] SELF_REVIEW → CRITICS on PASS signal
- [ ] CRITICS → CODEX_REVIEW when both critic markers exist
- [ ] CODEX_REVIEW → IMPLEMENT on REQUEST_CHANGES
- [ ] CODEX_REVIEW → VERIFY on APPROVE
- [ ] VERIFY → PR_READY when all markers present
- [ ] Code edit during any state → marker invalidation → IMPLEMENT
- [ ] Codex review blocked when critic markers missing

**Evidence tests (`test-evidence.sh`):**
- [ ] Codex evidence created on APPROVE
- [ ] Codex evidence NOT created on REQUEST_CHANGES
- [ ] Staleness detection: evidence older than last edit = stale
- [ ] All 7 markers required for `evidence_complete` to return true
- [ ] Missing any single marker = incomplete

**Pane I/O tests (`test-pane-io.sh`):**
- [ ] File-based handoff: agent writes JSON to specified path
- [ ] Sentinel detection in pane capture
- [ ] ANSI stripping in pane capture
- [ ] Timeout handling: no output within timeout → error
- [ ] Idle detection: stable pane hash = idle

**Integration test (`test-integration.sh`):**
- [ ] Full review cycle with mock agents: IMPLEMENT → critics → codex review → APPROVE → PR_READY
- [ ] Multi-review cycle: 3 REQUEST_CHANGES → APPROVE (simulates real usage)
- [ ] Planning dialogue: Codex asks Claude → Claude responds → Codex continues
- [ ] Crash recovery: kill agent pane, verify respawn

**Deliverables:**
- [ ] `tests/mock-claude.sh`, `tests/mock-codex.sh`
- [ ] `tests/test-state-machine.sh`
- [ ] `tests/test-evidence.sh`
- [ ] `tests/test-pane-io.sh`
- [ ] `tests/test-integration.sh`
- [ ] `tests/run-tests.sh`

---

## Phase 6: Installation & Migration

### 6.1 Installer

Adapted from `ai-config/install.sh`. Symlinks the new `claude/` and `codex/` directories:

```bash
# Option A: replace ai-config entirely
./install.sh                    # Creates ~/.claude → ai-config-tmux/claude, ~/.codex → ai-config-tmux/codex

# Option B: install alongside (both systems available)
./install.sh --alongside        # Creates ~/.claude-tmux → ai-config-tmux/claude
                                # User switches by re-symlinking ~/.claude
```

### 6.2 Migration path

```
Week 1-2: Build coordinator core (Phase 1) + tests
Week 2-3: Build review flow (Phase 2) + planning dialogue (Phase 3) + tests
Week 3-4: Update documentation (Phase 4)
Week 4:   Integration testing with real agents
Week 5:   Side-by-side evaluation vs current system
          → Decision: adopt tmux, stay with CLI, or hybrid
```

**Rollback:** `ln -sf ~/ai-config/claude ~/.claude` — instant revert to subprocess model.

---

## Risk Register

| Risk | Severity | Mitigation |
|------|----------|------------|
| File-based handoff fails (agent doesn't write file) | High | Fallback to pane capture with sentinel |
| Codex ignores file-write instruction | Medium | Retry with explicit instruction; fall back to pane capture |
| ANSI artifacts corrupt pane capture | Medium | Primary strategy is file-based (avoids pane capture for data) |
| Agent crashes during review | Medium | Health check respawns; state file preserves progress |
| Race condition: code edit during Codex review | Medium | `marker-invalidate.sh` still fires on Claude's Edit/Write; coordinator detects stale evidence |
| iTerm2 `tmux -CC` behavior differences | Low | Test both `tmux -CC` and raw tmux; `--raw` flag as fallback |
| Coordinator daemon crashes | Medium | PID file + wrapper script that restarts; state file survives |
| Large diff exceeds tmux send-keys limit | Medium | Write diff to file, tell Codex to read the file instead |
| Codex `--sandbox read-only` incompatible with file-write handoff | High | Test that `--sandbox read-only` allows writing to `/tmp/`; if not, use `workspace-write` with AGENTS.md constraints or write output via stdout capture |

---

## Success Criteria

1. **Full review cycle works:** Claude implements → critics → codex review → APPROVE → PR created
2. **Multi-review cycle works:** 3+ REQUEST_CHANGES → eventual APPROVE with persistent context
3. **Claude is not blocked:** During Codex review, Claude can receive and process coordinator messages
4. **Planning dialogue works:** Codex asks Claude a question, coordinator mediates, Codex continues
5. **All existing hooks still work:** agent-trace, marker-invalidate, skill-marker, pr-gate, worktree-guard, session-cleanup, skill-eval
6. **Markers are compatible:** Same `/tmp/claude-*` paths, same semantics, pr-gate.sh works unchanged
7. **iTerm2 UX:** `tmux -CC` gives native panes with scrollback and search
8. **Tests pass:** All test suites green
9. **Rollback works:** Single symlink change reverts to subprocess model
