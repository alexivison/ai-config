---
name: codex-transport
description: >-
  Transport layer for communicating with Codex CLI via tmux. Provides modes for
  code review (--review), plan review (--plan-review), ad-hoc tasks (--prompt),
  review evidence (--review-complete), and verdict signaling (--approve,
  --needs-discussion). Use whenever dispatching work to Codex, recording review
  evidence, or signaling completion after triaging findings.
user-invocable: false
---

# codex-transport — Communicate with Codex via tmux

## When to contact Codex

- **For code review**: After implementing changes and passing sub-agent critics, request Codex review
- **For tasks**: When you need Codex to investigate or work on something in parallel
- **For verdict**: After triaging Codex's findings, signal your decision

## How to contact Codex

Use the transport script:
```bash
~/.claude/skills/codex-transport/scripts/tmux-codex.sh <mode> [args...]
```

## Modes

### Request code review (non-blocking)
After implementing changes and passing sub-agent critics:
```bash
~/.claude/skills/codex-transport/scripts/tmux-codex.sh --review <work_dir> [base_branch] ["PR title"]
```
`work_dir` is **REQUIRED** — the absolute path to the worktree or repo where changes live. The script will error if omitted. Codex's pane is in a different directory; it needs this to `cd` into the correct location. `base_branch` defaults to `main`, `PR title` defaults to `Code review`.

This sends a message to Codex's pane. You are NOT blocked — continue with non-edit work while Codex reviews. Codex will notify you via `[CODEX] Review complete. Findings at: <path>` when done. Findings are TOON format (`.toon` file). Handle that message per your `tmux-handler` skill.

### Request plan review (non-blocking)
After creating a plan:
```bash
~/.claude/skills/codex-transport/scripts/tmux-codex.sh --plan-review "<plan_path>" <work_dir>
```
`work_dir` is **REQUIRED**. Plan review is advisory — it is intentionally ungated by critic markers and does NOT create or reuse the `codex-ran` approval marker. Codex will notify via `[CODEX] Plan review complete. Findings at: <path>` when done. Findings are TOON format (`.toon` file).

### Send a task (non-blocking)
**IMPORTANT:** Prompts with quotes, backticks, or >500 characters risk `unmatched '` shell errors when passed inline. Write to a temp file first:
```bash
cat > /tmp/codex-prompt.md << 'EOF'
Your long prompt here...
EOF
~/.claude/skills/codex-transport/scripts/tmux-codex.sh --prompt "$(cat /tmp/codex-prompt.md)" /path/to/repo
```

Short prompts can be passed directly:
```bash
~/.claude/skills/codex-transport/scripts/tmux-codex.sh --prompt "<task description>" <work_dir>
```
`work_dir` is **REQUIRED**. Returns immediately. Codex will notify via `[CODEX] Task complete. Response at: <path>` when done. Response is TOON format (`.toon` file).

### Record review completion evidence
**CRITICAL:** The argument is the **full path to the `.toon` findings file** from the `[CODEX] Review complete. Findings at: <path>` notification — NOT a worktree path. Passing a worktree path will fail with "Findings file not found."

```bash
~/.claude/skills/codex-transport/scripts/tmux-codex.sh --review-complete "<findings_file>"
```
This preserves the existing evidence-chain invariant: `CODEX_REVIEW_RAN` means a completed review, not merely a queued request. The file existence check is extension-agnostic.

### Signal verdict (after triaging findings)
```bash
# All findings non-blocking — approve
~/.claude/skills/codex-transport/scripts/tmux-codex.sh --approve

# Unresolvable after max iterations
~/.claude/skills/codex-transport/scripts/tmux-codex.sh --needs-discussion "reason"
```

**Blocking findings?** Fix the code, re-run critics, then dispatch a new `--review`. Editing code auto-invalidates all markers (via `marker-invalidate.sh`), so the full cascade re-runs naturally. There is no shortcut — the gates enforce it.

## Important

- `--review`, `--plan-review`, and `--prompt` are NON-BLOCKING. Continue working while Codex processes.
- `--review-complete` emits `CODEX_REVIEW_RAN` only after findings exist.
- Verdict modes (`--approve`, `--needs-discussion`) are instant — they output sentinels for hook detection.
- You decide the verdict. Codex produces findings, you triage them.
- Before calling `--review`, ensure sub-agent critics have passed (codex-gate.sh enforces this).
- Before calling `--approve`, ensure codex-ran marker exists (codex-gate.sh enforces this).
- `--plan-review` is ungated — no critic markers or codex-ran markers required or affected.
- **Blocking codex findings:** fix code → (markers auto-invalidated) → re-run critics → new `--review` → `--review-complete` → `--approve`. No special flag needed.
