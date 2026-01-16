---
name: autoskill
description: Learns from session feedback to extract durable preferences and propose skill updates. Use when the user says "learn from this session", "remember this pattern", or invokes /autoskill.
---

# Autoskill

Extract durable preferences from session feedback and update skill files.

## When to Activate

Trigger on explicit requests:
- `/autoskill`
- "learn from this session"
- "remember this pattern"
- "update skills based on this"

**Do NOT activate** for one-off corrections or declined modifications.

## Signal Detection

Scan the current session for feedback signals:

| Signal Type | Value | Examples |
|-------------|-------|----------|
| **Corrections** | Highest | "No, use X instead of Y", "We always do it this way" |
| **Repeated patterns** | High | Same feedback given 2+ times |
| **Approvals** | Supporting | "Yes, that's right", "Perfect" |

**Ignore:**
- Context-specific one-offs
- Ambiguous feedback
- Contradictory signals

## Signal Quality Filter

Before proposing changes, confirm:

1. Was the correction repeated or stated as a general rule?
2. Would it apply to future sessions?
3. Is it specific enough to be actionable?
4. Is it new information beyond standard best practices?

### Worth Capturing

- Project-specific conventions
- Custom component/file locations
- Team preferences differing from defaults
- Domain-specific terminology
- Architectural decisions
- Stack-specific integrations
- Workflow preferences

### Not Worth Capturing

- General best practices
- Language/framework conventions
- Common library usage
- Universal security practices
- Standard accessibility guidelines

## Mapping Signals to Skills

1. Match each signal to the relevant skill in `~/.claude/skills/`
2. If 3+ related signals don't fit any existing skill, propose a new one
3. Ignore signals unrelated to skill usage

### Skill Locations

- Skills: `~/.claude/skills/<skill-name>/SKILL.md`
- Reference docs: `~/.claude/skills/<skill-name>/reference/`
- Sub-agents: `~/.claude/agents/<agent-name>.md`
- Global config: `~/.claude/CLAUDE.md`

## Proposing Changes

For each proposed edit, provide:

```
### [SKILL-NAME] — [CONFIDENCE]

**Signal:** "[exact quote or paraphrase]"
**File:** `path/to/file.md`
**Section:** [section name or "new section"]

**Current:**
> [existing text, if modifying]

**Proposed:**
> [new or replacement text]

**Rationale:** [one sentence]
```

Confidence levels:
- **HIGH** — Explicit rule stated, repeated 2+ times, or clearly generalizable
- **MEDIUM** — Single instance but appears intentional, or slightly ambiguous scope

## Review Flow

Present changes grouped by confidence:

```
## Autoskill Summary

Detected [N] durable preferences from this session.

### HIGH Confidence
[changes...]

### MEDIUM Confidence
[changes...]

---
Apply changes? [all / high-only / selective / none]
```

Always wait for explicit approval before editing.

## Applying Changes

On approval:

1. Make minimal, focused edits
2. One concept per change (easier to revert)
3. Preserve existing file structure and tone
4. If git available, commit: `chore(autoskill): [description]`
5. Report changes made

## Constraints

- **Never delete** existing rules without explicit instruction
- **Prefer additive changes** over rewrites
- **Downgrade to MEDIUM** when uncertain about scope
- **Skip** if no actionable signals detected
