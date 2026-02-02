# Multimodal Analysis Templates

Use these templates for PDF, video, and audio analysis via Gemini.

## PDF Analysis

```bash
gemini -p "Analyze this PDF document:

Extract:
- Key concepts and definitions
- API specifications (if technical doc)
- Code examples
- Important constraints
- Action items or requirements

Summarize in structured markdown.
" < /path/to/document.pdf 2>/dev/null
```

## Video Analysis

```bash
gemini -p "Analyze this video:

Provide:
- Main topics covered
- Key points with timestamps
- Code snippets shown (if tutorial)
- Important warnings or gotchas
- Summary of conclusions

Format as structured notes.
" < /path/to/video.mp4 2>/dev/null
```

## Audio Analysis (Meetings)

```bash
gemini -p "Analyze this audio recording:

Extract:
- Key decisions made
- Action items (who, what, when)
- Open questions
- Technical details discussed
- Follow-up needed

Format as meeting notes.
" < /path/to/meeting.mp3 2>/dev/null
```

## Output Location

Save to: `~/.claude/research/{descriptive-name}-{date}.md`

## Supported Formats

| Type | Formats |
|------|---------|
| Document | PDF, DOCX |
| Video | MP4, MOV, WebM |
| Audio | MP3, WAV, M4A |
| Image | PNG, JPG, GIF |

## When to Use

- Extracting specs from PDF documentation
- Summarizing tutorial videos
- Creating notes from recorded meetings
- Analyzing design mockups
