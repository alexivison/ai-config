# Task 8 — Example Stub Adapter

**Dependencies:** Task 1

## Goal

Create a well-documented stub adapter that serves as a reference for anyone writing a new companion integration. It implements the full adapter interface with clear comments explaining each function, but its actual behavior is minimal (log-only or interactive-prompt-based).

## Scope Boundary

**In scope:**
- `shared/companions/adapters/example-stub.sh` — fully documented adapter implementing all four interface functions
- Inline comments explaining what a real adapter would do at each step
- A sample `.party.toml` snippet showing how to register the stub

**Out of scope:**
- Any real companion CLI integration
- Transport or hook changes
- Testing infrastructure for the stub (it's documentation, not production code)

**Design References:** N/A (non-UI task)

## Files to Create/Modify

| File | Action |
|------|--------|
| `shared/companions/adapters/example-stub.sh` | Create |

## Requirements

**Functionality:**
- `adapter_start`: Log "Starting stub companion in pane X" and set `@party_role` metadata. Comment explains: "Real adapters launch the CLI binary here, optionally with a thread ID for session resumption."
- `adapter_send`: Log the mode and payload to a file in the runtime dir. For `review` mode, immediately write a TOON findings file with `VERDICT: APPROVED` and zero findings. Comment explains: "Real adapters send-keys to the companion's tmux pane and return immediately."
- `adapter_receive`: Check if the findings file exists. Comment explains: "Real adapters poll the companion pane or check for a completion signal."
- `adapter_health`: Check if the tmux pane exists. Comment explains: "Real adapters may also verify the CLI process is responsive."
- Include a header comment block with: purpose, how to register in `.party.toml`, and the four functions that must be implemented.

**Key gotchas:**
- The stub should be functional enough that the harness doesn't break when it's the active companion — it just auto-approves everything
- This is the onboarding ramp for new companion authors; clarity matters more than cleverness

## Tests

- Source the stub → all four functions are defined
- `adapter_send "stub" ... "review" ...` creates a findings file with APPROVED verdict
- `adapter_health "stub" ...` returns 0 when pane exists

## Acceptance Criteria

- [ ] Stub adapter implements all four interface functions
- [ ] Every function has inline comments explaining what real adapters do
- [ ] Header includes registration instructions (`.party.toml` snippet)
- [ ] Stub is functional — harness runs without errors when stub is the active companion
- [ ] Auto-approves reviews (so workflows complete without a real companion)
