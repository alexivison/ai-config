# Task 3 — Update CLAUDE.md and Execution-Core

**Dependencies:** Task 1, Task 2

## Goal

Update CLAUDE.md and execution-core.md to use source-agnostic language. Make it clear that all implementation follows execution-core regardless of what triggered it — TASK files, external planning tools, or direct user instructions.

## Scope Boundary

**In scope:**
- CLAUDE.md: update workflow selection to cover any planning source triggering the full cascade
- CLAUDE.md: state that all implementation follows execution-core regardless of entry point
- execution-core.md: replace TASK-native wording with source-agnostic wording
- execution-core.md: core sequence line — change "requirements-auditor if TASK file" to "requirements-auditor when requirements are provided"
- execution-core.md: minimality gate — change "TASK scope" to "provided scope"
- execution-core.md: scope enforcement — change "TASK file scope boundaries" to "scope boundaries"
- execution-core.md: tiered execution — update requirements-auditor activation language
- execution-core.md: review governance — update "requirements not in TASK" to "requirements not in scope"

**Out of scope:**
- Changing the execution sequence itself
- Changing evidence system, PR gate, dispute resolution
- Adding planning-tool-specific code or documentation

## Files to Modify

- `claude/CLAUDE.md`
- `claude/rules/execution-core.md`

## Acceptance Criteria

- [ ] CLAUDE.md clearly states all implementation follows execution-core regardless of how work was triggered
- [ ] CLAUDE.md workflow selection does not assume TASK files are the only planned-work trigger
- [ ] execution-core.md has zero references to TASK files as the assumed input format
- [ ] execution-core.md requirements-auditor activation is conditional on "requirements being provided," not "TASK file existing"
- [ ] The execution sequence, evidence system, and PR gate are functionally unchanged
- [ ] No planning-tool-specific language introduced anywhere
