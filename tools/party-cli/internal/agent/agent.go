package agent

import "context"

// TmuxClient is the subset of tmux.Client used by agent providers.
type TmuxClient interface {
	UnsetEnvironment(ctx context.Context, session, key string) error
}

// Agent represents any CLI coding agent that can run in a tmux pane.
type Agent interface {
	Name() string
	DisplayName() string
	Binary() string

	BuildCmd(opts CmdOpts) string
	ResumeKey() string
	ResumeFileName() string
	EnvVar() string
	MasterPrompt() string

	FilterPaneLines(raw string, max int) []string

	// TranscriptPath returns the absolute path to the agent's live session
	// JSONL file for the given working directory and resume ID, or "" if
	// the agent does not persist a transcript we can observe. The tracker
	// stats this file to infer agent activity (recent mtime = busy).
	TranscriptPath(cwd, resumeID string) (string, error)

	PreLaunchSetup(ctx context.Context, client TmuxClient, session string) error
	BinaryEnvVar() string
	FallbackPath() string
}

// CmdOpts controls agent launch command construction.
type CmdOpts struct {
	Binary    string
	AgentPath string
	ResumeID  string
	Prompt    string
	Title     string
	Master    bool
}
