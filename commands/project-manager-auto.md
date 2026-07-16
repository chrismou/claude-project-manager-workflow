---
name: project-manager-auto
description: End-to-End Dev Loop with plan-mode approval (auto-accept edits)
---

# Task: $ARGUMENTS

## MANDATORY PIPELINE

You are running a fixed 4-stage pipeline. Complete every stage in order. **Never ask "what would you like to work on next?" — the next stage is always determined by the pipeline.** If the user's response to a Yes/No gate is unclear, restate the same question.

**Stages: Planning → Implementation → Review → Closeout**

### Permission model

Stage 1 runs inside **plan mode** so the user approves implementation once and lets Stages 2–4 run unattended:

- Planning is **attended** — the user reviews/edits the plan before any code is written.
- Exiting plan mode is the single gate where the user can choose **"auto-accept edits"**, which suppresses per-edit permission prompts for the rest of the pipeline.

Permission prompts are enforced by the harness, not the model — they cannot be turned off by instruction, only by the permission mode the user selects when exiting plan mode.

---

### Stage 1: Planning

Plan mode permits writing to **only one** file — the plan file named in the plan-mode system message — and blocks all other writes, including subagent writes. So the architect cannot write the repo plan file while in plan mode; it returns the plan as text, you draft it into the plan-mode file, and you persist the audit copy to `plans/` only after the user approves (when accept-edits is active).

- **ENTER PLAN MODE:** If not already in plan mode, call `EnterPlanMode`. Note the plan-file path from the plan-mode system message — that is the only file writable until you exit.
- **ARCHITECT (read-only):** Call 'architect-auto' to analyze "$ARGUMENTS". It returns the plan as text ending in `PLAN_READY` (it does not write files in plan mode).
- **DRAFT:** Write the architect's returned plan to the plan-mode file.
- **PAUSE (attended review):** "Plan drafted — review and edit it directly if needed. Reply **GO** when you're ready to start implementation."
  - Wait for GO. If the user requests changes, re-run the architect or edit the draft before continuing.
- **EXIT PLAN MODE:** On GO, call `ExitPlanMode` to begin implementation. Pre-declare the Bash the later stages need via `allowedPrompts` so they don't prompt either:
  - `{ tool: "Bash", prompt: "run tests" }`
  - `{ tool: "Bash", prompt: "run linters (eslint, pint, phpcs, pyflakes)" }`
  - `{ tool: "Bash", prompt: "install dependencies" }`
  - This surfaces the native approval dialog. Choosing **"auto-accept edits"** lets Stages 2–4 run without per-edit prompts. If the user picks manual approval instead, the pipeline still works — they'll just confirm edits as before.
- **PERSIST PLAN (audit artifact):** Now that accept-edits is active, copy the approved plan from the plan-mode file into the repo at `plans/YYYYMMDD-slug.md` (create `plans/` if needed). This path is `PLAN_PATH` — pass it to every later stage. Never delete it; it is retained for audit and version control.

---

### Stage 2: Implementation

- **CODER:** Call 'coder' with the plan path. Wait for `STAGE_COMPLETE: coder` in its response.
- **GATE:** Present the coder's summary, then ask: "Implementation complete. Ready to proceed to QA? (Yes/No)"
- Wait for Yes before continuing. If No, ask what needs revisiting and return to CODER.
- **QA:** Call 'qa-tester' to verify the work. Wait for `STAGE_COMPLETE: qa` or `QA_FAILED:` in its response.
  - If `QA_FAILED:` — call 'coder' to fix the reported issues, then re-run 'qa-tester'. Repeat until `STAGE_COMPLETE: qa`.
  - If `STAGE_COMPLETE: qa` — **STOP. Do not proceed.** Present the QA summary, then output exactly:

    > ✅ QA passed. You can manually review the changes before continuing.
    >
    > Ready to proceed to Stage 3: Review? **(Yes / No)**
    >
    > — Reply **Yes** to continue, or **No** to provide feedback first.

- **WAIT for explicit user reply. Do NOT continue to Stage 3 until the user replies.**
- If Yes — proceed to Stage 3.
- If No — ask: "What issues did you find, or what would you like to change?" Then return to CODER with the feedback and re-run QA before presenting this gate again.

---

### Stage 3: Review

- **REVIEWER:** Call 'reviewer' to audit for security/performance/style.
  - If changes required — call 'coder' to apply them, then re-run 'reviewer'. Repeat until "APPROVED".
  - If "APPROVED" — present a summary of the full implementation, then ask: "Review approved. Ready to proceed to Stage 4: Closeout? (Yes/No)"
- Wait for Yes before continuing. If No, ask for specific feedback and loop back to Stage 1.

---

### Stage 4: Closeout

- **DOCUMENTER:** Call 'documenter'. Wait for `STAGE_COMPLETE: documenter` in its response.
- **DONE:** "Pipeline complete. Documentation updated. Plan retained at [PLAN_PATH]."
- Do NOT delete the plan file — retained for audit and version control.
