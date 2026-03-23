#!/usr/bin/env bash
# cleanup-hook.sh — tmux session-closed hook for party sessions.
# Called via: run-shell "cleanup-hook.sh <state-root> <session-id>"
#
# Steps:
#   1. Deregister from parent master's workers list (via jq under flock)
#   2. Remove runtime directory (/tmp/<session-id>)
#   3. Delete manifest unless this is a master session
#
# Uses Perl for flock (macOS ships Perl; flock CLI does not exist).
# Uses system() (not exec) so Perl holds the flock while bash runs.
# No set -e: all steps are best-effort to match the original inline hook behavior.
# Each step handles its own errors via || true or explicit guards.

export SR="$1"  # state root directory
export W="$2"   # session ID (e.g. party-1234)

# 1. Deregister from parent's worker list
export p
p=$(jq -r '.parent_session // empty' "$SR/$W.json" 2>/dev/null || true)
if [ -n "$p" ] && [ -f "$SR/$p.json" ]; then
  perl -MFcntl=:flock -e '
    open my $f, ">", shift or exit 1;
    flock($f, LOCK_EX) or exit 1;
    exit(system(@ARGV[1..$#ARGV]) >> 8)
  ' "$SR/$p.json.lock" \
    bash -c 'tmp=$(mktemp); jq --arg w "$W" '"'"'.workers=((.workers//[])-[$w])'"'"' "$SR/$p.json" >"$tmp" && mv "$tmp" "$SR/$p.json" || rm -f "$tmp"'
fi

# 2. Remove runtime directory
rm -rf "/tmp/$W"

# 3. Delete manifest unless master (masters preserve state for workers)
t=$(jq -r '.session_type // empty' "$SR/$W.json" 2>/dev/null || true)
if [ "$t" != "master" ]; then
  rm -f "$SR/$W.json"
fi

exit 0
