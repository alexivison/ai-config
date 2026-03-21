#!/usr/bin/env bash
# evidence.sh — Shared evidence library for the PR gate system
#
# Replaces marker files with a JSONL evidence log per session.
# Each entry records a diff_hash (SHA-256 of branch diff from merge-base).
# Gate hooks compute current diff_hash and only accept matching evidence.
# Stale evidence is automatically ignored — no invalidation hook needed.
#
# Usage: source "$(dirname "$0")/lib/evidence.sh"

# ── Shell guard: evidence.sh requires bash ──
if [ -z "${BASH_VERSION:-}" ]; then
  echo "ERROR: evidence.sh must be sourced from bash, not ${ZSH_VERSION:+zsh }${0##*/}. The flock/fd-redirect syntax is bash-specific." >&2
  # shellcheck disable=SC2317
  return 1 2>/dev/null || exit 1  # exit is reachable when executed (not sourced)
fi

# ── Hook trace logging ──
# Append-only log for hook observability. Every hook should call this.
# Args: hook_name session_id outcome [details]

_HOOK_TRACE_LOG="${HOME}/.claude/logs/hook-trace.log"
mkdir -p "$(dirname "$_HOOK_TRACE_LOG")" 2>/dev/null || true

hook_log() {
  local hook_name="${1:-unknown}" session_id="${2:-unknown}" outcome="${3:-unknown}" details="${4:-}"
  local ts
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  local line="${ts} | ${hook_name} | ${session_id} | ${outcome}"
  [ -n "$details" ] && line="${line} | ${details}"
  echo "$line" >> "$_HOOK_TRACE_LOG"
}

# ── Path helpers ──

evidence_file() {
  local session_id="$1"
  echo "/tmp/claude-evidence-${session_id}.jsonl"
}

# ── Internal: resolve merge-base for a working directory ──
# Sets _EVIDENCE_MERGE_BASE and _EVIDENCE_DEFAULT_BRANCH, or returns 1
_resolve_merge_base() {
  local cwd="$1"
  _EVIDENCE_MERGE_BASE=""
  _EVIDENCE_DEFAULT_BRANCH=""

  if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
    return 1
  fi

  if (cd "$cwd" 2>/dev/null && git rev-parse --git-dir >/dev/null 2>&1); then
    _EVIDENCE_DEFAULT_BRANCH=$(cd "$cwd" && git rev-parse --verify refs/heads/main >/dev/null 2>&1 && echo main || echo master)
  else
    return 1
  fi

  _EVIDENCE_MERGE_BASE=$(cd "$cwd" && git merge-base "$_EVIDENCE_DEFAULT_BRANCH" HEAD 2>/dev/null || echo "")
  [ -n "$_EVIDENCE_MERGE_BASE" ]
}

# ── Worktree cwd resolution ──
# When a session operates in a git worktree but hook input carries the main repo cwd,
# the override file redirects to the actual worktree path.
# Validates that the override belongs to the same git repo as hook_cwd to prevent
# stale overrides from prior sessions or different projects from poisoning hashes.

_resolve_cwd() {
  local session_id="$1" hook_cwd="$2"
  local override_file="/tmp/claude-worktree-${session_id}"
  if [ -f "$override_file" ]; then
    local worktree_cwd
    worktree_cwd=$(cat "$override_file")
    if [ -d "$worktree_cwd" ]; then
      # Validate: if hook_cwd is a git repo, override must be from the same repo.
      # If hook_cwd is NOT a git repo (invalid/wrong cwd), trust the override.
      # Compare git-common-dir to verify same repo. pwd -P resolves
      # macOS symlinks (/var → /private/var). The cd chain ensures
      # relative git-common-dir paths (e.g. ".git") resolve from the repo dir.
      local hook_common
      hook_common=$(cd "$hook_cwd" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P) || true
      if [ -z "$hook_common" ]; then
        # hook_cwd is not a git repo — override is more reliable
        echo "$worktree_cwd"
        return
      fi
      local override_common
      override_common=$(cd "$worktree_cwd" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P) || true
      if [ -n "$override_common" ] && [ "$hook_common" = "$override_common" ]; then
        echo "$worktree_cwd"
        return
      fi
      # Override points to a different repo — ignore it (stale from prior session)
    fi
  fi
  echo "$hook_cwd"
}

# ── Diff exclusion pattern (shared constant) ──
_DIFF_EXCLUDES=(-- . ':!*.md' ':!*.log' ':!*.jsonl' ':!*.tmp')

# ── Diff hash computation ──
# Hashes committed changes only (merge-base..HEAD), excluding working-tree edits.
# This ensures hash stability while critics run in parallel — uncommitted edits
# during critic execution don't invalidate evidence. Committing new fixes correctly
# changes the hash, requiring both critics to re-run on the same committed state.
# Returns "clean" if no diff, "unknown" if not a git repo.

compute_diff_hash() {
  local cwd="$1"
  if ! _resolve_merge_base "$cwd"; then
    echo "unknown"
    return
  fi

  local diff_output
  diff_output=$(cd "$cwd" && git diff "$_EVIDENCE_MERGE_BASE"..HEAD "${_DIFF_EXCLUDES[@]}" 2>/dev/null)

  if [ -z "$diff_output" ]; then
    echo "clean"
  else
    echo "$diff_output" | shasum -a 256 | cut -d' ' -f1
  fi
}

# ── Diff stats for tiered gate decisions ──
# Outputs: lines files new_files

diff_stats() {
  local cwd="$1"
  if ! _resolve_merge_base "$cwd"; then
    echo "0 0 0"
    return
  fi

  # Use --numstat for reliable line counting (handles binary files, renames)
  local numstat
  numstat=$(cd "$cwd" && git diff --numstat "$_EVIDENCE_MERGE_BASE"..HEAD "${_DIFF_EXCLUDES[@]}" 2>/dev/null)

  local lines=0 files=0 new_files=0

  if [ -n "$numstat" ]; then
    # numstat format: "adds\tdeletes\tfilename" per file; "-" for binary
    lines=$(echo "$numstat" | awk '{if ($1 != "-") sum += $1 + $2} END {print sum+0}')
    files=$(echo "$numstat" | wc -l | tr -d ' ')
  fi

  new_files=$(cd "$cwd" && git diff --diff-filter=A --name-only "$_EVIDENCE_MERGE_BASE"..HEAD "${_DIFF_EXCLUDES[@]}" 2>/dev/null \
    | wc -l | tr -d ' ')
  new_files=${new_files:-0}

  echo "$lines $files $new_files"
}

# ── Evidence writers ──

# Atomic append with lock for concurrent sub-agent safety
_atomic_append() {
  local file="$1" entry="$2" session_id="$3"
  local lock_file="/tmp/claude-evidence-${session_id}.lock"

  if command -v flock >/dev/null 2>&1; then
    # Use exec to open the fd inside the subshell — avoids the bare
    # `200>"$lock_file"` redirect on the closing paren which is a zsh parse error.
    (
      exec 200>"$lock_file"
      flock -x 200
      echo "$entry" >> "$file"
    )
  else
    # Spin-lock using mkdir (atomic on all platforms)
    local lock_dir="${lock_file}.d"
    local max_wait=50  # 50 * 0.01s = 0.5s max
    local i=0
    while ! mkdir "$lock_dir" 2>/dev/null; do
      i=$((i + 1))
      [ "$i" -ge "$max_wait" ] && break
      sleep 0.01
    done
    echo "$entry" >> "$file"
    rmdir "$lock_dir" 2>/dev/null || true
  fi
}

append_evidence() {
  local session_id="$1" type="$2" result="$3" cwd="$4"
  cwd=$(_resolve_cwd "$session_id" "$cwd")
  local file
  file=$(evidence_file "$session_id")
  local diff_hash
  diff_hash=$(compute_diff_hash "$cwd")
  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  local entry
  entry=$(jq -cn \
    --arg ts "$timestamp" \
    --arg type "$type" \
    --arg result "$result" \
    --arg hash "$diff_hash" \
    --arg session "$session_id" \
    '{timestamp: $ts, type: $type, result: $result, diff_hash: $hash, session: $session}')

  _atomic_append "$file" "$entry" "$session_id"
}

# ── Triage override ──
# Allows overriding a critic verdict with a rationale when findings are out-of-scope.
# Only permitted for critic types (code-critic, minimizer). Cannot override codex or PR gates.
# Records the override in evidence with triage_override flag for audit trail.

append_triage_override() {
  local session_id="$1" type="$2" rationale="$3" cwd="$4"

  # Guard: only critic types can be overridden
  case "$type" in
    code-critic|minimizer) ;;
    *) echo "ERROR: triage override not allowed for type '$type' (only: code-critic, minimizer)" >&2; return 1 ;;
  esac

  if [ -z "$rationale" ]; then
    echo "ERROR: triage override requires a rationale" >&2
    return 1
  fi

  cwd=$(_resolve_cwd "$session_id" "$cwd")
  local file
  file=$(evidence_file "$session_id")
  local diff_hash
  diff_hash=$(compute_diff_hash "$cwd")

  # Guard: critic must have actually run on this hash (has any entry at current diff_hash).
  # Accepts both base type (e.g., "minimizer") and run-tracking type (e.g., "minimizer-run")
  # as proof — the -run entries are recorded by oscillation tracking in agent-trace-stop.
  if [ -f "$file" ]; then
    if ! jq -e --arg type "$type" --arg run_type "${type}-run" --arg hash "$diff_hash" \
      'select((.type == $type or .type == $run_type) and .diff_hash == $hash)' "$file" >/dev/null 2>&1; then
      echo "ERROR: triage override requires '$type' to have run at current diff_hash. Run the critic first." >&2
      return 1
    fi
  else
    echo "ERROR: no evidence file — critic must run before override is possible" >&2
    return 1
  fi
  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  local entry
  entry=$(jq -cn \
    --arg ts "$timestamp" \
    --arg type "$type" \
    --arg result "APPROVED" \
    --arg hash "$diff_hash" \
    --arg session "$session_id" \
    --arg rationale "$rationale" \
    '{timestamp: $ts, type: $type, result: $result, diff_hash: $hash, session: $session, triage_override: true, rationale: $rationale}')

  _atomic_append "$file" "$entry" "$session_id"

  # Update the -run verdict timeline so check_evidence sees the override.
  # Without this, the latest -run entry would still show REQUEST_CHANGES,
  # causing check_evidence to reject despite the triage override.
  local run_entry
  run_entry=$(jq -cn \
    --arg ts "$timestamp" \
    --arg type "${type}-run" \
    --arg result "APPROVED" \
    --arg hash "$diff_hash" \
    --arg session "$session_id" \
    '{timestamp: $ts, type: $type, result: $result, diff_hash: $hash, session: $session, triage_override: true}')
  _atomic_append "$file" "$run_entry" "$session_id"
}

# ── Evidence readers ──

check_evidence() {
  local session_id="$1" type="$2" cwd="$3"
  cwd=$(_resolve_cwd "$session_id" "$cwd")
  local file
  file=$(evidence_file "$session_id")
  [ ! -f "$file" ] && return 1

  local diff_hash
  diff_hash=$(compute_diff_hash "$cwd")

  # Match on type AND current diff_hash — stale evidence is ignored
  if ! jq -e --arg type "$type" --arg hash "$diff_hash" \
    'select(.type == $type and .diff_hash == $hash)' "$file" >/dev/null 2>&1; then
    return 1
  fi

  # For types with -run tracking (critics), the latest verdict at this hash
  # supersedes prior APPROVED entries. A later REQUEST_CHANGES invalidates approval.
  local run_type="${type}-run"
  if jq -e --arg rt "$run_type" --arg hash "$diff_hash" \
    'select(.type == $rt and .diff_hash == $hash)' "$file" >/dev/null 2>&1; then
    local latest_run
    latest_run=$(jq -s --arg rt "$run_type" --arg hash "$diff_hash" \
      '[.[] | select(.type == $rt and .diff_hash == $hash)] | last | .result' "$file" 2>/dev/null)
    if [ "$latest_run" = '"REQUEST_CHANGES"' ]; then
      return 1
    fi
  fi
  return 0
}


check_all_evidence() {
  local session_id="$1" types_string="$2" cwd="$3"
  local missing=""
  local diagnostics=""
  # Lazy-computed on first miss to avoid redundant git calls when all evidence is present
  local _diag_hash="" _diag_file=""

  # Split space-separated types
  for type in $types_string; do
    if ! check_evidence "$session_id" "$type" "$cwd"; then
      missing="$missing $type"
      # Stale diagnostic: compute hash lazily on first miss
      if [ -z "$_diag_hash" ]; then
        local resolved_cwd
        resolved_cwd=$(_resolve_cwd "$session_id" "$cwd")
        _diag_hash=$(compute_diff_hash "$resolved_cwd")
        _diag_file=$(evidence_file "$session_id")
      fi
      if [ -f "$_diag_file" ] && [ "$_diag_hash" != "unknown" ]; then
        # Skip stale hint if a -run entry exists at the current hash — the critic
        # already ran on current code (e.g. REQUEST_CHANGES), so this is an active
        # failure, not stale evidence.
        local has_current_run=""
        has_current_run=$(jq -r --arg rt "${type}-run" --arg hash "$_diag_hash" \
          'select(.type == $rt and .diff_hash == $hash) | .type' "$_diag_file" 2>/dev/null | head -1)
        if [ -z "$has_current_run" ]; then
          local stale_hash
          stale_hash=$(jq -r --arg type "$type" \
            'select(.type == $type) | .diff_hash' "$_diag_file" 2>/dev/null | tail -1)
          if [ -n "$stale_hash" ] && [ "$stale_hash" != "$_diag_hash" ]; then
            diagnostics="${diagnostics}\n  ${type}: exists at stale hash ${stale_hash:0:12}… but current code is at ${_diag_hash:0:12}… — re-run to refresh"
          fi
        fi
      fi
    fi
  done

  if [ -n "$missing" ]; then
    echo "$missing"
    if [ -n "$diagnostics" ]; then
      echo -e "$diagnostics" >&2
    fi
    return 1
  fi
  return 0
}
