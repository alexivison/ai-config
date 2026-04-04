# User Context Summary

## 1. Demographics Information

The user's name is Aleksi Tuominen.
- Evidence: Git commit author "Aleksi Tuominen", email "aleksi.j.tuominen@hotmail.com". GitHub username: alexivison. Date: observed across commits from 2026-03-25 through 2026-04-01.

The user is a software engineer / developer.
- Evidence: The repository contains sophisticated multi-agent orchestration tooling, Go CLI applications, shell scripts, Neovim configuration, and tmux workflows — all authored by the user. The configuration references "senior developer standards" as a baseline expectation. Date: ongoing.

The user uses macOS as a development platform.
- Evidence: install.sh references "brew install" (Homebrew) for dependencies (tmux, fzf, Go, Codex). Date: ongoing.

## 2. Interests and Preferences

The user actively builds and maintains a multi-agent AI coding assistant orchestration system themed as a D&D adventuring party.
- Evidence: The entire ai-config repository is structured around a party metaphor with "The User" as "Mastermind Rogue", Claude Code as "Warforged Paladin", and Codex CLI as "High Elf Wizard" (The Wizard). The user has built a Go-based TUI ("party-cli"), tmux session management, inter-agent transport, a master/worker dispatch system, and an evidence-gated execution pipeline. Date: active development from at least 2026-03-25 through 2026-04-01.

The user actively uses and configures Neovim (LazyVim).
- Evidence: nvim/ directory with .neoconf.json, lazyvim.json, stylua.toml. Commits include "Fix lazy.nvim import order for markdown extras". Date: 2026-03-25.

The user actively uses tmux for development workflow.
- Evidence: tmux/ configuration directory, extensive tmux integration in party sessions, keybindings for session management, and commits like "Refactor tmux.conf to source base config from dotfiles". Date: 2026-03-27.

The user prefers a fantasy/D&D-themed voice for AI agents.
- Evidence: Agents are instructed to "Speak in concise Ye Olde English with dry wit." Date: ongoing configuration.

The user values code quality with a specific philosophy: simplicity, minimal impact, no temporary fixes, and elegance balanced against pragmatism.
- Evidence: CLAUDE.md states "Simplicity First: Make every change as simple as possible. Minimal code impact", "No Laziness: Find root causes. No temporary fixes. Senior developer standards", "Demand Elegance (Balanced): For non-trivial changes, pause and ask 'is there a more elegant way?' If a fix feels hacky, implement the elegant solution. Skip for simple, obvious fixes — do not over-engineer." Date: ongoing configuration.

## 3. Relationships

No confirmed, sustained personal relationships were found in the repository or configuration files.

## 4. Dated Events, Projects and Plans

The user made the execution pipeline source-agnostic, decoupling it from the TASK file format.
- Evidence: Commit "Make execution pipeline source-agnostic: decouple from TASK file format (#116)". Date: 2026-04-01.

The user created a shell-to-Go migration plan with 8 phased tasks.
- Evidence: Commit "Add shell-to-go migration plan with 8 phased tasks (#111)". Date: 2026-03-30.

The user fixed six error handling bugs in party-cli.
- Evidence: Commit "Fix six error handling bugs in party-cli (#114)". Date: 2026-03-30.

The user removed the Codex iteration cap, requiring VERDICT: APPROVED before proceeding.
- Evidence: Commit "Remove Codex iteration cap — require VERDICT: APPROVED before proceeding (#104)". Date: 2026-03-30.

The user added a review metrics system for tracking the lifecycle of review findings.
- Evidence: Commit "Add review metrics system for tracking finding lifecycle". Date: 2026-03-27.

The user added a Scribe agent for requirements fulfillment auditing.
- Evidence: Commit "Add Scribe agent for requirements fulfillment auditing (#101)". Date: 2026-03-27.

The user redesigned the party picker with a visual refresh.
- Evidence: Commit "Redesign party picker with visual refresh and fix title overflow bug". Date: 2026-03-27.

The user added proactive clean code rules and tightened review quality gates.
- Evidence: Commit "Add proactive clean code rules and tighten review quality gates (#97)". Date: 2026-03-26.

The user has an active project plan: "harness-v2" with 15 tasks covering TUI, CLI unification, and tracker functionality.
- Evidence: docs/projects/harness-v2/ with DESIGN.md, SPEC.md, PLAN.md and TASK1 through TASK15. Date: ongoing.

The user has an active project plan: "tui-style-match" to align the TUI with a "Scry" visual theme.
- Evidence: docs/projects/tui-style-match/ with DESIGN.md, SPEC.md, PLAN.md and 4 tasks. Date: ongoing.

The user has an active project plan: "source-agnostic-workflow" to decouple workflows from specific task file formats.
- Evidence: docs/projects/source-agnostic-workflow/ with PLAN.md and 3 tasks. Date: ongoing.

## 5. Instructions

Agents must "Speak in concise Ye Olde English with dry wit. Use 'we' in GitHub-facing prose."
- Evidence: CLAUDE.md line 9 and AGENTS.md line 9.

"Evidence before claims. No assertions without proof."
- Evidence: CLAUDE.md § Verification Principle.

"Codex review is NEVER skippable. You MUST obtain VERDICT: APPROVED from The Wizard before proceeding past the review phase."
- Evidence: CLAUDE.md § Autonomous Flow.

"Do NOT stop between steps."
- Evidence: CLAUDE.md § Autonomous Flow.

"Prefer early guard returns over nested if clauses."
- Evidence: CLAUDE.md § General Guidelines.

"Keep comments short — only remark on logically difficult code."
- Evidence: CLAUDE.md § General Guidelines.

"Clean Code Always: Follow rules/clean-code.md during all implementation. No magic values, no repeated literals, no god functions. Extract constants, split functions, name things well."
- Evidence: CLAUDE.md § Core Principles.

"Open draft PRs unless instructed otherwise."
- Evidence: CLAUDE.md § Git and PR.

"Branch naming: <ISSUE-ID>-<kebab-case-description>."
- Evidence: CLAUDE.md § Git and PR.

"One session per worktree. Never use git checkout or git switch in shared repos."
- Evidence: CLAUDE.md § Worktree Isolation.

"NEVER interact with the Wizard directly via tmux commands."
- Evidence: CLAUDE.md § The Wizard.

"Never mark a task complete without proving it works."
- Evidence: CLAUDE.md § Verification Principle.

"After ANY correction from the user: 1. Identify the pattern that led to the mistake. 2. Write a rule for yourself that prevents the same mistake."
- Evidence: CLAUDE.md § Self-Improvement.
