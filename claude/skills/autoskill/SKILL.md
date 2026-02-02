---
name: autoskill
description: Learns from session feedback to extract durable preferences and propose skill updates. Use when the user says "learn from this session", "remember this pattern", or invokes /autoskill.
user-invocable: true
---

# Autoskill

Extract durable preferences and create/update skills from multiple sources.

## Modes

| Mode | Trigger | Source |
|------|---------|--------|
| **Session** | `/autoskill`, "learn from this session" | Current conversation |
| **Document** | `/autoskill [url or path]`, "learn from this doc" | Book, article, codebase |

---

# Mode 1: Session Learning

## When to Activate

Trigger on explicit requests:
- `/autoskill`
- "learn from this session"
- "remember this pattern"

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

---

# Mode 2: Document Learning

## When to Activate

Trigger on:
- `/autoskill [url]` or `/autoskill [file path]`
- "learn from this book/article/doc"
- "extract skills from [source]"

## Process

1. **Read the source** — Fetch URL or read file(s)
2. **Extract techniques** — Identify patterns, methodologies, principles not already in your skills
3. **Filter for novelty** — Skip what you already know or is standard practice
4. **Propose skills** — Either updates to existing skills OR new skill creation

## What to Extract

- Methodologies (e.g., debugging approaches, testing strategies)
- Workflows (e.g., review processes, deployment patterns)
- Principles with concrete rules (e.g., "always X before Y")
- Red flags / anti-patterns with alternatives

## What to Skip

- General advice without actionable rules
- Content already covered by existing skills
- Context-specific examples that don't generalize
- Opinion without methodology

---

# Creating New Skills (TDD Approach)

When signals suggest a new skill (3+ related signals not fitting existing skills), use test-driven skill development.

## The Process

### 1. RED — Document the Failure

Before writing the skill, identify what goes wrong without it:

```markdown
## Skill Gap: [name]

**Problem observed:**
- [What happened without this skill]
- [Specific failure or suboptimal behavior]

**Desired behavior:**
- [What should happen instead]
```

### 2. GREEN — Write Minimal Skill

Create `~/.claude/skills/<skill-name>/SKILL.md` addressing **only** the documented failures.

```yaml
---
name: [skill-name]
description: [triggering conditions only — when to use, not what it does]
user-invocable: [true if callable via /skill-name]
---
```

Skill content should be minimal — just enough to fix the observed problem.

### 3. REFACTOR — Test and Iterate

After creating the skill:
1. Consider: "How might I rationalize ignoring this skill?"
2. Add rules to close those loopholes
3. Keep the skill focused — resist scope creep

## Skill Structure

```markdown
# [Skill Name]

[One sentence: what this skill does]

## When to Use
[Triggering conditions]

## Workflow / Process
[Steps or phases]

## Key Rules
[Non-negotiable constraints]

## Output Format (if applicable)
[Expected deliverable structure]
```

---

# Mapping Signals to Locations

## Skill Locations

- Skills: `~/.claude/skills/<skill-name>/SKILL.md`
- Reference docs: `~/.claude/skills/<skill-name>/reference/`
- Sub-agents: `~/.claude/agents/<agent-name>.md`
- Rules: `~/.claude/rules/<category>.md`
- Global config: `~/.claude/CLAUDE.md`

## Decision Tree

```
Signal about...
├── Workflow/process → Skill
├── Agent behavior → Agent definition
├── Code style/patterns → Rules
├── Global preferences → CLAUDE.md
└── Doesn't fit → Consider new skill (TDD)
```

---

# Output Format

```markdown
## Autoskill: [session name / document title]

### Signals

| #  | Type       | Quote/Context              |
|----|------------|----------------------------|
| 1  | Correction | "No, use X instead of Y"   |
| 2  | Process    | "We always do it this way" |

**Detected:** 2 updates, 0 new skills

### Proposed Updates

#### ▸ [1] SKILL-NAME — `HIGH`

**Signal:** "exact quote or paraphrase"
**File:** `~/.claude/skills/skill-name/SKILL.md`
**Section:** Section name or "new section"

**Current:**
> existing text, if modifying

**Proposed:**
> new or replacement text

**Rationale:** One sentence explanation.

> |

#### ▸ [2] SKILL-NAME — `MED`

**Signal:** "another quote"
**File:** `~/.claude/rules/category.md`
**Section:** New section

**Proposed:**
> new text (no current if adding new)

**Rationale:** One sentence explanation.


**Apply changes?** [all / high-only / selective / none]
```

## Confidence Levels

- **HIGH** — Explicit rule stated, repeated 2+ times, or clearly generalizable
- **MED** — Single instance but appears intentional, or slightly ambiguous scope

Always wait for explicit approval before editing.

---

# Applying Changes

On approval:

1. Make minimal, focused edits
2. One concept per change (easier to revert)
3. Preserve existing file structure and tone
4. **Check related files:** Update templates, reference docs, and examples in the skill folder to match new guidelines
5. If git available, commit: `chore(autoskill): [description]`
6. Report changes made

---

# Constraints

- **Never delete** existing rules without explicit instruction
- **Prefer additive changes** over rewrites
- **Downgrade to MEDIUM** when uncertain about scope
- **Skip** if no actionable signals detected
- **New skills require RED phase** — Document the gap before writing
