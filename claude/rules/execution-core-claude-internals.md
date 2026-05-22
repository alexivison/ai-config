# Claude Execution-Core Internals

Claude's hook chain is the concrete implementation behind the shared execution-core rules. These details are Claude-specific and do not apply to Codex.

## Preset and PR Gate Enforcement

- `skill-marker.sh` writes `execution-preset = <name>` when a workflow skill is invoked.
- `pr-gate.sh` reads the latest preset and enforces the required evidence set at the current committed `diff_hash`.
- Claude hooks read evidence overrides from the `party-cli` config: `cfg.Evidence.Required` in `~/.config/party-cli/config.toml`.

## Evidence Plumbing

- Evidence is recorded in the per-session JSONL log at `/tmp/claude-evidence-{session_id}.jsonl`.
- `agent-trace-stop.sh` records critic and runner evidence.
- `companion-trace.sh` records companion-review evidence from `--review-complete`.
- `companion-gate.sh` blocks direct `--approve`; approval must flow through the companion findings verdict.

## Oscillation Handling

- `agent-trace-stop.sh` performs same-hash oscillation detection.
- Cross-hash repeated-finding suppression applies to the minimizer only.

## Review Metrics

- Review metrics are defined in `claude/reference/review-metrics.md` (installed at `~/.claude/reference/review-metrics.md`).
- Metrics are written under `~/.claude/logs/review-metrics/` when Claude hooks are active.

## Stage Bindings

Workflow skills describe logical stages; this section binds each stage to the concrete mechanism Claude uses.

| Stage | Claude binding |
|-------|----------------|
| `write-tests` | Dispatch the `test-runner` sub-agent via the Task tool (both RED and GREEN). |
| `critics` | Dispatch `code-critic` + `minimizer` (+ `requirements-auditor` when requirements are provided) in parallel via the Task tool. |
| `companion-review` | Dispatch the configured companion via the `agent-transport` skill, then record the verdict with `--review-complete`. |
| `pre-pr-verification` | Dispatch `test-runner` + `check-runner` in parallel via the Task tool. |
