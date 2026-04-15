package tui

import (
	"context"
	"fmt"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

type fakeActions struct {
	attachCalls    []string
	relayCalls     []relayCall
	broadcastCalls []broadcastCall
	spawnCalls     []spawnCall
	stopCalls      []string
	deleteCalls    []string
	manifestJSON   map[string]string
	err            error
}

type relayCall struct {
	workerID string
	message  string
}

type broadcastCall struct {
	masterID string
	message  string
}

type spawnCall struct {
	masterID string
	title    string
}

func (f *fakeActions) Attach(_ context.Context, _, targetID string) error {
	f.attachCalls = append(f.attachCalls, targetID)
	return f.err
}

func (f *fakeActions) Relay(_ context.Context, workerID, message string) error {
	f.relayCalls = append(f.relayCalls, relayCall{workerID: workerID, message: message})
	return f.err
}

func (f *fakeActions) Broadcast(_ context.Context, masterID, message string) error {
	f.broadcastCalls = append(f.broadcastCalls, broadcastCall{masterID: masterID, message: message})
	return f.err
}

func (f *fakeActions) Spawn(_ context.Context, masterID, title string) error {
	f.spawnCalls = append(f.spawnCalls, spawnCall{masterID: masterID, title: title})
	return f.err
}

func (f *fakeActions) Stop(_ context.Context, _, workerID string) error {
	f.stopCalls = append(f.stopCalls, workerID)
	return f.err
}

func (f *fakeActions) Delete(_ context.Context, _, workerID string) error {
	f.deleteCalls = append(f.deleteCalls, workerID)
	return f.err
}

func (f *fakeActions) ManifestJSON(sessionID string) (string, error) {
	if f.manifestJSON == nil {
		return "", fmt.Errorf("manifest not found")
	}
	return f.manifestJSON[sessionID], nil
}

func snapshotFetcher(snapshot TrackerSnapshot) SessionFetcher {
	return func(SessionInfo) (TrackerSnapshot, error) {
		return snapshot, nil
	}
}

func newTestTracker(current SessionInfo, snapshot TrackerSnapshot, actions TrackerActions) TrackerModel {
	tm := NewTrackerModel(current, snapshotFetcher(snapshot), actions)
	tm.width = 80
	tm.height = 24
	tm.refreshSessions()
	return tm
}

func keyMsg(r rune) tea.KeyMsg {
	return tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{r}}
}

func TestTrackerViewNoSessions(t *testing.T) {
	t.Parallel()

	tm := newTestTracker(SessionInfo{ID: "party-solo"}, TrackerSnapshot{}, &fakeActions{})
	view := tm.View()

	if !strings.Contains(view, "No sessions") {
		t.Fatalf("expected empty-state message, got:\n%s", view)
	}
}

func TestTrackerViewShowsHierarchy(t *testing.T) {
	t.Parallel()

	snapshot := TrackerSnapshot{
		Sessions: []SessionRow{
			{ID: "party-1230", Title: "Project Alpha", Status: "active", SessionType: "master", WorkerCount: 2, IsCurrent: true},
			{ID: "party-1231", Title: "fix-auth", Status: "active", SessionType: "worker", ParentID: "party-1230", PrimaryState: "active", Stage: StageCriticsOK},
			{ID: "party-1232", Title: "dark-mode", Status: "active", SessionType: "worker", ParentID: "party-1230", PrimaryState: "active", CompanionState: string(CompanionIdle)},
			{ID: "party-1236", Title: "solo task", Status: "active", SessionType: "standalone", PrimaryState: "active"},
		},
		Current: CurrentSessionDetail{
			ID:              "party-1230",
			SessionType:     "master",
			Cwd:             "~/Code/project-b",
			WorkerCount:     2,
			CompanionName:   "codex",
			CompanionStatus: CompanionStatus{State: CompanionIdle, Verdict: "APPROVED"},
		},
	}

	tm := newTestTracker(SessionInfo{ID: "party-1230", SessionType: "master"}, snapshot, &fakeActions{})
	view := tm.View()

	for _, needle := range []string{"Project Alpha", "fix-auth", "dark-mode", "solo task"} {
		if !strings.Contains(view, needle) {
			t.Fatalf("expected %q in view, got:\n%s", needle, view)
		}
	}
	if !strings.Contains(view, "●") {
		t.Fatalf("expected master/standalone glyph in view, got:\n%s", view)
	}
	if !strings.Contains(view, "│") {
		t.Fatalf("expected worker glyph in view, got:\n%s", view)
	}
}

func TestTrackerViewShowsCurrentSessionDetail(t *testing.T) {
	t.Parallel()

	snapshot := TrackerSnapshot{
		Sessions: []SessionRow{
			{ID: "party-2001", Title: "bugfix", Status: "active", SessionType: "worker", ParentID: "party-master", IsCurrent: true},
		},
		Current: CurrentSessionDetail{
			ID:               "party-2001",
			SessionType:      "worker",
			Cwd:              "~/Code/project",
			CompanionName:    "codex",
			CompanionStatus:  CompanionStatus{State: CompanionIdle, Verdict: "APPROVED"},
			CompanionSnippet: "last companion line",
			Evidence: []EvidenceEntry{
				{Type: "code-critic", Result: "APPROVED"},
				{Type: "minimizer", Result: "APPROVED"},
			},
		},
	}

	tm := newTestTracker(SessionInfo{ID: "party-2001", SessionType: "worker"}, snapshot, &fakeActions{})
	view := tm.View()

	for _, needle := range []string{"this session", "companion: codex (idle, APPROVED)", "evidence:", "code-critic", "last companion line"} {
		if !strings.Contains(view, needle) {
			t.Fatalf("expected %q in detail view, got:\n%s", needle, view)
		}
	}
}

func TestTrackerUpdateEnterAttachesActiveSession(t *testing.T) {
	t.Parallel()

	actions := &fakeActions{}
	tm := newTestTracker(SessionInfo{ID: "party-current"}, TrackerSnapshot{
		Sessions: []SessionRow{
			{ID: "party-current", Title: "current", Status: "active", SessionType: "standalone", IsCurrent: true},
			{ID: "party-target", Title: "target", Status: "active", SessionType: "standalone"},
		},
	}, actions)
	tm.cursor = 1

	tm, _ = tm.Update(tea.KeyMsg{Type: tea.KeyEnter})

	if len(actions.attachCalls) != 1 || actions.attachCalls[0] != "party-target" {
		t.Fatalf("expected attach to selected active session, got %#v", actions.attachCalls)
	}
}

func TestTrackerUpdateRelayOnManagedWorker(t *testing.T) {
	t.Parallel()

	actions := &fakeActions{}
	tm := newTestTracker(SessionInfo{ID: "party-master", SessionType: "master"}, TrackerSnapshot{
		Sessions: []SessionRow{
			{ID: "party-master", Title: "master", Status: "active", SessionType: "master", IsCurrent: true},
			{ID: "party-worker", Title: "worker", Status: "active", SessionType: "worker", ParentID: "party-master"},
		},
	}, actions)
	tm.cursor = 1

	tm, _ = tm.Update(keyMsg('r'))
	if tm.mode != trackerModeRelay {
		t.Fatalf("expected relay mode, got %v", tm.mode)
	}

	for _, r := range "investigate" {
		tm, _ = tm.Update(keyMsg(r))
	}
	tm, _ = tm.Update(tea.KeyMsg{Type: tea.KeyEnter})

	if len(actions.relayCalls) != 1 {
		t.Fatalf("expected one relay call, got %#v", actions.relayCalls)
	}
	if actions.relayCalls[0].workerID != "party-worker" || actions.relayCalls[0].message != "investigate" {
		t.Fatalf("unexpected relay call: %#v", actions.relayCalls[0])
	}
}

func TestTrackerUpdateRelayIgnoredOutsideCurrentMaster(t *testing.T) {
	t.Parallel()

	actions := &fakeActions{}
	tm := newTestTracker(SessionInfo{ID: "party-worker", SessionType: "worker"}, TrackerSnapshot{
		Sessions: []SessionRow{
			{ID: "party-master", Title: "master", Status: "active", SessionType: "master"},
			{ID: "party-other-worker", Title: "worker", Status: "active", SessionType: "worker", ParentID: "party-master"},
			{ID: "party-worker", Title: "current", Status: "active", SessionType: "worker", ParentID: "party-master", IsCurrent: true},
		},
	}, actions)
	tm.cursor = 1

	tm, _ = tm.Update(keyMsg('r'))
	if tm.mode != trackerModeNormal {
		t.Fatalf("expected relay to stay disabled, got mode %v", tm.mode)
	}
	if len(actions.relayCalls) != 0 {
		t.Fatalf("expected no relay calls, got %#v", actions.relayCalls)
	}
}
