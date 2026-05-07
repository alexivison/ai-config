# Pi Companion Support

Pi (`@mariozechner/pi-coding-agent`) is available as a third selectable `party-cli` provider. The default party remains Claude primary + Codex companion.

## Configure Pi

```bash
# Claude primary + Pi companion
party-cli config set-primary claude
party-cli config set-companion pi
./session/party.sh "review this change"

# Pi primary + Codex companion
party-cli config set-primary pi
party-cli config set-companion codex
./session/party.sh "work on this task"

# Restore defaults
party-cli config set-primary claude
party-cli config set-companion codex
```

Install Pi when needed:

```bash
npm install -g @mariozechner/pi-coding-agent
pi install npm:pi-subagents
```

## What works now

- `party-cli` can launch Pi as primary or companion using the normal role configuration.
- Pi panes receive the same master/worker/standalone party prompts as other providers.
- `party-cli read <session>` for Pi prefers the Pi activity sidecar:
  1. latest `recent` activity lines,
  2. then `snippet`,
  3. then cleaned raw tmux capture prefixed with `[raw Pi pane output — no usable activity sidecar]`.
- Pi resume UUIDs are read from sidecar `pi_session_id` or Pi `session_file` names shaped like `<timestamp>_<uuid>.jsonl`.
- `party-cli continue` persists the UUID into both `agents[].resume_id` and `pi_session_id`, then relaunches Pi with `--session` and `PI_SESSION_ID`.
- Reattaching to an already-running session keeps Pi resume capture best-effort so a missing or stale manifest does not block reattach.

## Limitations

- Manual end-to-end validation for the full Pi role-swap and transport matrix is still pending.
- Pi panes do not run the Claude/Codex hook chain, evidence capture, PR gate, or governance checks.
- Pi-specific hooks, skills, subagents, MCP, and evidence integrations are out of scope for this third-agent milestone.
- Raw-pane `read` fallback is intentionally best-effort. Prefer the activity sidecar output when available.
- Use Pi panes at your own risk for governed work. Prefer the default Claude+Codex layout when hook/evidence enforcement is required.

Track remaining validation in [`docs/projects/pi-third-agent/PLAN.md`](projects/pi-third-agent/PLAN.md).
