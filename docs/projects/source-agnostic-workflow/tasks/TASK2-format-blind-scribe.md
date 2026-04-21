# Task 2 — Format-Blind Requirements Auditor

**Dependencies:** none (parallel with Task 1)

## Goal

Make the requirements-auditor receive requirements and scope as text in its prompt rather than reading planning files itself. The caller (task-workflow) handles extraction from whatever source; the requirements-auditor just audits text against diff and tests.

## Scope Boundary

**In scope:**
- Replace `task_file` input with `requirements` (text) and `scope` (in_scope + out_of_scope text)
- Remove Phase 1 "Extract Requirements" (reading and parsing the TASK file) — requirements arrive pre-extracted
- Keep Phase 2 (map requirements to implementation), Phase 3 (map to tests), Phase 4 (scope audit)
- Keep output format, severity labels, verdict rules unchanged
- Update the Boundaries section to reflect the new input contract

**Out of scope:**
- Changing the requirements-auditor's audit logic, verdict format, or coverage matrix
- Changing any other critic agent
- Adding planning-tool-specific code

## Files to Modify

- `claude/agents/requirements-auditor.md`

## Acceptance Criteria

- [ ] Requirements-auditor inputs section specifies `requirements` and `scope` as text, not `task_file`
- [ ] Phase 1 is replaced with "receive requirements" (pre-extracted, numbered list provided)
- [ ] Phases 2-4 work against the provided text, not parsed files
- [ ] Output format and verdict rules are identical to current
- [ ] Requirements-auditor has zero knowledge of any planning file format
