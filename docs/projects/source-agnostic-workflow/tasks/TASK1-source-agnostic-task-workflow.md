# Task 1 — Source-Agnostic Task Workflow

**Dependencies:** none

## Goal

Remove TASK*.md hardcoding from task-workflow so it can execute work from any planning source. The workflow still does everything it does today — tests, critics, Codex, evidence, PR — it just doesn't assume the input came from a TASK file.

## Scope Boundary

**In scope:**
- Update skill frontmatter description to be source-agnostic
- Rewrite pre-implementation gate to accept scope/requirements/goal from any source
- Make checkpoint/checkbox updates conditional: update source files when they exist, skip when they don't
- Generalize scope references throughout (step 5 minimality, step 6 requirements-auditor handoff, step 8 deep-reviewer)
- Preserve backward compatibility with classic TASK/PLAN files

**Out of scope:**
- Changing the requirements-auditor itself (Task 2)
- Changing execution-core or CLAUDE.md wording (Task 3)
- Adding any planning-tool-specific code

## Files to Modify

- `claude/skills/task-workflow/SKILL.md`

## Acceptance Criteria

- [ ] Skill description does not reference TASK*.md as the only valid input
- [ ] Pre-implementation gate works when scope/requirements/goal are provided directly (no TASK file)
- [ ] Pre-implementation gate still works when a TASK file is the source (reads it to extract scope/requirements/goal)
- [ ] Checkbox enforcement section is conditional on source files existing, not assumed
- [ ] All sub-agent prompt guidance references "scope boundaries" generically, not "TASK file scope"
- [ ] The execution sequence (tests → implement → critics → Codex → PR) is unchanged
