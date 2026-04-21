# Severity & Verdict Reference

## Severity Labels

| Label | Meaning | Blocks? |
|-------|---------|---------|
| `[must]` | Correctness bug, security issue, data loss risk, principle violation | Yes |
| `[q]` | Question, debatable design, clarification needed | No |
| `[nit]` | Style, minor improvement, optional polish | No |

**Variants:** deep-reviewer and requirements-auditor use `[should]` instead of `[q]` for robustness gaps / minor scope creep.

## Verdicts

| Verdict | When |
|---------|------|
| **APPROVE** | No `[must]` findings |
| **REQUEST_CHANGES** | One or more `[must]` findings |
| **NEEDS_DISCUSSION** | Architectural concerns, unclear requirements, persistent blocking findings |

requirements-auditor and deep-reviewer use only APPROVE / REQUEST_CHANGES (no NEEDS_DISCUSSION).

In Codex findings files, verdicts appear as `VERDICT: APPROVED` / `VERDICT: REQUEST_CHANGES`.

## Default Suppression

`[q]` and `[nit]` are opt-in — suppress by default unless explicitly requested. Critics should APPROVE when only non-blocking findings remain.
