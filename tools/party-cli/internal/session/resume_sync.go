package session

import (
	"context"
	"fmt"
	"time"

	"github.com/anthropics/ai-party/tools/party-cli/internal/agent"
	"github.com/anthropics/ai-party/tools/party-cli/internal/state"
)

type resumeRecoverer interface {
	RecoverResumeID(cwd, createdAt string) (string, error)
}

// ResumeSyncStatus reports whether more polling is needed for a session's
// resume metadata. Pending stays true while a recoverable agent still lacks
// a stable resume ID.
type ResumeSyncStatus struct {
	Pending bool
}

const (
	resumeBackfillAttempts = 50
	resumeBackfillInterval = 200 * time.Millisecond
)

// SyncMissingResumeIDs backfills missing per-agent resume metadata into the
// manifest, runtime files, and tmux environment for a live session.
func (s *Service) SyncMissingResumeIDs(ctx context.Context, sessionID string) (ResumeSyncStatus, error) {
	alive, err := s.Client.HasSession(ctx, sessionID)
	if err != nil {
		return ResumeSyncStatus{}, fmt.Errorf("check session: %w", err)
	}
	if !alive {
		return ResumeSyncStatus{}, nil
	}

	manifest, err := s.Store.Read(sessionID)
	if err != nil {
		return ResumeSyncStatus{}, fmt.Errorf("read manifest: %w", err)
	}

	registry, err := s.agentRegistry()
	if err != nil {
		return ResumeSyncStatus{}, fmt.Errorf("load agent registry: %w", err)
	}

	desired := make(map[agent.Role]resumeInfo, len(manifest.Agents))
	pending := false
	for _, spec := range manifest.Agents {
		role := agent.Role(spec.Role)
		provider, err := agent.Resolve(spec.Name, registry)
		if err != nil {
			continue
		}

		resumeID := spec.ResumeID
		if resumeID == "" {
			resumeID = manifest.ExtraString(provider.ResumeKey())
		}
		if resumeID == "" {
			recoverer, ok := provider.(resumeRecoverer)
			if !ok {
				continue
			}
			resumeID, err = recoverer.RecoverResumeID(manifest.Cwd, manifest.CreatedAt)
			if err != nil {
				continue
			}
			if resumeID == "" {
				pending = true
				continue
			}
		}

		desired[role] = resumeInfo{
			provider: provider,
			resumeID: resumeID,
		}
	}
	if len(desired) == 0 {
		return ResumeSyncStatus{Pending: pending}, nil
	}

	rtDir, err := ensureRuntimeDir(sessionID)
	if err != nil {
		return ResumeSyncStatus{Pending: pending}, err
	}
	if err := s.persistResumeIDs(rtDir, desired); err != nil {
		return ResumeSyncStatus{Pending: pending}, err
	}
	if err := s.setResumeEnv(ctx, sessionID, desired); err != nil {
		return ResumeSyncStatus{Pending: pending}, err
	}
	if err := s.Store.Update(sessionID, func(m *state.Manifest) {
		mergeResumeMetadata(m, desired)
	}); err != nil {
		return ResumeSyncStatus{Pending: pending}, fmt.Errorf("update manifest: %w", err)
	}

	return ResumeSyncStatus{Pending: pending}, nil
}

// BackfillMissingResumeIDs performs a bounded retry loop for resume metadata
// that only appears after a real user turn (for example, Codex rollout files).
func (s *Service) BackfillMissingResumeIDs(ctx context.Context, sessionID string, attempts int, interval time.Duration) error {
	if attempts <= 0 {
		attempts = resumeBackfillAttempts
	}
	if interval <= 0 {
		interval = resumeBackfillInterval
	}

	for attempt := 0; attempt < attempts; attempt++ {
		status, err := s.SyncMissingResumeIDs(ctx, sessionID)
		if err != nil {
			return err
		}
		if !status.Pending {
			return nil
		}
		if attempt == attempts-1 {
			return nil
		}

		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(interval):
		}
	}
	return nil
}

func mergeResumeMetadata(m *state.Manifest, resume map[agent.Role]resumeInfo) {
	for role, info := range resume {
		if info.provider == nil || info.resumeID == "" {
			continue
		}
		m.SetExtra(info.provider.ResumeKey(), info.resumeID)
		for i := range m.Agents {
			if m.Agents[i].Role == string(role) && m.Agents[i].Name == info.provider.Name() {
				m.Agents[i].ResumeID = info.resumeID
			}
		}
	}
}
