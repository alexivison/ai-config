package session

import (
	"context"
	"fmt"

	"github.com/anthropics/ai-party/tools/party-cli/internal/agent"
	"github.com/anthropics/ai-party/tools/party-cli/internal/state"
	"github.com/anthropics/ai-party/tools/party-cli/internal/tmux"
)

// Promote converts a worker or standalone session to a master session.
// Replaces the sidebar pane in window 1 with the tracker and kills the hidden
// companion window — master mode has no Wizard.
func (s *Service) Promote(ctx context.Context, sessionID string) error {
	if err := validateSessionID(sessionID); err != nil {
		return err
	}

	m, err := s.Store.Read(sessionID)
	if err != nil {
		return fmt.Errorf("read manifest: %w", err)
	}
	if m.SessionType == "master" {
		return nil // idempotent
	}

	registry, err := s.agentRegistry()
	if err != nil {
		return fmt.Errorf("load agent registry: %w", err)
	}

	if err := s.Client.EnsureSessionRunning(ctx, sessionID, "target"); err != nil {
		return err
	}

	// Set master in manifest BEFORE respawn so party-cli sees correct mode on first render.
	// Clear codex_thread_id — master mode has no Wizard, stale ID confuses the picker.
	newWinName := windowName(m.Title, roleMaster)
	companionEnvVars := companionEnvVars(m, registry)
	if err := s.Store.Update(sessionID, func(m2 *state.Manifest) {
		m2.SessionType = "master"
		m2.WindowName = newWinName
		kept := m2.Agents[:0]
		for _, spec := range m2.Agents {
			if spec.Role != string(agent.RoleCompanion) {
				kept = append(kept, spec)
			}
		}
		m2.Agents = kept
		delete(m2.Extra, "codex_thread_id")
	}); err != nil {
		return fmt.Errorf("update manifest: %w", err)
	}

	for _, envVar := range companionEnvVars {
		_ = s.Client.UnsetEnvironment(ctx, sessionID, envVar)
	}

	winTarget := tmux.WindowTarget(sessionID, tmux.WindowWorkspace)
	if err := s.Client.RenameWindow(ctx, winTarget, newWinName); err != nil {
		return fmt.Errorf("rename window: %w", err)
	}

	cliCmd, err := s.resolveCLICmd()
	if err != nil {
		return fmt.Errorf("resolve party-cli: %w", err)
	}

	if err := s.injectMasterPrompt(ctx, sessionID, m, registry); err != nil {
		return err
	}

	cwd := m.Cwd
	if cwd == "" {
		cwd = "."
	}

	return s.promoteSidebar(ctx, sessionID, cwd, cliCmd)
}

func companionEnvVars(m state.Manifest, registry *agent.Registry) []string {
	envVars := make(map[string]struct{})
	for _, spec := range m.Agents {
		if spec.Role != string(agent.RoleCompanion) {
			continue
		}
		provider, err := agent.Resolve(spec.Name, registry)
		if err != nil || provider.EnvVar() == "" {
			continue
		}
		envVars[provider.EnvVar()] = struct{}{}
	}
	// Legacy manifests may store a stale codex thread ID without a
	// companion agent entry; clear its env var unconditionally.
	if m.ExtraString("codex_thread_id") != "" {
		if provider, err := agent.Resolve("codex", registry); err == nil && provider.EnvVar() != "" {
			envVars[provider.EnvVar()] = struct{}{}
		}
	}
	out := make([]string, 0, len(envVars))
	for envVar := range envVars {
		out = append(out, envVar)
	}
	return out
}

func (s *Service) injectMasterPrompt(ctx context.Context, sessionID string, m state.Manifest, registry *agent.Registry) error {
	primaryName := ""
	for _, spec := range m.Agents {
		if spec.Role == string(agent.RolePrimary) {
			primaryName = spec.Name
			break
		}
	}
	if primaryName == "" {
		binding, err := registry.ForRole(agent.RolePrimary)
		if err != nil {
			return nil
		}
		primaryName = binding.Agent.Name()
	}

	provider, err := registry.Get(primaryName)
	if err != nil || provider.MasterPrompt() == "" {
		return nil
	}

	primaryPane, err := s.Client.ResolveRole(ctx, sessionID, string(agent.RolePrimary), -1)
	if err != nil {
		return fmt.Errorf("find primary pane: %w", err)
	}
	result := s.Client.Send(ctx, primaryPane, provider.MasterPrompt())
	if result.Err != nil {
		return fmt.Errorf("send master prompt to primary: %w", result.Err)
	}
	return nil
}

// promoteSidebar replaces the sidebar pane (window 1, pane 0) with the tracker
// and kills the hidden companion window (window 0) — master mode has no Wizard.
func (s *Service) promoteSidebar(ctx context.Context, sessionID, cwd, cliCmd string) error {
	sidebarTarget := tmux.PaneTarget(sessionID, tmux.WindowWorkspace, 0)

	if err := s.Client.RespawnPane(ctx, sidebarTarget, cwd, cliCmd); err != nil {
		return fmt.Errorf("respawn tracker in sidebar: %w", err)
	}
	if err := s.Client.SetPaneOption(ctx, sidebarTarget, tmux.PaneRoleOption, tmux.RoleTracker); err != nil {
		return err
	}
	if err := s.Client.SelectPaneTitle(ctx, sidebarTarget, "Tracker"); err != nil {
		return err
	}

	// Kill the hidden companion window — master mode doesn't use the Wizard.
	companionWindow := tmux.WindowTarget(sessionID, tmux.WindowCompanion)
	return s.Client.KillWindow(ctx, companionWindow)
}
