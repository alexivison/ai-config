---
name: tmux-handler
description: >-
  Handle incoming [CODEX] messages from Codex via tmux. Covers review completion,
  questions, task results, and plan review findings in TOON format. Triggers whenever
  a [CODEX] prefixed message appears — review complete notifications, questions from
  Codex, task completion notices, or plan review results. Use this skill to correctly
  parse, validate, triage, and respond to any Codex communication.
user-invocable: false
---

# tmux-handler — Handle incoming messages from Codex via tmux

## Trigger

You see a message in your pane prefixed with `[CODEX]`. These are from Codex's tmux pane.

## TOON findings format

Codex findings files use TOON format.

### Triage checklist

When reading a TOON findings file:
1. Validate header line matches `findings[N]{id,file,line,severity,category,description,suggestion}:`
2. Verify `[N]` equals the actual row count
3. Read `summary` and `stats` sections
4. If malformed: record validation issue, request re-emit from Codex via `--prompt`, OR triage manually as plain text if urgent

## Transport direction

| Agent calling | Script to use | Direction |
|---|---|---|
| Claude | `tmux-codex.sh` | Claude → Codex |
| Codex | `tmux-claude.sh` | Codex → Claude |

## Message types

### Review complete
Message: `[CODEX] Review complete. Findings at: <path>`

1. Read the FULL findings file (TOON format) with your Read tool
2. Validate per the triage checklist above
3. Mark review evidence as complete:
   `tmux-codex.sh --review-complete <path>`
4. Triage each finding: blocking / non-blocking / out-of-scope
5. Update your issue ledger (reject re-raised closed findings, detect oscillation)
6. Decide verdict:
   - All non-blocking → `tmux-codex.sh --approve`
   - Blocking findings → fix code, re-run critics, dispatch new `tmux-codex.sh --review`, then `--review-complete` → `--approve`
   - Unresolvable → `tmux-codex.sh --needs-discussion "reason"`

### Question from Codex
Message: `[CODEX] Question: <question>. Write response to: <response_file>`

1. Read the question
2. Investigate the codebase to answer the question
3. **Structured findings response**: When Codex requests structured findings and provides a `.toon` response path, emit TOON with the canonical findings schema — not markdown tables. Codex (the requester) controls the extension; write to the exact path provided.
4. **Narrative Q&A**: When the request is conversational, write concise text to the provided path.
5. Notify Codex: `tmux-codex.sh --prompt "Response ready at: <response_file>" "$(pwd)"`

### Task complete
Message: `[CODEX] Task complete. Response at: <path>`

1. Read the response file (TOON format)
2. Continue your workflow with the information Codex provided

### Plan review complete
Message: `[CODEX] Plan review complete. Findings at: <path>`

1. Read the findings file (TOON format)
2. Validate per the triage checklist above
3. Triage findings same as code review (blocking / non-blocking / out-of-scope)
4. Incorporate feedback into the plan
