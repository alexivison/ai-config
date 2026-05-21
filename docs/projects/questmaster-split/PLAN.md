# Questmaster split — extract `tools/party-cli/` into its own OSS repo

Status: planning. Branch: `claude/party-cli-open-source-JkX27`.

Goal: extract the Go CLI currently at `tools/party-cli/` into a standalone open-source repo, rename it to `questmaster` (binary alias `qm`), and update this dotfiles repo to consume it as an external dependency.

## Locked decisions

| Item | Value |
|---|---|
| New repo | `github.com/alexivison/questmaster` (personal GitHub, not an org) |
| Binary name | `questmaster` (primary), `qm` (alias) |
| License | MIT |
| Go module path | `github.com/alexivison/questmaster` |
| History strategy | `git subtree split` (preserves all 42 commits as-is) |
| Author email rewrite | No — keep `aleksi.j.tuominen@hotmail.com` on public commits |
| Distribution (v0.1) | `go install` only. Defer goreleaser/Homebrew until there's demand. |
| Theme | Fantasy / adventuring-party (continues existing branding) |

## Current state assessment

Researched by 5 parallel sub-agents covering boundaries, coupling, OSS readiness, build/CI, and migration strategy.

### What's good

- **Self-contained Go module.** No imports outside the module (only third-party deps: cobra, bubbletea, lipgloss, toml). No file reads from sibling dirs (`claude/`, `codex/`, `pi/`, `shared/`, `session/`).
- **Tests pass cleanly.** All 13 packages green via `go test ./...` from `tools/party-cli/`. ~41 test files, all unit-scoped with no host-layout dependencies.
- **State is self-contained.** Uses `$PARTY_STATE_ROOT` / `~/.party-state` for state, XDG (`~/.config/party-cli/`) for config.
- **Hook installers write to user dotfile dirs** (`~/.claude`, `~/.codex`, `~/.pi`) via standard env-var resolution. On this machine those dirs are symlinks to repo dirs; questmaster doesn't know that.
- **No secrets in source or git history.**
- **Embedded asset** (`internal/hooks/assets/party-cli-state.sh`) ships in the binary — no external file deps.
- **Existing CI** (`.github/workflows/ci.yml`) already scopes the Go portion to `tools/party-cli/`.

### What needs fixing before split

| # | Issue | Location | Effort |
|---|---|---|---|
| 1 | Module path renames `github.com/anthropics/ai-party/tools/party-cli` → `github.com/alexivison/questmaster`. ~153 import statements. | `go.mod:1` + every `*.go` | Trivial (sed) |
| 2 | Hardcoded user path in test fixture | `internal/session/session_test.go:371` (`/Users/aleksi/.pi/agent/sessions/project`) | Trivial |
| 3 | Hardcoded `~/Code/ai-party/...` in Codex master prompt | `internal/agent/codex.go:14` | Trivial |
| 4 | Stray reference to `~/Code/scry/...` in comment | `internal/tui/style.go:9` | Trivial |
| 5 | `<repoRoot>/tools/party-cli/main.go` layout assumption (`go run` fallback) | `internal/config/resolve.go:22-26` | Low — delete fallback |
| 6 | Stale phase-named constant `PartyCLISidecarVersion = "phase2-v1"` | `internal/hooks/pi.go:13` | Trivial |
| 7 | No LICENSE | (missing) | Trivial — add MIT |
| 8 | No standalone README | (missing) | Medium — needs prose + TUI screenshot |
| 9 | Binary rename `party-cli` → `questmaster` + `qm` alias | Makefile, `cmd/root.go`, install paths | Low |
| 10 | No version embedding via ldflags despite `Version = "dev"` declared | `Makefile`, `cmd/root.go:14` | Trivial |
| 11 | Hooks install writes `party-cli-state.sh` and managed config blocks tagged `# BEGIN/END party-cli ...` | `internal/hooks/{claude,codex}.go` | Low — rename to `questmaster-state.sh`, update markers, migration code for existing installs |
| 12 | No CONTRIBUTING / CODE_OF_CONDUCT / SECURITY / issue+PR templates | (missing) | Low — boilerplate |

### What stays in this dotfiles repo (touch-up only)

These call into questmaster via `$PATH`. They need a name swap (`party-cli` → `questmaster` or `qm`) but no architectural change:

- `install.sh:121-127, 348-385, 460-467` and `install:106-120` — installer entry points
- `session/party.sh`, `session/party-relay.sh` — bash wrappers
- `claude/hooks/lib/party-cli.sh:29-34` — has a `go run` fallback that breaks after split; delete it
- `claude/hooks/{companion-gate,companion-guard,companion-trace,pr-gate}.sh` — gate hooks
- `claude/hooks/tests/test-*.sh` and top-level `tests/test-*.sh` — mock the binary
- `pi/agent/extensions/{activity-sidecar,ask-user}.ts` — TypeScript wrappers
- Docs: `README.md`, `claude/CLAUDE.md`, `codex/AGENTS.md`, `claude/rules/execution-core-claude-internals.md`, `shared/skills/party-dispatch/SKILL.md`, `docs/pi-companion.md`
- `.github/workflows/ci.yml` — drop the `go-tests` job (moves to new repo); keep the `shell-tests` job

## Effort estimate

Rough sizing for prioritization against other work:

| Phase | Net effort | Calendar time if focused |
|---|---|---|
| Phase 1: cleanup commits | ~4-6 hours | Half a day |
| Phase 2: extraction + push + tag v0.1.0 | ~1 hour | Lunch |
| Phase 3: dotfiles updates (rename sweep + verify) | ~3-4 hours | Half a day |
| **Total active work** | **~8-11 hours** | **1-1.5 focused days** |

Add to that: writing a presentable README (the only soft-skill task) — another 2-3 hours if you want it actually good with a recorded TUI gif.

The work is highly parallelizable and reversible at every step until Phase 2 step "push to GitHub". Nothing is destructive before that.

## Phased execution plan

### Phase 1 — cleanup commits (on `claude/party-cli-open-source-JkX27`)

Each numbered item is one commit, reviewable in isolation.

1. **Add MIT LICENSE** at `tools/party-cli/LICENSE`. Year, copyright holder = the user.
2. **Rename Go module path.** `go.mod:1` to `github.com/alexivison/questmaster`. Then:
   ```
   find tools/party-cli -name '*.go' -exec sed -i \
     's|github.com/anthropics/ai-party/tools/party-cli|github.com/alexivison/questmaster|g' {} +
   cd tools/party-cli && go mod tidy && go build ./... && go test ./...
   ```
3. **Rename binary `party-cli` → `questmaster`.** Update:
   - `tools/party-cli/Makefile` — output binary name
   - `tools/party-cli/cmd/root.go` — cobra `Use:` field
   - User-facing strings that say "party-cli: warning: ..." (`internal/session/start.go:82`, `continue.go:103`, etc.)
   - The embedded `assets/party-cli-state.sh` filename → `questmaster-state.sh` and its on-disk install path
   - Hook config block markers (`# BEGIN/END party-cli codex hook trust` → `# BEGIN/END questmaster codex hook trust`) in `internal/hooks/codex.go`
   - Add migration code in `hooks install` that recognizes and removes the old `party-cli-state.sh` + `# BEGIN/END party-cli ...` markers when upgrading from an existing install, so users (you) don't end up with both
4. **Scrub personal info** in three files:
   - `internal/session/session_test.go:371` — `/Users/aleksi/...` → `t.TempDir()`
   - `internal/agent/codex.go:14` — drop the `~/Code/ai-party/session/party-relay.sh` reference from the master prompt
   - `internal/tui/style.go:9` — remove the `~/Code/scry/...` comment
5. **Drop the `go run` fallback** in `internal/config/resolve.go:22-26` (no longer makes sense standalone). Callers that expected it must now require `questmaster` on `$PATH`.
6. **Rename stale constant** `PartyCLISidecarVersion = "phase2-v1"` → e.g. `QuestmasterSidecarVersion = "v1"` in `internal/hooks/pi.go:13`.
7. **Add `-ldflags` version embedding** to `Makefile` so `questmaster version` reports the tag:
   ```
   VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
   go build -ldflags "-X github.com/alexivison/questmaster/cmd.Version=$(VERSION)" ...
   ```
8. **Write standalone `tools/party-cli/README.md`** — what questmaster is, who it's for, install (`go install github.com/alexivison/questmaster@latest`), usage examples (start/spawn/relay/broadcast/status), the tracker TUI with a screenshot or asciinema link, config schema. Don't reference the parent dotfiles repo (it's a downstream consumer, not a dependency).
9. **Add standalone CI workflow** at `tools/party-cli/.github/workflows/ci.yml` — `go build && go vet && go test` on Ubuntu and macOS, Go 1.25.x. This gets carried into the new repo by `subtree split`.
10. **Add `.github/ISSUE_TEMPLATE/`, `PULL_REQUEST_TEMPLATE.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`** inside `tools/party-cli/` — boilerplate, carried into the new repo by the split.

### Phase 2 — extraction

11. **Subtree split** off `claude/party-cli-open-source-JkX27`:
    ```
    git subtree split --prefix=tools/party-cli -b questmaster-extract
    ```
12. **Clone to staging** at `/tmp/questmaster-staging`, verify `go build ./...`, `go test ./...`, `go vet ./...`.
13. **Create empty `alexivison/questmaster` repo** on GitHub (no auto-init).
14. **Push staging to `main`**:
    ```
    cd /tmp/questmaster-staging
    git remote add origin git@github.com:alexivison/questmaster.git
    git push -u origin questmaster-extract:main
    ```
15. **Tag `v0.1.0`** and create the first GitHub Release: `git tag -a v0.1.0 -m "Initial public release" && git push --tags`.
16. **Enable branch protection** on `main` (require PR + green CI).

### Phase 3 — dotfiles repo updates (only after v0.1.0 release exists)

Each numbered item is one commit.

17. **Delete `tools/party-cli/`** and replace with a stub `tools/party-cli/README.md`: "Moved to https://github.com/alexivison/questmaster".
18. **Update installers** (`install.sh:121-127, 348-385, 460-467` and `install:106-120`):
    - Replace `make -C "$SCRIPT_DIR/tools/party-cli" install` with `GOBIN="$HOME/.local/bin" go install github.com/alexivison/questmaster@v0.1.0` (pin the tag — don't use `@latest` so dotfiles stay reproducible).
    - Drop the `go -C tools/party-cli run .` fallbacks.
    - Add `~/.local/bin/qm -> questmaster` symlink for the alias.
    - Add fallback message: "install Go, or download a binary from <release URL>".
19. **Update shell wrappers** to call `questmaster` (or `qm`):
    - `claude/hooks/lib/party-cli.sh` — rename file to `claude/hooks/lib/questmaster.sh`, drop the `go run` fallback, replace `party-cli` invocations with `questmaster` (or `qm`).
    - `claude/hooks/{companion-gate,companion-guard,companion-trace,pr-gate}.sh` — update the source path and invocation.
    - `session/party.sh`, `session/party-relay.sh` — rename to `session/quest.sh`, `session/quest-relay.sh` (optional but consistent), or keep filenames and only update calls.
20. **Update TypeScript extensions** `pi/agent/extensions/{activity-sidecar,ask-user}.ts` — `const PARTY_CLI = "party-cli"` → `const QUESTMASTER = "questmaster"`.
21. **Update test mocks** — `claude/hooks/tests/test-*.sh` and `tests/test-*.sh` that mock the binary.
22. **Update docs** — sweep `README.md`, `claude/CLAUDE.md`, `codex/AGENTS.md`, `claude/rules/execution-core-claude-internals.md`, `shared/skills/party-dispatch/SKILL.md`, `docs/pi-companion.md`. Replace command references and link to the new repo.
23. **Trim `go-tests` from `.github/workflows/ci.yml`** — that job now lives in the new repo. Keep `shell-tests`.
24. **Delete `docs/projects/party-cli-refactor/`** (or keep as historical) and this `docs/projects/questmaster-split/` directory once the migration is done.

## Open implementation details

These don't block starting; decide when reached.

- **`qm` alias mechanism.** Three options:
  - (a) `install.sh` creates `~/.local/bin/qm -> questmaster` symlink (recommended — zero code change in questmaster)
  - (b) A second cobra root command registered as an alias in questmaster itself
  - (c) Documented shell alias only
- **Hooks-install migration.** When existing users upgrade past the rename, do we auto-clean the old `party-cli-state.sh` / `# BEGIN party-cli` markers, or print a "run `questmaster hooks reinstall`" warning? Recommend auto-clean to avoid double-installs.
- **TUI demo.** Asciinema cast vs. GIF vs. static screenshot for README. GIF is highest-effort, highest-conversion.
- **Repo description + topic tags** for GitHub: e.g. `tmux`, `cli`, `tui`, `ai-agents`, `claude-code`, `codex`, `bubbletea`, `orchestration`, `agent-harness`.

## Risk and rollback

- **Phases 1 and 2 are fully reversible** until the `git push` in step 14. The subtree split is non-destructive (creates a new branch, leaves working tree alone).
- **Don't delete `tools/party-cli/` from this repo until** the new repo has a tagged release AND `go install github.com/alexivison/questmaster@v0.1.0` works on a clean machine.
- **Recommended safety step:** push first to a **private** `alexivison/questmaster-staging` repo to validate CI on GitHub before pushing to the real public `alexivison/questmaster`. Delete the staging repo afterward.
- **If the split goes wrong:** `git branch -D questmaster-extract` and retry. Nothing in `claude/party-cli-open-source-JkX27` is harmed.

## Prioritization notes

If weighing against other in-flight work:

- **Phase 1 commits 1, 2, 7** (LICENSE, module rename, ldflags) are pure mechanical — could batch in 30 minutes between other tasks.
- **Phase 1 commit 8** (README) is the only "creative" work and the bottleneck for actually opening the repo to the public. Could be drafted in parallel with everything else.
- **Phase 3** can be deferred indefinitely after Phase 2 — the new repo and the dotfiles repo can co-exist for as long as you want, with this repo still building `party-cli` from `tools/party-cli/` (until you delete it). Splitting Phase 2 from Phase 3 by days or weeks is fine.
- **The riskiest single step** is the binary rename (commit 3) because it touches the hook-install on-disk contract. The migration code there needs care so existing installs don't end up with both `party-cli-state.sh` and `questmaster-state.sh` registered.

## Reference: agent research summaries

Five sub-agents researched in parallel; their findings are condensed above. Notable quotes:

- *Boundaries*: "The cut is **nearly clean**. The party-cli Go module is self-contained: no imports out, no file reads from sibling dirs, no embedded parent-repo assets."
- *Coupling*: "party-cli is essentially decoupled already. The only Go-level extraction work is renaming the module path and cleaning up the `go run` fallback in `resolve.go`. All other items are dotfiles-side changes."
- *OSS readiness*: "Code itself is OSS-clean (no secrets, virtually no offensive comments, minimal TODOs). The blockers are organizational: missing LICENSE/README, hardcoded ai-party/anthropics paths, one personal-username test fixture, and a 'scry' leak. Maybe a day's work to get presentable."
- *Build/CI*: "41 `_test.go` files. `go test -count=1 ./...` from `tools/party-cli/`: all 13 packages PASS. Nothing reads files from the surrounding ai-party repo."
- *Migration*: "42 commits touch `tools/party-cli/`, path has been stable (no renames), so `git subtree split --prefix=tools/party-cli -b questmaster-extract` is the right tool."
