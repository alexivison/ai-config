---
name: tmux-handler
description: >-
  Handle incoming [CODEX] messages from The Wizard via tmux. Covers review completion,
  questions, task results, and plan review findings in TOON format. Triggers whenever
  a [CODEX] prefixed message appears — review complete notifications, questions from
  The Wizard, task completion notices, or plan review results. Use this skill to correctly
  parse, validate, triage, and respond to any Wizard communication.
user-invocable: false
---

# tmux-handler — Handle incoming messages from The Wizard via tmux

## Trigger

You see a message in your pane prefixed with `[CODEX]`. These are from Codex's tmux pane.

## TOON findings format

Codex findings files use TOON format.

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
4. If malformed: record validation issue, request re-emit from Codex via `--prompt`, OR triage manually as plain text if urgent

### Helper workflow

When Bash is available, prefer the shared transport helper over manual TOON parsing or emission.

Use `~/.claude/skills/codex-transport/scripts/toon-transport.sh`:

- Decode a TOON findings file to JSON:
  `~/.claude/skills/codex-transport/scripts/toon-transport.sh decode <findings_file>`
- Validate a TOON findings file:
  `~/.claude/skills/codex-transport/scripts/toon-transport.sh validate-findings <findings_file>`
- Encode canonical findings JSON to raw TOON:
  `~/.claude/skills/codex-transport/scripts/toon-transport.sh encode-findings /tmp/findings.json <findings_file>`

## Transport direction

| Agent calling | Script to use | Direction |
|---|---|---|
| Claude | `tmux-codex.sh` | Claude → Codex |
| Codex | `tmux-claude.sh` | Codex → Claude |

## Message types

### Review complete
Message: `[CODEX] Review complete. Findings at: <path>`

1. Read the FULL findings file (TOON format) with your Read tool or decode it via the helper workflow above
2. Validate per the triage checklist above (or via `validate-findings`)
3. Mark review evidence as complete:
   `tmux-codex.sh --review-complete <path>`
4. Triage each finding: blocking / non-blocking / out-of-scope
5. Update your issue ledger (reject re-raised closed findings, detect oscillation)
6. The verdict comes from the `VERDICT:` line Codex wrote in the findings file — `--review-complete` reads it automatically:
   - `VERDICT: APPROVED` in findings → approval evidence created
   - `VERDICT: REQUEST_CHANGES` → no approval evidence; fix code, re-run critics, dispatch new `--review` → `--review-complete`
   - Unresolvable → `tmux-codex.sh --needs-discussion "reason"`
   - **Do NOT call `--approve` directly** — the gate blocks it.

### Question from Codex
Message: `[CODEX] Question: <question>. Write response to: <response_file>`

1. Read the question
2. Investigate the codebase to answer the question
3. **Structured findings response**: When Codex requests structured findings and provides a `.toon` response path, emit canonical TOON with the helper workflow above — not markdown tables. Codex (the requester) controls the extension; write to the exact path provided.
4. **Narrative Q&A**: When the request is conversational, write concise text to the provided path. A `.toon` extension alone does not force a structured TOON payload.
5. Notify Codex: `tmux-codex.sh --prompt "Response ready at: <response_file>" "$(pwd)"`

### Task complete
Message: `[CODEX] Task complete. Response at: <path>`

1. Read the response file. If the original request asked for structured findings, expect TOON; otherwise treat it as plain text.
2. Continue your workflow with the information Codex provided

### Plan review complete
Message: `[CODEX] Plan review complete. Findings at: <path>`

1. Read the findings file (TOON format), preferably via the helper workflow above
2. Validate per the triage checklist above
3. Triage findings same as code review (blocking / non-blocking / out-of-scope)
4. Incorporate feedback into the plan

## Dispute Resolution

When Codex or critics return out-of-scope findings or NEEDS_DISCUSSION, follow the dispute resolution protocol in [execution-core.md § Dispute Resolution](~/.claude/rules/execution-core.md#dispute-resolution). Key points: critic disputes re-run with context (max 2 dispute rounds before user escalation), Codex disputes use `--dispute <file>` with `--review`, NEEDS_DISCUSSION debates via `--prompt`. **Codex has no dispute round cap** — continue until Codex approves or both agents agree human input is needed. After resolution, a fresh `--review` → `--review-complete` is still required for gate evidence.
