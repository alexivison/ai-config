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
