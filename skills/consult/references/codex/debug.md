# Debug Investigation (Codex)

**Trigger:** "debug", "error", "bug", "why", "root cause", "investigate"

For complex debugging, Codex applies four-phase methodology with full codebase access.

## Command (Complex Cases)

```bash
codex exec -s read-only "Investigate bug: {error/symptom}.

Apply four-phase methodology:
1. ROOT CAUSE INVESTIGATION - Read error messages, check recent changes (git diff/log), trace data flow
2. PATTERN ANALYSIS - Find similar working code, compare completely, list differences
3. HYPOTHESIS TESTING - Form single hypothesis, test with smallest change, verify
4. SPECIFY FIX - Describe fix without implementing, note required tests

Return structured findings with confidence level."
```

## Four-Phase Methodology

| Phase | Focus | Actions |
|-------|-------|---------|
| 1. Root Cause | Understanding | Read errors, check git history, trace data |
| 2. Pattern Analysis | Comparison | Find working code, compare, list differences |
| 3. Hypothesis Testing | Validation | One hypothesis, smallest test, verify |
| 4. Fix Specification | Documentation | Describe fix, note tests needed |

## Output Format (VERDICT FIRST for marker detection)

```markdown
## Debug Investigation (Codex)

**Verdict**: **CONFIRMED** | **LIKELY** | **INCONCLUSIVE**
**Attempts**: {N} hypotheses tested

### Summary
{One-line description of the bug}

### Root Cause
**{file}:{line}** - Confidence: high/medium/low

{Explanation}

### Evidence
- {How confirmed}

### Data Flow Trace
{origin} → {step} → {where it breaks}

### Fix Specification
**Current (broken):**
```{lang}
{code snippet}
```

**Required fix:**
```{lang}
{fix snippet}
```

### Actions
- [ ] **{file}:{line}** - {fix description}
- [ ] **{test file}** - {regression test description}
```

## Quick Debug (Simple Cases)

For simple errors, use shorter prompt:

```bash
codex exec -s read-only "Debug: {error/symptom}. Find root cause and suggest fix."
```

Returns shorter format:
```markdown
## Debug Analysis (Codex)

**Verdict**: **CONFIRMED** | **LIKELY**

### Root Cause
{1-2 sentences}

### Recommended Fix
{Concrete action}
```
