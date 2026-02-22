---
name: codex-cli
description: Invoke Codex CLI for deep reasoning, review, and analysis
user-invocable: false
---

# codex-cli — Communicate with Codex via tmux

## When to contact Codex

- **For code review**: After implementing changes and passing sub-agent critics, request Codex review
- **For tasks**: When you need Codex to investigate or work on something in parallel
- **For verdict**: After triaging Codex's findings, signal your decision

## How to contact Codex

Use the transport script:
```bash
~/.claude/skills/codex-cli/scripts/tmux-codex.sh <mode> [args...]
```

## Modes

### Request review (non-blocking)
After implementing changes and passing sub-agent critics:
```bash
~/.claude/skills/codex-cli/scripts/tmux-codex.sh --review <base_branch> "<PR title>"
```
This sends a message to Codex's pane. You are NOT blocked — continue with non-edit work while Codex reviews. Codex will notify you via `[CODEX] Review complete. Findings at: <path>` when done. Handle that message per your `tmux-handler` skill.

### Send a task (non-blocking)
```bash
~/.claude/skills/codex-cli/scripts/tmux-codex.sh --prompt "<task description>"
```
Returns immediately. Codex will notify you when done.

### Record review completion evidence
After Codex notifies you that findings are ready:
```bash
~/.claude/skills/codex-cli/scripts/tmux-codex.sh --review-complete "<findings_file>"
```
This preserves the existing evidence-chain invariant: `CODEX_REVIEW_RAN` means a completed review, not merely a queued request.

### Signal verdict (after triaging findings)
```bash
# All findings non-blocking — approve
~/.claude/skills/codex-cli/scripts/tmux-codex.sh --approve

# Blocking findings fixed, request re-review
~/.claude/skills/codex-cli/scripts/tmux-codex.sh --re-review "what was fixed"

# Unresolvable after max iterations
~/.claude/skills/codex-cli/scripts/tmux-codex.sh --needs-discussion "reason"
```
Verdict modes output sentinel strings that hooks detect to create evidence markers.

## Important

- `--review` and `--prompt` are NON-BLOCKING. Continue working while Codex processes.
- `--review-complete` emits `CODEX_REVIEW_RAN` only after findings exist.
- Verdict modes (`--approve`, `--re-review`, `--needs-discussion`) are instant — they output sentinels for hook detection.
- You decide the verdict. Codex produces findings, you triage them.
- Before calling `--review`, ensure sub-agent critics have passed (codex-gate.sh enforces this).
- Before calling `--approve`, ensure codex-ran marker exists (codex-gate.sh enforces this).
