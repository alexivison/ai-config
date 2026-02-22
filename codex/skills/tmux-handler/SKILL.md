# tmux-handler — Handle incoming messages from Claude via tmux

## Trigger

You see a message in your tmux pane from Claude (sent via `tmux-codex.sh`).

## Message types

### Review request
Message asks you to review changes against a base branch.

1. **Get the diff**: Run `git diff $(git merge-base HEAD <base>)..HEAD` to see the changes
2. **Review scope**: Review changed files AND adjacent files (callers, callees, types, tests)
   for: correctness bugs, crash paths, security issues, wrong output, architectural concerns
3. **Classify each finding**:
   - **blocking**: correctness bug, crash path, wrong output, security HIGH/CRITICAL
   - **non-blocking**: style nit, "could be simpler", defensive edge case, consistency preference
4. **Write findings** to the file path specified in the message, using this JSON format:
   ```json
   {
     "findings": [
       {
         "id": "F1",
         "file": "path/to/file.ts",
         "line": 42,
         "severity": "blocking",
         "category": "correctness|security|architecture|style|performance",
         "description": "Clear description of the issue",
         "suggestion": "How to fix it"
       }
     ],
     "summary": "One paragraph summary of the review",
     "stats": { "blocking_count": 0, "non_blocking_count": 0, "files_reviewed": 0 }
   }
   ```
5. **Do NOT include a "verdict" field.** You produce findings — the verdict is Claude's decision.
6. **Notify Claude** when done:
   ```bash
   ~/.codex/skills/claude-cli/scripts/tmux-claude.sh "Review complete. Findings at: <findings_file>"
   ```

### Re-review request
Claude fixed blocking issues and requests another pass.

- Verify previous blocking issues were addressed
- Flag only genuinely NEW issues
- Do NOT re-raise findings that were already addressed

### Task request
Claude asks you to investigate or work on something.

1. Perform the requested task
2. Write results to the file path specified (if given)
3. Notify Claude: `tmux-claude.sh "Task complete. Response at: <path>"`

### Plan review request
Claude shares a plan and asks for your assessment.

1. Read the plan
2. Evaluate feasibility, risks, missing steps
3. Write feedback to the specified file (same findings JSON format, but categories may include `architecture`, `feasibility`, `missing-step`)
4. Notify Claude: `tmux-claude.sh "Plan review complete. Findings at: <path>"`

### Question from Claude
Claude asks for information or your opinion.

1. Read the question
2. Investigate the codebase or reason about the answer
3. Write response to the specified file
4. Notify Claude: `tmux-claude.sh "Response ready at: <path>"`
