---
name: claude-transport
description: Communicate with Claude via tmux for codebase investigation, review notifications, and multi-turn dialogue.
---

# claude-transport — Communicate with Claude via tmux

## When to contact Claude

- **During review**: After writing findings to the file, notify Claude that review is complete
- **During planning**: When you need codebase context that would require extensive exploration
  (e.g., "how does the auth middleware chain work?", "what calls this function?")
- **During tasks**: When you need Claude to investigate something in parallel

## How to contact the other agent

Choose the transport by your current role:

- **Companion role**: `~/.codex/skills/claude-transport/scripts/tmux-claude.sh "<message>"`
- **Primary role**: `~/.codex/skills/claude-transport/scripts/tmux-codex.sh --prompt "<task or question>" "$(pwd)"`

Both paths are role-aware. New sessions use `[PRIMARY]` / `[COMPANION]`; legacy sessions still use `[CLAUDE]` / `[CODEX]`.

## Visibility rule (required)

After every outbound `tmux-claude.sh` message, immediately post a short digest in the local chat.

Digest format:
- what you sent (one sentence)
- handshake summary (required when a handoff file is referenced): 2-4 bullets summarizing what was written to the file

Handshake summary rules:
1. If the outbound message references a response/findings file path (for example `.toon`), read that file first.
2. Include 2-4 concise bullets with the key content (for findings: top issues and severity counts).
3. If the file is missing or unreadable, state that explicitly in the digest.

Do not skip this. The user must be able to follow Codex-Paladin coordination without reading tmux panes.

## Message conventions

### Notify review complete
After writing findings to the specified file:
```bash
~/.codex/skills/claude-transport/scripts/tmux-claude.sh "Review complete. Findings at: <findings_file>"
```

### Ask a question
When you need information from the other agent:
```bash
RESPONSE_FILE="$STATE_DIR/response-$(date +%s%N).toon"
~/.codex/skills/claude-transport/scripts/tmux-claude.sh "Question: <your question>. Write response to: $RESPONSE_FILE"
```

If you are the primary agent, send the same request via:
```bash
~/.codex/skills/claude-transport/scripts/tmux-codex.sh --prompt "Question: <your question>. Write response to: $RESPONSE_FILE" "$(pwd)"
```

After sending a request with a response file, do not poll the file as though it were already the answer. Wait for the companion's completion notice (`Task complete. Response at:`; legacy `Response ready at:` is still accepted), then read the file and relay the result. That notice is the stop signal.

If you need structured findings rather than narrative prose, say so explicitly and have Claude emit canonical TOON via `~/.claude/skills/codex-transport/scripts/toon-transport.sh`. A `.toon` response path alone does not guarantee a structured payload.

### Notify plan review complete
After writing plan-review findings to the specified `.toon` file:
```bash
~/.codex/skills/claude-transport/scripts/tmux-claude.sh "Plan review complete. Findings at: <findings_file>"
```

### Report task completion
After completing a delegated task:
```bash
~/.codex/skills/claude-transport/scripts/tmux-claude.sh "Task complete. Response at: <response_file>"
```

If you are the primary agent and need to notify the companion instead, use:
```bash
~/.codex/skills/claude-transport/scripts/tmux-codex.sh --prompt "Task complete. Response at: <response_file>" "$(pwd)"
```

## Handling Claude's responses

When you see a message in your pane from Claude (e.g., "Task complete. Response at: <path>"):
1. Read the response file
2. Incorporate the answer into your current work
3. Continue — you have full context of what you were doing before asking

## Important

- Each exchange creates unique timestamped files — multi-turn dialogue works naturally
- You retain your full context across exchanges (persistent tmux session)
- Keep questions specific and actionable — Claude will investigate the codebase for you
- `.toon` is the transport-file convention. It implies canonical TOON only when the request explicitly asks for structured findings.
- Do NOT ask Claude to make code changes. You make changes, Claude reviews.
- Always post the required local digest after messaging Claude.
