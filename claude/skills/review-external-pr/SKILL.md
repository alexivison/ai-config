---
name: review-external-pr
description: >-
  Review someone else's PR by dispatching four independent reviewers
  (companion, code-critic, minimizer, sentinel) in parallel, then combining and
  deduplicating their findings into a single PENDING GitHub review with inline
  comments. Use when the user shares a PR URL or number and asks to review it,
  says "review this PR", "check this PR", "look at PR #123", or wants a
  multi-perspective code review of an external pull request. Also use when the
  user asks to run critics/sentinel/the companion on a PR. This skill
  orchestrates the full pipeline — do not review the PR yourself; dispatch the
  reviewers.
user-invocable: true
---

# Review External PR

Orchestrate a four-reviewer pipeline on someone else's PR and post a combined PENDING review.

## Input

The user provides either:
- A full PR URL: `https://github.com/{owner}/{repo}/pull/{number}`
- A PR number (assumes current repo): `#123` or `123`

Parse the owner, repo, and number from the input. For bare numbers, detect the current repo from `gh repo view --json owner,name`.

## Phase 1: Gather

1. **Fetch PR metadata**:
   ```
   gh pr view {number} --json title,body,baseRefName,headRefName,headRefOid,files,url --repo {owner}/{repo}
   ```

2. **Fetch and save the diff**:
   ```
   gh pr diff {number} --repo {owner}/{repo} > /tmp/pr-{number}.diff
   ```

3. **Read the diff** into your context. For very large diffs (>2000 lines), read in chunks. Note the changed files, line counts, and overall scope.

4. **Check for project review guidelines**. Look for these in the repo (read from the PR's head branch if possible):
   - `.github/code-review-perspectives.xml`
   - `.github/code-review-prompt.xml`
   - `docs/guidelines/coding-quality-standards.md`

   If they exist, their content should be included in the critic prompts so reviewers apply project-specific standards.

5. **Detect the review language**. Match the language of the PR title and description — if the PR is written in Japanese, review comments should be in Japanese. If English, use English. This follows the AGENTS.md rule: "PR Title / Description の言語に、レビューコメントをあわせること。"

## Phase 2: Dispatch (all parallel, single message)

Launch all four reviewers in the **same message** so they run concurrently:

### The Companion

Dispatch via tmux-companion.sh:
```bash
~/.claude/skills/agent-transport/scripts/tmux-companion.sh --prompt "<prompt>" <work_dir>
```

The companion prompt should include the diff path, PR title, summary of changes, and ask for severity-labeled findings (`[must]`, `[q]`, `[nit]`) with file:line references. The default companion excels at deep reasoning — ask it to focus on correctness bugs, architectural concerns, subtle edge cases, and design-doc compliance.

### Code Critic (background Agent, subagent_type: code-critic)

Provide: diff path, PR context, project review guidelines (if found). Ask for structured findings with severity labels and a verdict (APPROVE / REQUEST_CHANGES / NEEDS_DISCUSSION).

### Minimizer (background Agent, subagent_type: minimizer)

Provide: diff path, PR context. Ask it to identify unnecessary complexity, bloat, over-engineering, duplicated patterns, trivial wrappers, and dead code.

### Sentinel (background Agent, subagent_type: sentinel)

Provide: diff path, PR context. Ask for adversarial deep review covering correctness, security, integration risks, race conditions, stale closures, and clean code violations.

See `references/reviewer-prompts.md` for prompt templates. Adapt them to the specific PR.

## Phase 3: Collect and Wait

- The three sub-agents complete via background task notifications.
- The companion notifies via a `[COMPANION]` message in new sessions and `[CODEX]` in legacy sessions, with a response file path.
- **Do not proceed until all four have reported.** As each completes, note its findings. Continue waiting for the remainder.
- If the companion takes significantly longer, start preparing the triage from the three critics and fold in the companion's findings when they arrive.

## Phase 4: Triage

Combine all findings into a single deduplicated list. This is the critical step — the value of four reviewers is in the synthesis, not in dumping four raw reports.

### Deduplication

Multiple reviewers often flag the same issue. When findings overlap:
- Merge them into a single comment
- Keep the most detailed explanation
- Attribute all contributing reviewers: `*Reviewers: code-critic, sentinel*`

### Severity Classification

Severity labels (`[must]`/`[q]`/`[nit]`): see `~/.claude/reference/severity-verdict.md`.

When reviewers disagree on severity, use your judgment. Downgrade non-blocking findings mislabeled as `[must]`. Drop out-of-scope findings (pre-existing issues in untouched code).

### Line Number Resolution

For each finding that should become an inline comment:
1. Fetch the file at the PR head: `git fetch origin {headRefName}` then `git show origin/{headRefName}:{path}`
2. Grep for the relevant code to find the exact line number in the new version
3. The GitHub API `line` parameter refers to the line number in the **new file**, with `side: "RIGHT"`

Only findings on **changed lines** (lines that appear in the diff) can receive inline comments. For findings on unchanged code, include them in the review body instead.

## Phase 5: Post

Create a PENDING review via the GitHub API. Omit the `event` field entirely — this creates a PENDING review that the user submits manually.

### Build the payload

```json
{
  "body": "<summary with severity sections>",
  "comments": [
    {
      "path": "relative/file/path.ts",
      "line": 42,
      "side": "RIGHT",
      "body": "[must] Description of finding.\n\n*Reviewers: code-critic, sentinel*"
    }
  ]
}
```

### Summary body format

```markdown
## Combined Review (code-critic + minimizer + sentinel + companion)

<verdict summary — how many reviewers said what>

### Blocking
1. One-line summary of each [must] finding

### Questions
2. One-line summary of each [q] finding

### Nits
3. One-line summary of each [nit] finding
```

### Post the review

```bash
gh api repos/{owner}/{repo}/pulls/{number}/reviews \
  --method POST \
  --input /tmp/pr-{number}-review.json
```

**Never auto-submit.** The review must remain PENDING. The user decides when and how to submit it.

## Phase 6: Report

Tell the user:
- **Verdict**: State your overall recommendation clearly — one of: **merge as-is**, **merge with minor changes** (nits/questions only, no blockers), **request changes** (has blocking findings that should be addressed before merge), or **do not merge** (fundamental design or correctness issues). Base this on the triaged findings, not raw reviewer verdicts — reviewers often over-flag non-blocking items as REQUEST_CHANGES.
- The review is posted as PENDING
- Summary of findings count by severity
- The PR URL so they can navigate to it and submit

## Error Handling

- **Companion unavailable** (no tmux pane): Proceed with the three critics only. Note in the review body that the companion was not available.
- **gh auth failure**: Ask the user to authenticate.
- **Empty diff**: Warn the user and abort.
- **API errors on posting**: Show the error. Common issue: commenting on lines not in the diff — move those findings to the body instead and retry.
