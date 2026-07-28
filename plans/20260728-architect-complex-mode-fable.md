# Technical Design Doc — "Complex mode" (Fable architect) + revert standard architect to Opus 4.8

Date: 2026-07-28
Status: **Ready for implementation** — all clarifications resolved
Revision: 3 (closes §9-predicted failure-branch reachability gap: §5.4 scope clause now explicitly
covers every ARCHITECT invocation including clarification re-runs and loop-backs, matching the
stickiness language already in §5.3; Revision 2 text below)

Revision: 2 (incorporates user decisions on scope, trigger syntax, Fable-failure policy, and
version target; folds the branch-base and stale-branch housekeeping into §5.5/§5.6 as real steps;
adds §8, a verified method for proving which model actually ran)

**Branch base:** `main` (fetch/pull first — see §5.5)
**Version:** `0.3.2` → `0.4.0`

---

## 0. Decisions incorporated in this revision

The four open questions from Revision 1 are resolved. Recorded here so the rationale is not lost:

| # | Question | Decision |
| --- | --- | --- |
| Q1 | Scope of complex mode | **(a) Architect-only.** Only the architect escalates to Fable. `coder`, `qa-tester`, `reviewer`, `documenter` keep their current models. |
| Q2 | Trigger syntax | **(a) `--complex` prefix.** Must not collide with task text such as *"complex refactor of the auth module"*. Exact parse/strip rules specified in §5.2. |
| Q3 | Fable unavailable / consent-gated / out of credits | **Split by attendance.** Attended `/pm` **pauses and waits** so the user can resolve the consent prompt. Unattended `/pm-auto` **aborts and disarms** — see §5.4, which makes the disarm path explicit. |
| Q4 | Version target | **`0.4.0`** (new user-facing feature under the semver the repo claims to follow). |

Two items that were asides in Revision 1 are now numbered plan steps, not commentary:

- Branch from a freshly pulled `main` — §5.5.
- Delete the stale `origin/chore/architect-opus-5` branch — §5.6.

---

## 1. The request

Verbatim:

> I want to add a new "complex mode" that would use fable for the architect. I also want to switch
> the standard architect back to using opus 4.8
>
> Ideally the complex mode would be available to both PM commands (standard and auto) so am unsure
> if it would require a new command for each (ie pm-complex, pm-auto-complex) or if this can be a
> something I can trigger once the command is running?

Two deliverables:

1. **Revert** `architect` to Opus 4.8 as its default model (undoing v0.3.1, commit `9ba475f`).
2. **Add** an opt-in "complex mode" that runs the architect on Fable 5 instead, reachable from both
   `pm` and `pm-auto`.

## 2. Model IDs (verified, do not substitute)

Confirmed against the authoritative Claude model catalog via the `claude-api` skill. These are
complete as written — **never append a date suffix**:

| Model | Exact ID |
| --- | --- |
| Claude Opus 4.8 | `claude-opus-4-8` |
| Claude Fable 5 | `claude-fable-5` |

Both are also reachable by the short aliases `opus` and `fable`, but see §3.2 — the alias and the
full ID are **not** interchangeable for our purposes.

---

## 3. Harness capability findings

This section is the load-bearing research for the design. Everything below was verified against the
installed Claude Code bundle at `/home/mou/.local/share/claude/versions/2.1.220` (a single 275 MB
executable), using the same technique as the 0.3.2 plan.

### 3.1 A subagent's model CAN be overridden per invocation

The Agent tool exposes an optional `model` parameter. Its documented contract, extracted verbatim
from the bundle:

> Optional model override for this agent. Takes precedence over the agent definition's model
> frontmatter. If omitted, uses the agent definition's model, or inherits from the parent.

and, from the agent-definition side:

> model, reasoning effort, and tool access are set in its definition (`.claude/agents/*.md`
> frontmatter, or the SDK `agents` option); the `model` parameter here overrides the definition
> for this one call.

The resolution logic in the bundle makes the precedence explicit:

```js
[c,u] = l && l!=="inherit" ? [l,"env"]
      : r ? (r==="inherit" ? [t,"inherit"] : [r,"tool"])
      : e && e!=="inherit" ? [e,"frontmatter"]
      : [t,"inherit"]
```

Reading the tags off that chain, precedence is:

**`env` > `tool` (the Agent tool `model` parameter) > `frontmatter` > `inherit` (parent's model)**

A per-invocation override is therefore a first-class, supported feature — **not** a workaround.

### 3.2 …but the override accepts aliases only, and `fable` is one of them

The `model` parameter's schema enum appears in the bundle as, exactly:

```json
["sonnet","opus","haiku","fable"]
```

Two consequences, both load-bearing:

- **Good news:** `fable` is a valid override value. Complex mode needs no new agent file, no
  duplicated agent definition, and no manifest change — just a parameter on the existing call.
- **Constraint:** the enum is **aliases only**. You cannot pass `claude-opus-4-8` or
  `claude-fable-5` through this parameter. A separate, wider enum exists elsewhere in the bundle
  (`["sonnet","opus","haiku","fable","best","sonnet[1m]","opus[1m]…`) for the CLI `--model` flag
  and settings, but the *subagent* override is restricted to the four short aliases.

**Therefore the standard architect's Opus 4.8 pin must live in frontmatter, not in an override.**
The alias `opus` resolves to whichever model the harness currently considers the default Opus, and
that is explicitly *not* guaranteed to be 4.8 — the bundle contains a family/version table
`[["opus",[4,8]],["sonnet",[5]],["fable",[5]],["mythos",[5]]]` whose semantics I could not pin down
with confidence, and Opus 5 exists and is newer. Writing `model: opus` in frontmatter would leave
the "revert to 4.8" request at the mercy of alias drift. Use the explicit `claude-opus-4-8` string.

This yields the core split of the design:

| Path | Model | Set where | Why there |
| --- | --- | --- | --- |
| Standard | `claude-opus-4-8` | `agents/architect.md` frontmatter | Full ID needed; must be version-pinned |
| Complex | `fable` | Agent tool `model` param at call site | Only aliases accepted; must be per-call |

Frontmatter accepts both forms — this repo already mixes them (`claude-opus-5`,
`claude-sonnet-4-6`, `claude-haiku-4-5-20251001` as full IDs; `sonnet` as an alias in
`agents/qa.md`), and all five agents load today.

### 3.3 Commands receive free-text arguments

`commands/pm.md` and `commands/pm-auto.md` both interpolate `$ARGUMENTS`. There is no structured
flag parser — `$ARGUMENTS` is the raw remainder of the slash-command line. A "flag" is therefore
implemented as *prose instructions telling the orchestrating model to look for a token and strip
it*, not as a declarative option. That works reliably but must be written precisely, which is why
§5.2 specifies the parse rules to the character.

### 3.4 Fable is entitlement- and credit-gated

This is the finding that most affects the design, and it is not visible from the model catalog.
The bundle carries substantial Fable-specific gating machinery:

- **Session-state flags:** `fableCreditsRequired`, `fableConsentSessionFallback`,
  `fableBridgeDialogTimedOut`, `fableConsentDialogInteracted`, with getters/setters
  (`isFableCreditsRequired`, `hasFableConsentSessionFallback`, …).
- **A consent dialog** with telemetry event `model_fable_consent` and recorded outcomes:
  `declined`, `dismissed`, `switch`, `upsell_selected`, `overage_enable_deferred`.
- **User-facing strings**, verbatim:
  - `Buy more to keep using Fable 5, or switch models to keep working.`
  - `Switch models to keep working.`
  - `… isn't available for your account yet. Run /model to pick another model`
  - `Contact your admin to manage us…` (truncated; paired with `confirm-admin-request`)
- **Failure/telemetry states:** `fable_unavailable`, `fable_probe_failed`.

Read together: selecting Fable can (a) require an entitlement the account may not have, (b) consume
a separate credit pool that can be exhausted mid-run, and (c) surface an **interactive modal** that
blocks until answered, with a timeout path (`fableBridgeDialogTimedOut`) and a session-scoped
fallback (`fableConsentSessionFallback`).

That is tolerable in an attended `/pm` run and unacceptable in `/pm-auto`. Hence the split policy in
§5.4.

### 3.5 Verdict on the three options originally raised

| Option | Verdict |
| --- | --- |
| New commands (`pm-complex`, `pm-auto-complex`) | **Rejected** — see §4.2 |
| Flag/argument on existing commands | **Adopted** |
| Runtime toggle once the command is running | **Partially adopted, for free** — see §4.3 |

---

## 4. Design

> **Add a `--complex` flag to the existing `pm` command, implemented as an Agent-tool `model:
> fable` override on the architect call. Add no new commands. `pm-auto` inherits it automatically
> because it already forwards `$ARGUMENTS` verbatim to the `pm` skill.**

### 4.1 Why a flag

- The mechanism already exists and is designed for exactly this (§3.1). No new agent file, no
  duplicated architect definition that would drift from the original.
- It composes: `pm-auto` currently delegates with *"Invoke the `chrismou-project-manager:pm` skill
  with `$ARGUMENTS` and follow it in full. Do not restate or reinterpret the pipeline — it is
  defined there."* Because the flag is parsed inside `pm.md`, `/pm-auto --complex <task>` works
  with **no logic changes to `pm-auto.md`** — documentation and one ARM-block caveat only.

### 4.2 Why not separate commands

- **Combinatorial growth.** Two commands become four. Any future mode doubles it again.
- **Real duplication.** `pm-auto.md` carries ~70 lines of pre-flight, jq check, deny-override
  validation, ARM, and DISARM logic. A `pm-auto-complex` either duplicates all of it (drift risk on
  a **security-relevant** permissionless gate) or adds a third layer of delegation.
- **The name would not fit.** Not speculative: v0.3.0 renamed `project-manager` → `pm` *specifically
  because* the slash-command picker "prints the command name twice in a fixed-width column, so
  `<plugin>:<command> (<command>)` truncated on standard-width terminals."
  `chrismou-project-manager:pm-auto-complex (pm-auto-complex)` is materially worse than the string
  that already forced a breaking rename.

### 4.3 Runtime escalation comes almost free

The pipeline already re-runs ARCHITECT at three points: the clarification loop, GATE 1 "No", and
GATE 2 "No" (which loops back to Phase 1). At each the orchestrator asks for feedback and re-invokes
the architect. So the escalation path costs one sentence, not a new gate: if the user's GATE 1/GATE
2 feedback asks for complex mode, set `COMPLEX_MODE = true` for subsequent ARCHITECT runs.

Do **not** add a dedicated "do you want complex mode?" prompt to every run — it taxes every ordinary
run, cannot work under `pm-auto`, and conflicts with the command's standing rule: *"Never ask 'what
would you like to work on next?' — the next phase is always determined by the pipeline."*

---

## 5. Affected files and changes

| File | Change |
| --- | --- |
| `agents/architect.md` | Frontmatter line 4: `model: claude-opus-5` → `model: claude-opus-4-8` |
| `commands/pm.md` | Mode-selection preamble (§5.2); Phase 1 override + Fable-failure handling (§5.3, §5.4); runtime-escalation sentence on the GATE 1 / GATE 2 "No" branches |
| `commands/pm-auto.md` | Documentation only — note `--complex` is forwarded; ARM-block caveat |
| `README.md` | Agent table architect row → `claude-opus-4-8`; new "Complex mode" subsection |
| `.claude-plugin/plugin.json` | `version`: `0.3.2` → `0.4.0` |
| `CHANGELOG.md` | New `## [0.4.0]` section — **documenter's job, not the coder's** (see §5.7) |

Explicitly **not** changed (Q1 = architect-only):

- `agents/coder.md`, `agents/qa.md`, `agents/reviewer.md`, `agents/documenter.md` — all keep their
  current models. Complex mode does **not** touch them.
- `hooks/*` — complex mode touches no hook. The permissionless gate, deny list, and session cleanup
  are untouched.
- `plans/*` — audit artifacts, never edited. `plans/20260727-architect-opus-5-upgrade.md` documents
  the change we are now reverting; it stays exactly as written.

### 5.1 `agents/architect.md`

Single-line frontmatter edit. Role, workflow, output contract (`CLARIFICATIONS_NEEDED:` /
`PLAN_PATH:`), and constraints unchanged. This file must **not** gain any complex-mode awareness —
the architect does not know which model it is running on and does not need to. That knowledge lives
entirely in the caller.

```yaml
---
name: architect
description: Analyzes requirements and creates technical execution plans.
model: claude-opus-4-8
---
```

### 5.2 `commands/pm.md` — flag parsing (Q2)

Insert after the `# Task: $ARGUMENTS` heading and before `## MANDATORY PIPELINE`. The parse rules are
deliberately strict so that a task legitimately containing the word "complex" is never misread.

```md
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
```

Worked examples the implementer should treat as the specification:

| Input after the command name | `COMPLEX_MODE` | `TASK` |
| --- | --- | --- |
| `--complex add rate limiting` | `true` | `add rate limiting` |
| `complex refactor of the auth module` | `false` | `complex refactor of the auth module` |
| `add a --complex flag to the parser` | `false` | `add a --complex flag to the parser` |
| `--complex` (nothing else) | `true` | *(empty — stop and ask)* |
| `  --complex   fix the cache  ` | `true` | `fix the cache` |

`/pm-auto --complex <task>` needs no separate parsing: `pm-auto.md` forwards `$ARGUMENTS` verbatim
to the `pm` skill, so the same block above is what parses it. The flag never reaches the ARM step
and never becomes part of the task description.

### 5.3 `commands/pm.md` — Phase 1 ARCHITECT

```md
- **ARCHITECT:** Call 'architect' to analyze "$TASK".
  - If `COMPLEX_MODE` is true, pass the Agent tool's `model` parameter as `fable` on this call.
  - If `COMPLEX_MODE` is false, omit the `model` parameter entirely so the architect runs on its
    definition default (`claude-opus-4-8`). Do not pass `opus` — the alias is not version-pinned.
  - This applies to **every** ARCHITECT invocation in the session, including clarification re-runs
    and loop-backs from GATE 1 / GATE 2. `COMPLEX_MODE` is sticky once set.
```

Runtime escalation, appended to the GATE 1 "No" and GATE 2 "No" branches:

```md
  - If the feedback asks for complex mode (or names Fable, or asks for a deeper/more thorough
    plan), set `COMPLEX_MODE = true` before re-running ARCHITECT, and say so.
```

`COMPLEX_MODE` is one-way — it latches on and is never cleared. Downgrading mid-run is not requested
and would create ambiguity about which model produced which plan revision.

### 5.4 `commands/pm.md` — Fable failure handling (Q3), including the explicit disarm path

Add immediately after the ARCHITECT bullet in Phase 1. This is the safety-relevant part of the
change and must be implemented as written.

```md
- **COMPLEX-MODE FAILURE HANDLING** _(applies only when `COMPLEX_MODE` is true, on every ARCHITECT invocation including clarification re-runs and loop-backs):_
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
```

**Why this needs to be written explicitly rather than relying on what is already there.**
`pm-auto.md`'s DISARM section does say *"On any abort or unexpected stop: same."* — but that is a
catch-all in the *wrapper*, and `pm.md`'s own DISARM steps are conditional and located at the end of
Phase 2 and inside Phase 3. A Phase 1 abort currently has **no explicit disarm instruction in the
file that is actually executing the pipeline**. Since complex mode introduces a brand-new, entirely
plausible Phase 1 failure mode, that gap must be closed here rather than left to inference.

Note also the deliberate asymmetry with the existing deny-list behaviour, which *"pauses
indefinitely rather than failing"* in an unattended run. Pausing is right for a deny-list match —
the flag file's own expiry bounds the exposure and the operation is one the user may want to approve
later. It is wrong here, because a Fable consent modal in an unattended run has nobody to answer it
and may itself time out, so the run could park indefinitely with the flag armed.

### 5.5 Branch base and version (CI gate) — do this first

Verified by `git fetch` on 2026-07-28:

- `origin/main` is at `47d932d`, version **`0.3.2`** — the duplicate-hooks hotfix **has merged**.
- The local `hotfix/duplicate-hooks-manifest` branch is 1 commit *behind* `origin/main` and 0
  ahead. Its work is fully contained in `main`; it is stale and its purpose is served.

Implementer steps, in order:

1. `git checkout main && git pull`. **Do not branch from `hotfix/duplicate-hooks-manifest`.**
2. `git rev-parse --short HEAD` → expect `47d932d` (or later, if `main` has moved on since).
3. `jq -r .version .claude-plugin/plugin.json` → expect `0.3.2`. If it differs, stop and re-derive
   the bump target rather than writing `0.4.0` from this plan blindly.
4. `git checkout -b feat/architect-complex-mode`.
5. Apply the changes, setting `version` to `0.4.0`.

`version-bump.yml` fails any PR whose version does not sort strictly greater than base under
`sort -V`. It is a hard gate, not advisory. `0.4.0 > 0.3.2` under `sort -V`.

### 5.6 Delete the stale `chore/architect-opus-5` branch

`origin/chore/architect-opus-5` is the branch that introduced `model: claude-opus-5` (merged as
`c908d20`, released as v0.3.1). It is fully merged and now actively hazardous: re-merging it after
this change would silently reinstate `claude-opus-5` and undo the revert, with no conflict and no
test failure to catch it.

Delete it as part of this work:

```sh
git push origin --delete chore/architect-opus-5
```

Confirm with `git branch -r` that it is gone. If the user wants it kept for history, note that the
commit is already reachable from `main`, so nothing is lost by deleting the branch pointer.

*(Out of scope but worth mentioning to the user: `hotfix/duplicate-hooks-manifest`,
`hotfix/plugin-root-env-var`, `permissionless-auto-command`, `refactor/shorten-command-names`, and
`revert-3-refactor/shorten-command-names` are also still on the remote. Only
`chore/architect-opus-5` is a hazard to *this* change; the rest are general housekeeping and should
not be swept up into this PR.)*

### 5.7 `CHANGELOG.md` — coder must not touch it

Per the precedent set in the 0.3.1 plan and enforced by the pipeline's Phase 3, the CHANGELOG entry
is written by the **documenter**, not the coder. The coder must leave `CHANGELOG.md` alone.
Historical entries — including the 0.3.1 line *"architect agent model upgraded from
`claude-opus-4-8` to `claude-opus-5`"* — must **not** be rewritten even though we are reverting that
change. The new entry supersedes it; it does not erase it.

The 0.4.0 entry should cover, at minimum: the architect revert to Opus 4.8 and why; the new
`--complex` flag and its exact syntax; that it works on both `pm` and `pm-auto`; that it escalates
**only** the architect; and the Fable entitlement/credit caveat with the differing attended vs
unattended failure behaviour.

---

## 6. Logic changes — summary

There is no algorithmic change anywhere. The entire feature is:

1. One frontmatter string swap (the revert).
2. One conditional parameter on one existing tool call (the feature).
3. Argument parsing to decide that conditional.
4. One new failure branch with an explicit disarm (the safety work).

No hook, no script, no JSON schema, and no agent *behaviour* changes. The architect produces the
same artifact in the same format either way — only the model behind it differs.

---

## 7. QA / verification plan

### 7.1 Static checks

1. `grep -n '^model:' agents/architect.md` → `model: claude-opus-4-8`.
2. No occurrence of `claude-opus-5` remains outside `CHANGELOG.md` and `plans/` (both historical/
   audit files that legitimately still mention it).
3. `jq . .claude-plugin/plugin.json` exits 0; `.version` is `0.4.0`.
4. `printf '0.3.2\n0.4.0\n' | sort -V | tail -1` → `0.4.0` (mirrors the CI gate's own comparison).
5. `git diff --name-only origin/main` lists only the files in §5 (plus `CHANGELOG.md` after Phase 3).
6. `bash hooks/generate-readme-section.sh && git diff --quiet README.md` → **must pass**. See §9.
7. README agent table architect row reads `claude-opus-4-8`.
8. `git branch -r | grep -c chore/architect-opus-5` → `0` (§5.6 done).

### 7.2 Flag-parsing checks

Run each row of the §5.2 worked-example table and confirm the observed `COMPLEX_MODE` / `TASK`
split. The two negative cases are the important ones:

- `complex refactor of the auth module` must run in **standard** mode with the word "complex"
  intact in the task.
- `add a --complex flag to the parser` must run in **standard** mode with the flag text preserved.

Confirm too that the generated plan filename slug contains no flag residue.

### 7.3 Functional checks — must be done in a live Claude Code session

Static checks cannot prove any of this; the feature is a runtime routing decision.

1. **Standard path.** `/chrismou-project-manager:pm <trivial task>` → architect runs, plan
   produced. Verify via §8 that it ran on **`claude-opus-4-8`**.
2. **Complex path.** `/chrismou-project-manager:pm --complex <trivial task>` → "Complex mode"
   announcement appears; verify via §8 that the architect ran on **`claude-fable-5`**.
   *Release-blocking.*
3. **Stickiness.** Trigger a clarification round in complex mode; verify via §8 that **every**
   architect entry for that session is Fable, not just the first.
4. **Runtime escalation.** Start without the flag; answer GATE 1 with "No — redo this in complex
   mode"; confirm the re-run is on Fable.
5. **`pm-auto` forwarding.** `/chrismou-project-manager:pm-auto --complex <trivial task>` →
   flag consumed (not treated as task text), architect on Fable, and
   `.claude/.pm-permissionless.json` armed and disarmed exactly as before.
6. **Regression.** `/pm` and `/pm-auto` with **no** flag → identical behaviour to 0.3.2: same
   gates, same prompts, same disarm, architect on Opus 4.8.
7. **Attended Fable failure (Q3 path A).** Simulate by running `--complex` on an account or state
   where Fable is unavailable. Confirm the run **pauses** with the Retry/Standard prompt and does
   **not** proceed to Phase 2 or silently downgrade.
8. **Unattended Fable failure (Q3 path B).** Same simulation via `pm-auto --complex`. Confirm the
   run **aborts**, and — critically — that `.claude/.pm-permissionless.json` **no longer exists**
   afterwards. *Release-blocking.* This is the check that proves the §5.4 disarm path works.

Checks 2, 5, and 8 are release-blocking.

---

## 8. How to verify which model actually ran

Revision 1 flagged that the override **fails silently** — if it does not take, the architect runs on
its frontmatter model and produces a perfectly reasonable plan, indistinguishable at a glance. The
coordinator asked whether there is a practical way to confirm. **There is, and it is exact.** I
verified it empirically against the session that produced this document.

### 8.1 The mechanism

Claude Code writes a per-subagent transcript plus a metadata sidecar to:

```
~/.claude/projects/<project-slug>/<session-id>/subagents/
    agent-<id>.meta.json     # which agent this was
    agent-<id>.jsonl         # its messages, each tagged with the model that produced it
```

- `<project-slug>` is the working directory with `/` replaced by `-` — for this repo,
  `-home-mou-dev-claude-claude-project-manager-workflow`.
- `<session-id>` is the value of `$CLAUDE_CODE_SESSION_ID`. Convenient: `pm-auto.md` **already**
  captures this during ARM, so an unattended run can derive its own transcript path.

The sidecar identifies the agent, and every assistant entry in the `.jsonl` carries the real model
string in `.message.model` (plus `.effort`). Confirmed live — the sidecar for this planning run
reads:

```json
{
  "agentType": "chrismou-project-manager:architect",
  "description": "Plan complex mode + architect model",
  "toolUseId": "toolu_016JMEZGLGbZH5YFU6w6Emgo",
  "spawnDepth": 1
}
```

and its transcript reports `{"model":"claude-opus-5","sidechain":true,"effort":"high"}` on every
assistant entry — which matches `agents/architect.md`'s current frontmatter exactly. That is
end-to-end proof that this file is an accurate record of the model a subagent actually ran on.

### 8.2 The check

Run this after a `/pm` or `/pm-auto` run, in the repo:

```sh
SLUG=$(pwd | tr '/' '-')
SESSION="$CLAUDE_CODE_SESSION_ID"   # or the id printed by pm-auto's ARM step
for m in ~/.claude/projects/"$SLUG"/"$SESSION"/subagents/*.meta.json; do
  printf '%-45s' "$(jq -r .agentType "$m")"
  jq -r 'select(.type=="assistant") | .message.model' "${m%.meta.json}.jsonl" | sort -u | tr '\n' ' '
  echo
done
```

Expected output:

| Run | Expected architect line |
| --- | --- |
| `/pm <task>` | `chrismou-project-manager:architect   claude-opus-4-8` |
| `/pm --complex <task>` | `chrismou-project-manager:architect   claude-fable-5` |

Interpretation rules:

- **`claude-opus-4-8` on a `--complex` run means the override did not take.** That is the silent
  failure, caught. Treat it as release-blocking.
- A run with multiple architect invocations produces multiple entries; check 7.3.3 requires **all**
  of them to be Fable, not just the first.
- The override is passed as the alias `fable`; the transcript records the **resolved** model string.
  Expect `claude-fable-5`. If a future harness records the alias verbatim instead, `fable` is also
  acceptable — but `claude-opus-4-8` never is.

### 8.3 Limitations of this method — read before relying on it

- **It is post-hoc.** The transcript is written as the run proceeds, so this confirms what happened;
  it cannot gate a run before the architect executes. There is no pre-flight "is Fable actually
  going to be used" probe.
- **It is an internal file format, not a public API.** The `~/.claude/projects/**` layout and the
  `subagents/` sidecar are Claude Code implementation details, verified against 2.1.220 only. A
  future version may move or rename them. If the path does not exist, do not conclude the feature is
  broken — first confirm the layout still matches.
- **Do not automate the pipeline against it.** This is a human verification tool for QA and
  spot-checks. Wiring `pm.md` to parse its own transcript mid-run would couple a shipped plugin to
  an unstable internal format, for a check that cannot prevent the failure anyway.
- **There is no in-chat indicator.** Neither the architect's own output nor the orchestrator's
  summary states which model ran, and the architect genuinely does not know (§5.1). The
  "Complex mode: …" announcement from §5.2 reports *intent*, not *outcome* — it is printed before
  the call and will still appear if the override silently fails. Do not treat it as confirmation.
  Checking the transcript is the only reliable confirmation available.

---

## 9. Non-obvious side effects and traps

- **The override fails silently.** The single most important QA point. "Complex mode ran and gave
  me a good plan" is **not** evidence Fable was used — §8 is.
- **The mode announcement is not proof.** §5.2 prints "Complex mode: the architect will run on
  Fable 5" *before* the call. It reports intent. It will print identically on a run where the
  override is dropped.
- **Aliases only — `claude-fable-5` in the `model` parameter will not work.** The enum is
  `["sonnet","opus","haiku","fable"]`. Passing the full ID is a schema violation. Conversely,
  frontmatter needs the full ID. Getting these backwards is the most likely implementation mistake.
- **Do not write `model: opus` in the architect frontmatter.** It would satisfy a careless reading of
  "revert to Opus" while leaving the actual version to alias resolution — quite possibly landing on
  Opus 5, i.e. exactly the state we are reverting *from*. Use `claude-opus-4-8`.
- **Editing `README.md` triggers `check-readme.yml`.** Its path filter includes `README.md`, so this
  PR *will* run it even though we are not touching the deny list. It regenerates the deny-list
  section and fails if the README changes as a result. The generator only rewrites content between
  `<!-- deny-list-generated-start -->` and `<!-- deny-list-generated-end -->` (verified in
  `hooks/generate-readme-section.sh`), so edits outside those markers are safe — but **the new
  "Complex mode" section and the agent-table edit must land outside the markers.** Run the generator
  locally and confirm a clean diff before opening the PR (check 7.1.6).
- **Phase 1 has no pre-existing disarm path.** `pm.md`'s DISARM steps sit at the end of Phase 2 and
  inside Phase 3. Complex mode introduces a realistic Phase 1 abort, so §5.4's explicit
  disarm-before-report is load-bearing, not defensive boilerplate. Check 7.3.8 exists specifically
  to prove it.
- **Fable credits are a separate, exhaustible pool.** `fableCreditsRequired` and
  `longContext1mCreditsBlocked` are distinct session flags. Complex mode can therefore fail *partway
  through a series of architect re-runs* — the first call succeeds, a clarification re-run does not.
  Stickiness (7.3.3) and the failure handling (§5.4) interact directly here: the failure branch must
  be reachable on the **second and later** architect calls, not only the first.
- **The architect re-runs more often than it looks.** The clarification loop can invoke it many
  times, and GATE 2 "No" loops all the way back to Phase 1. An implementation that applies the
  override only on the first call will pass a naive smoke test and fail in real use.
- **Flag-token contamination reaches the filesystem.** The architect derives its plan filename from a
  slug of the task. If the flag is not stripped you get `plans/20260728-complex-<real-slug>.md` — a
  permanent, never-deleted artifact with a wrong name.
- **`agents/qa.md` uses the bare alias `sonnet`** while the other four use full IDs. Pre-existing
  inconsistency, out of scope, and Q1 confirms qa is untouched. Do not "fix" it as a drive-by.
- **Two model-mention sites drift easily.** `README.md`'s agent table and the architect frontmatter
  must agree. Nothing enforces this; `check-readme.yml` guards only the deny-list section.
- **Stale plugin cache.** Long-lived sessions pin orphaned cached plugin versions under
  `~/.claude/plugins/cache/chrismou-claude-plugins/chrismou-project-manager/`. After release, restart
  all Claude Code sessions before concluding complex mode "doesn't work" — you may be testing 0.3.2.

---

## 10. Assumptions

1. **A1 — Q1 is architect-only.** Confirmed by the user. Coder, QA, reviewer, and documenter keep
   their current models; complex mode changes nothing about them.
2. **A2 — Fable 5 availability is the user's responsibility.** Complex mode is opt-in, so an account
   without Fable access simply never uses it and the standard path is unaffected. The plugin declares
   no minimum Claude Code version and cannot detect entitlement ahead of time — hence §5.4 rather
   than a pre-flight check.
3. **A3 — The Agent-tool `model` override behaves for plugin-provided agents exactly as documented
   for `.claude/agents/*.md` agents.** The bundle's precedence chain has no plugin-specific branch,
   and this plugin's agents load through the same standard-directory discovery. Now also supported
   empirically: §8.1 shows a plugin-provided agent's resolved model recorded correctly.
4. **A4 — `pm-auto` forwards `$ARGUMENTS` opaquely.** Its `## Pipeline` section says to invoke the
   `pm` skill with `$ARGUMENTS` and explicitly *not* to reinterpret the pipeline, so the flag
   survives the hop. Check 7.3.5 confirms.
5. **A5 — No effort/thinking tuning is in scope.** Subagent frontmatter here carries only `model`.
   Fable's `effort` and always-on thinking take their defaults. (Note the transcript does record an
   `effort` field — currently `high` — but configuring it is not part of this change.)
6. **A6 — CHANGELOG is the documenter's output**, not the coder's. Every prior version has an entry.
7. **A7 — Nothing programmatic reads the architect's model string.** No hook, script, or command
   asserts on it; `commands/pm.md` addresses agents by name only.

---

## 11. Open questions

None outstanding. Q1–Q4 from Revision 1 were answered by the user and are recorded in §0 and
implemented in §5. The verification question raised alongside them is answered in §8, including its
limitations in §8.3.

---

## 12. Handoff

Implementer: `coder` agent. Ready to proceed.

Order of work:

1. §5.5 — pull `main`, verify `0.3.2`, branch.
2. §5.1 — architect frontmatter revert.
3. §5.2–§5.4 — `pm.md` mode selection, override, and failure handling.
4. §5.3 — `pm-auto.md` docs and ARM caveat.
5. README — agent table row plus the "Complex mode" section, **outside** the deny-list markers.
6. `plugin.json` → `0.4.0`.
7. §5.6 — delete `origin/chore/architect-opus-5`.
8. CHANGELOG is Phase 3 (documenter), not the coder.

The code change is small — one frontmatter line, one conditional tool parameter, the prose to decide
it, and one failure branch. Effectively all of the risk sits in the §7.3 live-session verification
(which cannot be delegated to static checks), the §5.4 disarm path, and the silent-failure mode that
§8 exists to catch.
