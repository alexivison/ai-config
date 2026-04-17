package agent

import (
	"context"
	"fmt"
	"strconv"

	"github.com/anthropics/ai-party/tools/party-cli/internal/config"
	"github.com/anthropics/ai-party/tools/party-cli/internal/tmux"
)

const codexMasterPrompt = "This is a master session. You are an orchestrator, not an implementor. " +
	"HARD RULES: (1) Never edit or write production code yourself — delegate all code changes to workers. " +
	"(2) Spawn workers with `party-cli spawn [title]` or `~/Code/ai-party/session/party-relay.sh --spawn [--prompt \"...\"] [title]`. " +
	"Relay follow-up instructions with `party-cli relay <worker-id> \"message\"`, broadcast with `party-cli broadcast \"message\"`, " +
	"and inspect workers with `party-cli workers` or the tracker pane. " +
	"(3) Read-only investigation is fine."

// Codex implements the built-in Codex provider.
type Codex struct {
	cli string
}

// NewCodex constructs a Codex provider from config.
func NewCodex(cfg AgentConfig) *Codex {
	cli := cfg.CLI
	if cli == "" {
		cli = "codex"
	}
	return &Codex{cli: cli}
}

func (c *Codex) Name() string        { return "codex" }
func (c *Codex) DisplayName() string { return "The Wizard" }
func (c *Codex) Binary() string      { return c.cli }

func (c *Codex) BuildCmd(opts CmdOpts) string {
	binary := opts.Binary
	if binary == "" {
		binary = c.Binary()
	}

	cmd := fmt.Sprintf("export PATH=%s; exec %s --dangerously-bypass-approvals-and-sandbox",
		config.ShellQuote(opts.AgentPath), config.ShellQuote(binary))
	if opts.Master {
		cmd += " -c " + config.ShellQuote("developer_instructions="+strconv.Quote(c.MasterPrompt()))
	}
	if opts.ResumeID != "" {
		cmd += " resume " + config.ShellQuote(opts.ResumeID)
	}
	if opts.Prompt != "" {
		cmd += " " + config.ShellQuote(opts.Prompt)
	}
	return cmd
}

func (c *Codex) ResumeKey() string      { return "codex_thread_id" }
func (c *Codex) ResumeFileName() string { return "codex-thread-id" }
func (c *Codex) EnvVar() string         { return "CODEX_THREAD_ID" }
func (c *Codex) MasterPrompt() string   { return codexMasterPrompt }

func (c *Codex) FilterPaneLines(raw string, max int) []string {
	return tmux.FilterWizardLines(raw, max)
}

func (c *Codex) PreLaunchSetup(_ context.Context, _ TmuxClient, _ string) error {
	return nil
}

func (c *Codex) BinaryEnvVar() string { return "CODEX_BIN" }
func (c *Codex) FallbackPath() string { return "/opt/homebrew/bin/codex" }
