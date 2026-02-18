# SPEC.md Template

**Answers:** "What should it do?"

## Structure

```markdown
# <Feature Name> Specification

## Problem Statement

- Current pain points
- User impact
- Business justification

## Goal

One sentence describing what success looks like.

## Feature Flag

| Flag Name | Default | Description |
|-----------|---------|-------------|
| `feature_<name>` | `false` | Enables <feature description> |

(Remove if no feature flag needed)

## User Experience

| Scenario | User Action | Expected Result |
|----------|-------------|-----------------|
| Happy path | ... | ... |
| Error | ... | ... |
| Edge case | ... | ... |

## Acceptance Criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Error states handled
- [ ] Loading states displayed

## Non-Goals

- Non-goal 1 (reason)
- Non-goal 2 (reason)

## Technical Reference

For implementation details, see [DESIGN.md](./DESIGN.md).
```
