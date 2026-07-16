# Technical Design Doc: Loosen stage-confirmation gates in `project-manager-test`

Date: 2026-06-26
Author: Lead System Architect
Target command: `/home/mou/dev/claude/claude-project-manager/project-manager/commands/project-manager-test.md`

## 1. Objective

Reduce the number of user Yes/No confirmation gates in the `project-manager-test`
pipeline. The pipeline keeps its 5 underlying agent stages (Plan, Code, QA,
Review, Document) but is conceptually regrouped into **3 phases**:

```
Plan  →  Implement (= Code + QA + Review)  →  Document
```

User confirmation gates should exist at **exactly two** points:

1. After **Plan** (architect) completes — confirm before entering **Implement**.
2. After **Implement** converges (coder + qa-tester + reviewer agree on the
   final change set) — confirm before **Document**/Closeout.

All Code↔QA↔Review transitions inside the Implement phase happen **without**
user confirmation. The architect's existing `CLARIFICATIONS_NEEDED:` gate in
the Plan phase is preserved.

## 2. Scope

In scope (the ONLY file modified):
- `project-manager/commands/project-manager-test.md`

Explicitly OUT of scope (do not touch):
- `project-manager/commands/project-manager.md`
- `project-manager/commands/project-manager-auto.md`
- `project-manager/agents/*` (architect-test, coder, qa, reviewer, documenter, etc.)
- `project-manager/plugin.json`
- `.claude-plugin/*`, `README.md`, `CHANGELOG.md`

## 3. Current behavior (as-is)

`project-manager-test.md` defines a 4-stage pipeline with **four** user gates:

| Location | Gate today |
|---|---|
| End of Stage 1 (Planning) | "Ready to proceed to Stage 2: Implementation? (Yes/No)" |
| Mid Stage 2 (after coder, before QA) | "Implementation complete. Ready to proceed to QA? (Yes/No)" |
| End of Stage 2 (after QA passes, before Review) | blockquote "Ready to proceed to Stage 3: Review? (Yes/No)" |
| End of Stage 3 (after reviewer APPROVED, before Closeout) | "Ready to proceed to Stage 4: Closeout? (Yes/No)" |

Plus the `CLARIFICATIONS_NEEDED:` clarification loop in Stage 1.

So today there are FOUR user gates between the five agents. The two interior
gates (before QA, before Review) are the ones the user finds too strict.

## 4. Desired behavior (to-be)

Two user gates only:

1. **Plan gate** — kept from current Stage 1 end gate (rename target to
   "Implement").
2. **Implement gate** — single gate after the whole Code/QA/Review loop has
   converged (reviewer returns `APPROVED`), before Document.

Removed gates:
- The "Ready to proceed to QA?" gate (currently between coder and qa-tester).
- The "Ready to proceed to Stage 3: Review?" blockquote gate (currently between
  qa pass and reviewer).

Preserved loops (no user interaction inside Implement):
- QA failure loop: `QA_FAILED:` → coder fixes → re-run qa-tester → repeat until
  `STAGE_COMPLETE: qa`.
- Reviewer-changes loop: reviewer requires changes → coder applies → re-run
  qa-tester then reviewer as needed → repeat until `APPROVED`.

Preserved signals (unchanged, must keep matching the agent definitions):
- `CLARIFICATIONS_NEEDED:` / `PLAN_PATH:` (architect-test)
- `STAGE_COMPLETE: coder` (coder)
- `STAGE_COMPLETE: qa` / `QA_FAILED:` (qa-tester)
- `APPROVED` (reviewer)
- `STAGE_COMPLETE: documenter` (documenter)

## 5. Proposed new structure of `project-manager-test.md`

Replace the body (everything from the `## MANDATORY PIPELINE` heading down)
with a 3-phase structure. Keep the YAML frontmatter (`name`,
`description`) unchanged.

### Header / framing
- Change the intro from "fixed 4-stage pipeline" to a "3-phase pipeline (5
  underlying stages)" framing.
- Change the stages line from
  `Stages: Planning → Implementation → Review → Closeout`
  to
  `Phases: Plan → Implement → Document` with a note that Implement runs the
  Code → QA → Review agents internally.
- Keep the existing guardrails: "Never ask 'what would you like to work on
  next?'" and "If the user's response to a Yes/No gate is unclear, restate the
  same question."

### Phase 1 — Plan
- **ARCHITECT:** Call `architect-test` on "$ARGUMENTS" (unchanged wording).
- **CLARIFICATION GATE:** Preserve verbatim the current Stage 1
  `CLARIFICATIONS_NEEDED:` block (lines 18–19 today). No behavioral change.
- **GATE 1:** "Plan generated at [PLAN_PATH]. Review and edit it if needed.
  Ready to proceed to Implement? (Yes/No)" — wait for Yes; on No, ask what to
  change and loop back to ARCHITECT.

### Phase 2 — Implement (Code + QA + Review, no interior user gates)
State explicitly at the top of this phase: "The coder, qa-tester, and reviewer
agents iterate among themselves. Do NOT ask the user for confirmation at any
point inside this phase until the gate at the end."

Sub-steps:
1. **CODER:** Call `coder` with the plan path. Wait for `STAGE_COMPLETE: coder`.
   (Removed: the old "Ready to proceed to QA?" gate.)
2. **QA:** Call `qa-tester`. Wait for `STAGE_COMPLETE: qa` or `QA_FAILED:`.
   - On `QA_FAILED:` → call `coder` to fix → re-run `qa-tester`. Repeat until
     `STAGE_COMPLETE: qa`. (No user gate.)
3. **REVIEW:** On `STAGE_COMPLETE: qa`, immediately call `reviewer` (no gate).
   - If changes required → call `coder` to apply them → re-run `qa-tester`
     (to confirm fixes don't regress) then `reviewer`. Repeat until `APPROVED`.
   - On `APPROVED` → Implement has converged.
4. **GATE 2:** Present a summary of the full implementation (files changed, QA
   result, review result), then ask for confirmation before Document. Reuse the
   existing blockquote style for visibility, e.g.:

   > Implement phase complete — code, QA, and review have converged.
   > You can manually review the changes before continuing.
   >
   > Ready to proceed to Document/Closeout? **(Yes / No)**
   >
   > — Reply **Yes** to continue, or **No** to provide feedback first.

   - WAIT for explicit user reply.
   - On Yes → Phase 3.
   - On No → ask for specific feedback, then loop back to **Phase 1 (Plan /
     architect)**, mirroring the current Stage 3 "No" branch (which loops back
     to Stage 1). RESOLVED (Q1): No does NOT loop back into Implement; it
     returns to the architect for replanning. The architect's clarification gate
     and GATE 1 then run again before re-entering Implement.

### Phase 3 — Document / Closeout
- **DOCUMENTER:** Call `documenter`. Wait for `STAGE_COMPLETE: documenter`.
- **DONE:** "Pipeline complete. Documentation updated. Plan retained at
  [PLAN_PATH]."
- Do NOT delete the plan file — retained for audit and version control.

## 6. Logic changes summary

| Change | Detail |
|---|---|
| Framing | 4 stages → 3 phases (Plan / Implement / Document); 5 underlying agents noted |
| Remove gate | "Ready to proceed to QA?" (coder→qa) deleted |
| Remove gate | "Ready to proceed to Stage 3: Review?" (qa→reviewer) deleted |
| Keep gate | Plan→Implement gate (renamed target) |
| Keep gate | Implement→Document gate (was Review→Closeout; now fires after reviewer APPROVED). On No → loop back to Phase 1 (architect). |
| Keep loop | QA_FAILED → coder → qa loop |
| Keep loop | reviewer-changes → coder → qa/reviewer loop |
| Keep | Clarification gate in Plan phase |
| Keep | All handoff signals verbatim |

Net result: user gates drop from 4 to 2; interior Code/QA/Review transitions
become automatic.

## 7. Assumptions

- A1: The visible phase labels should be renamed to "Plan / Implement /
  Document" to match the new 3-phase mental model, and gate prompt text should
  reference "Implement" and "Document" rather than "Stage 2/3/4". (Cosmetic but
  improves clarity; no agent name changes.)
- A2: The two surviving gates should keep waiting for an explicit Yes/No and
  restate the question if the reply is unclear (existing guardrail retained).
- A3: Inside the reviewer-changes loop, re-running qa-tester before reviewer is
  desirable (prevents regressions) — matches the task's "re-run qa/reviewer as
  needed" language.
- A4: Only the body of the file changes; YAML frontmatter (`name:
  project-manager-test`, `description: ... (test build)`) stays as-is.
- A5 (RESOLVED, Q2): `plugin.json` is left untouched by this change and by the
  Implement phase. The CI version-bump gate is satisfied SEPARATELY at
  Closeout/commit time (handled outside this command file). The command file
  itself does not manage the version bump.

## 8. Open Questions (all resolved)

- Q1 (No-path at the Implement gate) — **RESOLVED:** On **No** at GATE 2, loop
  back to **Phase 1 (Plan / architect)**, mirroring the current Stage 3 "No"
  branch. Do NOT loop back into Implement. Reflected in §5 Phase 2 GATE 2 and §6.
- Q2 (CI version-bump gate) — **RESOLVED:** Leave `plugin.json` untouched during
  Implement. The version bump is handled SEPARATELY at Closeout/commit time so
  the CI gate passes. The command file does not manage this. Reflected in §2 and
  §7 A5.

## 9. Potential side effects for the QA agent (prompt-flow review)

There is **no automated test suite** in this repo — these are agent/command
markdown prompt definitions. Validation is by careful read-through of the
prompt flow. QA should verify:

- S1: Exactly **two** user Yes/No gates remain in the file (Plan→Implement and
  Implement→Document). Grep for "Yes/No" / "(Yes" occurrences and confirm count.
- S2: The two removed gates ("Ready to proceed to QA?" and "Ready to proceed to
  Stage 3: Review?") are gone — no residual "proceed to QA" / "proceed to Stage
  3" text.
- S3: The `CLARIFICATIONS_NEEDED:` clarification loop text is still present and
  unchanged in behavior.
- S4: All handoff signals still appear verbatim and spelled exactly:
  `CLARIFICATIONS_NEEDED:`, `PLAN_PATH:`, `STAGE_COMPLETE: coder`,
  `STAGE_COMPLETE: qa`, `QA_FAILED:`, `APPROVED`, `STAGE_COMPLETE: documenter`.
- S5: The QA-failure loop and reviewer-changes loop are still described and
  still terminate on `STAGE_COMPLETE: qa` and `APPROVED` respectively.
- S6: No stray references to "4-stage" / "Stage 4" / old stage numbering that
  contradict the new 3-phase framing.
- S7: The "do not delete the plan file" closeout instruction is retained.
- S8: YAML frontmatter is intact and parseable (name + description unchanged).
- S9: Cross-file consistency: confirm `project-manager.md` and
  `project-manager-auto.md` were NOT modified (diff scope is a single file).

## 10. Non-obvious side effects / things easy to miss

- N1: `project-manager.md` (the non-test command) has a **near-identical**
  4-stage body. It is intentionally left as-is. Do not "helpfully" apply the
  same change there — the constraint is test-only. A diff touching more than
  `project-manager-test.md` is a defect.
- N2: The reviewer agent signals approval with the bare string `APPROVED`
  (not `STAGE_COMPLETE: review`). The Implement gate must trigger on `APPROVED`,
  not invent a new signal.
- N3: The qa-tester is the agent named `qa-tester` in invocations, but its
  definition file is `agents/qa.md` and it emits `STAGE_COMPLETE: qa`. Keep the
  invocation name `qa-tester` and the signal `qa` consistent — do not rename.
- N4: The existing QA-pass blockquote (lines 32–38 today) is being repurposed/
  moved to the single Implement→Document gate. Ensure it is not left duplicated
  in two places after editing.
- N5: The command is also surfaced as a Skill
  (`chrismou-claude-plugins:project-manager-test`). The frontmatter
  `description` is what shows in the skill list, so it must not change.
- N6: Removing interior gates means the model now runs coder→qa→reviewer
  autonomously; the prompt must explicitly forbid asking the user mid-phase,
  otherwise the model may still volunteer confirmation prompts out of habit.
  This is why Phase 2 carries an explicit "do NOT ask the user" instruction.

## 11. Implementation approach for the coder

- Single-file edit of `project-manager-test.md`.
- Rewrite the `## MANDATORY PIPELINE` section and the four stage sections into
  the three-phase structure in §5. Preserve frontmatter verbatim.
- After editing, re-read the file top-to-bottom and run the §9 checklist as a
  self-review (no syntax tooling applies to markdown prompts here).
- Do not modify any other file.

## 12. Validation

- Manual read-through against the §9 checklist (no automated tests exist).
- `git diff --stat` must show exactly one file changed:
  `project-manager/commands/project-manager-test.md`.
