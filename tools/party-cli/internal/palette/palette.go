package palette

import "github.com/charmbracelet/lipgloss"

const (
	Added      lipgloss.Color = "2"
	Deleted    lipgloss.Color = "1"
	HunkHeader lipgloss.Color = "6"

	Clean      lipgloss.Color = Added
	Warn       lipgloss.Color = "3"
	Error      lipgloss.Color = Deleted
	Accent     lipgloss.Color = "4"
	Muted      lipgloss.Color = "8"
	StatusBg   lipgloss.Color = "235"
	StatusFg   lipgloss.Color = "252"
	DividerFg  lipgloss.Color = "240"
	BrightText lipgloss.Color = "15"

	MasterRole lipgloss.Color = "#ffd700"
	// WorkerRole is the picker-reference worker identity color; tracker worker
	// dots and headers share it so the two UIs stay aligned.
	WorkerRole     lipgloss.Color = Warn
	StandaloneRole lipgloss.Color = Clean
	TmuxRole       lipgloss.Color = Accent
	OrphanRole     lipgloss.Color = Muted

	DividerBorder lipgloss.Color = "#484f58"
	// PickerDividerLine intentionally stays darker than DividerBorder to
	// preserve the picker's existing section-separator contrast.
	PickerDividerLine lipgloss.Color = "#2e3440"
	// PickerVerticalDivider intentionally stays brighter than DividerBorder so
	// the split between the list and preview panes remains legible.
	PickerVerticalDivider lipgloss.Color = "#555555"
	SelectedBoxBorder     lipgloss.Color = "#6e7681"
	SelectedRowBg         lipgloss.Color = "#161b22"
	ActivityDim           lipgloss.Color = "#555555"
)

const (
	ResetANSI = "\033[0m"
	BoldANSI  = "\033[1m"
	FaintANSI = "\033[2m"

	AccentANSI     = "\033[34m"
	CleanANSI      = "\033[32m"
	WarnANSI       = "\033[33m"
	ErrorANSI      = "\033[31m"
	MutedANSI      = "\033[90m"
	DividerFgANSI  = "\033[38;5;240m"
	BrightTextANSI = "\033[97m"
	MasterRoleANSI = "\033[38;2;255;215;0m"

	SelectedRowBgANSI = "\x1b[48;2;22;27;34m"
)
