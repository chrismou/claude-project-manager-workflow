# Technical Design Doc: Retire `project-manager`, promote `project-manager-test`

**Date:** 2026-07-15
**Task:** Retire the original `project-manager` command and promote `project-manager-test` to become the new `project-manager`. The test build has fully superseded the original.

**Status:** Clarifications resolved (2026-07-15). Decisions D1–D3 below are final; the approach in Section 3 is now the committed plan.

### Resolved decisions
- **D1 — Consolidate the architect (and any command-specific `-test` agents).** Port `architect-test`'s behaviour onto the base `architect`, then remove the `-test` variant and its `plugin.json` entry. The promoted command wires to base agent names only. **Verified:** the test command's only command-specific agent is `architect-test`; its other calls (`coder`, `qa-tester`, `reviewer`, `documenter`) are already the shared base agents, and `architect-test.md` is the **only** `*-test` agent file in `agents/`. Therefore consolidating `architect-test` → `architect` is sufficient to satisfy the "port ANY command-specific agents" instruction — no other `-test` agents exist to port.
- **D2 — Keep `model: claude-opus-4-8`** for the consolidated `architect` (the validated test model).
- **D3 — `project-manager-auto` is out of scope.** `project-manager-auto.md` and `architect-auto.md` stay on the existing 4-stage flow, untouched.

---

## 1. Goal

Make the promoted pipeline (currently `project-manager-test`, 3-phase Plan → Implement →
Document with the clarifying-questions architect) the one and only `project-manager` command.
The name `project-manager-test` disappears from the plugin surface. The original 4-stage
`project-manager` content is retired.

`project-manager-auto` is **not** in scope for a behavioural change (see Open Questions Q3).

---

## 2. Current state (verified)

Commands (`project-manager/commands/`):
- `project-manager.md` — original, `name: project-manager`, `description: Interactive End-to-End Dev Loop`. 4-stage pipeline (Planning → Implementation → Review → Closeout). Calls `architect` (base), then coder / qa-tester / reviewer / documenter.
- `project-manager-test.md` — `name: project-manager-test`, `description: Interactive End-to-End Dev Loop (test build)`. 3-phase pipeline (Plan → Implement → Document) with a CLARIFICATION GATE and UNATTENDED-SCOPE gate. Calls **`architect-test`** (line 19), then coder / qa-tester / reviewer / documenter.
- `project-manager-auto.md` — `name: project-manager-auto`. Plan-mode 4-stage flow. Calls `architect-auto`. Not referenced by the task.

Agents (`project-manager/agents/`):
- `architect.md` — `name: architect`, `model: claude-sonnet-4-6`. No clarifications flow. **Only referenced by the original `project-manager.md`.**
- `architect-test.md` — `name: architect-test`, `model: claude-opus-4-8`. Has the Assumptions / Open Questions / Non-Obvious Side Effects / `CLARIFICATIONS_NEEDED:` flow. Only referenced by `project-manager-test.md`.
- `architect-auto.md` — `name: architect-auto`, `model: claude-sonnet-4-6`. Plan-mode text-only variant. Referenced only by `project-manager-auto.md`.
- `coder.md`, `qa.md` (agent name `qa-tester`), `reviewer.md`, `documenter.md` — shared by all commands; no changes needed. Only `coder.md` mentions "architect" and only generically ("the plan file passed to you by the architect") — no rename impact.

Metadata:
- `project-manager/plugin.json` — `agents` array lists `architect`, `architect-auto`, `architect-test`, coder, qa, reviewer, documenter. `version: 0.0.6`. `commands: ./commands/` (whole directory — no per-command list to update).
- `.claude-plugin/marketplace.json` — `plugins[0].version: 0.0.6`.
- CI gate `.github/workflows/version-bump.yml` — **blocks merge** unless `plugin.json` AND `marketplace.json` are bumped to the same version, strictly greater than base (0.0.6). Both files must move together to 0.0.7.

Docs:
- `README.md` — describes "Three ways to run it" including a dedicated `project-manager-test` section and a "What to expect (`project-manager-test`)" block; agents table lists architect / architect-auto (not architect-test); the "Project structure" tree is already stale (omits architect-auto, architect-test, project-manager-test, project-manager-auto).
- `CHANGELOG.md` — historical entries reference `project-manager-test` / `architect-test`. These are history and must **not** be rewritten; a new entry is added.

---

## 3. Chosen approach (D1 consolidate, D2 keep opus, D3 auto untouched)

Promote by content, consolidating the architect. Net result: two commands
(`project-manager`, `project-manager-auto`) and no `-test` anything.

### Command layer
1. **Replace `project-manager/commands/project-manager.md`** with the body of
   `project-manager-test.md`, with these frontmatter edits:
   - `name: project-manager` (was `project-manager-test`)
   - `description: Interactive End-to-End Dev Loop` (drop the `(test build)` suffix)
2. In that promoted content, **change the ARCHITECT call from `architect-test` to `architect`**
   (line ~19: `Call 'architect-test'` → `Call 'architect'`). This is the load-bearing rename —
   without it the command points at a deleted agent.
   - **`project-manager-test` self-references:** verified there are **none** in the body — the
     only `project-manager-test` token in the file is the frontmatter `name:` (handled in step 1).
     No further in-body renames are required. (If any future edit introduces a self-reference,
     it must be updated to `project-manager`.)
3. **Delete `project-manager/commands/project-manager-test.md`.** Prefer `git mv` semantics:
   git-move `project-manager-test.md` onto `project-manager.md` (overwriting), then apply the
   frontmatter + architect-call edits, so history follows the surviving file. Either way the
   original `project-manager.md` content is gone and `project-manager-test.md` no longer exists.

### Agent layer (consolidation)
4. **Overwrite `project-manager/agents/architect.md`** with the body of `architect-test.md`,
   setting `name: architect`. Keep `model: claude-opus-4-8` (Q2 default — validated model).
   This makes the base `architect` agent BE the promoted clarifying-questions architect.
5. **Delete `project-manager/agents/architect-test.md`.**
6. **`project-manager/plugin.json`** — remove the `./agents/architect-test.md` entry from the
   `agents` array. Leave `architect`, `architect-auto`, coder, qa, reviewer, documenter.

### Metadata / version
7. **Bump versions to `0.0.7`** in BOTH `project-manager/plugin.json` (`.version`) and
   `.claude-plugin/marketplace.json` (`.plugins[0].version`). Required by the CI gate; they must
   match. (Semver: interface change / removal — a 0.0.x patch bump is consistent with prior
   releases in this repo, all of which used patch bumps.)

### Docs (Document phase / documenter)
8. **`README.md`:**
   - Collapse "Three ways to run it" → two ways (`project-manager`, `project-manager-auto`).
   - Remove the dedicated `project-manager-test` bullet and the "What to expect
     (`project-manager-test`)" section; fold its behaviour (clarification gate, unattended-scope
     gate, auto Code/QA/Review loop, single post-implementation gate) into the primary
     `project-manager` description and "What to expect (`project-manager`)" section, since the
     standard command now IS that flow.
   - Update the agents table: `architect` row should reflect the promoted agent (model
     `claude-opus-4-8`, surfaces clarifications). No `architect-test` row.
   - Refresh the stale "Project structure" tree to match reality (architect, architect-auto,
     coder, qa, reviewer, documenter; commands project-manager, project-manager-auto).
9. **`CHANGELOG.md`:** add a `## [0.0.7]` entry under a `### Changed` (and/or `### Removed`)
   heading describing the promotion of the test pipeline to the default `project-manager`, the
   consolidation of `architect-test` into `architect`, and removal of the `project-manager-test`
   command. **Do not edit existing historical entries.**

---

## 4. Affected files (summary)

| File | Change |
| --- | --- |
| `project-manager/commands/project-manager.md` | Overwritten with promoted (test) content; frontmatter name/description reset; ARCHITECT call → `architect` |
| `project-manager/commands/project-manager-test.md` | Deleted |
| `project-manager/agents/architect.md` | Overwritten with architect-test body; `name: architect` |
| `project-manager/agents/architect-test.md` | Deleted |
| `project-manager/plugin.json` | Remove `architect-test.md` from `agents`; version → 0.0.7 |
| `.claude-plugin/marketplace.json` | version → 0.0.7 |
| `README.md` | Remove test references; two-command model; agents table + structure tree refresh |
| `CHANGELOG.md` | New 0.0.7 entry (append only) |

No changes to `coder.md`, `qa.md`, `reviewer.md`, `documenter.md`, `architect-auto.md`,
`project-manager-auto.md`, or `version-bump.yml`.

---

## 5. Assumptions (all confirmed)

- **A1 — Content-level promotion, not just a rename.** The promoted command must literally
  contain the 3-phase clarifying-questions pipeline; renaming the file alone would not satisfy
  the intent.
- **A2 — `project-manager-test` name is fully retired.** No back-compat alias command is kept —
  a clean cut, consistent with the user's statement that the test has "fully superseded" the
  original.
- **A3 — `project-manager-auto` stays as-is** (D3). Its `architect-auto` agent and 4-stage flow
  are untouched.
- **A4 — Consolidate the architect** `architect-test` → `architect` (D1); this is the only
  command-specific `-test` agent, so no other agents need porting.
- **A5 — Keep `claude-opus-4-8`** for the consolidated architect (D2).
- **A6 — Version bump to 0.0.7**, patch-level, both version files moving together to satisfy the
  CI gate.
- **A7 — CHANGELOG history is immutable**; only a new entry is added.

---

## 6. Open Questions

None outstanding — Q1/Q2/Q3 resolved as D1/D2/D3 (see top of doc). No decision-forcing
ambiguities remain.

---

## 7. Non-Obvious Side Effects / notes for QA

- **Dangling agent reference is the highest-risk failure.** If the ARCHITECT call in the promoted
  command is not updated from `architect-test` to `architect` (or if consolidation is skipped and
  `architect-test.md` is deleted anyway), the command invokes a non-existent agent. QA: grep the
  final command for the exact agent name and confirm a matching `name:` exists in `agents/` and in
  `plugin.json`'s `agents` array.
- **CI merge gate.** Forgetting either version file, or bumping them to different values, will
  fail `version-bump.yml` and block the PR. QA: assert `plugin.json.version ==
  marketplace.json.plugins[0].version == 0.0.7` and both are strictly greater than base 0.0.6.
- **plugin.json `agents` array must not reference a deleted file.** After deleting
  `architect-test.md`, its entry must be removed or the plugin manifest points at a missing file.
- **`commands: ./commands/` is a directory glob** — the plugin auto-discovers commands. Simply
  deleting `project-manager-test.md` removes the command; there is no per-command list to edit.
  Conversely, leaving a stray copy would re-expose the `-test` command.
- **README "Project structure" tree is already inaccurate** (predates architect-auto,
  architect-test, and the extra commands). Refreshing it is part of the doc update, not a
  regression introduced here — but do not "restore" the wrong tree.
- **CHANGELOG references to `project-manager-test` in historical entries are intentional** and
  must remain; only the new 0.0.7 entry is added.
- **`coder.md`'s generic "passed to you by the architect" wording** needs no change — it does not
  name `architect-test`.
- **No functional/behavioural change to the pipeline logic itself** — the promoted flow is copied
  verbatim aside from the frontmatter and the architect agent name. QA should confirm the gate
  wording, CLARIFICATION GATE, and UNATTENDED-SCOPE GATE text survive the move intact (a diff of
  the promoted `project-manager.md` body vs the old `project-manager-test.md` body should show
  only the two intended edits).

---

## 8. Handoff

Coder: implement Section 3 in file order; run the QA checks in Section 7 before converging.
All decisions are final (D1–D3 at the top of this doc) — no clarifications remain outstanding.
