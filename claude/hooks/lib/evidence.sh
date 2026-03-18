#!/usr/bin/env bash
# evidence.sh — Shared evidence library for the PR gate system
#
# Replaces marker files with a JSONL evidence log per session.
# Each entry records a diff_hash (SHA-256 of branch diff from merge-base).
# Gate hooks compute current diff_hash and only accept matching evidence.
# Stale evidence is automatically ignored — no invalidation hook needed.
#
# Usage: source "$(dirname "$0")/lib/evidence.sh"

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

# ── Diff exclusion pattern (shared constant) ──
_DIFF_EXCLUDES=(-- . ':!*.md' ':!*.log' ':!*.jsonl' ':!*.tmp')

# ── Diff hash computation ──
# Hashes the full working-tree diff from merge-base (committed + staged + unstaged).
# Returns "clean" if no diff, "unknown" if not a git repo.

compute_diff_hash() {
  local cwd="$1"
  if ! _resolve_merge_base "$cwd"; then
    echo "unknown"
    return
  fi

  local diff_output
  diff_output=$(cd "$cwd" && git diff "$_EVIDENCE_MERGE_BASE" "${_DIFF_EXCLUDES[@]}" 2>/dev/null)

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
  numstat=$(cd "$cwd" && git diff --numstat "$_EVIDENCE_MERGE_BASE" "${_DIFF_EXCLUDES[@]}" 2>/dev/null)

  local lines=0 files=0 new_files=0

  if [ -n "$numstat" ]; then
    # numstat format: "adds\tdeletes\tfilename" per file; "-" for binary
    lines=$(echo "$numstat" | awk '{if ($1 != "-") sum += $1 + $2} END {print sum+0}')
    files=$(echo "$numstat" | wc -l | tr -d ' ')
  fi

  new_files=$(cd "$cwd" && git diff --diff-filter=A --name-only "$_EVIDENCE_MERGE_BASE" "${_DIFF_EXCLUDES[@]}" 2>/dev/null \
    | wc -l | tr -d ' ')
  new_files=${new_files:-0}

  echo "$lines $files $new_files"
}

# ── Evidence writers ──

append_evidence() {
  local session_id="$1" type="$2" result="$3" cwd="$4"
  local file
  file=$(evidence_file "$session_id")
  local lock_file="/tmp/claude-evidence-${session_id}.lock"
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

  # Atomic append with lock for concurrent sub-agent safety
  if command -v flock >/dev/null 2>&1; then
    (
      flock -x 200
      echo "$entry" >> "$file"
    ) 200>"$lock_file"
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

# ── Evidence readers ──

check_evidence() {
  local session_id="$1" type="$2" cwd="$3"
  local file
  file=$(evidence_file "$session_id")
  [ ! -f "$file" ] && return 1

  local diff_hash
  diff_hash=$(compute_diff_hash "$cwd")

  # Match on type AND current diff_hash — stale evidence is ignored
  jq -e --arg type "$type" --arg hash "$diff_hash" \
    'select(.type == $type and .diff_hash == $hash)' "$file" >/dev/null 2>&1
}

check_all_evidence() {
  local session_id="$1" types_string="$2" cwd="$3"
  local missing=""

  # Split space-separated types
  for type in $types_string; do
    if ! check_evidence "$session_id" "$type" "$cwd"; then
      missing="$missing $type"
    fi
  done

  if [ -n "$missing" ]; then
    echo "$missing"
    return 1
  fi
  return 0
}
