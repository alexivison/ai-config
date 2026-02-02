# PR Comment Reply Template

Use `--raw-field` (not `-F`) for body to avoid `@` being interpreted as file reference.

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  -X POST \
  --raw-field 'body=@{username} {message}

Addressed in {commit}.' \
  -F in_reply_to={comment_id}
```

## Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `{owner}/{repo}` | Repository | `legalforce/loc-app` |
| `{pr_number}` | PR number | `58959` |
| `{comment_id}` | Review comment ID | `2730495039` |
| `{username}` | Original commenter | `claude[bot]` |
| `{message}` | Your reply text | `Fixed the issue.` |
| `{commit}` | Commit hash (if applicable) | `6a5ec38` |

## Example

```bash
gh api repos/legalforce/loc-app/pulls/58959/comments \
  -X POST \
  --raw-field 'body=@claude[bot] Fixed the naming issue.

Addressed in 6a5ec38.' \
  -F in_reply_to=2730495039
```
