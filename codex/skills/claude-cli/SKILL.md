---
name: claude-cli
description: Communicate with Claude via tmux for codebase investigation, review notifications, and multi-turn dialogue.
---

# claude-cli — Communicate with Claude via tmux

## When to contact Claude

- **During review**: After writing findings to the file, notify Claude that review is complete
- **During planning**: When you need codebase context that would require extensive exploration
  (e.g., "how does the auth middleware chain work?", "what calls this function?")
- **During tasks**: When you need Claude to investigate something in parallel

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
