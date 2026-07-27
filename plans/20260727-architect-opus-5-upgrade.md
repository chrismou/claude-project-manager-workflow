# Technical Design Doc: Upgrade `architect` subagent to Opus 5

**Date:** 2026-07-27
**Task:** "Up the architect to use Opus 5."
**Target model ID:** `claude-opus-5` (verified against the authoritative Claude model catalog — Opus 5 is a fixed ID with no date suffix, same scheme as `claude-opus-4-8`).

## Summary

Change the `architect` subagent's model from `claude-opus-4-8` to `claude-opus-5`, and keep the README agent/model table in sync. No behavioural/logic changes to the agent's workflow — model string swap only.

## Affected Files

1. **`agents/architect.md`** (line 4) — YAML frontmatter `model: claude-opus-4-8` → `model: claude-opus-5`. This is the load-bearing change: it is what actually determines which model the subagent runs on.
2. **`README.md`** (line 269) — agent/model table row `| architect | claude-opus-4-8 | ... |` → `claude-opus-5`. Documentation sync only; no functional effect.

## Logic Changes

None. This is a pure configuration/model-ID substitution. The architect's role, workflow steps, output contract (`CLARIFICATIONS_NEEDED:` / `PLAN_PATH:`), and tool usage are unchanged.

## Explicitly Out of Scope

- **`CHANGELOG.md`** — contains a historical entry (line 62) mentioning `claude-opus-4-8`. Historical changelog entries must NOT be rewritten. Any new changelog entry announcing this upgrade is the **documenter's** responsibility, not the coder's. The coder must not touch `CHANGELOG.md`.
- **Other agents' models** — `coder`/`qa-tester`/`reviewer` (`claude-sonnet-4-6`), `documenter` (`claude-haiku-4-5`). No change requested and no strong reason to flag; leave untouched.
- **`plans/20260715-promote-test-to-project-manager.md`** — historical plan file referencing `claude-opus-4-8`. Plan files are audit artifacts and are never edited/deleted.

## Assumptions

- **A1 — Model ID.** "Opus 5" maps to the exact string `claude-opus-5`. Confirmed against the model catalog. No date suffix, no `-fast` variant.
- **A2 — Scope.** "The architect" means only the `architect` subagent defined in `agents/architect.md`. No other agent is being upgraded.
- **A3 — README should stay in sync.** The agent/model table in `README.md` is user-facing documentation and should reflect the new model. (Strictly, only `agents/architect.md` is functionally required; README is included so docs don't drift.)
- **A4 — No settings/effort tuning requested.** The task is a model swap only. No `effort`, thinking, or other Opus-5-specific parameter tuning is being introduced (subagent frontmatter here only carries `model`, not effort).

## Open Questions

None that block implementation. See clarifications section — the only judgment call (whether the README edit is in-scope) is resolved by A3 and is low-risk either way.

## Non-Obvious Side Effects / QA Notes

- **Markdown table alignment (cosmetic).** `claude-opus-5` (13 chars) is shorter than `claude-opus-4-8` (15 chars). The README table column is space-padded for source-readability. After the edit the `architect` row's padding will be slightly off relative to the other rows. This does NOT affect rendered Markdown (pipe tables ignore internal padding), so it is safe to leave, but a tidy edit would re-pad the row to match column width. QA: verify the table still renders correctly and, optionally, that source padding is consistent.
- **Global CLAUDE.md hyphen rule.** User global instructions require the standard ASCII hyphen `-` (U+002D) in any dash output. `claude-opus-5` uses ASCII hyphens — no Unicode dash risk here, but do not "prettify" the model ID.
- **Runtime dependency.** After the change, the `architect` subagent will only launch successfully if `claude-opus-5` is available to the running Claude Code environment/account. If the model is unavailable, the subagent invocation will fail. This is an environmental precondition, not a code defect — flag to the user if the plugin is used in an environment without Opus 5 access.
- **No callers parse the model string.** Grep shows no hook, command, or script that reads or asserts on the architect's model ID, so the swap has no downstream logic impact. `commands/pm.md` references the architect by name/behaviour only.
- **Plugin manifest.** `.claude-plugin/plugin.json` registers `./agents/architect.md` by path but does not embed the model ID, so no manifest change is needed.

## Verification Checklist (for QA)

1. `agents/architect.md` frontmatter reads `model: claude-opus-5`.
2. `README.md` line 269 shows `claude-opus-5` for the architect row.
3. No occurrences of `claude-opus-4-8` remain outside `CHANGELOG.md` and `plans/` (historical/audit files).
4. `CHANGELOG.md` was NOT modified by the coder.
5. README table renders correctly.
