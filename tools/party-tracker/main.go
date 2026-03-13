package main

import (
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ANSI palette colors — inherits terminal theme automatically.
var (
	blue  = lipgloss.Color("4")
	green = lipgloss.Color("2")
	dim   = lipgloss.Color("8")
	red   = lipgloss.Color("1")
	fg    = lipgloss.Color("7")

	titleStyle    = lipgloss.NewStyle().Foreground(blue).Bold(true)
	activeStyle   = lipgloss.NewStyle().Foreground(green)
	stoppedStyle  = lipgloss.NewStyle().Foreground(red)
	dimStyle      = lipgloss.NewStyle().Foreground(dim)
	selectedStyle = lipgloss.NewStyle().Foreground(blue).Bold(true)
	snippetStyle  = lipgloss.NewStyle().Foreground(dim).PaddingLeft(6)
	footerStyle   = lipgloss.NewStyle().Foreground(dim)
	headerRule    = lipgloss.NewStyle().Foreground(dim)
)

type mode int

const (
	modeNormal mode = iota
	modeRelay
	modeBroadcast
	modeSpawn
	modeManifest
)

type tickMsg time.Time
type refreshMsg struct{}

type model struct {
	masterID     string
	workers      []Worker
	cursor       int
	mode         mode
	input        textinput.Model
	width        int
	height       int
	err          error
	manifestJSON string // pretty-printed manifest for inspect mode
	manifestID   string // session ID being inspected
	manifestScrl int    // scroll offset for manifest view
}

func initialModel(masterID string) model {
	ti := textinput.New()
	ti.CharLimit = 500
	ti.Width = 60

	return model{
		masterID: masterID,
		workers:  fetchWorkers(masterID),
		input:    ti,
	}
}

func tickCmd() tea.Cmd {
	return tea.Tick(3*time.Second, func(t time.Time) tea.Msg {
		return tickMsg(t)
	})
}

func (m model) Init() tea.Cmd {
	return tickCmd()
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.input.Width = max(10, msg.Width-8)
		return m, nil

	case tickMsg, refreshMsg:
		m.workers = fetchWorkers(m.masterID)
		if m.cursor >= len(m.workers) {
			m.cursor = max(0, len(m.workers)-1)
		}
		if _, ok := msg.(tickMsg); ok {
			return m, tickCmd()
		}
		return m, nil

	case tea.KeyMsg:
		if m.mode == modeManifest {
			return m.updateManifest(msg)
		}
		if m.mode != modeNormal {
			return m.updateInput(msg)
		}
		return m.updateNormal(msg)
	}

	return m, nil
}

func (m model) updateNormal(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "q", "ctrl+c":
		return m, tea.Quit

	case "j", "down":
		if m.cursor < len(m.workers)-1 {
			m.cursor++
		}

	case "k", "up":
		if m.cursor > 0 {
			m.cursor--
		}

	case "enter":
		if len(m.workers) > 0 && m.workers[m.cursor].Status == "active" {
			_ = attachWorker(m.workers[m.cursor].ID)
			// Immediate refresh after returning
			m.workers = fetchWorkers(m.masterID)
		}

	case "r":
		if len(m.workers) > 0 {
			m.mode = modeRelay
			m.input.Placeholder = fmt.Sprintf("message to %s...", m.workers[m.cursor].ID)
			m.input.Reset()
			m.input.Focus()
			return m, textinput.Blink
		}

	case "b":
		m.mode = modeBroadcast
		m.input.Placeholder = "broadcast to all workers..."
		m.input.Reset()
		m.input.Focus()
		return m, textinput.Blink

	case "s":
		m.mode = modeSpawn
		m.input.Placeholder = "worker title..."
		m.input.Reset()
		m.input.Focus()
		return m, textinput.Blink

	case "x":
		if len(m.workers) > 0 {
			w := m.workers[m.cursor]
			_ = stopWorker(w.ID)
			m.workers = fetchWorkers(m.masterID)
			if m.cursor >= len(m.workers) {
				m.cursor = max(0, len(m.workers)-1)
			}
		}

	case "d":
		if len(m.workers) > 0 {
			w := m.workers[m.cursor]
			_ = deleteWorker(w.ID)
			m.workers = fetchWorkers(m.masterID)
			if m.cursor >= len(m.workers) {
				m.cursor = max(0, len(m.workers)-1)
			}
		}

	case "m":
		if len(m.workers) > 0 {
			id := m.workers[m.cursor].ID
			if j, err := readManifestPretty(id); err == nil {
				m.mode = modeManifest
				m.manifestJSON = j
				m.manifestID = id
				m.manifestScrl = 0
			}
		}

	case "M":
		if j, err := readManifestPretty(m.masterID); err == nil {
			m.mode = modeManifest
			m.manifestJSON = j
			m.manifestID = m.masterID
			m.manifestScrl = 0
		}
	}

	return m, nil
}

func (m model) updateInput(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.mode = modeNormal
		m.input.Blur()
		return m, nil

	case "enter":
		val := m.input.Value()
		if val != "" {
			switch m.mode {
			case modeRelay:
				if len(m.workers) > 0 {
					_ = relayMessage(m.workers[m.cursor].ID, val)
				}
			case modeBroadcast:
				_ = broadcastMessage(m.masterID, val)
			case modeSpawn:
				_ = spawnWorker(m.masterID, val)
			}
		}
		m.mode = modeNormal
		m.input.Blur()
		// Delayed refresh after action (non-blocking)
		return m, tea.Tick(500*time.Millisecond, func(time.Time) tea.Msg { return refreshMsg{} })
	}

	var cmd tea.Cmd
	m.input, cmd = m.input.Update(msg)
	return m, cmd
}

// truncate cuts a string to maxLen, adding ellipsis if needed.
func truncate(s string, maxLen int) string {
	if maxLen <= 0 || len(s) <= maxLen {
		return s
	}
	if maxLen <= 1 {
		return "…"
	}
	return s[:maxLen-1] + "…"
}

// innerWidth returns usable content width (pane width minus padding).
func (m model) innerWidth() int {
	w := m.width - 4 // 2 char padding each side
	if w < 10 {
		w = 10
	}
	return w
}

func (m model) View() string {
	if m.mode == modeManifest {
		return m.viewManifest()
	}

	var b strings.Builder
	inner := m.innerWidth()
	compact := m.width < 50

	// Header
	workerCount := len(m.workers)
	if compact {
		b.WriteString(titleStyle.Render(truncate(fmt.Sprintf(" %s", m.masterID), inner)) + "\n")
		b.WriteString(dimStyle.Render(fmt.Sprintf(" %dw", workerCount)) + "\n")
	} else {
		header := titleStyle.Render(fmt.Sprintf("  Master: %s", m.masterID))
		count := dimStyle.Render(fmt.Sprintf("  %d worker(s)", workerCount))
		b.WriteString(header + count + "\n")
	}
	b.WriteString(headerRule.Render("  " + strings.Repeat("─", inner)) + "\n\n")

	// Worker list
	if workerCount == 0 {
		b.WriteString(dimStyle.Render("  No workers. 's' to spawn.") + "\n")
	} else {
		for i, w := range m.workers {
			cursor := "  "
			nameStyle := dimStyle
			if i == m.cursor {
				cursor = selectedStyle.Render("▸ ")
				nameStyle = selectedStyle
			}

			// Status indicator
			var status string
			if compact {
				if w.Status == "active" {
					status = activeStyle.Render("●")
				} else {
					status = stoppedStyle.Render("○")
				}
			} else {
				if w.Status == "active" {
					status = activeStyle.Render("● active")
				} else {
					status = stoppedStyle.Render("○ stopped")
				}
			}

			// Worker line
			title := w.Title
			if title == "" {
				title = w.ID
			}
			// Reserve space for cursor(2) + status + gap(2)
			statusLen := 2
			if !compact {
				statusLen = 10
			}
			maxTitle := inner - statusLen
			if maxTitle < 4 {
				maxTitle = 4
			}
			title = truncate(title, maxTitle)

			line := fmt.Sprintf("%s%s  %s", cursor, nameStyle.Render(title), status)
			b.WriteString(line + "\n")

			// Snippet (may be multi-line) — skip in very narrow panes
			if w.Snippet != "" && m.width >= 30 {
				pad := 6
				if compact {
					pad = 3
				}
				snipStyle := lipgloss.NewStyle().Foreground(dim).PaddingLeft(pad)
				maxSnip := inner - pad
				for _, sline := range strings.Split(w.Snippet, "\n") {
					b.WriteString(snipStyle.Render(truncate(sline, maxSnip)) + "\n")
				}
			}

			b.WriteString("\n")
		}
	}

	// Footer
	b.WriteString(headerRule.Render("  " + strings.Repeat("─", inner)) + "\n")

	if m.mode != modeNormal {
		var label string
		switch m.mode {
		case modeRelay:
			label = "r"
		case modeBroadcast:
			label = "b"
		case modeSpawn:
			label = "s"
		}
		b.WriteString(fmt.Sprintf(" %s> %s\n", label, m.input.View()))
		b.WriteString(footerStyle.Render(" ⏎:send esc:cancel") + "\n")
	} else if compact {
		b.WriteString(footerStyle.Render(" j/k ⏎ r b s m M x d q") + "\n")
	} else {
		b.WriteString(footerStyle.Render("  j/k:nav  ⏎:attach  r/b:msg  s:spawn  m/M:manifest  x/d:stop  q:quit") + "\n")
	}

	return b.String()
}

func (m model) updateManifest(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	lines := strings.Split(m.manifestJSON, "\n")
	viewable := m.height - 6 // header + footer overhead
	if viewable < 1 {
		viewable = 1
	}
	maxScroll := len(lines) - viewable
	if maxScroll < 0 {
		maxScroll = 0
	}

	switch msg.String() {
	case "esc", "m", "M", "q":
		m.mode = modeNormal
		return m, nil
	case "j", "down":
		if m.manifestScrl < maxScroll {
			m.manifestScrl++
		}
	case "k", "up":
		if m.manifestScrl > 0 {
			m.manifestScrl--
		}
	}
	return m, nil
}

func (m model) viewManifest() string {
	var b strings.Builder
	inner := m.innerWidth()

	b.WriteString(titleStyle.Render(fmt.Sprintf("  Manifest: %s", truncate(m.manifestID, inner-12))) + "\n")
	b.WriteString(headerRule.Render("  "+strings.Repeat("─", inner)) + "\n")

	lines := strings.Split(m.manifestJSON, "\n")
	viewable := m.height - 6
	if viewable < 1 {
		viewable = 1
	}

	end := m.manifestScrl + viewable
	if end > len(lines) {
		end = len(lines)
	}
	for _, line := range lines[m.manifestScrl:end] {
		b.WriteString("  " + truncate(line, inner) + "\n")
	}

	b.WriteString(headerRule.Render("  "+strings.Repeat("─", inner)) + "\n")
	scrollInfo := ""
	if len(lines) > viewable {
		scrollInfo = fmt.Sprintf("  [%d/%d]  ", m.manifestScrl+1, len(lines))
	}
	b.WriteString(footerStyle.Render(scrollInfo+"j/k:scroll  esc:back") + "\n")

	return b.String()
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, "Usage: party-tracker <master-session-id>\n")
		os.Exit(1)
	}

	masterID := os.Args[1]

	p := tea.NewProgram(
		initialModel(masterID),
		tea.WithAltScreen(),
	)

	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
