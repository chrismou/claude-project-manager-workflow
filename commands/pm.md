---
name: pm
description: Interactive dev loop (Plan > Code > QA > Review > Docs)
---

# Task: $ARGUMENTS

## Mode selection (resolve this before Phase 1)

Inspect "$ARGUMENTS" once, before doing anything else, and derive two values:

1. Let `RAW` be "$ARGUMENTS" with leading and trailing whitespace removed.
2. If `RAW` begins with the exact token `--complex` — that is, `RAW` is either exactly
   `--complex`, or starts with `--complex` followed by whitespace — then:
   - Set `COMPLEX_MODE = true`.
   - Set `TASK` to `RAW` with that leading `--complex` token removed and the remaining
     leading whitespace trimmed.
3. Otherwise set `COMPLEX_MODE = false` and `TASK = RAW`.

Rules that matter:
- The match is on the **first** token only. `--complex` appearing later in the task text is part
  of the task and must be left alone.
- The match is **exact and case-sensitive**. `--Complex`, `-complex`, and a bare `complex` do NOT
  enable the mode. A task beginning with the ordinary word "complex" (e.g. "complex refactor of
  the auth module") is therefore passed through untouched, with `COMPLEX_MODE = false`.
- If `TASK` is empty after stripping the flag, do not proceed — ask the user what the task is.

Use `TASK` — never the raw "$ARGUMENTS" — everywhere the pipeline below refers to the task.

If `COMPLEX_MODE` is true, state this once, before Phase 1:
> Complex mode: the architect will run on Fable 5. All other agents are unchanged.

## MANDATORY PIPELINE

You are running a 3-phase pipeline (5 underlying agents). Complete every phase in order. **Never ask "what would you like to work on next?" — the next phase is always determined by the pipeline.** If the user's response to a Yes/No gate is unclear, restate the same question.

**Phases: Plan → Implement → Document**
(The Implement phase runs the Code → QA → Review agents internally, without user confirmation between them.)

---

### Phase 1: Plan

- **ARCHITECT:** Call 'architect' to analyze "$TASK". It will write a plan and return a `CLARIFICATIONS_NEEDED:` block followed by `PLAN_PATH: ...`.
  - If `COMPLEX_MODE` is true, pass the Agent tool's `model` parameter as `fable` on this call.
  - If `COMPLEX_MODE` is false, omit the `model` parameter entirely so the architect runs on its definition default (`claude-opus-4-8`). Do not pass `opus` — the alias is not version-pinned.
  - This applies to **every** ARCHITECT invocation in the session, including clarification re-runs and loop-backs from GATE 1 / GATE 2. `COMPLEX_MODE` is sticky once set.
- **COMPLEX-MODE FAILURE HANDLING** _(applies only when `COMPLEX_MODE` is true):_
  Fable 5 is entitlement- and credit-gated. The architect call may fail, stall on a consent
  prompt, or report that Fable is unavailable or out of credits. If that happens:

  - **If this run did NOT arm a permissionless flag file** (i.e. it was invoked as `pm`, attended):
    **PAUSE and wait for the user.** Report exactly what happened and what is needed:
    > Complex mode could not start the architect on Fable 5. Resolve the prompt above (or run
    > `/model` to check availability), then reply **Retry** to try Fable again, or **Standard** to
    > continue on Opus 4.8.
    Do not silently downgrade to Opus 4.8, and do not proceed to Phase 2. Wait for the reply.

  - **If this run DID arm a permissionless flag file** (i.e. it was invoked via `pm-auto`,
    unattended): **ABORT — and disarm first.** In this order:
    1. Delete the flag file immediately:
       `rm -f "$(git rev-parse --show-toplevel)/.claude/.pm-permissionless.json"`
    2. Then report the abort:
       > Aborted: complex mode could not start the architect on Fable 5, and this is an unattended
       > run with nobody available to resolve it. Permissionless mode has been disarmed. Re-run
       > without `--complex`, or resolve Fable availability and try again.
    3. Stop. Do not fall back to Opus 4.8, and do not continue the pipeline.

    The disarm MUST happen before the report, and MUST happen even though this failure occurs in
    Phase 1 — well before the pipeline's normal disarm points at GATE 2 and DONE. Leaving the flag
    armed on an aborted run would leave permissionless mode live for the remainder of its 2-hour
    expiry window.
- **CLARIFICATION GATE:** If `CLARIFICATIONS_NEEDED:` is anything other than `none`, you MUST resolve it before the proceed gate. Present the numbered questions to the user verbatim and ask them to answer each one. **Do not proceed, and do not pick answers yourself.** Wait for the user's answers, then re-run ARCHITECT with "$TASK" plus the answers so it can revise the plan. Repeat until the architect returns `CLARIFICATIONS_NEEDED: none` (or the user explicitly tells you to proceed with the open questions as-is).
- **GATE 1:** "Plan generated at [PLAN_PATH]. Review and edit it if needed. Ready to proceed to Implement? (Yes/No)"
- Wait for Yes before continuing. If No, ask what changes are needed and loop back to ARCHITECT.
  - If the feedback asks for complex mode (or names Fable, or asks for a deeper/more thorough plan), set `COMPLEX_MODE = true` before re-running ARCHITECT, and say so.
- **UNATTENDED-SCOPE GATE** _(triggered only when the user's GATE 1 response itself implies unattended execution — any phrasing such as "run it unattended", "do it in the background", "I won't be around to confirm", "just finish it without me", etc.):_
  - Do NOT treat unattended phrasing as authorization to skip all remaining gates. Before starting Implement, use `AskUserQuestion` presenting exactly two options:
    - **"Entire process"** — Implement + Document run back-to-back; GATE 2 is skipped automatically; pipeline stops only when the full pipeline is complete.
    - **"Implementation only"** — Implement runs unattended, then STOP at GATE 2 and wait for explicit confirmation before Document.
  - Record the user's selection as `UNATTENDED_SCOPE`.
  - If the approval did NOT imply unattended execution, skip this selection entirely — `UNATTENDED_SCOPE` remains unset and GATE 2 will stop and wait as normal.

---

### Phase 2: Implement (Code + QA + Review)

The coder, qa-tester, and reviewer agents iterate among themselves. **Do NOT ask the user for confirmation at any point inside this phase until the gate at the end.**

- **CODER:** Call 'coder' with the plan path. Wait for `STAGE_COMPLETE: coder` in its response.
- **QA:** Immediately call 'qa-tester' to verify the work. Wait for `STAGE_COMPLETE: qa` or `QA_FAILED:` in its response.
  - If `QA_FAILED:` — call 'coder' to fix the reported issues, then re-run 'qa-tester'. Repeat until `STAGE_COMPLETE: qa`. (No user gate.)
- **REVIEW:** On `STAGE_COMPLETE: qa`, immediately call 'reviewer' to audit for security/performance/style. (No user gate.)
  - If changes required — call 'coder' to apply them, then re-run 'qa-tester' and 'reviewer'. Repeat until `APPROVED`.
  - On `APPROVED` — Implement has converged.
- **DISARM (conditional):** If you armed a permissionless flag file at the start of this session (i.e., this run was invoked via `pm-auto`) AND `UNATTENDED_SCOPE` is `"Implementation only"` or unset, delete it now: `rm -f "$(git rev-parse --show-toplevel)/.claude/.pm-permissionless.json"`. If no flag was armed in this session, skip this step entirely — no tool call, no output.
- **GATE 2:** Present a summary of the full implementation (files changed, QA result, review result), then:
  - _(Note: Unattended phrasing alone NEVER authorizes skipping GATE 2 — only an explicit "Entire process" selection at the UNATTENDED-SCOPE GATE does.)_
  - If `UNATTENDED_SCOPE == "Entire process"` — record the GATE 2 summary and proceed automatically to Phase 3 (Document). **This is the only path that may auto-proceed past GATE 2.**
  - Otherwise (including `UNATTENDED_SCOPE == "Implementation only"` or `UNATTENDED_SCOPE` unset) — output exactly:

    > Implement phase complete — code, QA, and review have converged. You can manually review the changes before continuing.
    >
    > Ready to proceed to Document/Closeout? **(Yes / No)**
    >
    > — Reply **Yes** to continue, or **No** to provide feedback first.

    **WAIT for explicit user reply. Do NOT continue to Phase 3 until the user replies.**
- If Yes — proceed to Phase 3.
- If No — ask for specific feedback, then loop back to **Phase 1 (Plan / ARCHITECT)**.
  - If the feedback asks for complex mode (or names Fable, or asks for a deeper/more thorough plan), set `COMPLEX_MODE = true` before re-running ARCHITECT, and say so.

---

### Phase 3: Document

- **DOCUMENTER:** Call 'documenter'. Wait for `STAGE_COMPLETE: documenter` in its response.
- **DISARM (conditional):** If you armed a permissionless flag file at the start of this session AND `UNATTENDED_SCOPE == "Entire process"`, delete it now: `rm -f "$(git rev-parse --show-toplevel)/.claude/.pm-permissionless.json"`. If no flag was armed in this session, skip this step entirely — no tool call, no output.
- **DONE:** "Pipeline complete. Documentation updated. Plan retained at [PLAN_PATH]."
- Do NOT delete the plan file — retained for audit and version control.
