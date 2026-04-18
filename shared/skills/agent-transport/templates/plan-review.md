[PRIMARY] cd '{{WORK_DIR}}' && Review the plan at '{{PLAN_PATH}}' for architecture soundness and execution feasibility.

## Evaluate

1. **Feasibility**: Can the plan be implemented as described? Are there missing prerequisites or unstated assumptions?
2. **Risk**: What could go wrong? Are there failure modes the plan doesn't address?
3. **Missing steps**: Are there gaps in the sequence? Dependencies that aren't accounted for?
4. **Scope**: Is the plan doing too much or too little for the stated goal?
5. **Alternatives**: Is there a materially simpler approach that achieves the same outcome?

Write TOON findings to: {{FINDINGS_FILE}}
Emit raw TOON file contents only; no markdown fences.
Categories may include: `architecture`, `feasibility`, `missing-step`, `risk`, `scope`.

When done, run: {{NOTIFY_CMD}}
