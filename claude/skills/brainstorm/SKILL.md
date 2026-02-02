---
name: brainstorm
description: Structured context capture before planning. Use before /plan-implementation for new features, when requirements are unclear, or when multiple approaches exist. Gathers understanding through targeted questions.
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash(git:*)
---

# Brainstorm

Capture context and explore approaches before jumping into planning. This skill ensures you understand the problem space before committing to a solution.

## When to Use

- Before `/plan-implementation` for non-trivial features
- When requirements are vague or incomplete
- When multiple valid approaches exist
- When you need to understand existing code before modifying

**Skip for**: Bug fixes, small refactors, or changes with clear requirements.

## Three-Phase Workflow

### Phase 1: Understand

Gather context before proposing anything.

1. **Review current state**
   - Read relevant files, docs, recent commits
   - Understand existing patterns and constraints

2. **Ask clarifying questions** (one at a time)
   - Prefer multiple-choice over open-ended
   - Focus on: purpose, constraints, success criteria, edge cases
   - Stop when you have enough to propose approaches

**Question format:**
```
What should happen when [specific scenario]?
- A) [Option with tradeoff]
- B) [Option with tradeoff]
- C) Something else
```

### Phase 2: Explore Approaches

Present 2-3 approaches with tradeoffs.

1. **Lead with recommendation** and explain why
2. **Compare alternatives** with clear tradeoffs
3. **Be opinionated** — don't present equal options without guidance

**Approach format:**
```
## Recommended: [Approach Name]
[Why this is best for this situation]

**Tradeoffs:**
- Pro: [benefit]
- Con: [cost]

## Alternative: [Approach Name]
[When you'd choose this instead]
```

### Phase 3: Validate Design

Break design into digestible sections.

1. **Present in 200-300 word sections**
2. **Validate after each section** — don't dump everything at once
3. **Adjust if misunderstandings arise**

Cover (as relevant):
- Architecture / component structure
- Data flow
- Error handling approach
- Testing strategy

## Principles

- **YAGNI ruthlessly** — eliminate features you don't need yet
- **One question per message** — don't overwhelm
- **Stay flexible** — adjust when new info emerges
- **Explore before settling** — don't commit to first idea

## Output

After completing all phases, summarize and save to file.

**Location:** Same directory where PLAN.md will live:
- If project folder exists: `doc/projects/<project-name>/YYYY-MM-DD-brainstorm.md`
- If starting fresh: Create the folder first, then save there

**Why same directory?** Keeps all feature documentation together (brainstorm → SPEC → DESIGN → PLAN → TASKs). No orphaned docs.

```
## Brainstorm Summary: [Feature Name]

### Context
[2-3 sentences on what we're building and why]

### Decisions Made
- [Key decision 1]: [Choice] — [Reason]
- [Key decision 2]: [Choice] — [Reason]

### Approach
[1 paragraph describing the chosen approach]

### Open Questions
- [Any remaining uncertainties for implementation]

### Next Step
Ready for `/plan-implementation` or [specific next action]
```

## Handoff to Planning

When brainstorm is complete and user confirms:
- Save the brainstorm summary to file
- Offer to run `/plan-implementation` with captured context
- Reference the saved brainstorm file in planning docs
