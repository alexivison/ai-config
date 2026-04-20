package session

import (
	"context"
	"fmt"
	"time"

	"github.com/anthropics/ai-party/tools/party-cli/internal/agent"
	"github.com/anthropics/ai-party/tools/party-cli/internal/config"
)

// launchConfig captures the resolved parameters for launching a session.
// Both Start and Continue build this from their respective inputs, then
// delegate to launchSession for the shared setup sequence.
type launchConfig struct {
	sessionID   string
	cwd         string
	runtimeDir  string
	title       string
	agentPath   string
	master      bool
	worker      bool
	agentCmds   map[agent.Role]string
	agents      map[agent.Role]agent.Agent
	agentResume map[agent.Role]resumeInfo
}

type resumeInfo struct {
	provider agent.Agent
	resumeID string
}

const (
	freshResumeRecoveryAttempts = 30
	freshResumeRecoveryInterval = 100 * time.Millisecond
)

// launchSession performs the shared tmux session setup:
// clear env → set PARTY_SESSION → build commands → persist resume IDs →
// set resume env → choose layout → launch panes → set cleanup hook.
func (s *Service) launchSession(ctx context.Context, lc launchConfig) error {
	for _, role := range []agent.Role{agent.RolePrimary, agent.RoleCompanion} {
		provider, ok := lc.agents[role]
		if !ok {
			continue
		}
		if _, ok := lc.agentCmds[role]; !ok {
			continue
		}
		if err := provider.PreLaunchSetup(ctx, s.Client, lc.sessionID); err != nil {
			return err
		}
	}

	if err := s.Client.SetEnvironment(ctx, lc.sessionID, "PARTY_SESSION", lc.sessionID); err != nil {
		return err
	}

	if lc.agentCmds[agent.RolePrimary] == "" {
		return fmt.Errorf("primary agent command not configured")
	}
	if err := s.persistResumeIDs(lc.runtimeDir, lc.agentResume); err != nil {
		return err
	}
	if err := s.setResumeEnv(ctx, lc.sessionID, lc.agentResume); err != nil {
		return err
	}

	if lc.master {
		if err := s.launchMaster(ctx, lc.sessionID, lc.cwd, lc.agentCmds); err != nil {
			return err
		}
	} else {
		if err := s.launchSidebar(ctx, lc.sessionID, lc.cwd, lc.title, lc.worker, lc.agentCmds); err != nil {
			return err
		}
	}

	if err := s.setCleanupHook(ctx, lc.sessionID); err != nil {
		return err
	}

	s.recoverMissingResumeIDs(ctx, lc.sessionID)
	s.startResumeBackfillSync(ctx, lc)

	return nil
}

func (s *Service) recoverMissingResumeIDs(ctx context.Context, sessionID string) {
	for attempt := 0; attempt < freshResumeRecoveryAttempts; attempt++ {
		status, err := s.SyncMissingResumeIDs(ctx, sessionID)
		if err == nil && !status.Pending {
			return
		}
		if attempt == freshResumeRecoveryAttempts-1 {
			return
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(freshResumeRecoveryInterval):
		}
	}
}

func (s *Service) startResumeBackfillSync(ctx context.Context, lc launchConfig) {
	if !needsResumeBackfillWatcher(lc) {
		return
	}
	s.TriggerResumeBackfillSync(ctx, lc.sessionID)
}

// TriggerResumeBackfillSync launches a bounded background sync that writes any
// newly discovered resume metadata into the manifest, runtime files, and tmux
// session environment. The helper exits on its own once the metadata appears
// or its retry budget expires.
func (s *Service) TriggerResumeBackfillSync(ctx context.Context, sessionID string) {
	cliCmd, err := s.resolveCLICmd()
	if err != nil {
		return
	}

	cmd := fmt.Sprintf(
		"%s backfill-resume %s >/dev/null 2>&1",
		cliCmd,
		config.ShellQuote(sessionID),
	)
	_ = s.Client.RunShell(ctx, sessionID, cmd)
}

func needsResumeBackfillWatcher(lc launchConfig) bool {
	for _, role := range []agent.Role{agent.RolePrimary, agent.RoleCompanion} {
		if _, ok := lc.agentResume[role]; ok {
			continue
		}
		provider, ok := lc.agents[role]
		if !ok || provider == nil {
			continue
		}
		if _, ok := provider.(resumeRecoverer); ok {
			return true
		}
	}
	return false
}
