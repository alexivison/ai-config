---
name: call-claude
description: Invoke Claude CLI from Codex for one-shot analysis, review, synthesis, or structured outputs. Use when the user explicitly asks to consult Claude (for example "ask Claude to review this") or when a second-model opinion from Opus/Sonnet is needed without leaving Codex.
---

# Call Claude

## Overview

Run Claude non-interactively from Codex and return the result in the current session.

## Safety Defaults

1. Use `claude -p` for one-shot execution.
2. Always pass `--disable-slash-commands` to avoid recursive workflow/skill invocation.
3. Default to `--tools ""` (no tools) unless file reads are required.
4. When file reads are required, prefer `--tools Read` and constrain scope with explicit paths.
5. Use explicit output contracts (plain text verdict or JSON schema).

## Workflow

1. Identify target input:
   - Inline text already in context
   - File(s) in the workspace
2. Build a precise prompt with required output format.
3. Execute `scripts/call_claude.sh` with the smallest required tool surface.
4. Return Claude output to the user.

## Command Patterns

### General one-shot analysis (safe default)

```bash
codex/skills/call-claude/scripts/call_claude.sh \
  --model opus \
  --prompt "Analyze this proposal and list the top 5 risks with mitigations: ..."
```

### Plan/document review from files

```bash
codex/skills/call-claude/scripts/call_claude.sh \
  --model opus \
  --tools Read \
  --permission-mode bypassPermissions \
  --prompt "Review doc/projects/example/PLAN.md for architecture gaps, dependency ordering issues, and missing verification. Return APPROVE|REQUEST_CHANGES|NEEDS_DISCUSSION with file:line findings."
```

### Structured JSON result

```bash
codex/skills/call-claude/scripts/call_claude.sh \
  --model opus \
  --output-format json \
  --json-schema '{"type":"object","properties":{"verdict":{"type":"string"},"findings":{"type":"array","items":{"type":"string"}}},"required":["verdict","findings"]}' \
  --prompt "Review the plan and return schema-compliant JSON."
```

## Prompt Templates

Use `references/prompt-templates.md` for reusable templates.

## Failure Handling

1. If `claude` CLI is missing, stop and report the install command.
2. If command fails, return stderr and the exact command shape that failed.
3. If output contract is violated, rerun once with tighter instructions.
