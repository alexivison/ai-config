# Architecture Review (Codex)

**Trigger:** "architecture", "arch", "structure", "complexity"

**Path handling:** If prompt includes a path, cd there first for all git/codex commands.

## Step 1: Early Exit Check (CRITICAL — Do This First)

```bash
cd /path/to/worktree

# For uncommitted changes:
git diff --stat | tail -1

# Check what files changed:
git diff --name-only
```

**SKIP immediately if ANY of these conditions are true:**
1. Less than 30 lines changed total
2. Only test files changed (`*.test.*`, `*.spec.*`, `*_test.*`)
3. Only docs/markdown changed (`*.md`, `docs/*`)
4. Only config/checkbox updates

Return this and STOP:
```
## Architecture Review

**Verdict**: SKIP
**Reason**: Trivial change ({lines} lines, {file_types} only)
```

**Do NOT run Codex for trivial changes** — it wastes tokens and time.

## Step 2: Identify Related Files (Only if NOT skipping)

Find related files:
- Files that import/are imported by changed files
- Files in same module/package

```bash
cd /path/to/worktree && grep -h "import\|require\|from" $(git diff --name-only) 2>/dev/null | sort -u
```

## Step 3: Run Comprehensive Review

```bash
cd /path/to/worktree && codex exec -s read-only "
Architecture review with regression detection.

Changed files: $(git diff --name-only HEAD~1 | tr '\n' ' ')

Review scope (see guidelines for thresholds):
1. METRICS - Cyclomatic complexity, function length, file length, nesting depth
2. REGRESSION CHECK - Compare before/after, flag degradations as [must]
3. CODE SMELLS - God class, Long function, Deep nesting, Feature envy
4. STRUCTURAL - SRP violations, layer violations
5. CONTEXT FIT - Do changes integrate well with surrounding code?

Use [must], [q], [nit] severity labels per guidelines.
"
```

## Output Format (VERDICT FIRST for marker detection)

```markdown
## Architecture Review (Codex)

**Verdict**: **SKIP** | **APPROVE** | **REQUEST_CHANGES** | **NEEDS_DISCUSSION**
**Mode**: Quick scan | Deep review
**Files reviewed**: {N changed} + {M related}

### Metrics Delta
| File:Function | Metric | Before | After | Status |
|---------------|--------|--------|-------|--------|

### Regression Check
{None detected | List regressions with [must] label}

### Code Smells
{None detected | List with severity}

### Structural Issues
{None detected | List SRP/layer violations}

### Context Fit
{How changes integrate with surrounding code}
```
