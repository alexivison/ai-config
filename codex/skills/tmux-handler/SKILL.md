---
name: tmux-handler
description: Handle incoming messages from the primary agent via tmux — review requests, task requests, plan reviews, and questions.
---

# tmux-handler — Handle incoming messages from the Primary Agent via tmux

## Trigger

You see a message in your pane prefixed with `[PRIMARY]`, `[COMPANION]`, `[CLAUDE]`, or `[CODEX]`. These are from the other agent's tmux pane.

## Reply direction

Choose the transport by your current role:

- If you are **companion**: `~/.codex/skills/agent-transport/scripts/tmux-primary.sh "<message>"`
- If you are **primary**: `~/.codex/skills/agent-transport/scripts/tmux-companion.sh --prompt "<message>" "$(pwd)"`

## TOON findings format

All structured findings (code review, plan review) use TOON format.

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

### Rules

- Field order is fixed: `id,file,line,severity,category,description,suggestion`.
- `line` MUST be an unquoted integer.
- `description` and `suggestion` MUST be quoted when they contain commas, colons, quotes, backslashes, or control characters.
- Quoted strings use TOON escaping: `\\`, `\"`, `\n`, `\r`, `\t`.
- `findings[N]` MUST equal the actual row count.
- Findings files contain raw TOON only. Do NOT wrap file contents in markdown fences.

### Helper workflow

When Bash is available, do not hand-type structured TOON.

Use `~/.codex/skills/agent-transport/scripts/toon-transport.sh`:

- Encode canonical findings JSON to raw TOON:
  `~/.codex/skills/agent-transport/scripts/toon-transport.sh encode-findings /tmp/findings.json <findings_file>`
- Decode a TOON findings file to JSON for inspection:
  `~/.codex/skills/agent-transport/scripts/toon-transport.sh decode <findings_file>`
- Validate a TOON findings file:
  `~/.codex/skills/agent-transport/scripts/toon-transport.sh validate-findings <findings_file>`

Preferred emission flow:
1. Draft findings as canonical JSON in a temp file.
2. Run `encode-findings` to produce the final `.toon` file.
3. If uncertain, run `validate-findings` before notifying the primary agent.

## Transport direction

| Agent calling | Script to use | Direction |
|---|---|---|
| Primary agent (default: Claude) | `tmux-companion.sh` | primary → companion |
| Companion agent (default: Codex) | `tmux-primary.sh` | companion → primary |

## Message types

### Review request
Message asks you to review changes against a base branch.

Default priority for review findings (highest first):
1. Correctness and regression risk
2. Unnecessary complexity / over-abstraction
3. Simpler equivalent approach
4. Style and preference nits (only when explicitly requested)

1. **Get the diff**: Run `git diff $(git merge-base HEAD <base>)..HEAD` to see the changes
2. **Review scope**: Review changed files AND adjacent files (callers, callees, types, tests)
   for: correctness bugs, crash/regression paths, security issues, wrong output, and avoidable complexity
3. **Classify each finding**:
   - **blocking**: correctness bug, crash/regression path, wrong output, security HIGH/CRITICAL
   - **non-blocking**: a materially simpler equivalent implementation that reduces complexity/risk
   - **omit by default**: style nits, naming preferences, minor consistency tweaks (include only if the primary agent explicitly asks for polish/nits)
4. **Write findings** to the file path specified in the message, using the helper workflow above whenever Bash is available.
5. **Do NOT include a "verdict" field.** You produce findings — the verdict is the primary agent's decision.
6. **Notify the other agent** when done, using the reply direction above.

### Re-review request
The primary agent fixed blocking issues and requests another pass.

- Verify previous blocking issues were addressed
- Flag only genuinely NEW blocking/non-blocking issues
- Do NOT re-raise findings that were already addressed
- Do not introduce new nit-level churn in re-review unless explicitly requested

### Task request
The primary agent asks you to investigate or work on something.

1. Perform the requested task
2. Write results to the file path specified (if given)
3. Notify the other agent using the reply direction above.

### NEEDS_DISCUSSION debate (via --prompt)
The primary agent sends a structured position on a disputed finding — either from your review or a critic's.

1. Read the primary agent's position: it will state concede, counter-argue, or propose compromise, with evidence
2. Evaluate the evidence against the codebase:
   - If the primary agent's position is well-supported (concrete file:line, diff evidence) → **concede** explicitly
   - If the primary agent's position has gaps → **counter** with your own file:line evidence showing why the finding stands
   - If both positions have merit → **propose compromise** (e.g., "fix X but defer Y")
3. Responses must be evidence-based — "I still think this is wrong" without a file:line reference is not a valid counter
4. **No fixed exchange cap.** Continue the discussion — each round should make progress (concede valid points, counter with new evidence, or propose concrete compromises). If the discussion becomes genuinely circular (same arguments repeated 3+ times with no new evidence from either side), state your final position clearly so the primary agent can escalate to the user with both sides summarized
5. Write response to the specified path
6. Notify the other agent using the canonical completion notice `Task complete. Response at: <response_file>`. Legacy `Response ready at:` remains accepted on read, but do not emit it for new replies.

### Plan review request
The primary agent shares a plan and asks for your assessment.

1. Read the plan
2. Evaluate feasibility, risks, missing steps
3. Write feedback to the specified file using the TOON findings schema above (categories may include `architecture`, `feasibility`, `missing-step`). Prefer the helper workflow above over hand-typing TOON.
4. Notify the other agent using the reply direction above.

### Question from the Primary Agent
The primary agent asks for information or your opinion.

1. Read the question
2. Investigate the codebase or reason about the answer
3. **Structured findings response**: When the primary agent requests structured findings and provides a `.toon` response path, emit canonical TOON with the helper workflow above — not markdown.
4. **Narrative Q&A**: When the request is conversational, write concise text. A `.toon` extension alone does not mean the payload must be structured TOON.
5. Write response to the exact path the primary agent specified (do not change the extension).
6. Notify the other agent using the canonical completion notice `Task complete. Response at: <response_file>`. Legacy `Response ready at:` remains accepted on read, but do not emit it for new replies.
