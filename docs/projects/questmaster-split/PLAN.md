# Questmaster split — extract `tools/party-cli/` into its own OSS repo

Status: planning. Branch: `claude/party-cli-open-source-JkX27`.

Goal: extract the Go CLI currently at `tools/party-cli/` into a standalone open-source repo, rename it to `questmaster` (binary alias `qm`), and update this dotfiles repo to consume it as an external dependency.

## Locked decisions

| Item | Value |
|---|---|
| New repo | `github.com/alexivison/questmaster` (personal GitHub, not an org) |
| Binary name | `questmaster` (primary), `qm` (optional short alias), `party-cli` compatibility shim in dotfiles for one release only |
| Alias mechanism | `go install` only creates `questmaster`; dotfiles `install.sh` creates `~/.local/bin/qm -> questmaster` and a temporary `party-cli -> questmaster` compatibility symlink. Standalone README gives the optional `ln -s` command rather than implying `go install` creates aliases |
| License | MIT |
| Go module path | `github.com/alexivison/questmaster` |
| History strategy | `git filter-repo` — single pass that extracts `tools/party-cli/`, rewrites author/committer identities via `--mailmap`, and rewrites commit-message trailers via `--replace-message` (mailmap alone does **not** touch `Co-authored-by:` lines) |
| Public-history identities | Allow privacy-safe emails only: `aleksi.j.tuominen@hotmail.com` plus public bot noreply identities (`noreply@anthropic.com`, `noreply@github.com`). Scrub local/corporate identities (`ci@test.local`, `ci@local`, `aleksi.tuominen@legalontech.jp`) from metadata and commit messages |
| Distribution (v0.1) | `go install` only. Requires a Go 1.25.x-capable toolchain (current `go.mod` is `go 1.25.7`; older Go may work only with toolchain auto-download). Defer goreleaser/Homebrew until there's demand |
| Version embedding | `runtime/debug.ReadBuildInfo()` in `cmd/root.go` — works automatically with `go install ...@vX.Y.Z`; fallback to `dev` for `(devel)` builds. No ldflags / Makefile dependency |
| State/config migration | Migrate `~/.party-state` → `~/.questmaster-state` and `~/.config/party-cli/` → `~/.config/questmaster/` with detection code. Old paths preserved with `.moved-to-questmaster` marker, not deleted |
| Env-var policy | Prefer `QUESTMASTER_STATE_ROOT` for new sessions. Read legacy `PARTY_STATE_ROOT` as a backward-compatible override. Keep `PARTY_SESSION` / `party-*` session IDs because "party" is product vocabulary, not just the old binary name |
| Phase sequencing | Phase 1 in this repo is **purely additive** — no binary rename, no breaking changes to `install.sh`. The user-visible rename happens in the new repo before v0.1.0 tag (Phase 2) |
| Theme | Fantasy / adventuring-party (continues existing branding) |

## Current state assessment

Researched by 5 parallel sub-agents covering boundaries, coupling, OSS readiness, build/CI, and migration strategy.

### What's good

- **Self-contained Go module.** No imports outside the module (only third-party deps: cobra, bubbletea, lipgloss, toml). No file reads from sibling dirs (`claude/`, `codex/`, `pi/`, `shared/`, `session/`).
- **Tests mostly pass cleanly.** All 14 packages green via `go test ./...` from `tools/party-cli/` — but with a caveat (see #6 below): three `TestSpawnCmd_*` tests in `cmd/lifecycle_test.go` rely on the `go run` fallback in `internal/config/resolve.go:22-26` finding `<repoRoot>/tools/party-cli/main.go`, and would fail in isolation outside the dotfiles layout.
- **State is self-contained.** Uses `$PARTY_STATE_ROOT` / `~/.party-state` for state, XDG (`~/.config/party-cli/`) for config.
- **Hook installers write to user dotfile dirs** (`~/.claude`, `~/.codex`, `~/.pi`) via standard env-var resolution. On this machine those dirs are symlinks to repo dirs; questmaster doesn't know that.
- **No secrets in source or git history.**
- **Embedded asset** (`internal/hooks/assets/party-cli-state.sh`) ships in the binary — no external file deps.
- **Existing CI** (`.github/workflows/ci.yml`) already scopes the Go portion to `tools/party-cli/`.

### What needs fixing

| # | Issue | Location | Effort |
|---|---|---|---|
| 1 | Module path rename `github.com/anthropics/ai-party/tools/party-cli` → `github.com/alexivison/questmaster`. 152 import statements across `*.go` files (verified by `grep -r "github.com/anthropics/ai-party/tools/party-cli" tools/party-cli --include='*.go' \| wc -l`) | `go.mod:1` + every `*.go` | Trivial (sed) |
| 2 | Hardcoded user path in test fixture | `internal/session/session_test.go:371` (`/Users/aleksi/.pi/agent/sessions/project`) | Trivial |
| 3 | Hardcoded `~/Code/ai-party/...` in Codex master prompt | `internal/agent/codex.go:14` | Trivial |
| 4 | Stray reference to `~/Code/scry/...` in comment | `internal/tui/style.go:9` | Trivial |
| 5 | Company-name leak in test fixtures: `"legalon-next"`, `"legalon-web"`, `/legalon` | `internal/picker/create_test.go:132, 201, 203, 207` | Trivial |
| 6 | Three `TestSpawnCmd_*` tests depend on `go run` fallback at `internal/config/resolve.go:22-26` finding `<repoRoot>/tools/party-cli/main.go`. Need rework before the fallback is dropped (Phase 2 in the new repo) | `cmd/lifecycle_test.go` | Low — inject stub binary path via env var or test hook |
| 7 | `<repoRoot>/tools/party-cli/main.go` layout assumption (`go run` fallback) | `internal/config/resolve.go:22-26` | Low — delete in new repo only, alongside test rework |
| 8 | Stale phase-named constant `PartyCLISidecarVersion = "phase2-v1"`. **Verify with `grep -rn "phase2-v1\|PartyCLISidecarVersion" tools/party-cli/`** before renaming — if anything does an `==` comparison, this is a breaking change requiring upgrade logic | `internal/hooks/pi.go:13` | Trivial if write-only marker; Low if read-compared |
| 9 | No LICENSE | (missing) | Trivial — add MIT |
| 10 | No standalone README | (missing) | Medium — needs prose + TUI screenshot |
| 11 | No CHANGELOG.md | (missing) | Trivial scaffold |
| 12 | No CONTRIBUTING / CODE_OF_CONDUCT / SECURITY / issue+PR templates | (missing) | Low — boilerplate |
| 13 | Binary rename `party-cli` → `questmaster` + `qm` alias. Touches: Makefile, cobra `Use:`, version output, all prompt/help/error strings in `internal/agent/{claude,codex,pi}.go`, `cmd/*`, TUI title, benchmark script, tests, embedded asset filename, Codex hook markers/tags at `internal/hooks/codex.go:33-34`, Claude/Codex backup suffixes, Pi marker files, migration code for legacy installs | Multiple files | Medium — happens in new repo, split into 3 commits (see Phase 2) |
| 14 | No version embedding via `runtime/debug.ReadBuildInfo()` despite `Version = "dev"` declared. Note: ldflags via Makefile is incompatible with `go install` (which ignores Makefile) | `cmd/root.go:14-15` | Trivial — switch to `ReadBuildInfo()` |
| 15 | `go.mod` requires Go 1.25.7, so install docs and installer errors must not say Go 1.18+ (ReadBuildInfo needs 1.18, but the module/toolchain needs 1.25.x) | `tools/party-cli/go.mod:3` + README/installers | Trivial |
| 16 | History identity plan must cover actual identities and trailers. Current path history has author/committer emails `ci@test.local`, `noreply@anthropic.com`, `noreply@github.com`, and trailers for `ci@test.local`, `ci@local`, `aleksi.tuominen@legalontech.jp`, `noreply@anthropic.com`; `git filter-repo --mailmap` rewrites metadata but not commit-message trailers | git history | Low |
| 17 | Pi sidecar marker is outside the Go module too: `pi/agent/extensions/activity-sidecar.ts` writes `.party-cli-installed` and shells out to `party-cli`; Phase 3 must update marker paths/version as well as the binary constant | `internal/hooks/pi.go`, `pi/agent/extensions/activity-sidecar.ts` | Low |
| 18 | Standalone OSS README must document runtime assumptions for agent-transport/party-dispatch references in generated prompts, or the prompts must be made generic/configurable. The Go module is source-isolated, but user-facing prompts still point at `~/.claude/skills/...`, `~/.codex/skills/...`, `~/.pi/agent/skills/...`, and `/party-dispatch` | `internal/agent/{claude,codex,pi}.go` | Medium |

### What stays in this dotfiles repo (touch-up only)

These call into questmaster via `$PATH`. They need a name swap (`party-cli` → `questmaster` or `qm`) but no architectural change:

- `install.sh:121-127, 348-385, 460-467` and `install:106-120` — installer entry points
- `session/party.sh`, `session/party-relay.sh` — bash wrappers
- `claude/hooks/lib/party-cli.sh:29-34` — has a `go run` fallback that breaks after split; delete it
- `claude/hooks/{companion-gate,companion-guard,companion-trace,pr-gate}.sh` — gate hooks
- `claude/hooks/tests/test-*.sh` and top-level `tests/test-*.sh` — mock the binary
- `pi/agent/extensions/{activity-sidecar,ask-user}.ts` — TypeScript wrappers, binary name, and Pi sidecar marker (`.party-cli-installed` → `.questmaster-installed`)
- Docs: `README.md`, `claude/CLAUDE.md`, `codex/AGENTS.md`, `claude/rules/execution-core-claude-internals.md`, `shared/skills/party-dispatch/SKILL.md`, `docs/pi-companion.md`
- `.github/workflows/ci.yml` — drop the `go-tests` job (moves to new repo); keep the `shell-tests` job

## Effort estimate

| Phase | Net effort |
|---|---|
| Phase 1: additive cleanup commits in this repo | ~3-4 hours |
| Phase 2: extraction + rename + push + tag v0.1.0 (in the new repo) | ~4-6 hours |
| Phase 3: dotfiles updates (rename sweep + verify) | ~4-5 hours |
| **Total active work** | **~11-15 hours / ~2 focused days** |

Add ~2-3 hours for a presentable README with a recorded TUI gif (the only "creative" task).

The work is reversible at every step until Phase 2 "push to GitHub". Nothing is destructive before that.

## Phased execution plan

### Phase 1 — purely additive cleanup commits (on `claude/party-cli-open-source-JkX27`)

**Invariant: every Phase 1 commit leaves `install.sh` working with the existing `party-cli` name.** No user-visible renames here.

Each numbered item is one commit, reviewable in isolation.

1. **Add MIT LICENSE** at `tools/party-cli/LICENSE`. Year, copyright holder = the user.

2. **Add CHANGELOG.md scaffold** at `tools/party-cli/CHANGELOG.md` with an "Unreleased" section. Populate during Phase 2.

3. **Rewrite Go module path** purely at the import level. Doesn't touch binary name, doesn't break anything at runtime.
   ```
   # First enumerate every file that mentions the old path:
   grep -rln 'github.com/anthropics/ai-party/tools/party-cli' tools/party-cli/
   # Then sed narrowly on .go files only:
   find tools/party-cli -name '*.go' -exec sed -i \
     's|github.com/anthropics/ai-party/tools/party-cli|github.com/alexivison/questmaster|g' {} +
   # Update go.mod:1 manually
   cd tools/party-cli && go mod tidy && go build -buildvcs=false ./... && go test ./...
   ```

4. **Scrub personal info** in five files:
   - `internal/session/session_test.go:371` — `/Users/aleksi/...` → `t.TempDir()`
   - `internal/agent/codex.go:14` — drop the `~/Code/ai-party/session/party-relay.sh` reference from the master prompt
   - `internal/tui/style.go:9` — remove the `~/Code/scry/...` comment
   - `internal/picker/create_test.go:132, 201, 203, 207` — `"legalon-next"` → `"project-next"`, `"legalon-web"` → `"project-web"`, `/legalon` → `/project`

5. **Rework `TestSpawnCmd_*` tests in `cmd/lifecycle_test.go`** to not depend on the `go run` fallback (inject a stub binary path via env var or `t.Setenv`). The fallback itself stays in this repo (Phase 1 doesn't drop it — Phase 2 does, in the new repo). This commit just makes the tests robust enough to survive the eventual fallback removal.

6. **Switch version to `runtime/debug.ReadBuildInfo()`** in `cmd/root.go`. Replace `var Version = "dev"` with a function that pulls from `BuildInfo.Main.Version` when present, fallback to `"dev"`. Works automatically with `go install github.com/alexivison/questmaster@v0.1.0`.

7. **Write standalone `tools/party-cli/README.md`** — what questmaster is, who it's for, prerequisites (Go 1.25.x-capable toolchain, tmux, chosen agent CLIs, and any retained agent-transport/party-dispatch assumptions), install (`go install github.com/alexivison/questmaster@latest`), optional `qm` symlink command, usage examples (start/spawn/relay/broadcast/status), the tracker TUI with a screenshot or asciinema link, and config schema. Don't make the parent dotfiles repo a dependency; if examples assume companion skills from that repo, document them as optional prerequisites. Note: still describes the binary as `party-cli` here; gets rewritten in Phase 2 step 14.

8. **Add inert OSS scaffolding** inside `tools/party-cli/`:
   - `.github/workflows/ci.yml` — `go build -buildvcs=false ./... && go vet ./... && go test ./...` on Ubuntu and macOS, Go 1.25.x.
   - `.github/ISSUE_TEMPLATE/{bug_report,feature_request}.md`
   - `.github/PULL_REQUEST_TEMPLATE.md`
   - `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`

   These files are **inert in this dotfiles repo** — GitHub Actions only reads `.github/` at the repo root, and the templates need to be at root too. They activate after Phase 2 step 10 lifts them via filter-repo.

### Phase 2 — extraction, rename, and first release (in the new repo)

This phase has two distinct halves: (a) get the code into the new repo via filter-repo, then (b) do the binary rename + tag in the new repo.

9. **Prepare identity rewrite inputs** at `/tmp/questmaster.mailmap` and `/tmp/questmaster-message-replacements.txt`:
   ```
   cat >/tmp/questmaster.mailmap <<'EOF'
   Aleksi Tuominen <aleksi.j.tuominen@hotmail.com> CI <ci@test.local>
   Aleksi Tuominen <aleksi.j.tuominen@hotmail.com> CI <ci@local>
   Aleksi Tuominen <aleksi.j.tuominen@hotmail.com> Aleksi Tuominen <aleksi.tuominen@legalontech.jp>
   EOF

   # mailmap rewrites author/committer/tagger metadata only; commit-message
   # trailers need explicit message replacements. Drop CI noise, map corporate
   # co-author trailers to the personal email.
   cat >/tmp/questmaster-message-replacements.txt <<'EOF'
   Co-authored-by: CI <ci@test.local>==>
   Co-authored-by: CI <ci@local>==>
   Co-authored-by: Aleksi Tuominen <aleksi.tuominen@legalontech.jp>==>Co-authored-by: Aleksi Tuominen <aleksi.j.tuominen@hotmail.com>
   EOF
   ```

10. **Single `git filter-repo` pass** that extracts the path and rewrites identities/messages:
    ```
    pip install git-filter-repo  # if not already installed
    git clone --no-local /path/to/ai-party /tmp/questmaster-staging
    cd /tmp/questmaster-staging
    git filter-repo \
      --path tools/party-cli \
      --path-rename tools/party-cli/: \
      --mailmap /tmp/questmaster.mailmap \
      --replace-message /tmp/questmaster-message-replacements.txt

    # Verify source layout and history hygiene before any public push.
    ls    # should show: cmd/ internal/ main.go go.mod LICENSE README.md ...
    git log --format='%ae%n%ce' | sort -u
    # Expected emails: aleksi.j.tuominen@hotmail.com plus allowed public bot noreply identities only.
    ! git log --format='%ae%n%ce%n%B' | grep -E 'ci@test\.local|ci@local|legalontech\.jp'
    ! git log --format='%B' | grep -E '^Co-authored-by: (CI <ci@|Aleksi Tuominen <aleksi\.tuominen@legalontech\.jp>)'
    go build -buildvcs=false ./... && go test ./... && go vet ./...
    ```
    Caveat (worth noting in the eventual GitHub Release notes): commit messages preserved by filter-repo will reference dotfiles PR numbers (`#266`, `#241`, etc.) and may read out of context. Acceptable for v0.1.

11. **Do the binary rename inside `/tmp/questmaster-staging`**, split into three reviewable commits. The full rename never lives in the dotfiles repo — only in the new repo.

    **11a — Binary name + user-facing strings** (mechanical):
    - `Makefile`: output binary `questmaster` instead of `party-cli`
    - `cmd/root.go`: cobra `Use:` field and version output → `"questmaster"`
    - Rename resolver/user-facing identifiers where practical (`ResolvePartyCLICmd` → `ResolveQuestmasterCmd`, error prefixes, TUI title, config help text)
    - Update all generated agent prompts in `internal/agent/{claude,codex,pi}.go` so workers/masters are told to run `questmaster` (or `qm`) instead of `party-cli`
    - Sweep scripts/tests (`scripts/bench-hook.sh`, `*_test.go`) so `rg -n "party-cli" .` after 11a only shows intentional legacy-migration/compatibility references

    **11b — File-system contract + namespace rename**:
    - Rename `internal/hooks/assets/party-cli-state.sh` → `questmaster-state.sh`, update `//go:embed` directive in `internal/hooks/manager.go:24`, and update the rendered script body to call `questmaster hook ...`
    - Update Claude/Codex on-disk script paths from `party-cli-state.sh` → `questmaster-state.sh`; Pi has no hook script path, so handle its marker separately
    - Rename the Codex hook-trust block markers at `internal/hooks/codex.go:33-34`:
      ```
      codexTrustBegin = "# BEGIN questmaster codex hook trust"
      codexTrustEnd   = "# END questmaster codex hook trust"
      ```
    - Rename Codex hooks.json ownership tag from `_party_cli` to `_questmaster` (or document why the old key intentionally stays); migration recognizes old `_party_cli` entries
    - Rename Claude/Codex backup suffixes from `.party-cli.bak` to `.questmaster.bak` for new backups; leave old backup files untouched
    - Rename Pi marker files `.party-cli-installed` → `.questmaster-installed` and `PartyCLISidecarVersion` → `QuestmasterSidecarVersion`. If `grep -rn "phase2-v1\|PartyCLISidecarVersion" .` in the new repo finds read-side comparisons, keep the value `"phase2-v1"` for one release and only rename the identifier/marker path; Phase 3 separately updates the dotfiles TypeScript sidecar constant
    - Rename defaults to `~/.questmaster-state` and `~/.config/questmaster/config.toml`; add `QUESTMASTER_STATE_ROOT` as the primary state override while continuing to read `PARTY_STATE_ROOT` as a legacy alias
    - Keep legacy rendered hook templates or per-agent SHA-256 constants in the code so migration can distinguish pristine old scripts from user-edited scripts after the asset file is renamed

    **11c — Migration code for legacy `party-cli` installs.** This is the hard part. Implement in `internal/hooks/manager.go` (or a new `internal/hooks/migrate.go`), called automatically at the start of `questmaster hooks install`:

    **Algorithm:**

    State/config directory migration (`~/.party-state/` → `~/.questmaster-state/`, `~/.config/party-cli/` → `~/.config/questmaster/`):
    - If old path exists and new path doesn't → copy recursively, write `<old-path>/.moved-to-questmaster` marker file (don't delete originals; user can `rm -rf` themselves once confident).
    - If both exist → log warning: `"questmaster: both ~/.party-state and ~/.questmaster-state present; using ~/.questmaster-state"`. Skip copy.
    - If neither exists → noop (fresh install).
    - Active legacy tmux sessions are **not** live-synced after this one-time copy; README/release notes must tell users to restart or continue sessions through questmaster after migration.

    Hook-script cleanup for old Claude/Codex scripts (`~/.claude/hooks/party-cli-state.sh`, `~/.codex/hooks/party-cli-state.sh`):
    - If file doesn't exist → noop.
    - If file exists, compare SHA-256 against the rendered legacy script for that agent:
      - **Hash matches** (user never edited) → delete the file.
      - **Hash differs** (user edited) → move to `<path>.bak.YYYYMMDD` and log: `"questmaster: preserved your modified party-cli-state.sh as <bak path>"`.

    Pi marker cleanup:
    - Remove old `.party-cli-installed` markers only after writing the new `.questmaster-installed` marker.
    - If both markers exist and versions differ, keep the old marker and warn; don't guess whether a legacy Pi sidecar is still running.

    Managed config cleanup:
    - **Claude `~/.claude/settings.json`**: remove hook entries whose command references `party-cli-state.sh`. There are no begin/end markers in Claude JSON, so detection is command-token based; preserve unrelated hooks and malformed unknown entries.
    - **Codex `~/.codex/hooks.json`**: remove entries tagged `_party_cli` whose command references `party-cli-state.sh`; preserve untagged/user entries even if they call another script.
    - **Codex `~/.codex/config.toml` trust block**: remove a complete `# BEGIN party-cli codex hook trust` ... `# END party-cli codex hook trust` block only when its generated hashes match the legacy commands. If content was edited, leave intact and warn. If only one marker is present, log an error and don't mutate that block.
    - Install the new questmaster hook entries/markers after cleanup so the final state has only questmaster-managed hooks plus any intentionally preserved legacy edits.

    Add a `--dry-run` flag that prints every filesystem/config mutation without doing it. Mandatory tests: pristine old install, user-edited old script, corrupt Codex trust marker, pre-existing new state dir, both old+new state dirs, Pi old/new marker combinations, idempotent second `hooks install`.

12. **Update `tools/party-cli/README.md`** (now at repo root) to say `questmaster` throughout and explain that `qm` is an optional symlink, not something `go install` creates. Include Go 1.25.x prerequisite, the agent-transport/party-dispatch runtime assumption (or its removal), and the migration note: "Upgrading from `party-cli`? Run `questmaster hooks install` once — it auto-migrates state dirs and hook files. Restart existing party-cli tmux sessions after migration."

13. **Create empty `alexivison/questmaster` repo** on GitHub. At creation time configure:
    - Description: e.g. *"A fantasy-themed orchestration harness for AI coding agents — runs your party of Claude / Codex / Pi sessions in tmux"*
    - Topics: `tmux`, `cli`, `tui`, `ai-agents`, `claude-code`, `codex`, `bubbletea`, `orchestration`, `agent-harness`
    - Discussions: **off** for v0.1 (enable later if there's interest)
    - Wiki: **off** (README is canonical)
    - Issues: **on**
    - Sponsors button: **off** for v0.1
    - Dependabot alerts + secret scanning: **on** (free for public repos)
    - Social preview image: optional, defer to v0.2

14. **Push staging branch to `main`**:
    ```
    cd /tmp/questmaster-staging
    git remote add origin git@github.com:alexivison/questmaster.git
    git push -u origin HEAD:main
    ```

15. **Tag `v0.1.0`** and cut the first GitHub Release:
    ```
    git tag -a v0.1.0 -m "questmaster v0.1.0 — initial public release"
    git push --tags
    ```
    Release body: short paragraph on what questmaster is + a one-liner install (`go install github.com/alexivison/questmaster@v0.1.0`) + link to README sections (Features, Quickstart, Configuration). The CHANGELOG.md "Unreleased" section becomes "v0.1.0" with the same content.

16. **Enable branch protection** on `main` (require PR + green CI + linear history).

### Phase 3 — dotfiles repo updates (only after v0.1.0 release exists on GitHub)

Each numbered item is one commit. After this phase, the dotfiles repo no longer contains questmaster source — only references the published binary.

17. **Delete `tools/party-cli/`** and replace with a stub `tools/README.md` (or `tools/party-cli/README.md`): *"Moved to https://github.com/alexivison/questmaster — see the dotfiles `install.sh` for how it's wired up."*

18. **Update installers** (`install.sh:121-127, 348-385, 460-467` and `install:106-120`):
    - Replace `make -C "$SCRIPT_DIR/tools/party-cli" install` with:
      ```
      GOBIN="$HOME/.local/bin" go install github.com/alexivison/questmaster@v0.1.0
      ```
      (pin the tag — don't use `@latest` so dotfiles stay reproducible).
    - Require a Go 1.25.x-capable toolchain (or Go's toolchain auto-download); don't advertise Go 1.18+.
    - Drop the `go -C tools/party-cli run .` fallbacks.
    - Create `qm` alias symlink: `ln -sf questmaster "$HOME/.local/bin/qm"`.
    - Replace any stale `~/.local/bin/party-cli` binary with a temporary compatibility symlink/wrapper to `questmaster` (remove no earlier than a later deprecation release). This prevents old hooks/scripts from hitting a stale binary while still making `questmaster` the primary command.
    - **Force-run migration**: after install, run `questmaster hooks install` unconditionally so the migration algorithm fires.
    - Add fallback error message: *"Install Go 1.25.x (or enable Go toolchain auto-download) or download a binary from https://github.com/alexivison/questmaster/releases"*.

19. **Update shell wrappers**:
    - `claude/hooks/lib/party-cli.sh` → rename to `claude/hooks/lib/questmaster.sh`. Drop the `go run` fallback (lines 29-34). Replace `party-cli` invocations with `questmaster` (or `qm`).
    - `claude/hooks/{companion-gate,companion-guard,companion-trace,pr-gate}.sh` — update the `source` path to the renamed lib and update invocations.
    - `session/party.sh`, `session/party-relay.sh` — update invocations. Filename rename is optional (leave as-is for muscle memory, or rename to `session/quest.sh` / `session/quest-relay.sh` for consistency — decide at commit time).

20. **Update TypeScript extensions** `pi/agent/extensions/{activity-sidecar,ask-user}.ts` — `const PARTY_CLI = "party-cli"` → `const QUESTMASTER = "questmaster"`, marker paths `.party-cli-installed` → `.questmaster-installed`, and sidecar version constant to match `QuestmasterSidecarVersion`.

21. **Update test mocks** — `claude/hooks/tests/test-*.sh` and `tests/test-*.sh` that mock the binary by name. Sweep all `mock_party_cli` style helpers.

22. **Update docs** — sweep `README.md`, `claude/CLAUDE.md`, `codex/AGENTS.md`, `claude/rules/execution-core-claude-internals.md`, `shared/skills/party-dispatch/SKILL.md`, `docs/pi-companion.md`. Replace command references and link to the new repo.

23. **Trim `go-tests` job from `.github/workflows/ci.yml`** — that job now lives in the new repo. Keep `shell-tests`.

24. **Delete this planning directory** `docs/projects/questmaster-split/` and the historical `docs/projects/party-cli-refactor/` once the migration is complete and verified.

## Acceptance criteria and verification gates

Phase 1 is mergeable only when:
- `cd tools/party-cli && go mod tidy && go build -buildvcs=false ./... && go test ./... && go vet ./...` passes.
- `./install.sh --symlinks-only` and the normal installer path still resolve/build the existing `party-cli` name.
- `rg -n "aleksi\.tuominen@legalontech\.jp|/Users/aleksi|~/Code/ai-party|~/Code/scry|legalon" tools/party-cli` has no unintended hits.
- The PR diff contains no binary rename and no `install.sh` breaking change.

Phase 2 is releasable only when:
- Filtered repo CI passes on Ubuntu and macOS with Go 1.25.x.
- `GOBIN=$(mktemp -d) go install github.com/alexivison/questmaster@v0.1.0` installs a `questmaster` binary, and `questmaster version` prints `v0.1.0` (not `dev`).
- `git log --format='%ae%n%ce%n%B'` in the new repo has no `ci@test.local`, `ci@local`, or `legalontech.jp`; author/committer emails are only the allowed set from Locked decisions.
- `rg -n "github.com/anthropics/ai-party/tools/party-cli|~/Code/ai-party|/Users/aleksi|legalon" .` in the new repo has no hits.
- `rg -n "party-cli" .` shows only intentional legacy-migration/compatibility references documented in code comments/tests/README.
- `questmaster hooks install --dry-run` reports the expected migration actions on synthetic legacy homes for Claude, Codex, Pi, state dirs, and config dirs; real `hooks install` is idempotent on a second run.
- Private staging repo CI/secret scanning is green before pushing/tagging the public `alexivison/questmaster` repo.

Phase 3 is complete only when:
- Dotfiles installer works from a clean temp `$HOME`, installs `questmaster`, creates `qm`, replaces stale `party-cli` with the compatibility shim, and runs `questmaster hooks install`.
- A synthetic legacy `$HOME` containing old `party-cli` hooks/config/state migrates without data loss; edited legacy files are backed up or warned exactly as specified.
- `rg -n "go -C .*tools/party-cli|make -C .*tools/party-cli|party-cli" install install.sh session claude pi shared README.md docs tests .github` has only intentional compatibility/deprecation hits.
- Repo CI/shell tests pass after deleting `tools/party-cli/` and trimming the root `go-tests` job.

## Risk and rollback

- **Phase 1 is fully reversible and non-breaking.** Every commit leaves `install.sh` working with the existing `party-cli` binary name. Can be merged to `main` at any time without breaking anything.
- **Phase 2 is fully reversible until step 14** (`git push`). The filter-repo run is non-destructive (works on a clone); the binary rename happens entirely inside the staging clone. If the split goes wrong, `rm -rf /tmp/questmaster-staging` and start over.
- **Public push/tag is the point of no return for consumers.** Validate the filtered history, `go install`, release notes, and CI in a private staging repo before creating/pushing the public `alexivison/questmaster` repo or tag.
- **Recommended safety step:** push first to a **private** `alexivison/questmaster-staging` repo to validate CI on GitHub before pushing to the real public `alexivison/questmaster`. Delete the staging repo afterward.
- **Phase 3 is the only point where the dotfiles repo's `install.sh` changes from `party-cli` to `questmaster`.** Between v0.1.0 release (Phase 2) and Phase 3 commit 18, the dotfiles repo still builds and uses the old `party-cli`. They co-exist cleanly. Phase 3 can be deferred indefinitely.
- **Don't delete `tools/party-cli/` from this repo until** the new repo has a tagged release AND `go install github.com/alexivison/questmaster@v0.1.0` works on a clean machine.
- **Active legacy tmux sessions are not live-migrated.** The state copy is one-time; existing sessions may keep old `PARTY_STATE_ROOT` env and old hook config until restarted/continued. Document this and keep the temporary `party-cli` compatibility shim as rollback insurance.
- **The migration code (Phase 2 step 11c) is the highest-risk single piece** because it mutates user state on disk. Mandatory: write tests for it (golden-file comparisons for managed-block detection, JSON/TOML malformed cases, and synthetic old/new state dirs) and ship a `--dry-run` flag.

## Open implementation details

These don't block starting; decide when reached.

- **TUI demo for README.** Asciinema cast vs. GIF vs. static screenshot. GIF is highest-effort, highest-conversion. Asciinema is lightweight and embeddable.
- **Whether to rename `session/party.sh` → `session/quest.sh`** (and `party-relay.sh` → `quest-relay.sh`) in Phase 3 step 19. Pure aesthetics; muscle memory argues for leaving filenames alone.
- **CHANGELOG.md format.** Recommend Keep-a-Changelog style. Auto-generated from commits via tooling is overkill for v0.1.

## Reference: agent research summaries

Five sub-agents researched in parallel; their findings are condensed above. Notable quotes:

- *Boundaries*: "The cut is **nearly clean**. The party-cli Go module is self-contained: no imports out, no file reads from sibling dirs, no embedded parent-repo assets."
- *Coupling*: "party-cli is essentially decoupled already. The only Go-level extraction work is renaming the module path and cleaning up the `go run` fallback in `resolve.go`. All other items are dotfiles-side changes."
- *OSS readiness*: "Code itself is OSS-clean (no secrets, virtually no offensive comments, minimal TODOs). The blockers are organizational: missing LICENSE/README, hardcoded ai-party/anthropics paths, one personal-username test fixture, and a 'scry' leak. Maybe a day's work to get presentable."
- *Build/CI*: "41 `_test.go` files. `go test -count=1 ./...` from `tools/party-cli/`: all packages PASS. Nothing reads files from the surrounding ai-party repo."
- *Migration*: "221 commits touch `tools/party-cli/`, path has been stable (no renames), so `git filter-repo` with identity/message rewriting is the right tool."

Plus 21 review comments from a follow-up review session that caught: ldflags/`go install` incompatibility, the lifecycle test dependency on the `go run` fallback, the `legalon` company-name leak in picker tests, broader email exposure (CI + corporate co-authors), missing state-dir migration plan, under-specified migration algorithm, and Phase 1/3 sequencing breakage. All folded into this revision.
