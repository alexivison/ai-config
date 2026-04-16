# Task 11 — Relocate Config to User-Global Only (Drop `.party.toml`)

**Dependencies:** Tasks 1–10 (this task modifies code they created)
**Branch:** `feature/multi-agent-planning` (or a follow-up branch after Tasks 1–10 land)

## Goal

Remove `.party.toml` repo-level config entirely. Agent selection is a user preference, not a repo property — storing it in repos creates git noise. Replace it with a user-global config at `~/.config/party-cli/config.toml` (XDG-aware), and add `party-cli config` so users can manage preferences without editing TOML by hand.

## Scope

- `tools/party-cli/internal/agent/config.go` — remove repo walk, use user-global lookup only
- `tools/party-cli/cmd/config.go` — add `party-cli config` (`init`, `show`, `path`, `set-primary`, `set-companion`, `unset-companion`)
- `tools/party-cli/cmd/agent.go` — stop using `repoRoot` for config resolution
- Tests and hooks — move fixtures to XDG config homes instead of repo-local files
- Docs — update active docs to describe the user-global config model

## Acceptance Criteria

- [x] `.party.toml` support removed from the active config loader
- [x] `LoadConfig` no longer takes a `cwd` parameter
- [x] `UserConfigPath()` respects `XDG_CONFIG_HOME` and falls back to `~/.config/party-cli/config.toml`
- [x] `party-cli config` exists with `init`, `show`, `path`, `set-primary`, `set-companion`, and `unset-companion`
- [x] `party-cli agent query` no longer depends on CWD or `PARTY_REPO_ROOT`
- [x] Hook tests use user-global config fixtures
- [x] README, CLAUDE, AGENTS, and multi-agent planning docs describe the user-global config
