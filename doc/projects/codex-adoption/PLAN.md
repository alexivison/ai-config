# Codex Adoption Plan

Adopt valuable patterns from `ai-config-codex` into `ai-config-claude`, and reduce config bloat.

Source: `~/Code/ai-config-codex/` | Target: `~/Code/ai-config-claude/`

## Context

Claude config is **3.7x wordier** (16,451 vs 4,443 words) than Codex for broadly equivalent functionality. Biggest offenders: agents (5x), autonomous-flow rules (4.9x), language rules (4-5x).

Meanwhile, Codex introduced several patterns worth adopting in Claude: `research-project`, stricter plan evaluation artifacts, and stronger plan-conformance checks. Claude already has plan templates and marker-based PR enforcement; this plan focuses on normalizing and tightening those areas rather than duplicating them.

## Architecture End-State

- New `research-project` skill with report template
- Existing plan templates (SPEC/DESIGN/PLAN/TASK) in `plan-workflow` normalized to Codex-style structure
- Structured plan evaluation artifact in `plan-workflow`
- Plan-conformance check in `task-workflow` with explicit, measurable blocking criteria
- No LOC-based PR size rule in hooks or workflow rules
- All existing config files trimmed to Codex-comparable density

## Completed Pre-Work

- [x] TASK0 — Merge `plan-implementation` into `plan-workflow`: rewrote `plan-workflow/SKILL.md` as a single self-contained skill covering the full planning lifecycle (SPEC, DESIGN, PLAN, TASKs); moved templates from `plan-implementation/templates/` to `plan-workflow/templates/`; deleted `plan-implementation` skill directory; updated all references across `skill-eval.sh`, `autonomous-flow.md`, `CLAUDE.md`, `brainstorm`, `autoskill`, and `README` (deps: none)

## Tasks

### Phase 1 — New Capabilities

- [ ] TASK1 — Create `research-project` skill (deps: none)
- [ ] TASK2 — Normalize `plan-workflow` templates (SPEC/DESIGN/PLAN/TASK): align section order, required headers, and cross-links with Codex patterns; no new template types (deps: TASK0)
- [ ] TASK3 — Verify plan evaluation record in `plan-workflow` has explicit fields: `PLAN_EVALUATION_VERDICT: PASS|FAIL`, `CODEX_VERDICT: APPROVE|REQUEST_CHANGES|NEEDS_DISCUSSION`, and checklist evidence with file references; add any missing fields (deps: TASK0, TASK2)
- [ ] TASK4 — Add plan-conformance checks to `task-workflow` (blocking when PLAN.md exists) with measurable criteria only: TASK*.md and PLAN.md checkboxes are both updated; changed files remain within declared task scope or include an explicit scope-change note in PLAN.md; task dependency/order changes require explicit PLAN.md update (deps: none)
- [ ] TASK5 — Remove LOC-size gating from adoption scope and ensure no LOC-based PR limit is added to hooks/rules (deps: none)

### Phase 2 — Bloat Reduction

- [ ] TASK7 — Trim language rules (target: 50% reduction, ~4.5x → ~2x vs Codex)
- [ ] TASK9 — Trim verbose skills: autoskill, gemini-cli, codex-cli, plan-workflow (target: 30%, trim prose not procedures)
- [ ] TASK6 — Trim agent definitions (target: 33% reduction, ~5x → ~3x vs Codex; preserve security-scanner and code-critic density)
- [ ] TASK8 — Trim autonomous-flow.md and execution-core.md (target: 20% reduction; trim narrative, preserve decision matrix and pause logic)
- [ ] TASK10 — Final bloat audit: measure totals, compare ratios, validate marker system (code PRs need all 6 markers, plan PRs need codex only)

### Phase 3 — Stretch (Evaluate After Week with Codex)

- [ ] TASK11 — Create `session-retro-audit` skill (Claude-native, no Python scripts)
- [ ] TASK12 — Add command detection matrix to `pre-pr-verification`
- [ ] TASK13 — Capture any new patterns from continued Codex usage this week

## Cross-Task Invariants

- No functional regressions: all existing workflows must work identically after trimming
- Hook-based enforcement (markers, pr-gate) remains intact — trimming targets prose, not logic
- Codex-cli and gemini-cli skills are inherently larger due to wrapper complexity; trim prose, not procedures
- No LOC-based PR-size enforcement is introduced

## Bloat Audit Baseline

| Component | Claude (words) | Codex (words) | Ratio | Target Ratio |
|-----------|---------------|---------------|-------|-------------|
| Skills | 9,747 | 3,397 | 2.9x | ≤2.0x |
| Agents | 3,110 | 616 | 5.0x | ≤3.0x |
| Rules/References | 3,146 | 430 | 7.3x | ≤3.5x |
| Global instructions | 448 | — | N/A | No growth |
| **Total** | **16,451** | **4,443** | **3.7x** | **≤3.0x** |

Target: reduce total from ~16.5k to ~13.5k words (≤3.0x ratio). Claude's multi-agent coordination and iteration protocols justify more prose than Codex's single-agent model.

### Measurement Method (Required for TASK10)

Use the same command and file scope for baseline and final audit:

```bash
find claude/{skills,agents,rules} -type f -name '*.md' -print0 | xargs -0 wc -w
```

For Codex comparison, use the equivalent directories in `~/Code/ai-config-codex/codex/` and document any missing category (for example, no `agents/`) as `N/A` with explicit handling in ratio math.

## Definition of Done

- [x] Pre-work complete — plan-implementation merged into plan-workflow
- [ ] All Phase 1 tasks complete — new capabilities working
- [ ] All Phase 2 tasks complete — config at target density
- [ ] Bloat audit shows total ≤3.0x Codex ratio
- [ ] Marker system validated (no enforcement regressions)
- [ ] Phase 3 tracked separately as non-blocking stretch work
