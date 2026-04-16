[PRIMARY] cd '{{WORK_DIR}}' && Review the changes on this branch against {{BASE}}.

Title: {{TITLE}}

## Instructions

Get the diff: `git diff $(git merge-base HEAD {{BASE}})..HEAD`

Review changed files AND adjacent files (callers, callees, types, tests) for:
1. Correctness bugs, crash/regression paths, wrong output
2. Security issues (HIGH/CRITICAL)
3. Unnecessary complexity / over-abstraction
4. Simpler equivalent approach

Classify each finding:
- **blocking**: correctness bug, crash/regression, wrong output, security HIGH/CRITICAL
- **non-blocking**: materially simpler equivalent that reduces complexity/risk
- **omit by default**: style nits, naming preferences, minor consistency tweaks

Write TOON findings to: {{FINDINGS_FILE}}
Emit raw TOON file contents only; no markdown fences.

End with a verdict line — exactly `VERDICT: APPROVED` if no blocking findings, or `VERDICT: REQUEST_CHANGES` if there are blocking findings.

{{SCOPE_SECTION}}

{{DISPUTE_SECTION}}

{{REREVEW_SECTION}}

When done, run: {{NOTIFY_CMD}}
