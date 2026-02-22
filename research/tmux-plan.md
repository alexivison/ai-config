# Tmux Integration — Implementation Plan

Implementation plan for replacing the subprocess-based Claude/Codex orchestration with tmux-based persistent sessions. Built for iTerm2 on macOS.

---

## Context

### Why tmux

The current system invokes Codex as a blocking subprocess (`codex exec`). Each invocation is a cold start — fresh context, one-shot output, 15-minute block on Claude. The user's workflow involves 3-7 Codex reviews per task and bidirectional Claude↔Codex planning dialogues. At 7 reviews per task, that's ~105 minutes of dead blocking time. Tmux replaces this with persistent interactive sessions where both agents retain context across reviews and Claude isn't blocked during Codex work.

### Architecture: Direct tmux, no coordinator

**Previous approach (discarded):** A coordinator daemon sitting between Claude and Codex, managing a state machine, signal files, and pane I/O. This loses context — the coordinator doesn't know *why* Claude is requesting a review or what the findings mean.

**New approach:** Claude and Codex each use `tmux send-keys` and `tmux capture-pane` directly via their Bash tools. No middleman. Each agent retains full context of what it's doing and why. The only shared infrastructure is:

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

---

## New Repo: `ai-config-tmux`

This is built as a **new repository** alongside the existing `ai-config`. Reasoning:

1. Current system works and is used daily — can't break it during development
2. The 2 critical hooks (`codex-gate.sh`, `codex-trace.sh`) are structurally incompatible — they regex-match `call_codex.sh` at the Bash tool call level, which doesn't exist in tmux
3. Zero test infrastructure exists — new repo builds validation from day one
4. Can evaluate side-by-side before committing to migration

### Repo structure

```
ai-config-tmux/
├── session/
│   └── party.sh                       # Main entry point — session launcher + teardown
│
├── claude/                            # Copied + adapted from ai-config
│   ├── CLAUDE.md                      # Updated: tmux context, direct communication instructions
│   ├── settings.json                  # Updated: new script permissions, hook config
│   ├── hooks/
│   │   ├── session-cleanup.sh         # Unchanged
│   │   ├── skill-eval.sh             # Unchanged
│   │   ├── worktree-guard.sh         # Unchanged
│   │   ├── agent-trace.sh            # Unchanged (sub-agents still in-process)
│   │   ├── marker-invalidate.sh      # Unchanged
│   │   ├── skill-marker.sh           # Unchanged
│   │   ├── pr-gate.sh               # Unchanged (still checks same markers)
│   │   ├── codex-gate.sh            # Updated: regex matches tmux-codex.sh instead of call_codex.sh
│   │   └── codex-trace.sh           # Updated: regex matches tmux-codex.sh instead of call_codex.sh
│   ├── rules/
│   │   ├── execution-core.md         # Updated: tmux references
│   │   ├── autonomous-flow.md        # Updated: tmux references
│   │   └── (backend/, frontend/)     # Unchanged
│   ├── skills/
│   │   ├── codex-cli/
│   │   │   ├── SKILL.md              # Rewritten: direct tmux patterns
│   │   │   └── scripts/
│   │   │       └── tmux-codex.sh     # NEW: sends review/task/verdict to Codex pane via tmux
│   │   ├── task-workflow/SKILL.md    # Updated: step 7 uses tmux-codex.sh
│   │   ├── bugfix-workflow/SKILL.md  # Updated: codex step uses tmux-codex.sh
│   │   ├── pre-pr-verification/      # Unchanged
│   │   └── (other skills/)           # Unchanged
│   ├── agents/                        # Unchanged
│   └── scripts/                       # Unchanged
│
├── codex/                             # Copied + adapted from ai-config
│   ├── AGENTS.md                      # Updated: tmux context, direct communication instructions
│   ├── config.toml                    # Unchanged (sandbox mode set at launch)
│   ├── rules/                         # Unchanged
│   └── skills/
│       └── claude-cli/
│           ├── SKILL.md              # Rewritten: direct tmux patterns
│           └── scripts/
│               └── tmux-claude.sh    # NEW: sends question/response to Claude pane via tmux
│
├── shared/                            # Copied from ai-config
│   └── skills/                        # Unchanged
│
├── tests/
│   ├── test-party.sh                  # Session launch/teardown tests
│   ├── test-tmux-codex.sh            # Claude→Codex communication tests
│   ├── test-tmux-claude.sh           # Codex→Claude communication tests
│   ├── test-hooks.sh                 # Hook integration tests
│   ├── test-integration.sh           # Full review cycle with mock agents
│   ├── mock-claude.sh               # Mock Claude agent for testing
│   ├── mock-codex.sh                # Mock Codex agent for testing
│   └── run-tests.sh                 # Test runner
│
├── install.sh                         # Adapted from ai-config
└── README.md
```

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
│ Pane 0: Claude              │ Pane 1: Codex                │
│ claude --dangerously-skip-  │ codex --full-auto             │
│ permissions                 │ --sandbox read-only           │
│                             │                               │
│                             │                               │
└─────────────────────────────┴──────────────────────────────┘
```

No coordinator pane. No dashboard pane. Just two agents, side by side. The user watches both panes directly in iTerm2 (native scrollback, search, selection).

**Implementation:**

```bash
party_start() {
  SESSION="party-$(date +%s)"
  STATE_DIR="/tmp/$SESSION"
  mkdir -p "$STATE_DIR/messages/to-codex" "$STATE_DIR/messages/to-claude"

  # Write session metadata so scripts can discover the active session
  echo "$SESSION" > "$STATE_DIR/session-name"

  # Detect iTerm2 and use control mode
  TMUX_CMD="tmux"
  if [[ "${TERM_PROGRAM:-}" == "iTerm.app" && "${PARTY_RAW:-}" != "1" ]]; then
    TMUX_CMD="tmux -CC"
  fi

  # Create session
  $TMUX_CMD new-session -d -s "$SESSION" -n work -x 200 -y 50

  # Split into panes
  tmux split-window -h -t "$SESSION:work"  # Pane 1: Codex (right)

  # Launch agents
  tmux send-keys -t "$SESSION:work.0" \
    "claude --dangerously-skip-permissions" C-m
  tmux send-keys -t "$SESSION:work.1" \
    "codex --full-auto --sandbox read-only" C-m

  # Attach (iTerm2 control mode auto-attaches)
  if [[ "$TMUX_CMD" == "tmux" ]]; then
    tmux attach -t "$SESSION"
  fi
}
```

**Teardown:**

```bash
party_stop() {
  tmux kill-session -t "$SESSION" 2>/dev/null
  rm -rf "$STATE_DIR"
}
```

**How agents discover the session:** Both `tmux-codex.sh` and `tmux-claude.sh` find the active party session by looking for `/tmp/party-*/session-name`. They read the session name from that file to construct tmux target pane addresses.

```bash
# Shared helper used by both tmux-codex.sh and tmux-claude.sh
discover_session() {
  local state_dir
  state_dir=$(find /tmp -maxdepth 1 -name 'party-*' -type d 2>/dev/null | head -1)
  if [[ -z "$state_dir" ]]; then
    echo "Error: No active party session found" >&2
    return 1
  fi
  SESSION_NAME=$(cat "$state_dir/session-name")
  STATE_DIR="$state_dir"
}
```

**Deliverables:**
- [ ] `session/party.sh` — session launcher with iTerm2 detection
- [ ] iTerm2 control mode (`tmux -CC`) integration tested
- [ ] `--raw` fallback for non-iTerm terminals
- [ ] Clean teardown on SIGTERM/SIGINT
- [ ] `$STATE_DIR/messages/to-codex/` and `$STATE_DIR/messages/to-claude/` directories created on startup

---

## Phase 2: Claude → Codex Communication

### 2.1 `tmux-codex.sh` — Claude's interface to Codex

This single script replaces both `call_codex.sh` and `codex-verdict.sh`. Claude calls it via its Bash tool. The script uses `tmux send-keys` to communicate with Codex's pane and file-based handoff for structured data.

**Key principle: Claude keeps full context.** Claude knows why it's requesting a review, what the previous findings were, and what it expects. It sends the request directly and reads the response directly. No middleman losing context.

**Modes:**

| Mode | Replaces | What it does |
|------|----------|-------------|
| `--review` | `call_codex.sh --review` | Generates diff, writes review prompt to file, sends Codex a short message via tmux to read it, polls for findings file |
| `--prompt` | `call_codex.sh --prompt` | Writes prompt to file, sends Codex a short message via tmux to read it, polls for response file |
| `--approve` | `codex-verdict.sh approve` | Creates evidence markers (codex-ran + codex-approved). Returns immediately |
| `--re-review` | `codex-verdict.sh request_changes` | Creates codex-ran marker only. Returns immediately |
| `--needs-discussion` | `codex-verdict.sh needs_discussion` | Logs to trace. Returns immediately |

**Implementation:**

```bash
#!/usr/bin/env bash
# tmux-codex.sh — Claude's direct interface to Codex via tmux
# Replaces call_codex.sh + codex-verdict.sh
set -euo pipefail

MODE="${1:?Usage: tmux-codex.sh --review|--prompt|--approve|--re-review|--needs-discussion}"

# Discover active party session
STATE_DIR=$(find /tmp -maxdepth 1 -name 'party-*' -type d 2>/dev/null | head -1)
if [[ -z "$STATE_DIR" ]]; then
  echo "Error: No active party session found" >&2
  exit 1
fi
SESSION_NAME=$(cat "$STATE_DIR/session-name")
CODEX_PANE="$SESSION_NAME:work.1"
TIMESTAMP="$(date +%s%N)"

case "$MODE" in

  --review)
    BASE="${2:-main}"
    TITLE="${3:-Code review}"

    # Generate diff
    MERGE_BASE=$(git merge-base HEAD "$BASE")
    DIFF_FILE="$STATE_DIR/review-diff-$TIMESTAMP.patch"
    git diff "$MERGE_BASE"..HEAD > "$DIFF_FILE"

    # Build review prompt — write to file (never inline large content in send-keys)
    FINDINGS_FILE="$STATE_DIR/codex-findings-$TIMESTAMP.json"
    PROMPT_FILE="$STATE_DIR/messages/to-codex/review-$TIMESTAMP.md"

    cat > "$PROMPT_FILE" << PROMPT
# Code Review Request

**Title:** $TITLE
**Base branch:** $BASE
**Diff file:** $DIFF_FILE

## Instructions

1. Read the diff file at: $DIFF_FILE
2. Review the changes for: correctness bugs, crash paths, security issues, wrong output, architectural concerns
3. For each finding, classify severity:
   - **blocking**: correctness bug, crash path, wrong output, security HIGH/CRITICAL
   - **non-blocking**: style nit, "could be simpler", defensive edge case, consistency preference
4. Write your complete findings to: $FINDINGS_FILE

Use this exact JSON format for the findings file:
\`\`\`json
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
  "stats": {
    "blocking_count": 0,
    "non_blocking_count": 0,
    "files_reviewed": 0
  }
}
\`\`\`

**IMPORTANT:** Do NOT include a "verdict" field. You produce findings — the verdict is decided by Claude.
PROMPT

    # Send a SHORT command to Codex pane — just tell it to read the prompt file
    tmux send-keys -t "$CODEX_PANE" \
      "Read the review request at $PROMPT_FILE and follow the instructions exactly." C-m

    echo "CODEX_REVIEW_REQUESTED"
    echo "Review prompt: $PROMPT_FILE"
    echo "Findings will be written to: $FINDINGS_FILE"
    echo ""
    echo "Claude is NOT blocked. Continue non-edit work while Codex reviews."
    echo "Poll for findings with: test -f $FINDINGS_FILE && cat $FINDINGS_FILE"
    echo "CODEX_REVIEW_RAN"
    ;;

  --prompt)
    PROMPT_TEXT="${2:?Missing prompt text}"
    RESPONSE_FILE="$STATE_DIR/codex-response-$TIMESTAMP.md"
    PROMPT_FILE="$STATE_DIR/messages/to-codex/prompt-$TIMESTAMP.md"

    cat > "$PROMPT_FILE" << PROMPT
# Task from Claude

$PROMPT_TEXT

## Instructions

Write your complete response to: $RESPONSE_FILE
PROMPT

    tmux send-keys -t "$CODEX_PANE" \
      "Read the task at $PROMPT_FILE and follow the instructions." C-m

    echo "CODEX_TASK_REQUESTED"
    echo "Response will be written to: $RESPONSE_FILE"
    echo "Poll for response with: test -f $RESPONSE_FILE && cat $RESPONSE_FILE"
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
    echo "Usage: tmux-codex.sh --review|--prompt|--approve|--re-review|--needs-discussion" >&2
    exit 1
    ;;
esac
```

**How Claude uses this — the review flow:**

```
1. Claude implements code (same as today)
2. Claude runs sub-agent critics via Task tool (same as today)
3. Claude calls: tmux-codex.sh --review main "Add user auth"
   → Script generates diff, writes prompt file, sends tmux message to Codex
   → Script returns IMMEDIATELY — Claude is NOT blocked
4. Claude continues non-edit work (documentation, test planning, etc.)
5. Claude periodically checks: test -f /tmp/party-xxx/codex-findings-xxx.json
6. When findings file exists, Claude reads it with its Read tool
7. Claude triages each finding (blocking / non-blocking / out-of-scope)
8. Claude maintains issue ledger (same as current system — in Claude's context)
9. Claude decides:
   a. All non-blocking → calls tmux-codex.sh --approve
   b. Blocking issues → fixes them, re-runs critics, calls tmux-codex.sh --re-review
   c. Unresolvable → calls tmux-codex.sh --needs-discussion
```

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
- [ ] `claude/skills/codex-cli/scripts/tmux-codex.sh` — all modes
- [ ] File-based handoff: diff and prompt written to files, Codex told to read them
- [ ] Non-blocking `--review` and `--prompt` (return immediately, Claude polls)
- [ ] `--approve`, `--re-review`, `--needs-discussion` for verdict (same sentinels as current system for hook compatibility)

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

PROMPT_TEXT="${1:?Usage: tmux-claude.sh \"question for Claude\"}"

# Discover active party session
STATE_DIR=$(find /tmp -maxdepth 1 -name 'party-*' -type d 2>/dev/null | head -1)
if [[ -z "$STATE_DIR" ]]; then
  echo "Error: No active party session found" >&2
  exit 1
fi
SESSION_NAME=$(cat "$STATE_DIR/session-name")
CLAUDE_PANE="$SESSION_NAME:work.0"
TIMESTAMP="$(date +%s%N)"

# Write question to file
QUESTION_FILE="$STATE_DIR/messages/to-claude/question-$TIMESTAMP.md"
RESPONSE_FILE="$STATE_DIR/messages/to-claude/response-$TIMESTAMP.md"

cat > "$QUESTION_FILE" << EOF
# Question from Codex

$PROMPT_TEXT

## Instructions

Write your response to: $RESPONSE_FILE
EOF

# Send short notification to Claude's pane
tmux send-keys -t "$CLAUDE_PANE" \
  "[CODEX] Question waiting. Read: $QUESTION_FILE — Write response to: $RESPONSE_FILE" C-m

echo "CLAUDE_REQUEST_DISPATCHED"
echo "Question file: $QUESTION_FILE"
echo "Response will be at: $RESPONSE_FILE"
echo "Poll for response with: test -f $RESPONSE_FILE && cat $RESPONSE_FILE"
```

**How Codex uses this — the planning dialogue flow:**

```
1. User sends planning task to Codex pane directly
2. Codex works on the plan...
3. Codex needs to know how the database connection pool works
4. Codex calls: tmux-claude.sh "How does the database connection pool work in src/db/?"
   → Script writes question file, sends tmux message to Claude pane
   → Script returns immediately — Codex is NOT blocked
5. Claude sees "[CODEX] Question waiting..." in its pane
6. Claude reads the question file, investigates the codebase, writes answer to response file
7. Codex polls for response file, reads it when available
8. Codex incorporates the answer and continues planning
```

**Multi-turn dialogue:** Multiple exchanges work naturally. Each call creates a new question/response file pair with a unique timestamp. Both agents retain their full context across exchanges because they're persistent sessions — Codex remembers what it already planned, Claude remembers what it already investigated.

**How Claude recognizes Codex messages:**

Claude's `CLAUDE.md` documents a convention: messages prefixed with `[CODEX]` are from Codex's tmux pane. Claude should:
1. Read the referenced question file
2. Investigate/answer the question
3. Write the response to the specified response file

This is similar to how Claude handles user messages — it just comes from a different source. The `[CODEX]` prefix makes it distinguishable.

**Deliverables:**
- [ ] `codex/skills/claude-cli/scripts/tmux-claude.sh` — question dispatch
- [ ] File-based handoff: question and response via files in `$STATE_DIR/messages/to-claude/`
- [ ] Non-blocking (returns immediately, Codex polls for response)

---

## Phase 4: Hook Updates

### 4.1 Updated `codex-gate.sh`

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

### 4.2 Updated `codex-trace.sh`

Same logic as today, but detects `tmux-codex.sh` output sentinels instead of `call_codex.sh`:

```bash
# Detect tmux-codex.sh invocations
echo "$command" | grep -qE '(^|[;&|] *)([^ ]*/)?tmux-codex\.sh' || exit 0

# Same sentinel detection as today:
# CODEX_REVIEW_RAN → create codex-ran marker
# CODEX APPROVED → create codex-approved marker
# CODEX REQUEST_CHANGES → create codex-ran marker only
# CODEX NEEDS_DISCUSSION → log only
```

The sentinel strings in `tmux-codex.sh` are identical to the current `call_codex.sh` / `codex-verdict.sh` output, so `codex-trace.sh` only needs the regex update. Evidence markers are created by the same hook, triggered by the same sentinels. The dual-layer defense (codex-ran + codex-approved) is preserved.

### 4.3 All other hooks — unchanged

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

## Phase 5: Documentation Updates

### 5.1 Updated Workflow Skills

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
   non-edit work while Codex reviews. Poll for the findings file path printed by the script.
```

Current step 8:
```
8. **Handle codex verdict** — Triage findings (see Finding Triage). Classify fix impact for tiered re-review. Signal verdict via `codex-verdict.sh`.
```

New step 8:
```
8. **Triage codex findings** — When the findings file appears:
   a. Read the FULL findings file (not just the summary)
   b. Triage each finding: blocking / non-blocking / out-of-scope
   c. Update issue ledger (reject re-raised closed findings, detect oscillation)
   d. If no blocking findings:
      ```bash
      ~/.claude/skills/codex-cli/scripts/tmux-codex.sh --approve
      ```
   e. If blocking findings need fixes: fix them, choose re-review tier:
      - Targeted swap (typo): run test-runner only → if pass, `tmux-codex.sh --approve`
      - Logic change: re-run critics → if approve, `tmux-codex.sh --re-review`
      - New export/signature: full cascade → `tmux-codex.sh --re-review`
   f. If unresolvable (max 3 iterations):
      ```bash
      ~/.claude/skills/codex-cli/scripts/tmux-codex.sh --needs-discussion "reason"
      ```
```

**`bugfix-workflow/SKILL.md`** — Same pattern: replace `call_codex.sh` with `tmux-codex.sh`, replace `codex-verdict.sh` with `tmux-codex.sh --approve/--re-review/--needs-discussion`.

**`codex-cli/SKILL.md`** — Full rewrite: describe the tmux-based invocation pattern, file-based handoff, polling, and all modes. Document that `--review` and `--prompt` are non-blocking.

### 5.2 Updated Rules

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

### 5.3 Updated Settings

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

## Phase 6: Testing

### 6.1 Test Infrastructure

Shell-based test harness. Mock agents simulate Claude and Codex behavior.

**`mock-claude.sh`:**
```bash
# Simulates Claude Code responses
# Reads from stdin, pattern-matches, writes expected output
while IFS= read -r line; do
  case "$line" in
    *"[CODEX] Question waiting"*)
      # Extract file paths and respond
      question_file=$(echo "$line" | grep -oP 'Read: \K\S+')
      response_file=$(echo "$line" | grep -oP 'Write response to: \K\S+')
      echo "Mock Claude answering question from $question_file"
      echo "The database uses a pooled connection with max 10 connections." > "$response_file"
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
# Reads from stdin, writes findings to specified files
REVIEWS_BEFORE_APPROVE="${MOCK_REVIEWS:-3}"
review_count=0

while IFS= read -r line; do
  case "$line" in
    *"review request at"*)
      ((review_count++))
      # Read prompt file to find findings file path
      prompt_file=$(echo "$line" | grep -oP 'at \K\S+')
      findings_file=$(grep 'Write your complete findings to:' "$prompt_file" | grep -oP ': \K\S+')
      if (( review_count >= REVIEWS_BEFORE_APPROVE )); then
        echo '{"findings":[],"summary":"All issues addressed.","stats":{"blocking_count":0,"non_blocking_count":0,"files_reviewed":5}}' > "$findings_file"
      else
        echo '{"findings":[{"id":"F1","file":"src/auth.ts","line":42,"severity":"blocking","category":"correctness","description":"Missing null check","suggestion":"Add null guard"}],"summary":"Found 1 blocking issue.","stats":{"blocking_count":1,"non_blocking_count":0,"files_reviewed":5}}' > "$findings_file"
      fi
      echo "REVIEW_COMPLETE"
      ;;
  esac
done
```

### 6.2 Test Cases

**Session tests (`test-party.sh`):**
- [ ] `party.sh` creates tmux session with 2 panes
- [ ] `party.sh --raw` works without iTerm2
- [ ] `party.sh --stop` cleanly tears down session and state dir
- [ ] State directory has correct subdirectories

**Claude→Codex tests (`test-tmux-codex.sh`):**
- [ ] `--review` generates diff, writes prompt file, sends to Codex pane
- [ ] `--review` returns immediately (non-blocking)
- [ ] `--prompt` writes prompt file, sends to Codex pane
- [ ] `--approve` outputs correct sentinel string
- [ ] `--re-review` outputs correct sentinel string
- [ ] `--needs-discussion` outputs correct sentinel string
- [ ] Script fails gracefully when no party session exists

**Codex→Claude tests (`test-tmux-claude.sh`):**
- [ ] Question file written correctly
- [ ] Message sent to Claude pane
- [ ] Script returns immediately (non-blocking)
- [ ] Script fails gracefully when no party session exists

**Hook tests (`test-hooks.sh`):**
- [ ] `codex-gate.sh` blocks `tmux-codex.sh --review` without critic markers
- [ ] `codex-gate.sh` allows `tmux-codex.sh --review` with critic markers
- [ ] `codex-gate.sh` blocks `tmux-codex.sh --approve` without codex-ran marker
- [ ] `codex-trace.sh` creates codex-ran marker on CODEX_REVIEW_RAN sentinel
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

## Phase 7: Installation & Migration

### 7.1 Installer

Adapted from `ai-config/install.sh`. Symlinks the new `claude/` and `codex/` directories:

```bash
# Option A: replace ai-config entirely
./install.sh                    # Creates ~/.claude → ai-config-tmux/claude, ~/.codex → ai-config-tmux/codex

# Option B: install alongside (both systems available)
./install.sh --alongside        # Creates ~/.claude-tmux → ai-config-tmux/claude
                                # User switches by re-symlinking ~/.claude
```

### 7.2 iTerm2 Keybindings

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
| `Cmd+Shift+K` | Send Text: `party.sh --stop\n` | Kill the current party session |

### 7.3 Migration path

```
Week 1:   Build session launcher (Phase 1) + tmux-codex.sh (Phase 2) + tmux-claude.sh (Phase 3)
Week 2:   Update hooks (Phase 4) + documentation (Phase 5)
Week 3:   Testing (Phase 6) + installation (Phase 7)
Week 4:   Integration testing with real agents, side-by-side evaluation
          → Decision: adopt tmux, stay with CLI, or hybrid
```

**Rollback:** `ln -sf ~/ai-config/claude ~/.claude` — instant revert to subprocess model.

---

## Risk Register

| Risk | Severity | Mitigation |
|------|----------|------------|
| Codex ignores file-write instruction | Medium | Prompt engineering in review template; fall back to `tmux capture-pane` |
| Large diff exceeds tmux send-keys limit | Low | Already mitigated: diff written to file, Codex told to read the file |
| `[CODEX]` message confused with user input | Low | Distinctive prefix; documented in CLAUDE.md |
| Agent crashes | Medium | User can see both panes; restart agent manually or re-run `party.sh` |
| Race condition: code edit during Codex review | Medium | `marker-invalidate.sh` still fires on Edit/Write — same as today |
| Codex `--sandbox read-only` can't write to `/tmp/` | High | Test this first; if blocked, use `workspace-write` or capture pane output |
| Claude rubber-stamps --approve without reading findings | Medium | Same risk as today; mitigated by `codex-gate.sh` (gate 2: codex-ran required) and SKILL.md instructions |
| Polling for findings file is wasteful | Low | 5-second poll is cheap; could use `fswatch` for instant detection |
| Codex takes too long, Claude forgets to check | Low | Claude's skill docs include polling instructions; could add a timeout reminder |

---

## Success Criteria

1. **Full review cycle works:** Claude implements → critics → `tmux-codex.sh --review` → Codex writes findings → Claude reads → triages → `tmux-codex.sh --approve` → markers created → PR
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
12. **Rollback works:** Single symlink change reverts to subprocess model

---

## Appendix A: File Copy Manifest

### Copy unchanged (no modifications)

```bash
# Hooks that work identically
cp ai-config/claude/hooks/session-cleanup.sh    ai-config-tmux/claude/hooks/
cp ai-config/claude/hooks/skill-eval.sh         ai-config-tmux/claude/hooks/
cp ai-config/claude/hooks/worktree-guard.sh     ai-config-tmux/claude/hooks/
cp ai-config/claude/hooks/agent-trace.sh        ai-config-tmux/claude/hooks/
cp ai-config/claude/hooks/marker-invalidate.sh  ai-config-tmux/claude/hooks/
cp ai-config/claude/hooks/skill-marker.sh       ai-config-tmux/claude/hooks/
cp ai-config/claude/hooks/pr-gate.sh            ai-config-tmux/claude/hooks/

# Agent definitions (sub-agents unchanged)
cp -r ai-config/claude/agents/                  ai-config-tmux/claude/agents/

# Technology rules (unchanged)
cp -r ai-config/claude/rules/backend/           ai-config-tmux/claude/rules/backend/
cp -r ai-config/claude/rules/frontend/          ai-config-tmux/claude/rules/frontend/

# Skills that don't reference codex invocation
cp -r ai-config/claude/skills/pre-pr-verification/  ai-config-tmux/claude/skills/
cp -r ai-config/claude/skills/write-tests/           ai-config-tmux/claude/skills/
cp -r ai-config/claude/skills/code-review/           ai-config-tmux/claude/skills/

# Scripts (status line, etc.)
cp -r ai-config/claude/scripts/                 ai-config-tmux/claude/scripts/

# Shared skills (unchanged)
cp -r ai-config/shared/                         ai-config-tmux/shared/

# Codex rules (unchanged)
cp -r ai-config/codex/rules/                    ai-config-tmux/codex/rules/

# Codex planning skill (unchanged)
cp -r ai-config/codex/skills/planning/          ai-config-tmux/codex/skills/planning/
```

### Copy and modify

```
ai-config/claude/CLAUDE.md → ai-config-tmux/claude/CLAUDE.md
  Edits: Replace "call_codex.sh" → "tmux-codex.sh"
         Replace "codex-verdict.sh" → "tmux-codex.sh --approve/--re-review/--needs-discussion"
         Add tmux context section
         Add [CODEX] message convention
         Add verdict authority note

ai-config/claude/settings.json → ai-config-tmux/claude/settings.json
  Edits: Replace permission lines (call_codex.sh/codex-verdict.sh → tmux-codex.sh)

ai-config/claude/hooks/codex-gate.sh → ai-config-tmux/claude/hooks/codex-gate.sh
  Edits: Regex: call_codex.sh → tmux-codex.sh
         Regex: codex-verdict.sh → tmux-codex.sh

ai-config/claude/hooks/codex-trace.sh → ai-config-tmux/claude/hooks/codex-trace.sh
  Edits: Regex: call_codex.sh → tmux-codex.sh
         Regex: codex-verdict.sh → tmux-codex.sh

ai-config/claude/rules/execution-core.md → ai-config-tmux/claude/rules/execution-core.md
  Edits: call_codex.sh → tmux-codex.sh, codex-verdict.sh → tmux-codex.sh --approve

ai-config/claude/rules/autonomous-flow.md → ai-config-tmux/claude/rules/autonomous-flow.md
  Edits: call_codex.sh → tmux-codex.sh, codex-verdict.sh → tmux-codex.sh --approve

ai-config/claude/skills/task-workflow/SKILL.md → ai-config-tmux/claude/skills/task-workflow/SKILL.md
  Edits: Step 7 + 8 rewritten (see Phase 5.1)

ai-config/claude/skills/bugfix-workflow/SKILL.md → ai-config-tmux/claude/skills/bugfix-workflow/SKILL.md
  Edits: Codex steps rewritten (see Phase 5.1)

ai-config/codex/AGENTS.md → ai-config-tmux/codex/AGENTS.md
  Edits: Add tmux context section (see Phase 5.2)

ai-config/codex/config.toml → ai-config-tmux/codex/config.toml
  Edits: None needed (sandbox mode set at launch)
```

### Do NOT copy (replaced entirely)

```
ai-config/claude/skills/codex-cli/scripts/call_codex.sh    → REPLACED BY: tmux-codex.sh
ai-config/claude/skills/codex-cli/scripts/codex-verdict.sh → MERGED INTO: tmux-codex.sh --approve/--re-review/--needs-discussion
ai-config/codex/skills/claude-cli/scripts/call_claude.sh   → REPLACED BY: tmux-claude.sh
```

### New files (don't exist in ai-config)

```
ai-config-tmux/session/party.sh                                # Session launcher (Phase 1)
ai-config-tmux/claude/skills/codex-cli/scripts/tmux-codex.sh   # Claude→Codex (Phase 2)
ai-config-tmux/claude/skills/codex-cli/SKILL.md                # Rewritten skill doc (Phase 5)
ai-config-tmux/codex/skills/claude-cli/scripts/tmux-claude.sh  # Codex→Claude (Phase 3)
ai-config-tmux/codex/skills/claude-cli/SKILL.md                # Rewritten skill doc (Phase 5)

ai-config-tmux/tests/test-party.sh              # Session tests (Phase 6)
ai-config-tmux/tests/test-tmux-codex.sh         # Claude→Codex tests (Phase 6)
ai-config-tmux/tests/test-tmux-claude.sh        # Codex→Claude tests (Phase 6)
ai-config-tmux/tests/test-hooks.sh              # Hook tests (Phase 6)
ai-config-tmux/tests/test-integration.sh        # Integration tests (Phase 6)
ai-config-tmux/tests/mock-claude.sh             # Mock Claude (Phase 6)
ai-config-tmux/tests/mock-codex.sh              # Mock Codex (Phase 6)
ai-config-tmux/tests/run-tests.sh               # Test runner (Phase 6)

ai-config-tmux/install.sh                       # Installer (Phase 7)
```

---

## Appendix B: Dependencies

| Dependency | Required | Install | Purpose |
|-----------|----------|---------|---------|
| `tmux` | Yes | `brew install tmux` | Terminal multiplexer — core infrastructure |
| `jq` | Yes | `brew install jq` | JSON parsing for hook input |
| `claude` | Yes | `curl -fsSL https://cli.anthropic.com/install.sh \| sh` | Claude Code CLI |
| `codex` | Yes | `brew install --cask codex` | Codex CLI |
| iTerm2 | Recommended | `brew install --cask iterm2` | Terminal with native tmux integration. Raw tmux works without it |

Note: `fswatch` is no longer needed — there's no coordinator daemon watching for signal files. Claude and Codex poll for response files directly.
