#!/bin/bash
# Weekly report of Claude Code activity
# Collects investigations, git activity, code reviews, tech stack,
# quality signals, and session summaries

set -eo pipefail

# Optional: number of weeks back (0 = current week, 1 = last week, etc.)
WEEKS_AGO=${1:-0}

CLAUDE_DIR="$HOME/.claude"
REPORTS_DIR="$HOME/Documents/Claude-Reports"
HOME_ENCODED=$(echo "$HOME" | sed 's/\//-/g')
GIT_AUTHOR=$(git config user.name 2>/dev/null || echo "")

# Date range: 7-day window ending $WEEKS_AGO weeks from today
# UNTIL = exclusive upper bound (tomorrow for current week, TODAY for past weeks)
if [ "$WEEKS_AGO" -gt 0 ]; then
  TODAY=$(date -v-${WEEKS_AGO}w +%Y-%m-%d 2>/dev/null || date -d "${WEEKS_AGO} weeks ago" +%Y-%m-%d)
  UNTIL="$TODAY"
else
  TODAY=$(date +%Y-%m-%d)
  UNTIL=$(date -v+1d +%Y-%m-%d 2>/dev/null || date -d "tomorrow" +%Y-%m-%d)
fi
SINCE=$(date -jf %Y-%m-%d -v-7d "$TODAY" +%Y-%m-%d 2>/dev/null || date -d "$TODAY - 7 days" +%Y-%m-%d)
WEEK=$(date -jf %Y-%m-%d "$TODAY" +%G-W%V 2>/dev/null || date -d "$TODAY" +%G-W%V)
EXPORT_DIR="$REPORTS_DIR/$WEEK"

mkdir -p "$EXPORT_DIR"

echo "Generating weekly report: $SINCE to $TODAY"
echo "Output: $EXPORT_DIR"

# ── Copy investigation markdown (skip operational logs) ─────────
inv_files=()
if [ -d "$CLAUDE_DIR/investigations" ]; then
  while IFS= read -r f; do
    inv_files+=("$f")
    cp "$f" "$EXPORT_DIR/"
  done < <(find "$CLAUDE_DIR/investigations" -type f -name "*.md" -newermt "$SINCE" ! -newermt "$UNTIL" 2>/dev/null)
  [ ${#inv_files[@]} -gt 0 ] && echo "  - Investigations: ${#inv_files[@]} file(s)"
fi

# ── Build SUMMARY.md ───────────────────────────────────────────
SUMMARY="$EXPORT_DIR/SUMMARY.md"
{
  cat << EOF
# Weekly Report: $WEEK

**Period:** $SINCE to $TODAY
**Generated:** $(date +%Y-%m-%d\ %H:%M)

## Investigations

EOF

  # List investigation files copied to export dir
  inv_found=false
  for f in "$EXPORT_DIR"/*.md; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "SUMMARY.md" ] && continue
    inv_found=true
    BASENAME=$(basename "$f")
    TITLE=$(grep -m1 "^#" "$f" 2>/dev/null | sed 's/^#* *//' || true)
    [ -z "$TITLE" ] && TITLE="$BASENAME"
    echo "- [$TITLE]($BASENAME)"
  done
  $inv_found || echo "_No investigations this week_"

  # ── Phase 1: Per-repo loop (Git Activity + accumulate cross-repo data) ──

  echo ""
  echo "## Git Activity"
  echo ""

  git_found=false
  seen_repos=""
  total_my_commits=0
  total_additions=0
  total_deletions=0
  total_prs=0
  all_file_exts=""
  all_pr_branches=""
  active_projects=""

  for repo in "$HOME"/Code/*/; do
    # Support both regular repos and worktrees (.git can be a file)
    git -C "$repo" rev-parse --is-inside-work-tree &>/dev/null || continue

    # Deduplicate: worktrees share a common git dir — only report each repo once
    common_dir=$(git -C "$repo" rev-parse --git-common-dir 2>/dev/null) || continue
    common_dir=$(cd "$repo" && cd "$common_dir" && pwd -P)
    case "$seen_repos" in *"$common_dir"*) continue ;; esac
    seen_repos="$seen_repos $common_dir"

    # Use the repo name from the common dir (main worktree), not the branch worktree
    name=$(basename "$(dirname "$common_dir")")

    # Show user's own commits; note total team activity for context
    all_count=$(git -C "$repo" log --all --oneline --since="$SINCE" --until="$UNTIL" 2>/dev/null | wc -l | tr -d ' ') || true

    my_commits=""
    my_stat=""
    if [ -n "$GIT_AUTHOR" ]; then
      my_commits=$(git -C "$repo" log --all --oneline --author="$GIT_AUTHOR" --since="$SINCE" --until="$UNTIL" 2>/dev/null) || true
      my_stat=$(git -C "$repo" log --all --author="$GIT_AUTHOR" --since="$SINCE" --until="$UNTIL" --pretty=tformat: --numstat 2>/dev/null) || true
    fi
    my_count=0
    [ -n "$my_commits" ] && my_count=$(echo "$my_commits" | wc -l | tr -d ' ')

    # Accumulate line stats
    if [ -n "$my_stat" ]; then
      repo_add=$(echo "$my_stat" | awk '/^[0-9]/ {s+=$1} END {print s+0}')
      repo_del=$(echo "$my_stat" | awk '/^[0-9]/ {s+=$2} END {print s+0}')
      total_additions=$((total_additions + repo_add))
      total_deletions=$((total_deletions + repo_del))
    fi

    # Collect file extensions for tech stack (from changed files)
    if [ -n "$GIT_AUTHOR" ]; then
      repo_exts=$(git -C "$repo" log --all --author="$GIT_AUTHOR" --since="$SINCE" --until="$UNTIL" --name-only --pretty=format: 2>/dev/null \
        | awk -F. 'NF>1 && $NF !~ /\// {print $NF}' | sort) || true
      [ -n "$repo_exts" ] && all_file_exts="${all_file_exts}${repo_exts}"$'\n'
    fi

    # User's PRs this week (requires gh CLI + GitHub remote)
    prs=""
    pr_lines=""
    if command -v gh &>/dev/null; then
      pr_json=$(cd "$repo" && gh pr list --state all --author @me --limit 30 \
        --json number,title,state,createdAt,additions,deletions,changedFiles,mergedAt,reviewDecision,headRefName 2>/dev/null) || true

      if [ -n "$pr_json" ] && [ "$pr_json" != "[]" ] && [ "$pr_json" != "null" ]; then
        pr_lines=$(echo "$pr_json" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for pr in data:
        created = pr.get('createdAt', '')
        if created < '${SINCE}T00:00:00Z' or created >= '${UNTIL}T00:00:00Z':
            continue
        num = pr['number']
        title = pr['title']
        state = pr['state']
        adds = pr.get('additions', 0)
        dels = pr.get('deletions', 0)
        files = pr.get('changedFiles', 0)
        review = pr.get('reviewDecision', '')
        branch = pr.get('headRefName', '')
        if branch:
            print(f'BRANCH:{branch}')
        parts = [f'- #{num} {title} ({state})']
        if adds or dels:
            parts.append(f'+{adds}/-{dels}')
        if files:
            parts.append(f'{files} files')
        if review:
            parts.append(f'[{review}]')
        print(' '.join(parts))
except Exception:
    pass
" 2>/dev/null) || true
      fi
    fi

    # Extract branch names for resolution tracking
    if [ -n "$pr_lines" ]; then
      while IFS= read -r bline; do
        case "$bline" in BRANCH:*) all_pr_branches="${all_pr_branches}${bline#BRANCH:}"$'\n' ;; esac
      done <<< "$pr_lines"
      # Filter out BRANCH: lines for display
      prs=$(echo "$pr_lines" | { grep -v '^BRANCH:' || true; })
      pr_count=$(echo "$prs" | grep -c '^- #' 2>/dev/null || true)
      total_prs=$((total_prs + pr_count))
    fi

    # Skip repos with no personal activity at all
    [ "$my_count" -eq 0 ] && [ -z "$prs" ] && continue

    git_found=true
    total_my_commits=$((total_my_commits + my_count))
    active_projects="${active_projects:+$active_projects, }$name"

    echo "### $name — $my_count own / $all_count total commits"
    echo ""
    if [ -n "$my_commits" ]; then
      echo '```'
      echo "$my_commits" | head -25
      [ "$my_count" -gt 25 ] && echo "... and $((my_count - 25)) more"
      echo '```'
    fi
    if [ -n "$prs" ]; then
      echo ""
      echo "**Pull Requests:**"
      echo "$prs"
    fi
    echo ""
  done
  $git_found || echo "_No git activity this week_"

  # ── Phase 2: Cross-repo sections ────────────────────────────────

  # ── Code Reviews ──────────────────────────────────────────────
  echo ""
  echo "## Code Reviews"
  echo ""

  if command -v gh &>/dev/null; then
    review_prs=$(gh search prs --reviewed-by @me --updated ">=${SINCE}" --sort created --limit 50 \
      --json number,repository,title,createdAt 2>/dev/null \
      | python3 -c "
import json, sys
try:
    since = '${SINCE}T00:00:00Z'
    until_date = '${UNTIL}T00:00:00Z'
    data = json.load(sys.stdin)
    results = []
    for pr in data:
        created = pr.get('createdAt', '')
        if created < since or created >= until_date:
            continue
        repo_full = pr.get('repository', {})
        repo_name = repo_full.get('name', '') if isinstance(repo_full, dict) else str(repo_full)
        results.append((pr['number'], repo_name, pr['title']))
    if results:
        print(f'REVIEW_COUNT:{len(results)}')
        print(f'**Reviews given:** {len(results)}')
        print()
        print('| # | Repository | Title |')
        print('|---|------------|-------|')
        for num, repo, title in results:
            print(f'| {num} | {repo} | {title} |')
    else:
        print('REVIEW_COUNT:0')
        print('_No code reviews this week_')
except Exception:
    print('REVIEW_COUNT:0')
    print('_Could not process code reviews_')
" 2>/dev/null) || review_prs="REVIEW_COUNT:0
_No code reviews this week_"
    # Extract count sentinel, then print rest
    review_count=$(echo "$review_prs" | grep '^REVIEW_COUNT:' | head -1 | cut -d: -f2 || true)
    review_count=${review_count:-0}
    echo "$review_prs" | { grep -v '^REVIEW_COUNT:' || true; }
  else
    review_count=0
    echo "_gh CLI not available_"
  fi

  # ── Tech Stack Distribution ───────────────────────────────────
  echo ""
  echo "## Tech Stack Distribution"
  echo ""

  if [ -n "$all_file_exts" ]; then
    echo "$all_file_exts" | python3 -c "
import sys
from collections import Counter
try:
    frontend = {'tsx', 'ts', 'jsx', 'js', 'css', 'scss', 'html', 'vue', 'svelte'}
    backend = {'go', 'py', 'rb', 'java', 'rs', 'proto', 'sql', 'kt', 'cs', 'ex', 'exs'}
    infra = {'yaml', 'yml', 'json', 'toml', 'md', 'sh', 'bash', 'dockerfile', 'tf', 'hcl', 'nix'}
    lines = [l.strip().lower() for l in sys.stdin if l.strip()]
    counts = Counter(lines)
    categories = {'Frontend': {}, 'Backend': {}, 'Infra': {}}
    for ext, c in counts.items():
        if ext in frontend:
            categories['Frontend'][ext] = c
        elif ext in backend:
            categories['Backend'][ext] = c
        elif ext in infra:
            categories['Infra'][ext] = c
    print('| Category | Files | Top Extensions |')
    print('|----------|-------|----------------|')
    for cat in ('Frontend', 'Backend', 'Infra'):
        exts = categories[cat]
        total = sum(exts.values())
        if total == 0:
            continue
        top = sorted(exts.items(), key=lambda x: -x[1])[:5]
        top_str = ', '.join(f'{e}({c})' for e, c in top)
        print(f'| {cat} | {total} | {top_str} |')
except Exception:
    print('_Could not compute tech stack_')
" 2>/dev/null || echo "_Could not compute tech stack_"
  else
    echo "_No file change data available_"
  fi

  # ── Quality Signals ───────────────────────────────────────────
  echo ""
  echo "## Quality Signals"
  echo ""

  TRACE_LOG="$CLAUDE_DIR/logs/agent-trace.jsonl"
  if [ -f "$TRACE_LOG" ]; then
    python3 -c "
import json, sys
try:
    since = '${SINCE}T00:00:00Z'
    until_date = '${UNTIL}T00:00:00Z'
    agents = {'test-runner': 'Tests', 'check-runner': 'Checks'}
    pass_verdicts = {'PASS', 'COMPLETED', 'APPROVE', 'CLEAN'}
    fail_verdicts = {'FAIL', 'REQUEST_CHANGES', 'ISSUES_FOUND'}
    stats = {a: {'pass': 0, 'fail': 0} for a in agents}
    with open('$TRACE_LOG') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            ts = entry.get('timestamp', '')
            if ts < since or ts >= until_date:
                continue
            agent = entry.get('agent', '')
            verdict = entry.get('verdict', '')
            if agent in stats:
                if verdict in pass_verdicts:
                    stats[agent]['pass'] += 1
                elif verdict in fail_verdicts:
                    stats[agent]['fail'] += 1
    has_data = any(stats[a]['pass'] + stats[a]['fail'] > 0 for a in stats)
    if has_data:
        print('| Check | Pass | Fail |')
        print('|-------|------|------|')
        for agent, label in agents.items():
            p = stats[agent]['pass']
            f = stats[agent]['fail']
            if p + f > 0:
                print(f'| {label} | {p} | {f} |')
    else:
        print('_No quality signal data this week_')
except Exception:
    print('_Could not parse agent trace_')
" 2>/dev/null || echo "_Could not parse agent trace_"
  else
    echo "_No agent trace log found_"
  fi

  # ── Investigation Resolution Tracking ─────────────────────────
  if $inv_found; then
    echo ""
    echo "### Resolution Tracking"
    echo ""

    for f in "$EXPORT_DIR"/*.md; do
      [ -f "$f" ] || continue
      [ "$(basename "$f")" = "SUMMARY.md" ] && continue
      slug=$(basename "$f" .md)
      matched=false
      if [ -n "$all_pr_branches" ]; then
        while IFS= read -r branch; do
          [ -z "$branch" ] && continue
          case "$branch" in *"$slug"*)
            echo "- $slug — PR branch matched (\`$branch\`)"
            matched=true
            break
            ;;
          esac
        done <<< "$all_pr_branches"
      fi
      $matched || echo "- $slug — Open"
    done
  fi

  # ── Project Memory ──────────────────────────────────────────
  echo ""
  echo "## Project Memory"
  echo ""

  memory_count=0
  if [ -d "$CLAUDE_DIR/projects" ]; then
    while IFS= read -r mfile; do
      memory_count=$((memory_count + 1))
      rel="${mfile#"$CLAUDE_DIR"/projects/}"
      proj_dir=$(echo "$rel" | cut -d'/' -f1)
      clean=$(echo "$proj_dir" | sed "s/^${HOME_ENCODED}-//" | sed 's/^Code-//' | sed 's/^-//')
      case "$clean" in ""|Users-*|Home-*|Code) clean="$proj_dir" ;; esac

      echo "**$clean:**"
      { grep -v '^$' "$mfile" 2>/dev/null || true; } | head -15
      echo ""
    done < <(find "$CLAUDE_DIR/projects" -path "*/memory/MEMORY.md" -newermt "$SINCE" ! -newermt "$UNTIL" 2>/dev/null | sort)
  fi

  if [ "$memory_count" -eq 0 ]; then
    echo "_No project memory updates this week_"
  else
    echo ""
    echo "_${memory_count} project(s) with memory updates_"
  fi

  # ── Stats ────────────────────────────────────────────────────
  echo ""
  echo "## Stats"
  echo ""

  # Weekly-scoped session count from history.jsonl
  weekly_sessions=0
  if [ -f "$CLAUDE_DIR/history.jsonl" ]; then
    since_epoch=$(date -jf %Y-%m-%d "$SINCE" +%s 2>/dev/null || date -d "$SINCE" +%s)
    until_epoch=$(date -jf %Y-%m-%d "$UNTIL" +%s 2>/dev/null || date -d "$UNTIL" +%s)
    # Convert to milliseconds
    since_ms=$((since_epoch * 1000))
    until_ms=$((until_epoch * 1000))
    weekly_sessions=$(python3 -c "
import json, sys
try:
    sessions = set()
    with open('$CLAUDE_DIR/history.jsonl') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            ts = entry.get('timestamp', 0)
            if ${since_ms} <= ts < ${until_ms}:
                sid = entry.get('sessionId', '')
                if sid:
                    sessions.add(sid)
    print(len(sessions))
except Exception:
    print('?')
" 2>/dev/null) || weekly_sessions="?"
  fi

  echo "| Metric | Count |"
  echo "|--------|-------|"
  echo "| Sessions | $weekly_sessions |"
  echo "| Commits | $total_my_commits |"
  echo "| PRs created | $total_prs |"
  echo "| PRs reviewed | $review_count |"
  echo "| Lines added | +$total_additions |"
  echo "| Lines removed | -$total_deletions |"
  [ -n "$active_projects" ] && echo "| Active projects | $active_projects |"

} > "${SUMMARY}.tmp" && mv "${SUMMARY}.tmp" "$SUMMARY"

echo ""
echo "Done. Summary: $SUMMARY"
