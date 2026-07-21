---
name: pm-auto
description: Auto-approving dev loop (dangerous ops still prompt)
---

# Task: $ARGUMENTS

## Pre-flight

### 1. Check for jq

Run `command -v jq` via Bash. If it returns nothing, tell the user:
> `jq` is required for permissionless mode. Install it (`brew install jq` / `apt install jq`) and re-run.

Then stop.

### 2. Validate per-project overrides (if present)

Run `git rev-parse --show-toplevel` via Bash to find the project root. Check whether
`.claude/pm-deny-overrides.json` exists there.

If the file exists:
- Read it and verify it is valid JSON. If not, stop and report the problem.
- Compare every id in `exempt` against the ids in `hooks/deny-list.json` (installed alongside this
  plugin). Report any ids not found as a loud no-op:
  > Unknown rule id(s) in `exempt`: [list] — these will be silently ignored. See the deny-list
  > table in the README for valid ids.
- If `path-escape` is in `exempt` but NOT in `acknowledge_unsafe`, stop and report:
  > `path-escape` cannot be exempted without also adding it to `acknowledge_unsafe`. This prevents
  > accidental auto-approval of writes outside the project root. See the README for details.
- If `path-escape` is in both `exempt` and `acknowledge_unsafe`, continue but warn:
  > WARNING: writes outside the project root will be auto-approved for this run.
- Collect all known ids from `exempt` (excluding any unknown/inert ones) into ACTIVE_EXEMPTIONS.
  This list is used in the arming confirmation below.

## ARM

Run the following via Bash to capture the required values:
- `echo "$CLAUDE_CODE_SESSION_ID"` → SESSION_UUID (the current Claude Code session identifier)
- `date -u +"%Y-%m-%dT%H:%M:%SZ"` → ARMED_AT
- `date -u -d "+2 hours" +"%Y-%m-%dT%H:%M:%SZ"` → EXPIRES_AT

If `SESSION_UUID` is empty, stop and tell the user:
> `$CLAUDE_CODE_SESSION_ID` is not set — cannot arm session-bound permissionless mode.
> This should not happen in a normal Claude Code session. Check that you are running inside
> Claude Code (not a plain shell) and that you have a recent version installed.

Write `<project_root>/.claude/.pm-permissionless.json`:

```json
{
  "session_id": "<SESSION_UUID>",
  "armed_at":   "<ARMED_AT>",
  "expires_at": "<EXPIRES_AT>",
  "command":    "pm-auto"
}
```

This write prompts once — expected and harmless, you are present.

Confirm to the user:
> **Permissionless mode armed.**
> - Session: `<SESSION_UUID>` (bound to this Claude Code session; valid until `<EXPIRES_AT>` UTC).
> - Binding: the hook checks the session ID on every tool call — other sessions in the same
>   project directory are not affected.
> - Deny list: `hooks/deny-list.json` (plus `.claude/pm-deny-overrides.json` if present).
> - **Active exemptions (from `.claude/pm-deny-overrides.json`): `<ACTIVE_EXEMPTIONS>`** — these
>   rules will NOT fire during this run. (Omit this bullet if ACTIVE_EXEMPTIONS is empty.)
> - Existing `deny` / `ask` rules in your settings still apply — the hook cannot override them.
> - A deny-list match in an unattended run **pauses indefinitely** rather than failing.

## Pipeline

Invoke the `chrismou-project-manager:pm` skill with `$ARGUMENTS` and follow it in
full. Do not restate or reinterpret the pipeline — it is defined there.

## DISARM

Delete the flag file:
- At the scope boundary as directed by the pipeline (the pipeline text carries the conditional
  disarm instructions for GATE 2 and DONE).
- Immediately on GATE 2 "No": `rm -f "$(git rev-parse --show-toplevel)/.claude/.pm-permissionless.json"`
- On any abort or unexpected stop: same.
