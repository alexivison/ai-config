#!/usr/bin/env bash
# party-master.sh — RETIRED: all master logic now lives in party-cli.
# This stub exists only for backward compatibility with scripts that source it.
# party-cli handles: start --master, promote, master layout, worker management.
#
# All functions (party_launch_master, party_start_master, party_promote) have
# been removed. Callers should use party-cli directly:
#   party-cli start --master     (replaces party_start_master)
#   party-cli promote <session>  (replaces party_promote)
# See tools/party-cli/internal/session/ for the Go implementation.
