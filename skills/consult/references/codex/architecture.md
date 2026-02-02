# Architecture Review (Codex)

**Trigger:** "architecture", "arch", "structure", "complexity"

**Path handling:** If prompt includes a path, cd there first for all git/codex commands.

## Step 1: Early Exit Check

```bash
cd /path/to/worktree && git diff --stat HEAD~1 | tail -1  # If <50 lines total → SKIP
```

## Step 2: Load Reference Guidelines

Read appropriate guidelines based on changed file types:
- `.tsx`, `.jsx`, React hooks → `~/.claude/skills/architecture-review/reference/architecture-guidelines-frontend.md`
- `.go`, `.py`, backend `.ts` → `~/.claude/skills/architecture-review/reference/architecture-guidelines-backend.md`
- Always load → `~/.claude/skills/architecture-review/reference/architecture-guidelines-common.md`

## Step 3: Identify Related Files

Don't just review changed files. Find:
- Files that import/are imported by changed files
- Files in same module/package
- Interface definitions the changed code implements

```bash
# Find imports in changed files
cd /path/to/worktree && grep -h "import\|require\|from" $(git diff --name-only HEAD~1) | sort -u
```

## Step 4: Run Comprehensive Review

```bash
cd /path/to/worktree && codex exec -s read-only "
Architecture review with regression detection.

Changed files: $(git diff --name-only HEAD~1 | tr '\n' ' ')

Review scope:
1. METRICS - Measure cyclomatic complexity, function length, file length, nesting depth for changed functions
2. REGRESSION CHECK - Compare metrics before/after. Flag if:
   - CC increases by >5 → [must]
   - Any metric crosses warn→block threshold → [must]
   - New code smell introduced → [must]
3. CODE SMELLS - Check for: God class, Long function (>50 lines), Deep nesting (>4), Feature envy, Shotgun surgery
4. STRUCTURAL - SRP violations, layer violations (presentation→data direct access)
5. SURROUNDING CONTEXT - Do changes fit with related files? Any coupling issues introduced?

Thresholds (from guidelines):
| Metric | Warn [q] | Block [must] |
|--------|----------|--------------|
| Cyclomatic complexity | >10 | >15 |
| Function length | >30 lines | >50 lines |
| File length | >300 lines | >500 lines |
| Nesting depth | >3 levels | >4 levels |

Use [must], [q], [nit] severity labels.
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
| calc.ts:divide | CC | 2 | 4 | ✓ |
| calc.ts:divide | Lines | 5 | 12 | ✓ |

### Regression Check
{None detected | List regressions with [must] label}

### Code Smells
{None detected | List with severity}

### Structural Issues
{None detected | List SRP/layer violations}

### Context Fit
{How changes integrate with surrounding code}
```
