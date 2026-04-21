# Review Metrics Reference

Review effectiveness metrics are tracked in persistent per-session JSONL logs (`~/.claude/logs/review-metrics/{session_id}.jsonl`).

## Events Tracked

- `finding_raised` — A reviewer produced a finding (source, severity, category, file, line, description)
- `findings_summary` — Aggregate counts per reviewer pass (total, blocking, non-blocking, verdict)
- `triage` — Claude classified a finding (blocking/non-blocking/out-of-scope → fix/noted/dismissed/debate)
- `resolved` — A finding reached its final state (fixed/dismissed/debated/overridden/accepted/escalated)
- `review_cycle` — End-of-cycle summary with cumulative stats

## Automatic Recording (via hooks)

- `agent-trace-stop.sh` records `findings_summary` for code-critic, minimizer, requirements-auditor, and deep-reviewer by parsing `[must]`/`[should]`/`[nit]` tags and `**BLOCKING**`/`**NON-BLOCKING**` markers from agent responses.
- `companion-trace.sh` records individual `finding_raised` entries and a `findings_summary` by parsing the TOON findings file when `--review-complete` runs.

## Manual Recording (via CLI during triage)

```bash
# Record triage decision
~/.claude/hooks/scripts/review-metrics.sh --triage <session> <finding_id> <source> <classification> <action> [rationale]

# Record resolution
~/.claude/hooks/scripts/review-metrics.sh --resolved <session> <finding_id> <source> <resolution> [cwd] [detail]

# Record end of review cycle
~/.claude/hooks/scripts/review-metrics.sh --cycle <session> <cycle_number> [cwd]
```

## Querying

```bash
# Human-readable report for a session
~/.claude/hooks/scripts/review-metrics.sh --report <session>

# JSON export for programmatic analysis
~/.claude/hooks/scripts/review-metrics.sh --export <session>

# Report across all sessions
~/.claude/hooks/scripts/review-metrics.sh --report-all
```

## Key Metrics

Fix rate, dismiss rate, override rate, per-source finding counts, triage classification breakdown, resolution distribution. Use these to assess: how often reviewers catch real bugs, how often Claude ignores findings, and which reviewers produce the most actionable feedback.
