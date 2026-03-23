package session

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/anthropics/ai-config/tools/party-cli/internal/config"
	"github.com/anthropics/ai-config/tools/party-cli/internal/state"
)

// StartOpts configures a new session launch.
type StartOpts struct {
	Title          string
	Cwd            string
	Layout         LayoutMode
	Master         bool
	MasterID       string // parent master session ID (for worker spawn)
	ClaudeResumeID string
	CodexResumeID  string
	Prompt         string
	Detached       bool
}

// StartResult holds the outcome of a Start operation.
type StartResult struct {
	SessionID  string
	RuntimeDir string
}

// Start creates and launches a new party session.
func (s *Service) Start(ctx context.Context, opts StartOpts) (StartResult, error) {
	cwd := opts.Cwd
	if cwd == "" {
		var err error
		cwd, err = os.Getwd()
		if err != nil {
			return StartResult{}, fmt.Errorf("get working directory: %w", err)
		}
	}

	sessionID, err := s.generateSessionID(ctx)
	if err != nil {
		return StartResult{}, err
	}

	winName := windowName(opts.Title)
	claudeBin := resolveBinary("CLAUDE_BIN", "claude", filepath.Join(os.Getenv("HOME"), ".local", "bin", "claude"))
	codexBin := resolveBinary("CODEX_BIN", "codex", "/opt/homebrew/bin/codex")
	agentPath := fmt.Sprintf("%s/.local/bin:/opt/homebrew/bin:%s", os.Getenv("HOME"), os.Getenv("PATH"))

	runtimeDir, err := ensureRuntimeDir(sessionID)
	if err != nil {
		return StartResult{}, err
	}

	m := state.Manifest{
		PartyID:    sessionID,
		Title:      opts.Title,
		Cwd:        cwd,
		WindowName: winName,
		ClaudeBin:  claudeBin,
		CodexBin:   codexBin,
		AgentPath:  agentPath,
	}
	if opts.Master {
		m.SessionType = "master"
	}
	if err := s.Store.Create(m); err != nil {
		return StartResult{}, fmt.Errorf("create manifest: %w", err)
	}

	if err := s.Store.Update(sessionID, func(m *state.Manifest) {
		m.SetExtra("last_started_at", state.NowUTC())
		if opts.Prompt != "" {
			m.SetExtra("initial_prompt", opts.Prompt)
		}
		if opts.ClaudeResumeID != "" {
			m.SetExtra("claude_session_id", opts.ClaudeResumeID)
		}
		if opts.CodexResumeID != "" {
			m.SetExtra("codex_thread_id", opts.CodexResumeID)
		}
		if opts.MasterID != "" {
			m.SetExtra("parent_session", opts.MasterID)
		}
	}); err != nil {
		return StartResult{}, fmt.Errorf("update manifest: %w", err)
	}

	if opts.MasterID != "" {
		if err := s.Store.AddWorker(opts.MasterID, sessionID); err != nil {
			return StartResult{}, fmt.Errorf("register worker: %w", err)
		}
	}

	if err := s.Client.NewSession(ctx, sessionID, winName, cwd); err != nil {
		return StartResult{}, fmt.Errorf("create tmux session: %w", err)
	}

	if err := s.launchSession(ctx, launchConfig{
		sessionID:      sessionID,
		cwd:            cwd,
		runtimeDir:     runtimeDir,
		title:          opts.Title,
		claudeBin:      claudeBin,
		codexBin:       codexBin,
		agentPath:      agentPath,
		claudeResumeID: opts.ClaudeResumeID,
		codexResumeID:  opts.CodexResumeID,
		prompt:         opts.Prompt,
		master:         opts.Master,
		layout:         opts.Layout,
	}); err != nil {
		return StartResult{}, err
	}

	return StartResult{SessionID: sessionID, RuntimeDir: runtimeDir}, nil
}

// generateSessionID creates a unique session ID.
func (s *Service) generateSessionID(ctx context.Context) (string, error) {
	base := fmt.Sprintf("party-%d", s.Now())
	exists, err := s.Client.HasSession(ctx, base)
	if err != nil {
		return "", fmt.Errorf("check session: %w", err)
	}
	if !exists {
		return base, nil
	}
	for range 100 {
		id := fmt.Sprintf("party-%d-%d", s.Now(), s.RandSuffix())
		exists, err := s.Client.HasSession(ctx, id)
		if err != nil {
			return "", fmt.Errorf("check session: %w", err)
		}
		if !exists {
			return id, nil
		}
	}
	return "", fmt.Errorf("failed to generate unique session ID")
}

// resolveBinary finds a binary by env var, PATH, or default.
func resolveBinary(envKey, name, fallback string) string {
	if v := os.Getenv(envKey); v != "" {
		return v
	}
	if p, err := exec.LookPath(name); err == nil {
		return p
	}
	return fallback
}

// resolveLayout reads PARTY_LAYOUT from the environment.
// Default is sidebar; set PARTY_LAYOUT=classic to use the legacy layout.
func resolveLayout() LayoutMode {
	if v := os.Getenv("PARTY_LAYOUT"); v == "classic" {
		return LayoutClassic
	}
	return LayoutSidebar
}

// buildClaudeCmd builds the shell command string for launching Claude.
func buildClaudeCmd(claudeBin, agentPath, resumeID, prompt, title string) string {
	cmd := fmt.Sprintf("export PATH=%s; unset CLAUDECODE; exec %s --dangerously-skip-permissions",
		config.ShellQuote(agentPath), config.ShellQuote(claudeBin))
	if title != "" {
		cmd += " --name " + config.ShellQuote(title)
	}
	if resumeID != "" {
		cmd += " --resume " + config.ShellQuote(resumeID)
	}
	if prompt != "" {
		cmd += " -- " + config.ShellQuote(prompt)
	}
	return cmd
}

// buildCodexCmd builds the shell command string for launching Codex.
func buildCodexCmd(codexBin, agentPath, resumeID string) string {
	cmd := fmt.Sprintf("export PATH=%s; exec %s --dangerously-bypass-approvals-and-sandbox",
		config.ShellQuote(agentPath), config.ShellQuote(codexBin))
	if resumeID != "" {
		cmd += " resume " + config.ShellQuote(resumeID)
	}
	return cmd
}

// clearClaudeCodeEnv removes the CLAUDECODE env var from tmux.
// Errors are intentionally ignored — mirrors party.sh:100-101 where the
// unset is best-effort (the var may not exist, or tmux may not be running).
func (s *Service) clearClaudeCodeEnv(ctx context.Context, sessionID string) error {
	_ = s.Client.UnsetEnvironment(ctx, "", "CLAUDECODE")
	_ = s.Client.UnsetEnvironment(ctx, sessionID, "CLAUDECODE")
	return nil
}

// persistResumeIDs writes resume IDs to the runtime directory.
func (s *Service) persistResumeIDs(sessionID, rtDir, claudeID, codexID string) error {
	if claudeID != "" {
		path := filepath.Join(rtDir, "claude-session-id")
		if err := os.WriteFile(path, []byte(claudeID+"\n"), 0o644); err != nil {
			return fmt.Errorf("write claude-session-id: %w", err)
		}
	}
	if codexID != "" {
		path := filepath.Join(rtDir, "codex-thread-id")
		if err := os.WriteFile(path, []byte(codexID+"\n"), 0o644); err != nil {
			return fmt.Errorf("write codex-thread-id: %w", err)
		}
	}
	return nil
}

// setResumeEnv sets resume ID env vars in the tmux session.
func (s *Service) setResumeEnv(ctx context.Context, sessionID, claudeID, codexID string) error {
	if claudeID != "" {
		if err := s.Client.SetEnvironment(ctx, sessionID, "CLAUDE_SESSION_ID", claudeID); err != nil {
			return err
		}
	}
	if codexID != "" {
		if err := s.Client.SetEnvironment(ctx, sessionID, "CODEX_THREAD_ID", codexID); err != nil {
			return err
		}
	}
	return nil
}

// setCleanupHook registers the session-closed hook for cleanup.
// Delegates to scripts/cleanup-hook.sh which handles:
//   - Deregistering from parent's workers list (via jq under flock)
//   - Removing runtime dir
//   - Deleting manifest (unless master)
func (s *Service) setCleanupHook(ctx context.Context, sessionID string) error {
	if s.RepoRoot == "" {
		return fmt.Errorf("PARTY_REPO_ROOT required for cleanup hook")
	}
	scriptPath := filepath.Join(s.RepoRoot, "tools", "party-cli", "scripts", "cleanup-hook.sh")
	hookCmd := fmt.Sprintf(`run-shell "%s %s %s"`,
		config.ShellQuote(scriptPath),
		config.ShellQuote(s.Store.Root()),
		config.ShellQuote(sessionID),
	)
	return s.Client.SetHook(ctx, sessionID, "session-closed", hookCmd)
}
