package picker

import (
	"context"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
)

// StartFunc creates a session and returns its ID.
type StartFunc func(ctx context.Context, title, cwd string, master bool) (string, error)

type createField int

const (
	fieldTitle createField = iota
	fieldDir
)

// CreateForm handles the new-session creation UI within the picker.
type CreateForm struct {
	titleInput  textinput.Model
	dirInput    textinput.Model
	focus       createField
	master      bool
	submitting  bool     // true after Enter, blocks Esc/input until startFn returns
	completions []string // tab-completion matches (full paths)
	compIndex   int      // cycle index (-1 = common prefix shown, 0..N-1 = cycling)
	err         string
}

// NewCreateForm creates a form for new session creation.
// panePath pre-fills the directory input.
func NewCreateForm(master bool, panePath string) (CreateForm, tea.Cmd) {
	ti := textinput.New()
	ti.Placeholder = "optional, auto-generated if blank"
	ti.CharLimit = 64
	ti.Prompt = ""
	cmd := ti.Focus()

	di := textinput.New()
	di.Placeholder = "/path/to/project"
	di.CharLimit = 256
	di.Prompt = ""
	if panePath != "" {
		di.SetValue(panePath)
		di.SetCursor(len(panePath))
	}

	return CreateForm{
		titleInput: ti,
		dirInput:   di,
		master:     master,
	}, cmd
}

// Update handles input for the create form.
func (f CreateForm) Update(msg tea.Msg) (CreateForm, tea.Cmd) {
	if keyMsg, ok := msg.(tea.KeyMsg); ok {
		return f.handleKey(keyMsg)
	}
	var cmd tea.Cmd
	switch f.focus {
	case fieldTitle:
		f.titleInput, cmd = f.titleInput.Update(msg)
	case fieldDir:
		f.dirInput, cmd = f.dirInput.Update(msg)
	}
	return f, cmd
}

func (f CreateForm) handleKey(msg tea.KeyMsg) (CreateForm, tea.Cmd) {
	// While startFn is in-flight, only allow ctrl+c to quit entirely.
	if f.submitting {
		if msg.String() == "ctrl+c" {
			return f, tea.Quit
		}
		return f, nil
	}

	// Only preserve completions when Tab is pressed on the dir field.
	isTabOnDir := msg.String() == "tab" && f.focus == fieldDir
	if !isTabOnDir {
		f.completions = nil
		f.compIndex = 0
	}
	f.err = ""

	switch msg.String() {
	case "tab":
		if f.focus == fieldTitle {
			f.titleInput.Blur()
			cmd := f.dirInput.Focus()
			f.focus = fieldDir
			return f, cmd
		}
		f.tabComplete()
		return f, nil

	case "shift+tab":
		if f.focus == fieldDir {
			f.dirInput.Blur()
			cmd := f.titleInput.Focus()
			f.focus = fieldTitle
			return f, cmd
		}
		return f, nil

	case "enter":
		dir := expandTilde(f.dirInput.Value())
		if dir == "" {
			f.err = "directory is required"
			return f, nil
		}
		info, err := os.Stat(dir)
		if err != nil || !info.IsDir() {
			f.err = "directory does not exist"
			return f, nil
		}
		f.submitting = true
		return f, func() tea.Msg {
			return createRequestMsg{title: f.titleInput.Value(), dir: dir, master: f.master}
		}

	case "esc":
		return f, func() tea.Msg { return createCancelMsg{} }

	case "ctrl+c":
		return f, tea.Quit
	}

	// Pass to focused input.
	var cmd tea.Cmd
	switch f.focus {
	case fieldTitle:
		f.titleInput, cmd = f.titleInput.Update(msg)
	case fieldDir:
		f.dirInput, cmd = f.dirInput.Update(msg)
	}
	return f, cmd
}

// ---------------------------------------------------------------------------
// Model integration — create-mode message handling
// ---------------------------------------------------------------------------

func (m Model) updateCreate(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case createCancelMsg:
		m.mode = modePicker
		return m, m.loadPreview()
	case createRequestMsg:
		startFn, ctx := m.startFn, m.ctx
		return m, func() tea.Msg {
			sessionID, err := startFn(ctx, msg.title, msg.dir, msg.master)
			return createResultMsg{sessionID: sessionID, err: err}
		}
	case createResultMsg:
		m.createForm.submitting = false
		if msg.err != nil {
			m.createForm.err = msg.err.Error()
			return m, nil
		}
		m.selected = msg.sessionID
		return m, tea.Quit
	default:
		var cmd tea.Cmd
		m.createForm, cmd = m.createForm.Update(msg)
		return m, cmd
	}
}

// tabComplete performs zsh-style tab completion on the directory input.
func (f *CreateForm) tabComplete() {
	// Cycle through existing completions on repeated Tab.
	if len(f.completions) > 1 {
		f.compIndex = (f.compIndex + 1) % len(f.completions)
		f.dirInput.SetValue(f.completions[f.compIndex])
		f.dirInput.SetCursor(len(f.completions[f.compIndex]))
		return
	}

	raw := f.dirInput.Value()
	expanded := expandTilde(raw)

	parent, partial := splitDirPartial(expanded)
	matches := listDirMatches(parent, partial)
	if len(matches) == 0 {
		return
	}

	if len(matches) == 1 {
		completed := filepath.Join(parent, matches[0]) + "/"
		completed = shortPath(completed)
		f.dirInput.SetValue(completed)
		f.dirInput.SetCursor(len(completed))
		return
	}

	// Multiple matches: fill common prefix, store matches for cycling.
	common := commonPrefix(matches)
	completed := filepath.Join(parent, common)
	completed = shortPath(completed)
	f.dirInput.SetValue(completed)
	f.dirInput.SetCursor(len(completed))

	f.completions = make([]string, len(matches))
	for i, m := range matches {
		f.completions[i] = shortPath(filepath.Join(parent, m) + "/")
	}
	f.compIndex = -1 // next Tab goes to index 0
}

// View renders the create form.
func (f CreateForm) View(width, height int) string {
	pad := strings.Repeat(" ", padLeft)

	header := "New Session"
	if f.master {
		header = "New Master Session"
	}

	inputWidth := width - padLeft - 8 // 8 = len("Title:  ") or len("Dir:    ")
	if inputWidth < 10 {
		inputWidth = 10
	}
	f.titleInput.Width = inputWidth
	f.dirInput.Width = inputWidth

	headerLine := pad + pickerActiveTabStyle.Render(" "+header+" ")
	dividerLine := pickerDividerLineStyle.Render(strings.Repeat("─", width))

	titleLabel := pickerMutedStyle.Render("Title:  ")
	dirLabel := pickerMutedStyle.Render("Dir:    ")

	var lines []string
	lines = append(lines, headerLine)
	lines = append(lines, dividerLine)
	lines = append(lines, pad+titleLabel+f.titleInput.View())
	lines = append(lines, "")
	lines = append(lines, pad+dirLabel+f.dirInput.View())

	// Show completion hints below the dir input.
	if len(f.completions) > 0 {
		for i, c := range f.completions {
			name := filepath.Base(strings.TrimSuffix(c, "/")) + "/"
			style := pickerMutedStyle
			prefix := "  "
			if i == f.compIndex {
				style = pickerCleanStyle
				prefix = "> "
			}
			lines = append(lines, pad+"        "+style.Render(prefix+name))
		}
	}

	if f.err != "" {
		lines = append(lines, "")
		lines = append(lines, pad+pickerWarnStyle.Render(f.err))
	}

	// Pad body to fill height (header=2, footer=2 for divider+help).
	for len(lines) < height-2 {
		lines = append(lines, "")
	}

	lines = append(lines, dividerLine)
	footerText := pad + "⏎ create  tab complete  esc back"
	if f.submitting {
		footerText = pad + "Creating session..."
	}
	lines = append(lines, pickerFooterStyle.Render(fitToWidth(footerText, width)))

	return strings.Join(lines, "\n")
}

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

type createRequestMsg struct {
	title  string
	dir    string
	master bool
}

type createCancelMsg struct{}

type createResultMsg struct {
	sessionID string
	err       error
}

// ---------------------------------------------------------------------------
// Tab-completion helpers
// ---------------------------------------------------------------------------

func expandTilde(path string) string {
	if strings.HasPrefix(path, "~/") || path == "~" {
		home, _ := os.UserHomeDir()
		if home != "" {
			return home + path[1:]
		}
	}
	return path
}

func splitDirPartial(path string) (parent, partial string) {
	if strings.HasSuffix(path, "/") || path == "" {
		return path, ""
	}
	return filepath.Dir(path), filepath.Base(path)
}

func listDirMatches(parent, prefix string) []string {
	if parent == "" {
		parent = "."
	}
	entries, err := os.ReadDir(parent)
	if err != nil {
		return nil
	}
	var matches []string
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		if strings.HasPrefix(e.Name(), prefix) {
			matches = append(matches, e.Name())
		}
	}
	sort.Strings(matches)
	return matches
}

func commonPrefix(strs []string) string {
	if len(strs) == 0 {
		return ""
	}
	prefix := strs[0]
	for _, s := range strs[1:] {
		for !strings.HasPrefix(s, prefix) {
			prefix = prefix[:len(prefix)-1]
			if prefix == "" {
				return ""
			}
		}
	}
	return prefix
}
