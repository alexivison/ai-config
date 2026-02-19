---
name: codex-cli
description: Invoke Codex CLI for deep reasoning, review, and analysis
user-invocable: false
---

# Codex CLI — Direct Invocation

## Safety

- Sandbox always defaults to `read-only` (never `workspace-write`).
- `codex exec review`: inherently read-only (no sandbox flag needed).
- Timeout: 300s default via portable wrapper (`gtimeout` > `timeout` > none).

## Command Patterns

### Code Review

```bash
~/.claude/skills/codex-cli/scripts/call_codex.sh \
  --review --base main --title "{PR title or change summary}"
```

- Uses `codex exec review` with built-in GPT-5.3 review logic — no custom prompt needed.
- `--base main` diffs current branch against `main` (uses merge-base).
- `--title` gives GPT-5.3 context about the intent of the changes.
- Output: review findings as plain text (jq extracts final agent message internally).

### Architecture Analysis

```bash
~/.claude/skills/codex-cli/scripts/call_codex.sh \
  --prompt "TASK: Architecture analysis. SCOPE: {files/modules}. EVALUATE: 1) Pattern consistency 2) Coupling/cohesion 3) Complexity hotspots. OUTPUT: Findings with file:line refs, then verdict."
```

### Plan Review

```bash
~/.claude/skills/codex-cli/scripts/call_codex.sh \
  --prompt "TASK: Plan review. PLAN: {summary}. CHECKLIST: 1) Data flow mapped? 2) Standards referenced? 3) Cross-task scope explicit? 4) Bug prevention covered? OUTPUT: Pass/fail per item, then verdict."
```

### Design Decision

```bash
~/.claude/skills/codex-cli/scripts/call_codex.sh \
  --prompt "TASK: Design comparison. OPTIONS: A) {option_a} B) {option_b}. CRITERIA: 1) Complexity 2) Maintainability 3) Performance 4) Risk. OUTPUT: Pros/cons matrix, recommendation."
```

### Debugging

```bash
~/.claude/skills/codex-cli/scripts/call_codex.sh \
  --prompt "TASK: Error analysis. ERROR: {error_message}. CONTEXT: {file:line, stack trace}. ANALYZE: 1) Root cause 2) Contributing factors 3) Fix options. OUTPUT: Diagnosis with evidence, ranked fixes."
```

## Prompt Template Rules

- **Always use TASK/SCOPE/OUTPUT structure** — gives GPT-5.3 clear framing.
- **Fill all slots** before invocation — `{placeholders}` must be replaced with actual values.
- **Never paraphrase** as a bare sentence — always decompose into structured fields.
- **Keep prompts under 300 chars** — concise prompts reduce drift.

## Execution

1. Gather context — determine base branch, read domain rules from `claude/rules/` or `.claude/rules/`
2. Build prompt using structured template (review mode needs no prompt)
3. Invoke synchronously with `timeout: 300000` — **NEVER** use `run_in_background: true`
4. Read and analyze the complete Codex output
5. Decide verdict based on findings

## Verdict Protocol

After analyzing Codex output, signal the verdict via a **separate** Bash call:

```bash
~/.claude/skills/codex-cli/scripts/codex-verdict.sh approve
```

Valid verdicts: `approve`, `request_changes`, `needs_discussion`.

**CRITICAL:** `codex-verdict.sh` and `gh pr create` must be **separate Bash calls**, never chained with `&&`. The PR gate fires at PreToolUse before any command executes — a chained call would be denied before the marker is written.

### When to approve

- No bugs, security issues, or architectural concerns found
- All prior feedback addressed (on iteration 2+)

### When to request changes

- Bugs, security issues, or architectural misfit found
- Provide specific file:line references

### When to escalate (needs_discussion)

- Multiple valid approaches, unclear which is correct
- Findings contradict project conventions
- After 5 iterations without resolution

## Iteration

- Max 5 iterations, then NEEDS_DISCUSSION.
- On iteration 2+: verify previous issues addressed, check for new issues.
- Do NOT re-run after convention/style fixes from critics — only after logic or structural changes.
