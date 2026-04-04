//go:build linux || darwin

package transport

import (
	"fmt"
	"os"
	"regexp"
	"strings"
)

// placeholderLine matches lines that are just unreplaced {{VAR}} placeholders.
var placeholderLine = regexp.MustCompile(`^\{\{.*\}\}$`)

// RenderTemplate reads a template file and replaces {{VAR}} placeholders with values.
// Lines consisting only of unreplaced placeholders are stripped (conditional sections).
func RenderTemplate(templatePath string, vars map[string]string) (string, error) {
	data, err := os.ReadFile(templatePath)
	if err != nil {
		return "", fmt.Errorf("read template %s: %w", templatePath, err)
	}

	content := string(data)
	for key, val := range vars {
		content = strings.ReplaceAll(content, "{{"+key+"}}", val)
	}

	// Strip lines that are just unreplaced placeholders.
	var lines []string
	for _, line := range strings.Split(content, "\n") {
		if !placeholderLine.MatchString(strings.TrimSpace(line)) {
			lines = append(lines, line)
		}
	}
	return strings.Join(lines, "\n"), nil
}
