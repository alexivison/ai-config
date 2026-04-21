# Reviewer Prompt Templates

Adapt these templates to the specific PR. Replace placeholders with actual values.

## Companion Prompt

```
Review PR #{number}: '{title}'.

The diff is at {diff_path}. {file_count} files changed, {additions} additions, {deletions} deletions.

Summary: {brief description of what the PR does}

{project_guidelines_section — include if .github/code-review-perspectives.xml or similar exist}

Focus on:
- Correctness bugs, race conditions, edge cases
- Architectural concerns and design-doc compliance
- Security issues (XSS, injection, PII exposure)
- Subtle integration risks

Provide findings in severity-labeled format:
- [must] for blocking issues (correctness, security, data loss)
- [q] for questions or debatable design choices
- [nit] for minor items

Include file:line references for each finding.
```

## Code Critic

```
Review the diff for PR #{number} in {repo_context}.
The diff is at {diff_path}. Read the full diff.

This PR: {pr_summary}

{project_guidelines_section}

Focus on: correctness, security, missed edge cases, code quality, DRY violations, proper typing.
Label findings as [must] (blocking), [q] (question), [nit] (minor).
Return APPROVE, REQUEST_CHANGES, or NEEDS_DISCUSSION with your findings.
```

## Minimizer

```
Review the diff for PR #{number} for unnecessary complexity and bloat.
The diff is at {diff_path}. Read the full diff.

This PR: {pr_summary}

Look for:
- Unnecessary abstractions or indirection
- Code that could be simpler
- Duplicated patterns that could be consolidated
- Over-engineering and single-use wrappers
- Unnecessary new files or utilities

Label findings as [must], [q], or [nit].
Return APPROVE, REQUEST_CHANGES, or NEEDS_DISCUSSION.
```

## Deep Reviewer

```
Perform an adversarial deep-reasoning review of PR #{number}.
The diff is at {diff_path}. Read the full diff.

This PR: {pr_summary}

Key changes across {file_count} files:
{numbered list of major change areas}

Review for:
- Correctness bugs (race conditions, stale closures, missing deps)
- Security issues (XSS, injection, PII in metrics/logs)
- Integration risks (will this break existing behavior?)
- Edge cases (empty arrays, null/undefined, re-renders, timing)
- Clean code violations

Be adversarial. Challenge assumptions. Look for subtle bugs.
Provide severity-labeled findings: [must], [q], [nit].
```

## Adapting Prompts

- **Large PRs (20+ files)**: Add a bullet list of the major change areas so reviewers have structural context before reading the diff.
- **Test-heavy PRs**: Tell reviewers to focus on production code and only flag test issues if they indicate a gap in coverage or a wrong assertion.
- **Refactoring PRs**: Tell the minimizer to check that no behavior changed unintentionally, and tell the deep-reviewer to verify API surface compatibility.
- **Project guidelines available**: Append relevant excerpts to each prompt. Reviewers without project context miss convention violations.
