---
name: tmux-handler
description: >-
  Handle incoming companion messages via tmux. Covers review completion,
  questions, task results, and plan review findings in TOON format. Triggers
  whenever a [COMPANION] prefixed message appears — review complete
  notifications, questions from the companion, task completion notices, or
  plan review results. Use this skill to correctly parse, validate, triage,
  and respond to companion communication.
user-invocable: false
---

# tmux-handler — Handle incoming messages from the Companion via tmux

## Trigger

You see a message in your pane prefixed with `[PRIMARY]` or `[COMPANION]`. These are from the other agent's tmux pane.

## Reply direction

Choose the transport by your current role:

- If you are **primary**: `~/.claude/skills/agent-transport/scripts/tmux-companion.sh --prompt "<message>" "$(pwd)"`
- If you are **companion**: `~/.claude/skills/agent-transport/scripts/tmux-primary.sh "<message>"`

## TOON findings format

Companion findings files use TOON format.

### Canonical schema

```toon
findings[N]{id,file,line,severity,category,description,suggestion}:
  F1,path/to/file.ts,42,blocking,correctness,"Description here","Suggestion here"
summary: One paragraph summary
stats:
  blocking_count: 0
  non_blocking_count: 0
  files_reviewed: 0
```

### Triage checklist

When reading a TOON findings file:
1. Validate header line matches `findings[N]{id,file,line,severity,category,description,suggestion}:`
2. Verify `[N]` equals the actual row count
3. Read `summary` and `stats` sections
4. If malformed: record validation issue, request re-emit from the companion via `--prompt`, OR triage manually as plain text if urgent

### Helper workflow

When Bash is available, prefer the shared transport helper over manual TOON parsing or emission.

Use `~/.claude/skills/agent-transport/scripts/toon-transport.sh`:

- Decode a TOON findings file to JSON:
  `~/.claude/skills/agent-transport/scripts/toon-transport.sh decode <findings_file>`
- Validate a TOON findings file:
  `~/.claude/skills/agent-transport/scripts/toon-transport.sh validate-findings <findings_file>`
- Encode canonical findings JSON to raw TOON:
  `~/.claude/skills/agent-transport/scripts/toon-transport.sh encode-findings /tmp/findings.json <findings_file>`

## Transport direction

| Agent calling | Script to use | Direction |
|---|---|---|
| Primary agent (default: Claude) | `tmux-companion.sh` | primary → companion |
| Companion agent (default: Codex) | `tmux-primary.sh` | companion → primary |

## Message types

### Review complete
Message: `[COMPANION] Review complete. Findings at: <path>`
1. Read the FULL findings file (TOON format) with your Read tool or decode it via the helper workflow above
2. Validate per the triage checklist above (or via `validate-findings`)
3. Mark review evidence as complete:
   `tmux-companion.sh --review-complete <path>`
4. Triage each finding: blocking / non-blocking / out-of-scope
5. Update your issue ledger (reject re-raised closed findings, detect oscillation)
6. The verdict comes from the `VERDICT:` line the companion wrote in the findings file — `--review-complete` reads it automatically:
   - `VERDICT: APPROVED` in findings → approval evidence created
   - `VERDICT: REQUEST_CHANGES` → no approval evidence; fix code, re-run critics, dispatch new `--review` → `--review-complete`
   - Unresolvable → `tmux-companion.sh --needs-discussion "reason"`
   - **Do NOT call `--approve` directly** — the gate blocks it.

### Question from the Companion
Message: `[COMPANION] Question: <question>. Write response to: <response_file>`
1. Read the question
2. Investigate the codebase to answer the question
3. **Structured findings response**: When the companion requests structured findings and provides a `.toon` response path, emit canonical TOON with the helper workflow above — not markdown tables. The requester controls the extension; write to the exact path provided.
4. **Narrative Q&A**: When the request is conversational, write concise text to the provided path. A `.toon` extension alone does not force a structured TOON payload.
5. Notify the other agent using the reply direction above. For file-based replies, use the canonical completion notice `Task complete. Response at: <response_file>`.

### Task complete
Message: `[COMPANION] Task complete. Response at: <path>`
1. Read the response file. If the original request asked for structured findings, expect TOON; otherwise treat it as plain text.
2. Stop polling once that notice arrives, then continue your workflow with the information the companion provided

### Plan review complete
Message: `[COMPANION] Plan review complete. Findings at: <path>`
1. Read the findings file (TOON format), preferably via the helper workflow above
2. Validate per the triage checklist above
3. Triage findings same as code review (blocking / non-blocking / out-of-scope)
4. Incorporate feedback into the plan

## Dispute Resolution

Follow execution-core.md § Dispute Resolution. Use `--dispute <file>` with `--review` for companion disputes, `--prompt` for NEEDS_DISCUSSION debates.
