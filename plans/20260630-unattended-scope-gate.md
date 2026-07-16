# Technical Design Doc: Unattended-scope selection gate for project-manager-test

Date: 2026-06-30
Branch (current): `loosen-test-stage-gates`
Plugin version: 0.0.5 (to be bumped)

> **Scope (confirmed by operator):** This change is scoped ENTIRELY to
> `project-manager/commands/project-manager-test.md` plus the required version bumps.
> Do NOT modify `project-manager.md` or `project-manager-auto.md`. The "Implementation only"
> stop point is GATE 2 (pre-Document), which is already the natural stop in the 3-phase flow,
> so no 4-stage handling is required.

## Problem

The pipeline command prompts treat any "implied-unattended" approval (e.g. an operator
saying "implement in the background unattended, I won't be here to confirm") as blanket
authorization to skip **all** remaining gates. The operator's actual intent is usually
narrower: run the Implement phase unattended but still **stop at the pre-Document gate**
(`GATE 2` in `project-manager-test`) so the work can be reviewed before it is documented /
closed out.

Observed failure (in `project-manager-test`): the operator approved at the proceed-to-Implement
point with unattended phrasing; the pipeline then auto-proceeded through `GATE 2` into Phase 3
(Document), emitting:

> "Since you authorized unattended completion, I'll record the GATE 2 summary and proceed
> automatically to Phase 3 (Document)."

## Desired behavior

When the operator's approval implies unattended execution (any phrasing suggesting they won't be
present to confirm gates), the pipeline must **not** assume blanket gate-skipping. Instead, at the
point that authorization is given (the proceed-to-Implement gate, `GATE 1`), it must present a
**native multiple-choice selection** (`AskUserQuestion`-style, not free text) capturing scope:

1. **"Entire process"** — run Implement AND Document back-to-back; skip the pre-Document gate and
   only stop when the whole pipeline is complete.
2. **"Implementation only"** — run Implement unattended, then STOP at the pre-Document gate and
   wait for explicit confirmation before Document.

The captured choice is then honored at the pre-Document gate:
- "Implementation only" (or no unattended selection at all) => stop and wait as normal.
- "Entire process" => skip the gate and proceed to Document without further confirmation.

This is a **prompt/markdown-definition** change only. No application code is involved.

## Affected files

| File | Change |
|------|--------|
| `project-manager/commands/project-manager-test.md` | **The only command changed.** Add an "unattended-scope" native selection gate at `GATE 1`; make `GATE 2` conditional on the captured scope. |
| `project-manager/plugin.json` | Version bump `0.0.5` -> `0.0.6`. |
| `.claude-plugin/marketplace.json` | Version bump `0.0.5` -> `0.0.6` (MUST match plugin.json — CI enforces). |
| `CHANGELOG.md` | New `## [0.0.6]` entry + update compare-link footer. (Documenter stage will normally write this; include in plan so it isn't missed.) |

**Explicitly out of scope:** `project-manager/commands/project-manager.md` and
`project-manager/commands/project-manager-auto.md` are NOT to be modified.

## Logic changes

### `project-manager-test.md` (3-phase: Plan -> Implement -> Document)

1. **At `GATE 1` (after the existing Yes/No proceed prompt, before Phase 2 starts):**
   Insert a new **UNATTENDED-SCOPE GATE** step:
   - Trigger: the user's approval to proceed implies unattended execution — any phrasing such as
     "run it unattended", "do it in the background", "I won't be around to confirm", "just finish
     it without me", etc.
   - Action: do NOT treat this as authorization to skip every gate. Before starting Implement,
     use the native multiple-choice selection (`AskUserQuestion`) with exactly two options:
     - **"Entire process"** — Implement + Document run back-to-back; skip GATE 2; stop only when
       the pipeline is complete.
     - **"Implementation only"** — Implement runs unattended, then STOP at GATE 2 and wait for
       explicit confirmation before Document.
   - Record the result as `UNATTENDED_SCOPE` and carry it to GATE 2.
   - If the approval did **not** imply unattended execution, skip this selection entirely and run
     the pipeline normally (GATE 2 stops and waits as today).

2. **At `GATE 2`:** make the wait conditional:
   - If `UNATTENDED_SCOPE == "Entire process"` — record the GATE 2 summary and proceed
     automatically to Phase 3 (this is the only path that may auto-proceed).
   - Otherwise (including "Implementation only", or no unattended selection) — present the summary
     and the existing gate block, then WAIT for explicit user reply. Add an explicit guard line:
     unattended *phrasing alone* never authorizes skipping GATE 2; only an explicit "Entire
     process" selection does.

## Implementation notes for the coder

- Keep wording consistent with the existing bolded-step / blockquote-gate structure already used in
  `project-manager-test.md`. Do not restructure the phases.
- The new gate must be described as a **native multiple-choice** selection (`AskUserQuestion`), with
  the two option labels quoted exactly ("Entire process" / "Implementation only") so the operator
  LLM renders a selection rather than a free-text question.
- The carried state (`UNATTENDED_SCOPE`) is conceptual prompt state, not code — phrase GATE 2 so the
  operator checks "did the user select Entire process earlier?" before auto-proceeding.
- Bump BOTH `plugin.json` and `marketplace.json` to `0.0.6` — the CI `version-bump` job fails if
  they disagree or if the version is not strictly greater than `main`.

## Potential side effects for the QA agent

- **Non-unattended path unchanged:** Confirm that a plain "Yes" at GATE 1 (no unattended phrasing)
  produces NO selection gate and GATE 2 still stops and waits exactly as before. This is the most
  common path and must not regress.
- **GATE 2 default is "stop":** Verify the default/fallback when no unattended selection was made is
  always to stop and wait — never to auto-proceed.
- **Selection -> behavior wiring:** "Implementation only" must produce the identical stop-and-wait
  behavior as the normal pipeline; "Entire process" must auto-proceed past GATE 2 with the summary
  still recorded.
- **No code/test files touched:** This is a markdown-only change; there are no unit/integration
  tests in the repo for prompt behavior. QA should confirm no stray application files were modified.
- **Version sync:** Verify `plugin.json` and `marketplace.json` versions match and are `> 0.0.5`.
- **Markdown validity:** Frontmatter (`name`, `description`) and existing gate blockquotes remain
  intact and parseable.

## Assumptions

- The "pre-Document gate" referenced by the task is `GATE 2` in `project-manager-test`. Per the
  operator's confirmation, "Implementation only" stops here — already the natural stop in the
  3-phase flow.
- Version policy is a **patch** bump (`0.0.6`), consistent with the prior history of patch bumps for
  command-prompt changes (0.0.3, 0.0.5).
- "Native selection" means the `AskUserQuestion` tool available to the operating LLM; the markdown
  instructs the operator to use it rather than calling it itself.
- The selection should be presented at the GATE 1 / proceed-to-Implement point (where authorization
  is given), per the task's stated preference, rather than mid-Implement.
- The two-option set is exhaustive for this fix; no third "ask me at every gate" option is required.
- The CHANGELOG entry can be authored by the documenter stage of whatever pipeline runs this change;
  the plan lists it so it is not dropped if the change is applied directly.

## Open Questions (decision-forcing)

Both prior open questions have been resolved by the operator:
1. **Sibling scope — RESOLVED:** Change ONLY `project-manager-test.md`. `project-manager.md` and
   `project-manager-auto.md` are left untouched.
2. **"Implementation only" stop point — RESOLVED:** Stop at GATE 2 (pre-Document), which is the
   natural behavior of the 3-phase flow; no 4-stage handling needed.

No open questions remain.

## Non-obvious side effects

- The exact phrasing of the bug message ("Since you authorized unattended completion, I'll ... proceed
  automatically to Phase 3") should be explicitly contradicted by the new GATE 2 guard text, or an LLM
  operator may reproduce the old reasoning. The guard line ("unattended phrasing alone never authorizes
  skipping GATE 2") directly targets this.
- `marketplace.json` is easy to forget — the CI job fails the PR if it is not bumped in lockstep with
  `plugin.json`. Both are listed as affected files for this reason.
- The CHANGELOG footer has compare links (`[0.0.4]`, `[0.0.3]`, ...) that should gain a `[0.0.5]`/
  `[0.0.6]` entry to stay consistent; the existing footer already skips some versions, so this is
  cosmetic but worth matching.
