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
Message: `[CODEX] Question: <question>. Write response to: <response_file>`

1. Read the question
2. Investigate the codebase to answer the question
3. Write your response to the specified response file
4. Notify Codex: `tmux-codex.sh --prompt "Response ready at: <response_file>"`

### Task complete
Message: `[CODEX] Task complete. Response at: <path>`

1. Read the response file
2. Continue your workflow with the information Codex provided

### Plan review complete
Message: `[CODEX] Plan review complete. Findings at: <path>`

1. Read the findings file
2. Triage findings same as code review
3. Incorporate feedback into the plan
