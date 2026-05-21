# Questmaster split — extract `tools/party-cli/` into its own OSS repo

Status: planning. Branch: `claude/party-cli-open-source-JkX27`.

Goal: extract the Go CLI currently at `tools/party-cli/` into a standalone open-source repo, rename it to `questmaster` (binary alias `qm`), and update this dotfiles repo to consume it as an external dependency.

## Locked decisions

| Item | Value |
|---|---|
| New repo | `github.com/alexivison/questmaster` (personal GitHub, not an org) |
| Binary name | `questmaster` (primary), `qm` (alias) |
| `qm` alias mechanism | `install.sh` creates `~/.local/bin/qm -> questmaster` symlink (no code change in questmaster) |
| License | MIT |
| Go module path | `github.com/alexivison/questmaster` |
| History strategy | `git filter-repo` — single pass that extracts `tools/party-cli/` AND rewrites author emails via `--mailmap` |
| Author emails on public history | Keep `aleksi.j.tuominen@hotmail.com` only. Scrub `ci@test.local` (CI noise) and `aleksi.tuominen@legalontech.jp` (corporate co-author trailers) via mailmap |
| Distribution (v0.1) | `go install` only. Defer goreleaser/Homebrew until there's demand |
| Version embedding | `runtime/debug.ReadBuildInfo()` in `cmd/root.go` — works automatically with `go install ...@vX.Y.Z` since Go 1.18. No ldflags / Makefile dependency |
| State-dir migration | Migrate `~/.party-state` → `~/.questmaster-state` and `~/.config/party-cli/` → `~/.config/questmaster/` with detection code. Old paths preserved with `.moved-to-questmaster` marker, not deleted |
| Phase sequencing | Phase 1 in this repo is **purely additive** — no binary rename, no breaking changes to `install.sh`. The user-visible rename happens in the new repo before v0.1.0 tag (Phase 2) |
| Theme | Fantasy / adventuring-party (continues existing branding) |

## Current state assessment

Researched by 5 parallel sub-agents covering boundaries, coupling, OSS readiness, build/CI, and migration strategy.

### What's good

- **Self-contained Go module.** No imports outside the module (only third-party deps: cobra, bubbletea, lipgloss, toml). No file reads from sibling dirs (`claude/`, `codex/`, `pi/`, `shared/`, `session/`).
- **Tests mostly pass cleanly.** All 14 packages green via `go test ./...` from `tools/party-cli/` — but with a caveat (see #5 below): three `TestSpawnCmd_*` tests in `cmd/lifecycle_test.go` rely on the `go run` fallback in `internal/config/resolve.go:22-26` finding `<repoRoot>/tools/party-cli/main.go`, and would fail in isolation outside the dotfiles layout.
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
| 13 | Binary rename `party-cli` → `questmaster` + `qm` alias. Touches: Makefile, cobra `Use:`, user-facing warning strings, embedded asset filename, codex hook markers at `internal/hooks/codex.go:33-34` (`codexTrustBegin/End = "# BEGIN/END party-cli codex hook trust"`), migration code for legacy installs | Multiple files | Medium — happens in new repo, split into 3 commits (see Phase 2) |
| 14 | No version embedding via `runtime/debug.ReadBuildInfo()` despite `Version = "dev"` declared. Note: ldflags via Makefile is incompatible with `go install` (which ignores Makefile) | `cmd/root.go:14-15` | Trivial — switch to `ReadBuildInfo()` |

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

| Phase | Net effort |
|---|---|
| Phase 1: additive cleanup commits in this repo | ~3-4 hours |
| Phase 2: extraction + rename + push + tag v0.1.0 (in the new repo) | ~3-4 hours |
| Phase 3: dotfiles updates (rename sweep + verify) | ~3-4 hours |
| **Total active work** | **~9-12 hours / ~1.5 focused days** |

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
   cd tools/party-cli && go mod tidy && go build ./... && go test ./...
   ```

4. **Scrub personal info** in five files:
   - `internal/session/session_test.go:371` — `/Users/aleksi/...` → `t.TempDir()`
   - `internal/agent/codex.go:14` — drop the `~/Code/ai-party/session/party-relay.sh` reference from the master prompt
   - `internal/tui/style.go:9` — remove the `~/Code/scry/...` comment
   - `internal/picker/create_test.go:132, 201, 203, 207` — `"legalon-next"` → `"project-next"`, `"legalon-web"` → `"project-web"`, `/legalon` → `/project`

5. **Rework `TestSpawnCmd_*` tests in `cmd/lifecycle_test.go`** to not depend on the `go run` fallback (inject a stub binary path via env var or `t.Setenv`). The fallback itself stays in this repo (Phase 1 doesn't drop it — Phase 2 does, in the new repo). This commit just makes the tests robust enough to survive the eventual fallback removal.

6. **Switch version to `runtime/debug.ReadBuildInfo()`** in `cmd/root.go`. Replace `var Version = "dev"` with a function that pulls from `BuildInfo.Main.Version` when present, fallback to `"dev"`. Works automatically with `go install github.com/alexivison/questmaster@v0.1.0`.

7. **Write standalone `tools/party-cli/README.md`** — what questmaster is, who it's for, install (`go install github.com/alexivison/questmaster@latest`), usage examples (start/spawn/relay/broadcast/status), the tracker TUI with a screenshot or asciinema link, config schema. Don't reference the parent dotfiles repo (it's a downstream consumer, not a dependency). Note: still describes the binary as `party-cli` here; gets rewritten in Phase 2 step 14.

8. **Add inert OSS scaffolding** inside `tools/party-cli/`:
   - `.github/workflows/ci.yml` — `go build && go vet && go test` on Ubuntu and macOS, Go 1.25.x.
   - `.github/ISSUE_TEMPLATE/{bug_report,feature_request}.md`
   - `.github/PULL_REQUEST_TEMPLATE.md`
   - `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`

   These files are **inert in this dotfiles repo** — GitHub Actions only reads `.github/` at the repo root, and the templates need to be at root too. They activate after Phase 2 step 10 lifts them via filter-repo.

### Phase 2 — extraction, rename, and first release (in the new repo)

This phase has two distinct halves: (a) get the code into the new repo via filter-repo, then (b) do the binary rename + tag in the new repo.

9. **Prepare mailmap** at `/tmp/questmaster.mailmap`:
   ```
   Aleksi Tuominen <aleksi.j.tuominen@hotmail.com> CI <ci@test.local>
   Aleksi Tuominen <aleksi.j.tuominen@hotmail.com> CI <ci@local>
   Aleksi Tuominen <aleksi.j.tuominen@hotmail.com> Aleksi Tuominen <aleksi.tuominen@legalontech.jp>
   ```
   This collapses all three identities into the hotmail one across authors AND `Co-authored-by:` trailers.

10. **Single `git filter-repo` pass** that extracts the path AND rewrites identities:
    ```
    pip install git-filter-repo  # if not already installed
    git clone --no-local /home/user/ai-party /tmp/questmaster-staging
    cd /tmp/questmaster-staging
    git filter-repo \
      --path tools/party-cli \
      --path-rename tools/party-cli/: \
      --mailmap /tmp/questmaster.mailmap
    # Verify
    git log --format='%aE %cE' | sort -u    # should show only hotmail
    ls    # should show: cmd/ internal/ main.go go.mod LICENSE README.md ...
    go build ./... && go test ./... && go vet ./...
    ```
    Caveat (worth noting in the eventual GitHub Release notes): commit messages preserved by filter-repo will reference dotfiles PR numbers (`#266`, `#241`, etc.) and may read out of context. Acceptable for v0.1.

11. **Do the binary rename inside `/tmp/questmaster-staging`**, split into three reviewable commits. The full rename never lives in the dotfiles repo — only in the new repo.

    **11a — Binary name + cobra + user-facing strings** (mechanical):
    - `Makefile`: output binary `questmaster` instead of `party-cli`
    - `cmd/root.go`: cobra `Use:` field → `"questmaster"`
    - All user-facing warning/error strings that say `"party-cli: warning: ..."` (`internal/session/start.go:82`, `internal/session/continue.go:103`, etc.)

    **11b — Embedded asset + hook markers** (file-system contract):
    - Rename `internal/hooks/assets/party-cli-state.sh` → `questmaster-state.sh`, update `//go:embed` directive in `internal/hooks/manager.go:24`
    - Update on-disk install path in `internal/hooks/{claude,codex,pi}.go` from `party-cli-state.sh` → `questmaster-state.sh`
    - Rename the codex hook-trust block markers at `internal/hooks/codex.go:33-34`:
      ```
      codexTrustBegin = "# BEGIN questmaster codex hook trust"
      codexTrustEnd   = "# END questmaster codex hook trust"
      ```
    - Rename `PartyCLISidecarVersion = "phase2-v1"` → `QuestmasterSidecarVersion = "v1"` (verified write-only per #8 above; if grep finds an `==` comparison, the value stays `"phase2-v1"` and only the constant identifier changes)

    **11c — Migration code for legacy `party-cli` installs.** This is the hard part. Implement in `internal/hooks/manager.go` (or a new `internal/hooks/migrate.go`), called automatically at the start of `questmaster hooks install`:

    **Algorithm:**

    For each known hook-script location (`~/.claude/hooks/party-cli-state.sh`, `~/.codex/hooks/party-cli-state.sh`):
    - If file doesn't exist → noop.
    - If file exists, compare SHA-256 to the original embedded asset's hash:
      - **Hash matches** (user never edited) → delete the file.
      - **Hash differs** (user edited) → move to `<path>.bak.YYYYMMDD` and log: `"questmaster: preserved your modified party-cli-state.sh as <bak path>"`.

    For each managed config (`~/.claude/settings.json`, `~/.codex/config.toml`):
    - Locate `# BEGIN party-cli ...` ... `# END party-cli ...` block (or JSON equivalent for `settings.json`).
    - **Both markers present, content matches original embedded block** → delete silently.
    - **Both markers present, content was edited** → leave intact, log warning: `"questmaster: edited party-cli block in <path>; remove manually after verifying"`. Install the new questmaster block alongside.
    - **Only one marker present** (corrupt) → log error: `"questmaster: orphan party-cli marker in <path>; not touching"`. Install new block; don't repair.
    - **No markers** (clean) → install new questmaster block.

    For state-dir migration (`~/.party-state/` → `~/.questmaster-state/`, `~/.config/party-cli/` → `~/.config/questmaster/`):
    - If old path exists, new path doesn't → copy recursively, write `~/.party-state/.moved-to-questmaster` marker file (don't delete originals; user can `rm -rf` themselves once confident).
    - If both exist → log warning: `"questmaster: both ~/.party-state and ~/.questmaster-state present; using ~/.questmaster-state"`. Skip copy.
    - If neither exists → noop (fresh install).

    Order of operations within a single `hooks install` call:
    1. State-dir migration first (idempotent copy, lowest risk).
    2. Hook-file cleanup (delete or `.bak`).
    3. Managed-block cleanup (delete or warn).
    4. Install new questmaster hooks.

    Add a `--dry-run` flag that prints what would happen without doing it.

12. **Update `tools/party-cli/README.md`** (now at repo root) to say `questmaster` and `qm` throughout, with the migration note: "Upgrading from `party-cli`? Run `questmaster hooks install` once — it auto-migrates state dirs and hook files."

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
    - Drop the `go -C tools/party-cli run .` fallbacks.
    - Create `qm` alias symlink: `ln -sf questmaster "$HOME/.local/bin/qm"`.
    - **Remove stale `~/.local/bin/party-cli` from prior installs**: `rm -f "$HOME/.local/bin/party-cli"` (guarded so a fresh install isn't surprised by a missing-file error).
    - **Force-run migration**: after install, run `questmaster hooks install` unconditionally so the migration algorithm fires.
    - Add fallback error message: *"Install Go (1.18+) or download a binary from https://github.com/alexivison/questmaster/releases"*.

19. **Update shell wrappers**:
    - `claude/hooks/lib/party-cli.sh` → rename to `claude/hooks/lib/questmaster.sh`. Drop the `go run` fallback (lines 29-34). Replace `party-cli` invocations with `questmaster` (or `qm`).
    - `claude/hooks/{companion-gate,companion-guard,companion-trace,pr-gate}.sh` — update the `source` path to the renamed lib and update invocations.
    - `session/party.sh`, `session/party-relay.sh` — update invocations. Filename rename is optional (leave as-is for muscle memory, or rename to `session/quest.sh` / `session/quest-relay.sh` for consistency — decide at commit time).

20. **Update TypeScript extensions** `pi/agent/extensions/{activity-sidecar,ask-user}.ts` — `const PARTY_CLI = "party-cli"` → `const QUESTMASTER = "questmaster"`.

21. **Update test mocks** — `claude/hooks/tests/test-*.sh` and `tests/test-*.sh` that mock the binary by name. Sweep all `mock_party_cli` style helpers.

22. **Update docs** — sweep `README.md`, `claude/CLAUDE.md`, `codex/AGENTS.md`, `claude/rules/execution-core-claude-internals.md`, `shared/skills/party-dispatch/SKILL.md`, `docs/pi-companion.md`. Replace command references and link to the new repo.

23. **Trim `go-tests` job from `.github/workflows/ci.yml`** — that job now lives in the new repo. Keep `shell-tests`.

24. **Delete this planning directory** `docs/projects/questmaster-split/` and the historical `docs/projects/party-cli-refactor/` once the migration is complete and verified.

## Risk and rollback

- **Phase 1 is fully reversible and non-breaking.** Every commit leaves `install.sh` working with the existing `party-cli` binary name. Can be merged to `main` at any time without breaking anything.
- **Phase 2 is fully reversible until step 14** (`git push`). The filter-repo run is non-destructive (works on a clone); the binary rename happens entirely inside the staging clone. If the split goes wrong, `rm -rf /tmp/questmaster-staging` and start over.
- **Recommended safety step:** push first to a **private** `alexivison/questmaster-staging` repo to validate CI on GitHub before pushing to the real public `alexivison/questmaster`. Delete the staging repo afterward.
- **Phase 3 is the only point where the dotfiles repo's `install.sh` changes from `party-cli` to `questmaster`.** Between v0.1.0 release (Phase 2) and Phase 3 commit 18, the dotfiles repo still builds and uses the old `party-cli`. They co-exist cleanly. Phase 3 can be deferred indefinitely.
- **Don't delete `tools/party-cli/` from this repo until** the new repo has a tagged release AND `go install github.com/alexivison/questmaster@v0.1.0` works on a clean machine.
- **The migration code (Phase 2 step 11c) is the highest-risk single piece** because it mutates user state on disk. Mandatory: write tests for it (golden-file comparisons for the managed-block detection) and ship a `--dry-run` flag.

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
- *Migration*: "42 commits touch `tools/party-cli/`, path has been stable (no renames), so `git subtree split` (originally) or `git filter-repo` (per email scrubbing decision) is the right tool."

Plus 21 review comments from a follow-up review session that caught: ldflags/`go install` incompatibility, the lifecycle test dependency on the `go run` fallback, the `legalon` company-name leak in picker tests, broader email exposure (CI + corporate co-authors), missing state-dir migration plan, under-specified migration algorithm, and Phase 1/3 sequencing breakage. All folded into this revision.
