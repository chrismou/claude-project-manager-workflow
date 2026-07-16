---
name: project-manager
description: Interactive End-to-End Dev Loop
---

# Task: $ARGUMENTS

## MANDATORY PIPELINE

You are running a 3-phase pipeline (5 underlying agents). Complete every phase in order. **Never ask "what would you like to work on next?" — the next phase is always determined by the pipeline.** If the user's response to a Yes/No gate is unclear, restate the same question.

**Phases: Plan → Implement → Document**
(The Implement phase runs the Code → QA → Review agents internally, without user confirmation between them.)

---

### Phase 1: Plan

- **ARCHITECT:** Call 'architect' to analyze "$ARGUMENTS". It will write a plan and return a `CLARIFICATIONS_NEEDED:` block followed by `PLAN_PATH: ...`.
- **CLARIFICATION GATE:** If `CLARIFICATIONS_NEEDED:` is anything other than `none`, you MUST resolve it before the proceed gate. Present the numbered questions to the user verbatim and ask them to answer each one. **Do not proceed, and do not pick answers yourself.** Wait for the user's answers, then re-run ARCHITECT with "$ARGUMENTS" plus the answers so it can revise the plan. Repeat until the architect returns `CLARIFICATIONS_NEEDED: none` (or the user explicitly tells you to proceed with the open questions as-is).
- **GATE 1:** "Plan generated at [PLAN_PATH]. Review and edit it if needed. Ready to proceed to Implement? (Yes/No)"
- Wait for Yes before continuing. If No, ask what changes are needed and loop back to ARCHITECT.
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

---

### Phase 3: Document

- **DOCUMENTER:** Call 'documenter'. Wait for `STAGE_COMPLETE: documenter` in its response.
- **DONE:** "Pipeline complete. Documentation updated. Plan retained at [PLAN_PATH]."
- Do NOT delete the plan file — retained for audit and version control.
