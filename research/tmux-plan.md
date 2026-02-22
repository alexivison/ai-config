# Tmux Integration — Implementation Plan

Implementation plan for replacing the subprocess-based Claude/Codex orchestration with tmux-based persistent sessions. Built for iTerm2 on macOS.

This plan is the **direct tmux transport** track (no coordinator). It intentionally differs from `research/tmux-integration.md`, which evaluates a **full coordinator** architecture. Choose one track; do not mix steps from both.

---

## Context

### Why tmux

The current system invokes Codex as a blocking subprocess (`codex exec`). Each invocation is a cold start — fresh context, one-shot output, 15-minute block on Claude. The user's workflow involves 3-7 Codex reviews per task and bidirectional Claude↔Codex planning dialogues. At 7 reviews per task, that's ~105 minutes of dead blocking time. Tmux replaces this with persistent interactive sessions where both agents retain context across reviews and Claude isn't blocked during Codex work.

### Architecture: Direct tmux, no coordinator

Claude and Codex each use `tmux send-keys` and `tmux capture-pane` directly via their Bash tools. No middleman. Each agent retains full context of what it's doing and why. The only shared infrastructure is:

1. **`party.sh`** — launches the tmux session with panes for both agents
2. **A shared state directory** (`/tmp/party-*`) — for file-based message handoff between agents
3. **Existing hooks** — markers, gates, and traces work as today with minor regex updates

This is simpler, preserves context on both sides, and leverages what both agents already have: bash access.

### What stays the same

- Sub-agents (code-critic, minimizer, test-runner, check-runner, security-scanner) remain in-process via Claude's Task tool
- The marker system's names, semantics, and invalidation logic survive intact
- All workflow skills (task-workflow, bugfix-workflow, pre-pr-verification) keep their structure — only the Codex invocation step changes
- Agent personas (Paladin/Wizard), rules, decision matrices are reused
- The review governance model (severity triage, iteration caps, tiered re-review) is unchanged

### What changes

- `call_codex.sh` / `codex-verdict.sh` → replaced by direct tmux communication (Claude sends to Codex pane)
- `call_claude.sh` → replaced by direct tmux communication (Codex sends to Claude pane)
- `codex-gate.sh` / `codex-trace.sh` → updated to match new script names (`tmux-codex.sh`)
- `settings.json` → updated permissions, hook config
- Workflow skill docs → updated Codex invocation instructions
- `CLAUDE.md`, `execution-core.md`, `autonomous-flow.md` → updated references

### iTerm2 integration

iTerm2 supports `tmux -CC` (control mode), which maps tmux panes to native iTerm2 splits/tabs. The user gets native scrollback, selection, and search in each pane. Both agents use `tmux capture-pane` and `tmux send-keys` programmatically, but the user sees native iTerm2 windows.

### `tmux send-keys` for inter-agent notification

**Decision: `send-keys`** for all inter-agent notifications. Structured data (findings, responses) is exchanged via files in `$STATE_DIR/`. Notifications ("go read the file") are delivered via `tmux send-keys`.

**Why `send-keys` works here:** Both agents launch in non-interactive modes — Claude with `--dangerously-skip-permissions`, Codex with `--full-auto`. There are no tool approval prompts to accidentally confirm, which eliminates the worst-case TUI interaction scenario.

**What happens if a notification arrives mid-execution:** The text lands in the terminal's input buffer. When the agent finishes its current turn and returns to the input prompt, the buffered text gets submitted as the next user message. This is the desired behavior — the agent processes the notification when it's ready.

**Phase 0 validates this.** If `send-keys` doesn't work at all (e.g., the TUI swallows buffered input entirely), the architecture needs redesign before building.

---

## Branching Strategy

All work happens on a dedicated `tmux` worktree created from `main`. Daily use stays in the existing `main` worktree. This follows repo policy (`worktree-guard.sh`) and avoids `git checkout` / `git switch` in the shared worktree.

```bash
cd ~/ai-config
git fetch origin
git worktree add ../ai-config-tmux -b tmux main
```

### What changes on the `tmux` branch

**New files added:**

```
session/
├── party.sh                                     # Session launcher + teardown
└── party-lib.sh                                 # Shared helpers (discover_session)

claude/skills/codex-cli/scripts/tmux-codex.sh    # Claude→Codex transport (replaces call_codex.sh + codex-verdict.sh)
claude/skills/tmux-handler/SKILL.md              # How Claude handles incoming [CODEX] messages

codex/skills/claude-cli/scripts/tmux-claude.sh   # Codex→Claude transport (replaces call_claude.sh)
codex/skills/tmux-handler/SKILL.md               # How Codex handles incoming messages from Claude

tests/
├── test-party.sh                                # Session launch/teardown tests
├── test-tmux-codex.sh                           # Claude→Codex communication tests
├── test-tmux-claude.sh                          # Codex→Claude communication tests
├── test-hooks.sh                                # Hook integration tests
├── test-integration.sh                          # Full review cycle with mock agents
├── mock-claude.sh                               # Mock Claude agent for testing
├── mock-codex.sh                                # Mock Codex agent for testing
└── run-tests.sh                                 # Test runner
```

**Existing files edited:**

```
claude/CLAUDE.md                                 # Add tmux context, [CODEX] message convention, verdict authority
claude/settings.json                             # Swap permission lines: call_codex.sh/codex-verdict.sh → tmux-codex.sh
claude/hooks/codex-gate.sh                       # Regex: call_codex.sh → tmux-codex.sh
claude/hooks/codex-trace.sh                      # Regex: call_codex.sh → tmux-codex.sh
claude/rules/execution-core.md                   # call_codex.sh → tmux-codex.sh
claude/rules/autonomous-flow.md                  # call_codex.sh → tmux-codex.sh
claude/skills/codex-cli/SKILL.md                 # Rewritten: tmux-codex.sh modes + verdict semantics
claude/skills/task-workflow/SKILL.md             # Steps 7+8 rewritten for tmux
claude/skills/bugfix-workflow/SKILL.md           # Codex steps rewritten for tmux
codex/AGENTS.md                                  # Add tmux context section
codex/skills/claude-cli/SKILL.md                 # Rewritten: tmux-claude.sh + STATE_DIR discovery
```

**Existing files deleted (replaced by new scripts above):**

```
claude/skills/codex-cli/scripts/call_codex.sh    # Replaced by tmux-codex.sh
claude/skills/codex-cli/scripts/codex-verdict.sh # Merged into tmux-codex.sh --approve/--re-review/--needs-discussion
codex/skills/claude-cli/scripts/call_claude.sh   # Replaced by tmux-claude.sh
```

**Everything else is unchanged** — hooks (7 of 9), agents, scripts, technology rules, shared skills, codex rules, codex planning skill, config.toml all remain as-is on the branch.

---

## Phase 0: Prerequisites — Validate Before Building

These must be confirmed before any implementation begins. If either fails, the architecture needs redesign.

### 0.1 Codex sandbox write access to `/tmp/`

The entire file-based handoff depends on Codex writing findings to `/tmp/party-*/`. Codex is launched with `--sandbox read-only`, which may block writes outside the workspace.

**Test:**
```bash
# In a codex --full-auto --sandbox read-only session:
echo '{"test": true}' > /tmp/party-test/codex-findings-test.json
```

**If it works:** Proceed with the plan as designed.

**If it fails — fallback options (in order of preference):**
1. **`--sandbox write-only-outside-workspace`** — Codex can write to `/tmp/` but not to the repo. Check if this flag exists.
2. **Write to workspace instead** — Use `$REPO/.party/findings-$TIMESTAMP.json` instead of `/tmp/`. Gitignore `.party/`. Downside: clutters workspace.
3. **Capture pane output** — Codex writes findings as structured output to stdout. Claude uses `tmux capture-pane` to extract it. Fragile — parsing terminal output. Last resort.

### 0.2 `tmux send-keys` into idle CLI agent

Verify that `tmux send-keys` to a Claude Code / Codex pane works when the agent is waiting for input.

**Test:**
```bash
# Start Claude Code in a tmux pane, let it settle to input prompt
tmux send-keys -t test:0 "What is 2+2?" C-m
# Verify Claude processes it as a user message
```

**If it works:** Proceed — `send-keys` is the notification mechanism.

**If it fails:** The TUI doesn't accept raw `send-keys` at all, and we need a different input mechanism (e.g., `--pipe` mode, stdin redirection, or Claude Code's `--input-file` flag if it exists). This would require an architecture redesign.

**Deliverables:**
- [ ] Sandbox write test: confirm Codex can write to `/tmp/party-*/` (or identify fallback)
- [ ] `send-keys` input test: confirm agents accept `tmux send-keys` as user messages when idle
- [ ] Document results — if fallbacks needed, update Phase 2/3 scripts accordingly

---

## Phase 1: Session Launcher

### 1.1 Session Launcher (`party.sh`)

The main entry point. Starts a tmux session with panes for Claude and Codex. No daemon — just setup and attach.

**iTerm2 integration:** Launch with `tmux -CC` to get native iTerm2 panes:

```bash
# Launch in iTerm2 control mode
party.sh                # Default: uses tmux -CC if TERM_PROGRAM=iTerm.app
party.sh --raw          # Force raw tmux (for SSH, non-iTerm terminals)
```

**Pane layout:**

```
┌─────────────────────────────┬──────────────────────────────┐
│ Pane 0: The Paladin (Claude)│ Pane 1: The Wizard (Codex)   │
│ claude --dangerously-skip-  │ codex --full-auto             │
│ permissions                 │ --sandbox read-only           │
│                             │                               │
│                             │                               │
└─────────────────────────────┴──────────────────────────────┘
```

No coordinator pane. No dashboard pane. Just two agents, side by side. The user watches both panes directly in iTerm2 (native scrollback, search, selection).

### 1.2 tmux Keybindings

The default tmux keybindings (`Ctrl-b` prefix) are unfamiliar to iTerm2 users. `party.sh` applies iTerm2-like keybindings at session creation time so pane/window navigation feels natural.

These are set via `tmux set-option` and `tmux bind-key` at startup — no persistent `.tmux.conf` required. The bindings only exist while the party session is alive.

**Note on `tmux -CC` (iTerm2 control mode):** When running in control mode, iTerm2 maps tmux panes/windows to native iTerm2 tabs and splits. In that mode, your normal `Cmd-T`, `Cmd-W`, `Cmd-[`/`Cmd-]` already work because iTerm2 is managing the chrome. The keybindings below are for **raw tmux mode** (`--raw` flag, SSH, non-iTerm terminals) where you're in tmux's own UI.

```bash
configure_keybindings() {
  local session="${1:?Usage: configure_keybindings SESSION_NAME}"

  # ── Pane navigation (the most common action) ──────────────────────
  # Note: bind-key is always global (tmux doesn't support session-scoped bindings).
  # These are harmless in -CC mode (iTerm2 handles its own keybindings).
  tmux bind-key -n M-Left  select-pane -L    # Option-Left  → left pane (Paladin/Claude)
  tmux bind-key -n M-Right select-pane -R    # Option-Right → right pane (Wizard/Codex)
  tmux bind-key Left  select-pane -L
  tmux bind-key Right select-pane -R

  # ── Window/tab management ─────────────────────────────────────────
  tmux bind-key t new-window               # Prefix + t → new window
  tmux bind-key w kill-pane                # Prefix + w → close pane
  tmux bind-key -n M-1 select-window -t 0  # Option-1 → window 1
  tmux bind-key -n M-2 select-window -t 1  # Option-2 → window 2
  tmux bind-key f resize-pane -Z           # Prefix + f → zoom toggle

  # ── Pane theming (raw tmux mode only) ──────────────────────────────
  # In tmux -CC (iTerm2 control mode), iTerm2 renders its own chrome.
  # Pane borders, status bar, and border colors are NOT visible — iTerm2
  # uses native tabs/splits instead. The theming below only applies in
  # raw tmux mode (--raw flag, SSH, non-iTerm terminals).
  #
  # Color scheme:
  #   The Wizard (Codex)  → purple/violet colour141 (arcane magic)
  #   The Paladin (Claude) → gold/yellow colour220 (holy light)
  tmux set-option -t "$session" pane-border-status top
  tmux set-option -t "$session" pane-border-format \
    ' #{?#{==:#{pane_title},The Wizard},#[fg=colour141 bold],#[fg=colour220 bold]}#{pane_title}#[default] '
  tmux set-option -t "$session" pane-border-style "fg=colour240"
  tmux set-option -t "$session" pane-active-border-style "fg=colour220"

  # Swap active border color on pane focus
  tmux set-hook -t "$session" pane-focus-in "if-shell \
    'test \"#{pane_title}\" = \"The Paladin\"' \
    'set pane-active-border-style fg=colour220' \
    'set pane-active-border-style fg=colour141'"

  # Status bar
  tmux set-option -t "$session" status-style "bg=colour235,fg=colour248"
  tmux set-option -t "$session" status-left "#[fg=colour141,bold] party #[default] "
  tmux set-option -t "$session" status-right ""
}
```

**Keybinding summary (raw tmux mode):**

| Action | Keybinding | iTerm2 equivalent |
|--------|-----------|-------------------|
| Switch to left pane (Claude) | `Option-Left` | `Cmd-[` or `Cmd-Left` |
| Switch to right pane (Codex) | `Option-Right` | `Cmd-]` or `Cmd-Right` |
| New window | `Ctrl-b t` | `Cmd-T` |
| Close pane | `Ctrl-b w` | `Cmd-W` |
| Jump to window 1 | `Option-1` | `Cmd-1` |
| Jump to window 2 | `Option-2` | `Cmd-2` |
| Zoom/fullscreen pane | `Ctrl-b f` | `Cmd-Shift-Enter` |
| Detach (session keeps running) | `Ctrl-b d` | *(no equivalent)* |

### 1.3 Implementation

```bash
party_start() {
  SESSION="party-$(date +%s)"
  STATE_DIR="/tmp/$SESSION"
  ACTIVE_SESSION_FILE="/tmp/party-active-session"

  if [[ -f "$ACTIVE_SESSION_FILE" ]]; then
    echo "Error: active party session already registered at $(cat "$ACTIVE_SESSION_FILE")" >&2
    return 1
  fi

  mkdir -p "$STATE_DIR"

  # Write session metadata so scripts can discover the active session
  echo "$SESSION" > "$STATE_DIR/session-name"
  echo "$STATE_DIR" > "$ACTIVE_SESSION_FILE"

  # Detect iTerm2 and use control mode
  local use_cc=false
  if [[ "${TERM_PROGRAM:-}" == "iTerm.app" && "${PARTY_RAW:-}" != "1" ]]; then
    use_cc=true
  fi

  # Create session (always detached first — we attach explicitly below)
  tmux new-session -d -s "$SESSION" -n work -x 200 -y 50

  # Split into panes
  tmux split-window -h -t "$SESSION:work"  # Pane 1: Codex (right)

  # Label panes by their fantasy lore roles (Claude = Paladin, Codex = Wizard)
  tmux select-pane -t "$SESSION:work.0" -T "The Paladin"
  tmux select-pane -t "$SESSION:work.1" -T "The Wizard"

  # Apply keybindings and theming AFTER session exists, scoped to this session
  configure_keybindings "$SESSION"

  # Launch agents
  tmux send-keys -t "$SESSION:work.0" \
    "claude --dangerously-skip-permissions" C-m
  tmux send-keys -t "$SESSION:work.1" \
    "codex --full-auto --sandbox read-only" C-m

  # Attach
  if [[ "$use_cc" == true ]]; then
    tmux -CC attach -t "$SESSION"
  else
    tmux attach -t "$SESSION"
  fi
}
```

**Teardown:**

```bash
party_stop() {
  # Discover the running session (party_stop is called from a separate shell invocation)
  discover_session || { echo "No active party session to stop."; return 0; }
  tmux kill-session -t "$SESSION_NAME" 2>/dev/null
  rm -rf "$STATE_DIR"
  rm -f "/tmp/party-active-session"
  echo "Party session stopped."
}
```

**Argument dispatch:**

```bash
case "${1:-}" in
  --stop)  party_stop ;;
  --raw)   PARTY_RAW=1 party_start ;;
  "")      party_start ;;
  *)       echo "Usage: party.sh [--raw|--stop]" >&2; exit 1 ;;
esac
```

**How agents discover the session:** Both `tmux-codex.sh` and `tmux-claude.sh` read `/tmp/party-active-session` to get the active state directory, then load `session-name` from there.

**Constraint: one session at a time.** `party.sh` writes a single active-session pointer file (`/tmp/party-active-session`). Discovery is deterministic (no glob-scanning), and `discover_session()` validates both state files and tmux session liveness before returning.

```bash
# Shared helper — lives in session/party-lib.sh
# Sourced by party.sh, tmux-codex.sh, and tmux-claude.sh:
#   source "$(dirname "$0")/../../session/party-lib.sh"  (adjust relative path per script location)
discover_session() {
  local active_file="/tmp/party-active-session"
  local state_dir

  if [[ ! -f "$active_file" ]]; then
    echo "Error: No active party session found" >&2
    return 1
  fi

  state_dir=$(cat "$active_file")
  if [[ ! -d "$state_dir" || ! -f "$state_dir/session-name" ]]; then
    echo "Error: Stale party session pointer: $state_dir" >&2
    return 1
  fi

  SESSION_NAME=$(cat "$state_dir/session-name")
  if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "Error: tmux session '$SESSION_NAME' is not running" >&2
    return 1
  fi

  STATE_DIR="$state_dir"
}
```

**Deliverables:**
- [ ] `session/party.sh` — session launcher with iTerm2 detection
- [ ] iTerm2-like keybindings applied at session startup (Option-Left/Right, Prefix+t/w, Option-1/2, Prefix+f)
- [ ] Pane labels ("The Wizard" / "The Paladin") shown in border
- [ ] iTerm2 control mode (`tmux -CC`) integration tested (native keybindings pass through)
- [ ] `--raw` fallback for non-iTerm terminals
- [ ] Clean teardown on SIGTERM/SIGINT
- [ ] `$STATE_DIR/` created on startup (flat structure — timestamped filenames prevent collisions)

---

## Phase 2: Claude → Codex Communication

### 2.1 `tmux-codex.sh` — Claude's interface to Codex

This single script replaces both `call_codex.sh` and `codex-verdict.sh`. Claude calls it via its Bash tool. The script uses `tmux send-keys` to communicate with Codex's pane and file-based handoff for structured data.

**Key principle: Claude keeps full context.** Claude knows why it's requesting a review, what the previous findings were, and what it expects. It sends the request directly and reads the response directly. No middleman losing context.

**Modes:**

| Mode | Replaces | What it does |
|------|----------|-------------|
| `--review` | `call_codex.sh --review` | Sends a short message to Codex pane via `tmux send-keys` with base branch, title, and findings file path. Codex's `tmux-handler` skill defines the review protocol. Returns immediately (non-blocking) |
| `--prompt` | `call_codex.sh --prompt` | Sends prompt text and response file path to Codex pane via `tmux send-keys`. Returns immediately (non-blocking) |
| `--review-complete` | `call_codex.sh --review` completion sentinel | Emits `CODEX_REVIEW_RAN` **only after** Claude receives Codex's completion notification and confirms the findings file exists |
| `--approve` | `codex-verdict.sh approve` | Outputs `CODEX APPROVED` sentinel. `codex-trace.sh` hook detects this and creates evidence markers (codex-ran + codex-approved) |
| `--re-review` | `codex-verdict.sh request_changes` | Outputs `CODEX REQUEST_CHANGES` sentinel. Hook creates codex-ran marker only |
| `--needs-discussion` | `codex-verdict.sh needs_discussion` | Outputs `CODEX NEEDS_DISCUSSION` sentinel. Hook logs to trace |

**Implementation:**

```bash
#!/usr/bin/env bash
# tmux-codex.sh — Claude's direct interface to Codex via tmux
# Replaces call_codex.sh + codex-verdict.sh
set -euo pipefail

MODE="${1:?Usage: tmux-codex.sh --review|--prompt|--review-complete|--approve|--re-review|--needs-discussion}"

# Discover active party session
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../session/party-lib.sh"
discover_session

CODEX_PANE="$SESSION_NAME:work.1"
TIMESTAMP="$(date +%s%N)"

case "$MODE" in

  --review)
    BASE="${2:-main}"
    TITLE="${3:-Code review}"
    FINDINGS_FILE="$STATE_DIR/codex-findings-$TIMESTAMP.json"

    # Just tell Codex what to review. Codex's tmux-handler skill defines
    # the review protocol: severity classification, output format, notification.
    tmux send-keys -t "$CODEX_PANE" \
      "Review the changes on this branch against $BASE. Title: $TITLE. Write findings to: $FINDINGS_FILE" C-m

    echo "CODEX_REVIEW_REQUESTED"
    echo "Findings will be written to: $FINDINGS_FILE"
    echo "Claude is NOT blocked. Codex will notify Claude via tmux when review is complete."
    ;;

  --prompt)
    PROMPT_TEXT="${2:?Missing prompt text}"
    RESPONSE_FILE="$STATE_DIR/codex-response-$TIMESTAMP.md"

    # Just send the prompt. Codex's skills define how to handle it.
    tmux send-keys -t "$CODEX_PANE" \
      "$PROMPT_TEXT — Write response to: $RESPONSE_FILE" C-m

    echo "CODEX_TASK_REQUESTED"
    echo "Response will be written to: $RESPONSE_FILE"
    echo "Codex will notify Claude via tmux when task is complete."
    ;;

  --review-complete)
    FINDINGS_FILE="${2:?Missing findings file path}"
    if [[ ! -f "$FINDINGS_FILE" ]]; then
      echo "Error: Findings file not found: $FINDINGS_FILE" >&2
      exit 1
    fi
    echo "CODEX_REVIEW_RAN"
    ;;

  --approve)
    echo "CODEX APPROVED"
    ;;

  --re-review)
    REASON="${2:-Blocking findings fixed}"
    echo "CODEX REQUEST_CHANGES — $REASON"
    ;;

  --needs-discussion)
    REASON="${2:-Multiple valid approaches or unresolvable findings}"
    echo "CODEX NEEDS_DISCUSSION — $REASON"
    ;;

  *)
    echo "Error: Unknown mode '$MODE'" >&2
    echo "Usage: tmux-codex.sh --review|--prompt|--review-complete|--approve|--re-review|--needs-discussion" >&2
    exit 1
    ;;
esac
```

**How Claude uses this — the review flow:**

```
1. Claude implements code (same as today)
2. Claude runs sub-agent critics via Task tool (same as today)
3. Claude calls: tmux-codex.sh --review main "Add user auth"
   → Script sends short message to Codex pane via tmux send-keys
   → Script returns IMMEDIATELY — Claude is NOT blocked
4. Claude continues non-edit work (documentation, test planning, etc.)
5. Codex completes the review, writes findings to file, then notifies Claude
   via tmux-claude.sh → Claude sees "[CODEX] Review complete. Findings at: ..."
6. Claude reads the findings file with its Read tool
7. Claude records review evidence:
   `tmux-codex.sh --review-complete <findings_file>`
8. Claude triages each finding (blocking / non-blocking / out-of-scope)
9. Claude maintains issue ledger (same as current system — in Claude's context)
10. Claude decides:
   a. All non-blocking → calls tmux-codex.sh --approve
   b. Blocking issues → fixes them, re-runs critics, calls tmux-codex.sh --re-review
   c. Unresolvable → calls tmux-codex.sh --needs-discussion
```

**No polling needed.** Codex pushes a notification to Claude's pane when done. Claude reacts to incoming messages — same pattern in both directions.

**What Claude retains that a coordinator would lose:**
- Why it made the changes (full implementation context)
- Previous Codex findings and how it triaged them (issue ledger)
- Which findings it already fixed vs. rejected
- The re-review tier decision (targeted swap vs. logic change vs. full cascade)

**Mapping to current system:**

| Current | Tmux equivalent |
|---------|----------------|
| `call_codex.sh --review --base main --title "..."` | `tmux-codex.sh --review main "..."` |
| `call_codex.sh --prompt "..."` | `tmux-codex.sh --prompt "..."` |
| `codex-verdict.sh approve` | `tmux-codex.sh --approve` |
| `codex-verdict.sh request_changes` | `tmux-codex.sh --re-review "reason"` |
| `codex-verdict.sh needs_discussion` | `tmux-codex.sh --needs-discussion "reason"` |

**Deliverables:**
- [ ] `claude/skills/codex-cli/scripts/tmux-codex.sh` — all modes (thin transport, no protocol knowledge)
- [ ] `--review` and `--prompt` send messages via `tmux send-keys` and return immediately (non-blocking)
- [ ] `--review-complete` emits `CODEX_REVIEW_RAN` only after findings file existence is verified
- [ ] `--approve`, `--re-review`, `--needs-discussion` output sentinel strings for hook detection (same sentinels as current system)
- [ ] No `wait_for_idle()` needed — both agents run non-interactive (`--dangerously-skip-permissions` / `--full-auto`), and buffered input is processed when the agent returns to the prompt

---

## Phase 3: Codex → Claude Communication

### 3.1 `tmux-claude.sh` — Codex's interface to Claude

The mirror image of `tmux-codex.sh`. Codex calls this to ask Claude questions during planning or to request Claude's help investigating the codebase.

**Key principle: Codex keeps full context too.** When Codex is mid-plan and needs info from Claude, it sends the question directly, gets the answer back, and continues with full awareness of its planning context.

**Implementation:**

```bash
#!/usr/bin/env bash
# tmux-claude.sh — Codex's direct interface to Claude via tmux
# Replaces call_claude.sh
set -euo pipefail

MESSAGE="${1:?Usage: tmux-claude.sh \"message for Claude\"}"

# Discover active party session
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../session/party-lib.sh"
discover_session

CLAUDE_PANE="$SESSION_NAME:work.0"

# Just send the [CODEX] prefixed message to Claude's pane.
# Codex's claude-cli skill defines what messages to send and when.
# Claude's tmux-handler skill defines how to respond.
tmux send-keys -t "$CLAUDE_PANE" "[CODEX] $MESSAGE" C-m

echo "CLAUDE_MESSAGE_SENT"
```

**How Codex uses this — the planning dialogue flow:**

```
1. User sends planning task to Codex pane directly
2. Codex works on the plan...
3. Codex needs to know how the database connection pool works
4. Codex follows its claude-cli skill: creates a response file path, calls:
   tmux-claude.sh "Question: How does the DB connection pool work in src/db/? Write response to: <response_file>"
   → Script sends [CODEX] prefixed message to Claude's pane, returns immediately
5. Claude's tmux-handler skill fires: sees "[CODEX] Question..."
6. Claude investigates the codebase, writes answer to the response file
7. Claude notifies Codex via tmux-codex.sh --prompt "Response ready at: <response_file>"
8. Codex reads the response file, incorporates the answer, continues planning
```

**Multi-turn dialogue:** Multiple exchanges work naturally. Each call creates unique timestamped files. Both agents retain their full context across exchanges because they're persistent tmux sessions.

**Key design: skills define protocol, scripts are just transport.**

- Codex's `claude-cli` skill tells Codex *when* and *how* to contact Claude (message formats, file conventions)
- Claude's `tmux-handler` skill tells Claude *how* to handle incoming `[CODEX]` messages (triage, investigate, respond)
- `tmux-claude.sh` just sends `[CODEX] $MESSAGE` to Claude's pane — no protocol knowledge in the script

**Deliverables:**
- [ ] `codex/skills/claude-cli/scripts/tmux-claude.sh` — thin transport: sends `[CODEX]` prefixed message to Claude's pane
- [ ] Non-blocking (returns immediately, other agent notifies via tmux when done)

---

## Phase 4: Agent Skills for tmux

The scripts (`tmux-codex.sh`, `tmux-claude.sh`) are just thin transport — they send a short message via tmux. The actual behavior (how to review, what format to use, how to notify) lives in skills on each agent's side. This mirrors the current system where `codex exec review` works because Codex has built-in review logic, not because the calling script tells it every detail.

### 4.1 Codex: `tmux-handler` Skill

Defines how Codex handles incoming messages from Claude via tmux. Claude may send review requests, tasks, plan review requests, or other work. This is the Codex-side counterpart of Claude's `tmux-handler` skill.

**`codex/skills/tmux-handler/SKILL.md`:**

```markdown
# tmux-handler — Handle incoming messages from Claude via tmux

## Trigger

You see a message in your tmux pane from Claude (prefixed with `[CLAUDE]` or sent via `tmux-codex.sh`).

## Message types

### Review request
Message asks you to review changes against a base branch.

1. **Get the diff**: Run `git diff $(git merge-base HEAD <base>)..HEAD` to see the changes
2. **Review scope**: Review changed files AND adjacent files (callers, callees, types, tests)
   for: correctness bugs, crash paths, security issues, wrong output, architectural concerns
3. **Classify each finding**:
   - **blocking**: correctness bug, crash path, wrong output, security HIGH/CRITICAL
   - **non-blocking**: style nit, "could be simpler", defensive edge case, consistency preference
4. **Write findings** to the file path specified in the message, using this JSON format:
   ```json
   {
     "findings": [
       {
         "id": "F1",
         "file": "path/to/file.ts",
         "line": 42,
         "severity": "blocking",
         "category": "correctness|security|architecture|style|performance",
         "description": "Clear description of the issue",
         "suggestion": "How to fix it"
       }
     ],
     "summary": "One paragraph summary of the review",
     "stats": { "blocking_count": 0, "non_blocking_count": 0, "files_reviewed": 0 }
   }
   ```
5. **Do NOT include a "verdict" field.** You produce findings — the verdict is Claude's decision.
6. **Notify Claude** when done:
   ```bash
   ~/.codex/skills/claude-cli/scripts/tmux-claude.sh "Review complete. Findings at: <findings_file>"
   ```

### Re-review request
Claude fixed blocking issues and requests another pass.

- Verify previous blocking issues were addressed
- Flag only genuinely NEW issues
- Do NOT re-raise findings that were already addressed

### Task request
Claude asks you to investigate or work on something.

1. Perform the requested task
2. Write results to the file path specified (if given)
3. Notify Claude: `tmux-claude.sh "Task complete. Response at: <path>"`

### Plan review request
Claude shares a plan and asks for your assessment.

1. Read the plan
2. Evaluate feasibility, risks, missing steps
3. Write feedback to the specified file (same findings JSON format, but categories may include `architecture`, `feasibility`, `missing-step`)
4. Notify Claude: `tmux-claude.sh "Plan review complete. Findings at: <path>"`

### Question from Claude
Claude asks for information or your opinion.

1. Read the question
2. Investigate the codebase or reason about the answer
3. Write response to the specified file
4. Notify Claude: `tmux-claude.sh "Response ready at: <path>"`
```

### 4.2 Codex: `claude-cli` Skill (rewritten)

Defines when and how Codex contacts Claude via tmux. This replaces the old `claude-cli/SKILL.md` that used `call_claude.sh`.

**`codex/skills/claude-cli/SKILL.md`:**

```markdown
# claude-cli — Communicate with Claude via tmux

## When to contact Claude

- **During review**: After writing findings to the file, notify Claude that review is complete
- **During planning**: When you need codebase context that would require extensive exploration
  (e.g., "how does the auth middleware chain work?", "what calls this function?")
- **During tasks**: When you need Claude to investigate something in parallel

## Discovering the session state directory

Before sending messages, discover the active party session:
```bash
STATE_DIR=$(cat /tmp/party-active-session)
```
Use `$STATE_DIR` to construct file paths for questions and responses.

## How to contact Claude

Use the transport script:
```bash
~/.codex/skills/claude-cli/scripts/tmux-claude.sh "<message>"
```

This sends a `[CODEX]` prefixed message to Claude's tmux pane. The script returns immediately — you are NOT blocked.

## Message conventions

### Notify review complete
After writing findings to the specified file:
```bash
~/.codex/skills/claude-cli/scripts/tmux-claude.sh "Review complete. Findings at: <findings_file>"
```

### Ask a question
When you need information from Claude:
```bash
RESPONSE_FILE="$STATE_DIR/response-$(date +%s%N).md"
~/.codex/skills/claude-cli/scripts/tmux-claude.sh "Question: <your question>. Write response to: $RESPONSE_FILE"
```

### Report task completion
After completing a delegated task:
```bash
~/.codex/skills/claude-cli/scripts/tmux-claude.sh "Task complete. Response at: <response_file>"
```

## Handling Claude's responses

When you see a message in your pane from Claude (e.g., "Response ready at: <path>"):
1. Read the response file
2. Incorporate the answer into your current work
3. Continue — you have full context of what you were doing before asking

## Important

- Each exchange creates unique timestamped files — multi-turn dialogue works naturally
- You retain your full context across exchanges (persistent tmux session)
- Keep questions specific and actionable — Claude will investigate the codebase for you
- Do NOT ask Claude to make code changes. You make changes, Claude reviews.
```

### 4.3 Claude: `tmux-handler` Skill

Defines how Claude handles incoming messages from Codex's tmux pane.

**`claude/skills/tmux-handler/SKILL.md`:**

```markdown
# tmux-handler — Handle incoming messages from Codex via tmux

## Trigger

You see a message in your pane prefixed with `[CODEX]`. These are from Codex's tmux pane.

## Message types

### Review complete
Message: `[CODEX] Review complete. Findings at: <path>`

1. Read the FULL findings file with your Read tool
2. Mark review evidence as complete:
   `tmux-codex.sh --review-complete <path>`
3. Triage each finding: blocking / non-blocking / out-of-scope
4. Update your issue ledger (reject re-raised closed findings, detect oscillation)
5. Decide verdict:
   - All non-blocking → `tmux-codex.sh --approve`
   - Blocking findings → fix them, choose re-review tier, then `tmux-codex.sh --re-review`
   - Unresolvable → `tmux-codex.sh --needs-discussion "reason"`

### Question from Codex
Message: `[CODEX] Question waiting. Read: <question_file> — Write response to: <response_file>`

1. Read the question file
2. Investigate the codebase to answer the question
3. Write your response to the specified response file
4. Notify Codex: `tmux-codex.sh --prompt "Response ready at: <response_file>"`

### Task complete
Message: `[CODEX] Task complete. Response at: <path>`

1. Read the response file
2. Continue your workflow with the information Codex provided
```

### 4.4 Claude: `codex-cli` Skill (rewritten)

Defines when and how Claude contacts Codex via tmux. This replaces the old `codex-cli/SKILL.md` that used `call_codex.sh` and `codex-verdict.sh`.

**`claude/skills/codex-cli/SKILL.md`:**

```markdown
# codex-cli — Communicate with Codex via tmux

## When to contact Codex

- **For code review**: After implementing changes and passing sub-agent critics, request Codex review
- **For tasks**: When you need Codex to investigate or work on something in parallel
- **For verdict**: After triaging Codex's findings, signal your decision

## How to contact Codex

Use the transport script:
```bash
~/.claude/skills/codex-cli/scripts/tmux-codex.sh <mode> [args...]
```

## Modes

### Request review (non-blocking)
After implementing changes and passing sub-agent critics:
```bash
~/.claude/skills/codex-cli/scripts/tmux-codex.sh --review <base_branch> "<PR title>"
```
This sends a message to Codex's pane. You are NOT blocked — continue with non-edit work while Codex reviews. Codex will notify you via `[CODEX] Review complete. Findings at: <path>` when done. Handle that message per your `tmux-handler` skill.

### Send a task (non-blocking)
```bash
~/.claude/skills/codex-cli/scripts/tmux-codex.sh --prompt "<task description>"
```
Returns immediately. Codex will notify you when done.

### Record review completion evidence
After Codex notifies you that findings are ready:
```bash
~/.claude/skills/codex-cli/scripts/tmux-codex.sh --review-complete "<findings_file>"
```
This preserves the existing evidence-chain invariant: `CODEX_REVIEW_RAN` means a completed review, not merely a queued request.

### Signal verdict (after triaging findings)
```bash
# All findings non-blocking — approve
~/.claude/skills/codex-cli/scripts/tmux-codex.sh --approve

# Blocking findings fixed, request re-review
~/.claude/skills/codex-cli/scripts/tmux-codex.sh --re-review "what was fixed"

# Unresolvable after max iterations
~/.claude/skills/codex-cli/scripts/tmux-codex.sh --needs-discussion "reason"
```
Verdict modes output sentinel strings that hooks detect to create evidence markers.

## Important

- `--review` and `--prompt` are NON-BLOCKING. Continue working while Codex processes.
- `--review-complete` emits `CODEX_REVIEW_RAN` only after findings exist.
- Verdict modes (`--approve`, `--re-review`, `--needs-discussion`) are instant — they output sentinels for hook detection.
- You decide the verdict. Codex produces findings, you triage them.
- Before calling `--review`, ensure sub-agent critics have passed (codex-gate.sh enforces this).
- Before calling `--approve`, ensure codex-ran marker exists (codex-gate.sh enforces this).
```

**Deliverables:**
- [ ] `codex/skills/tmux-handler/SKILL.md` — Codex's inbound handler (reviews, tasks, plan reviews, questions from Claude)
- [ ] `codex/skills/claude-cli/SKILL.md` — Codex's outbound protocol (when/how to contact Claude, message conventions)
- [ ] `claude/skills/tmux-handler/SKILL.md` — Claude's handler for `[CODEX]` messages (triage, verdict, question answering)
- [ ] `claude/skills/codex-cli/SKILL.md` — Claude's outbound protocol (when/how to contact Codex, all modes, verdict semantics)

---

## Phase 5: Hook Updates

### 5.1 Updated `codex-gate.sh`

Same logic as today, but regex matches `tmux-codex.sh` instead of `call_codex.sh`:

```bash
# Only gate tmux-codex.sh invocations
echo "$COMMAND" | grep -qE '(^|[;&|] *)([^ ]*/)?tmux-codex\.sh' || { echo '{}'; exit 0; }

# Gate 1: --review requires critic APPROVE markers
if echo "$COMMAND" | grep -qE 'tmux-codex\.sh +--review'; then
  # ... same marker checks as today ...
fi

# Gate 2: --approve requires codex-ran marker
if echo "$COMMAND" | grep -qE 'tmux-codex\.sh +--approve'; then
  # ... same codex-ran check as today ...
fi
```

### 5.2 Updated `codex-trace.sh`

Same logic as today, but detects `tmux-codex.sh` output sentinels instead of `call_codex.sh`:

```bash
# Detect tmux-codex.sh invocations
echo "$command" | grep -qE '(^|[;&|] *)([^ ]*/)?tmux-codex\.sh' || exit 0

# Sentinel detection:
# CODEX_REVIEW_RAN (from --review-complete only) → create codex-ran marker
# CODEX APPROVED → create codex-approved marker
# CODEX REQUEST_CHANGES → create codex-ran marker only
# CODEX NEEDS_DISCUSSION → log only
```

`tmux-codex.sh --review` is non-blocking and **does not** emit `CODEX_REVIEW_RAN`. Claude emits `CODEX_REVIEW_RAN` via `tmux-codex.sh --review-complete <findings_file>` after it receives Codex's completion message and verifies the findings file exists. This preserves the dual-layer defense (codex-ran + codex-approved) without granting evidence on mere request dispatch.

### 5.3 All other hooks — unchanged

These hooks work identically because they don't reference Codex invocation scripts:

- `agent-trace.sh` — sub-agents still use Task tool
- `marker-invalidate.sh` — still fires on Edit/Write
- `skill-marker.sh` — still creates skill markers
- `pr-gate.sh` — still checks the same `/tmp/claude-*` marker files
- `worktree-guard.sh` — still checks worktree state
- `session-cleanup.sh` — still cleans up on session end
- `skill-eval.sh` — still evaluates skill triggers

**Deliverables:**
- [ ] `claude/hooks/codex-gate.sh` — updated regex only
- [ ] `claude/hooks/codex-trace.sh` — updated regex only
- [ ] All other hooks copied unchanged

---

## Phase 6: Documentation Updates

### 6.1 Updated Workflow Skills

**`task-workflow/SKILL.md` — Steps 7 and 8 change:**

Current step 7:
```
7. **codex** — Invoke `~/.claude/skills/codex-cli/scripts/call_codex.sh` for combined code + architecture review
```

New step 7:
```
7. **codex** — Request codex review via tmux:
   ```bash
   ~/.claude/skills/codex-cli/scripts/tmux-codex.sh --review main "{PR title}"
   ```
   This sends the review to Codex's tmux pane. You are NOT blocked — continue with
   non-edit work while Codex reviews. Codex will notify you via tmux when findings are ready.
```

Current step 8:
```
8. **Handle codex verdict** — Triage findings (see Finding Triage). Classify fix impact for tiered re-review. Signal verdict via `codex-verdict.sh`.
```

New step 8:
```
8. **Triage codex findings** — When the findings file appears:
   a. Read the FULL findings file (not just the summary)
   b. Record Codex completion evidence:
      ```bash
      ~/.claude/skills/codex-cli/scripts/tmux-codex.sh --review-complete "<findings_file>"
      ```
   c. Triage each finding: blocking / non-blocking / out-of-scope
   d. Update issue ledger (reject re-raised closed findings, detect oscillation)
   e. If no blocking findings:
      ```bash
      ~/.claude/skills/codex-cli/scripts/tmux-codex.sh --approve
      ```
   f. If blocking findings need fixes: fix them, choose re-review tier:
      - Targeted swap (typo): run test-runner only → if pass, `tmux-codex.sh --approve`
      - Logic change: re-run critics → if approve, `tmux-codex.sh --re-review`
      - New export/signature: full cascade → `tmux-codex.sh --re-review`
   g. If unresolvable (max 3 iterations):
      ```bash
      ~/.claude/skills/codex-cli/scripts/tmux-codex.sh --needs-discussion "reason"
      ```
```

**`bugfix-workflow/SKILL.md`** — Same pattern: replace `call_codex.sh` with `tmux-codex.sh`, replace `codex-verdict.sh` with `tmux-codex.sh --approve/--re-review/--needs-discussion`.

**`codex-cli/SKILL.md`** — Full rewrite: describe the tmux-based invocation pattern, file-based handoff, push notification (Codex notifies Claude), and all modes. Document that `--review` and `--prompt` are non-blocking.

### 6.2 Updated Rules

**`execution-core.md`:**
- Codex Review Gate section: same logic, `tmux-codex.sh` instead of `call_codex.sh`
- Decision matrix: unchanged logic, updated script names

**`autonomous-flow.md`:**
- Violation patterns: `call_codex.sh` → `tmux-codex.sh`, `codex-verdict.sh` → `tmux-codex.sh --approve`
- Checkpoint markers: same markers, same hooks (just updated regex)

**`CLAUDE.md`:**
- Sub-agents table: replace `call_codex.sh` / `codex-verdict.sh` with `tmux-codex.sh` (all modes)
- Add tmux context section: "You are running in a tmux pane alongside Codex. You can communicate with Codex directly via `tmux-codex.sh`. Codex reviews are non-blocking — you can continue working while Codex reviews."
- Add `[CODEX]` message convention: "Messages prefixed with `[CODEX]` are from Codex's tmux pane. Read the referenced question file, investigate, and write your response to the specified response file."
- Add verdict authority note: same as before (Claude triages, Claude decides)

**`codex/AGENTS.md`:**
- Add tmux context: "You are running as a persistent interactive session in a tmux pane alongside Claude. You can communicate with Claude directly via `tmux-claude.sh`. When asked to write output to a file, always comply — file-based handoff is how agents exchange structured data. You retain context across reviews within this session. IMPORTANT: You produce FINDINGS, not verdicts."

### 6.3 Updated Settings

**`settings.json`:**

```diff
- "Bash(~/.claude/skills/codex-cli/scripts/call_codex.sh:*)",
- "Bash(~/.claude/skills/codex-cli/scripts/codex-verdict.sh:*)",
+ "Bash(~/.claude/skills/codex-cli/scripts/tmux-codex.sh:*)",
```

Hook config: no structural changes needed — `codex-gate.sh` and `codex-trace.sh` keep their names, just updated regex inside.

**Deliverables:**
- [ ] Updated `task-workflow/SKILL.md`
- [ ] Updated `bugfix-workflow/SKILL.md`
- [ ] Rewritten `codex-cli/SKILL.md`
- [ ] Updated `execution-core.md`
- [ ] Updated `autonomous-flow.md`
- [ ] Updated `CLAUDE.md`
- [ ] Updated `codex/AGENTS.md`
- [ ] Updated `settings.json`

---

## Phase 7: Testing

### 7.1 Test Infrastructure

Shell-based test harness. Mock agents simulate Claude and Codex behavior.

**`mock-claude.sh`:**
```bash
# Simulates Claude Code responses
# Reads from stdin (tmux send-keys input), pattern-matches on [CODEX] messages
while IFS= read -r line; do
  case "$line" in
    *"[CODEX] Review complete. Findings at:"*)
      findings_file="${line##*Findings at: }"
      findings_file="${findings_file%% *}"
      echo "Mock Claude reading findings from $findings_file"
      # Simulate triage — if no blocking findings, approve
      if jq -e '.stats.blocking_count == 0' "$findings_file" >/dev/null 2>&1; then
        echo "CODEX APPROVED"
      else
        echo "CODEX REQUEST_CHANGES — Blocking findings need fixes"
      fi
      ;;
    *"[CODEX] Question:"*)
      response_file="${line##*Write response to: }"
      response_file="${response_file%% *}"
      echo "The database uses a pooled connection with max 10 connections." > "$response_file"
      echo "Mock Claude wrote response to $response_file"
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
# Reads from stdin (tmux send-keys input), extracts findings path from direct message
REVIEWS_BEFORE_APPROVE="${MOCK_REVIEWS:-3}"
review_count=0

while IFS= read -r line; do
  case "$line" in
    *"Review the changes"*"Write findings to:"*)
      ((review_count++))
      # Extract findings file path directly from the message (no prompt file)
      findings_file="${line##*Write findings to: }"
      findings_file="${findings_file%% *}"
      if (( review_count >= REVIEWS_BEFORE_APPROVE )); then
        echo '{"findings":[],"summary":"All issues addressed.","stats":{"blocking_count":0,"non_blocking_count":0,"files_reviewed":5}}' > "$findings_file"
      else
        echo '{"findings":[{"id":"F1","file":"src/auth.ts","line":42,"severity":"blocking","category":"correctness","description":"Missing null check","suggestion":"Add null guard"}],"summary":"Found 1 blocking issue.","stats":{"blocking_count":1,"non_blocking_count":0,"files_reviewed":5}}' > "$findings_file"
      fi
      # Notify Claude via tmux-claude.sh (simulated)
      echo "[MOCK] Review complete. Would call: tmux-claude.sh 'Review complete. Findings at: $findings_file'"
      ;;
  esac
done
```

### 7.2 Test Cases

**Session tests (`test-party.sh`):**
- [ ] `party.sh` creates tmux session with 2 panes
- [ ] `party.sh --raw` works without iTerm2
- [ ] `party.sh --stop` cleanly tears down session and state dir
- [ ] State directory has correct subdirectories

**Claude→Codex tests (`test-tmux-codex.sh`):**
- [ ] `--review` sends message with base branch, title, and findings path to Codex pane
- [ ] `--review` returns immediately (non-blocking)
- [ ] `--review` does **not** emit `CODEX_REVIEW_RAN`
- [ ] `--prompt` sends prompt text and response path to Codex pane
- [ ] `--review-complete <findings_file>` emits `CODEX_REVIEW_RAN` only if file exists
- [ ] `--approve` outputs correct sentinel string (`CODEX APPROVED`)
- [ ] `--re-review` outputs correct sentinel string (`CODEX REQUEST_CHANGES`)
- [ ] `--needs-discussion` outputs correct sentinel string (`CODEX NEEDS_DISCUSSION`)
- [ ] Script fails gracefully when no party session exists

**Codex→Claude tests (`test-tmux-claude.sh`):**
- [ ] `[CODEX]` prefixed message sent to Claude pane
- [ ] Script returns immediately (non-blocking)
- [ ] Script fails gracefully when no party session exists

**Hook tests (`test-hooks.sh`):**
- [ ] `codex-gate.sh` blocks `tmux-codex.sh --review` without critic markers
- [ ] `codex-gate.sh` allows `tmux-codex.sh --review` with critic markers
- [ ] `codex-gate.sh` blocks `tmux-codex.sh --approve` without codex-ran marker
- [ ] `codex-trace.sh` creates codex-ran marker on `tmux-codex.sh --review-complete` (`CODEX_REVIEW_RAN`)
- [ ] `codex-trace.sh` creates codex-approved marker on CODEX APPROVED sentinel

**Integration test (`test-integration.sh`):**
- [ ] Full review cycle with mock agents: Claude implements → critics → tmux-codex --review → Codex writes findings → Claude reads → tmux-codex --approve → markers created
- [ ] Multi-review cycle: 3 rounds of findings → fixes → re-review → eventual approve
- [ ] Planning dialogue: Codex asks Claude → Claude responds → Codex reads response
- [ ] Bidirectional: Claude reviews via Codex, then Codex asks Claude a question, both in same session

**Deliverables:**
- [ ] `tests/mock-claude.sh`, `tests/mock-codex.sh`
- [ ] `tests/test-party.sh`
- [ ] `tests/test-tmux-codex.sh`
- [ ] `tests/test-tmux-claude.sh`
- [ ] `tests/test-hooks.sh`
- [ ] `tests/test-integration.sh`
- [ ] `tests/run-tests.sh`

---

## Phase 8: iTerm2 Setup & Migration

### 8.1 iTerm2 Keybindings

Set up keybindings so launching and managing party sessions is a single keystroke.

**Setup (one-time, via iTerm2 Settings):**

1. **Create a "Party" profile** using iTerm2 dynamic profiles:

```json
{
  "Profiles": [
    {
      "Name": "Party",
      "Guid": "party-session-profile",
      "Custom Command": "Yes",
      "Command": "~/ai-config-tmux/session/party.sh",
      "Working Directory": "",
      "Custom Directory": "Recycle",
      "Tags": ["ai-config", "party"]
    }
  ]
}
```

2. **Add keybindings** (Settings → Keys → Key Bindings → `+`):

| Keybind | Action | Effect |
|---------|--------|--------|
| `Cmd+Shift+P` | New Tab with Profile → Party | Launch a new party session |
| `Cmd+Shift+K` | Send Text: `~/ai-config-tmux/session/party.sh --stop\n` | Kill the current party session |

### 8.2 Migration path

Build in phase order (0→8). Phase 0 must pass before any implementation. After Phase 7 tests pass, do integration testing with real agents in the `tmux` worktree. Decision: merge to `main`, keep in worktree, or abandon.

**Switching systems:**
```bash
# Use tmux system (direct transport branch)
cd ~/ai-config-tmux && ./session/party.sh

# Use subprocess system
cd ~/ai-config
```

No symlink changes needed — `~/.claude` already points to `~/ai-config/claude` in daily workflow. During tmux testing, launch tools from the tmux worktree paths explicitly.

**Merging when ready:**
```bash
cd ~/ai-config
git merge tmux
git worktree remove ../ai-config-tmux
```

After merge, `main` has the tmux system and the old `call_codex.sh`/`codex-verdict.sh`/`call_claude.sh` scripts are deleted. If rollback is needed post-merge, revert the merge commit rather than switching branches in the shared worktree.

---

## Risk Register

| Risk | Severity | Mitigation |
|------|----------|------------|
| `tmux send-keys` arrives while agent is mid-execution | Low | Both agents run non-interactive (no approval prompts). Buffered input processes when agent returns to prompt. Phase 0 validates. |
| Codex ignores file-write instruction | Medium | `tmux-handler` skill explicitly instructs file write; Codex's AGENTS.md reinforces. Fall back to `tmux capture-pane` |
| Large diff exceeds tmux send-keys limit | Low | Not applicable: Codex runs its own git diff in the shared repo |
| `[CODEX]` message confused with user input | Low | Distinctive prefix; documented in CLAUDE.md and `tmux-handler` skill |
| Agent crashes | Medium | User can see both panes; restart agent manually or re-run `party.sh` |
| Race condition: code edit during Codex review | Medium | `marker-invalidate.sh` still fires on Edit/Write — same as today |
| Codex sandbox write access to `/tmp/` | ~~High~~ | **Resolved in Phase 0.** Tested before implementation begins. Fallback options documented |
| Claude rubber-stamps --approve without reading findings | Medium | Same risk as today; mitigated by `codex-gate.sh` (gate 2: codex-ran required) and `tmux-handler` skill instructions |
| Codex forgets to notify Claude after writing findings | Medium | `tmux-handler` skill explicitly instructs notification step; Codex's AGENTS.md reinforces convention |
| Codex takes too long, no notification arrives | Low | User can see both panes in iTerm2 and nudge either agent; could add a timeout convention in skill docs |
| Multiple party sessions cause script confusion | Low | Single active-session pointer (`/tmp/party-active-session`) + tmux liveness checks enforce deterministic discovery |

---

## Success Criteria

1. **Full review cycle works:** Claude implements → critics → `tmux-codex.sh --review` → Codex writes findings → Claude reads → `tmux-codex.sh --review-complete` → triages → `tmux-codex.sh --approve` → markers created → PR
2. **Multi-review cycle works:** Multiple rounds with Claude triaging each, maintaining issue ledger, eventual approve — all with persistent Codex context
3. **Claude keeps full context:** No context loss between review iterations (Claude remembers previous findings, its issue ledger, why it made changes)
4. **Codex keeps full context:** Codex remembers previous reviews within the session (can focus on "was this fixed?" rather than re-reviewing from scratch)
5. **Planning dialogue works:** Codex asks Claude via `tmux-claude.sh`, Claude responds, Codex continues — both retain context
6. **Bidirectional:** Claude→Codex (reviews, tasks) and Codex→Claude (questions) both work
7. **Non-blocking:** Claude can work while Codex reviews; Codex can work while Claude answers
8. **All existing hooks still work:** agent-trace, marker-invalidate, skill-marker, pr-gate, worktree-guard, session-cleanup, skill-eval
9. **Markers are compatible:** Same `/tmp/claude-*` paths, same semantics, `pr-gate.sh` works unchanged
10. **iTerm2 UX:** `tmux -CC` gives native panes with scrollback and search
11. **Tests pass:** All test suites green
12. **Rollback works:** main worktree stays untouched until merge; post-merge rollback is a merge revert

---

## Appendix A: Change Manifest

Complete list of changes on the `tmux` branch relative to `main`.

### New files

```
session/party.sh                                     # Session launcher + teardown (Phase 1)
session/party-lib.sh                                 # Shared helpers: discover_session() (Phase 1)

claude/skills/codex-cli/scripts/tmux-codex.sh        # Claude→Codex transport (Phase 2)
claude/skills/tmux-handler/SKILL.md                  # How Claude handles incoming [CODEX] messages (Phase 4)

codex/skills/claude-cli/scripts/tmux-claude.sh       # Codex→Claude transport (Phase 3)
codex/skills/tmux-handler/SKILL.md                    # How Codex handles incoming messages from Claude (Phase 4)

tests/test-party.sh                                  # Session tests (Phase 7)
tests/test-tmux-codex.sh                             # Claude→Codex tests (Phase 7)
tests/test-tmux-claude.sh                            # Codex→Claude tests (Phase 7)
tests/test-hooks.sh                                  # Hook tests (Phase 7)
tests/test-integration.sh                            # Integration tests (Phase 7)
tests/mock-claude.sh                                 # Mock Claude (Phase 7)
tests/mock-codex.sh                                  # Mock Codex (Phase 7)
tests/run-tests.sh                                   # Test runner (Phase 7)
```

### Edited files

```
claude/CLAUDE.md                                     # Add tmux context, [CODEX] convention, verdict authority
claude/settings.json                                 # Swap permission lines: call_codex.sh/codex-verdict.sh → tmux-codex.sh
claude/hooks/codex-gate.sh                           # Regex: call_codex.sh → tmux-codex.sh, codex-verdict.sh → tmux-codex.sh
claude/hooks/codex-trace.sh                          # Regex: call_codex.sh → tmux-codex.sh, codex-verdict.sh → tmux-codex.sh
claude/rules/execution-core.md                       # call_codex.sh → tmux-codex.sh, codex-verdict.sh → tmux-codex.sh --approve
claude/rules/autonomous-flow.md                      # call_codex.sh → tmux-codex.sh, codex-verdict.sh → tmux-codex.sh --approve
claude/skills/codex-cli/SKILL.md                     # Rewritten: tmux-codex.sh modes + verdict semantics (Phase 4)
claude/skills/task-workflow/SKILL.md                 # Steps 7+8 rewritten for tmux (Phase 6)
claude/skills/bugfix-workflow/SKILL.md               # Codex steps rewritten for tmux (Phase 6)
codex/AGENTS.md                                      # Add tmux context section (Phase 6)
codex/skills/claude-cli/SKILL.md                     # Rewritten: tmux-claude.sh + STATE_DIR discovery (Phase 4)
```

### Deleted files (replaced by new scripts above)

```
claude/skills/codex-cli/scripts/call_codex.sh        # Replaced by tmux-codex.sh
claude/skills/codex-cli/scripts/codex-verdict.sh     # Merged into tmux-codex.sh --approve/--re-review/--needs-discussion
codex/skills/claude-cli/scripts/call_claude.sh       # Replaced by tmux-claude.sh
```

### Unchanged (no modifications needed)

All other files remain identical to `main`. Because this is a branch, they don't need to be copied — they're just there.

---

## Appendix B: Dependencies

| Dependency | Required | Install | Purpose |
|-----------|----------|---------|---------|
| `tmux` | Yes | `brew install tmux` | Terminal multiplexer — core infrastructure |
| `jq` | Yes | `brew install jq` | JSON parsing for hook input |
| `claude` | Yes | `curl -fsSL https://cli.anthropic.com/install.sh \| sh` | Claude Code CLI |
| `codex` | Yes | `brew install --cask codex` | Codex CLI |
| iTerm2 | Recommended | `brew install --cask iterm2` | Terminal with native tmux integration. Raw tmux works without it |

Note: `fswatch` is no longer needed — there's no coordinator daemon watching for signal files. Agents notify each other via `tmux send-keys` (push, not poll).

---

## Appendix C: Assumed Symlinks

The plan assumes `install.sh` has been run, which creates:

```
~/.claude → ~/ai-config/claude
~/.codex  → ~/ai-config/codex
```

Scripts reference these symlinks (e.g., `~/.codex/skills/claude-cli/scripts/tmux-claude.sh`). If symlinks don't exist, scripts won't find their paths.

## Appendix D: iTerm2 Dynamic Profile Location

The Party profile JSON from Phase 8 should be saved to:

```
~/Library/Application Support/iTerm2/DynamicProfiles/party.json
```

iTerm2 auto-discovers profiles from this directory — no restart needed.
