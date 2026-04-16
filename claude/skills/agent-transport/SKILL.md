---
name: agent-transport
description: Shared wrapper path for the canonical role-based tmux transport skill.
user-invocable: false
---

# agent-transport

This agent-local path wraps the shared implementation at `shared/skills/agent-transport/`.

Prefer these scripts:

- `~/.claude/skills/agent-transport/scripts/tmux-companion.sh`
- `~/.claude/skills/agent-transport/scripts/tmux-primary.sh`
- `~/.claude/skills/agent-transport/scripts/toon-transport.sh`

Legacy `codex-transport` paths remain as thin compatibility wrappers during migration.
