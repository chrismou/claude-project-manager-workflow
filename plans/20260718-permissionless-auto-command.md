# Technical Design: Permissionless `project-manager-auto` command

Date: 2026-07-18
Status: APPROVED — all clarifications resolved, ready to implement
Target: `chrismou-project-manager` plugin (Claude Code 2.1.214)
Supersedes: the second-gate design previously held at this path (renamed from
`20260718-permissionless-mode-gate.md`)

---

## 1. Approach

Permission posture is chosen by **which command the user invokes**, not by a gate mid-run. The user
is definitionally present at invocation, so that is the natural attended moment, and it puts the
one unavoidable arming prompt at t=0 where it costs nothing.

- `/project-manager` — unchanged, prompts as normal.
- `/project-manager-auto` — behaviourally identical pipeline, but arms a permissionless
  `PreToolUse` hook first.

`-auto` does **not** preset `UNATTENDED_SCOPE` and does **not** skip gates. GATE 1, the
UNATTENDED-SCOPE GATE (still triggered only by the user's own phrasing), and GATE 2 all behave
exactly as they do today. Permission posture and gate-skipping are orthogonal.

---

## 2. Feasibility (carried forward — still the governing constraint)

Verified against Claude Code 2.1.214 and the official docs. Recorded here because it explains why
the design looks the way it does.

**The model cannot change its own permission posture.** `docs/en/permission-modes`: "The mode is
set through these controls, not by asking Claude in chat." `docs/en/permissions`: "Permission rules
are enforced by Claude Code, not by the model. Instructions in your prompt or `CLAUDE.md` shape
what Claude tries to do, but they don't change what Claude Code allows." Ruled out: mid-session
mode switching, `defaultMode` in settings (seeds new sessions only), command/skill frontmatter
(only `allowed-tools`, which is availability not prompt suppression), `/permissions` and
`--dangerously-skip-permissions` (user surface only), SDK `setPermissionMode()` (host API).

**The one viable mechanism** is a plugin-shipped `PreToolUse` hook returning:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "..."
  }
}
```

Hook stdin provides `session_id`, `cwd`, `tool_name`, `tool_input`, `permission_mode`.

Limits that survive and must stay documented:

- **Deny and ask rules always win.** `docs/en/permissions`: "Hook decisions don't bypass permission
  rules. Claude Code evaluates deny and ask rules regardless of what a PreToolUse hook returns."
  A user with existing `ask` rules will still get prompts. This is the safety backstop.
- MCP tools set to `ask` by an org, or marked `requiresUserInteraction`, still prompt.
- Arming writes a flag file, which itself prompts once. Unavoidable, and by design harmless at t=0.

---

## 3. Single source of truth — decision

**Chosen: option (a).** `project-manager-auto.md` arms the hook, then invokes the
`chrismou-project-manager:project-manager` skill with `$ARGUMENTS` via the `Skill` tool.

Rationale, and why (b) was rejected:

- The plugin reference documents `commands/` as "Skills as flat .md files" — **every** flat `.md`
  in `commands/` is discovered and surfaced. A `commands/_pipeline.md` would appear to users as
  `/chrismou-project-manager:_pipeline`. There is no underscore convention or frontmatter opt-out.
  Option (b) would therefore need the shared body outside `commands/`, and both thin commands would
  have to `Read` it and follow it verbatim — an extra tool call plus a "follow this faithfully"
  instruction, which is exactly the kind of soft indirection that degrades.
- Commands *are* skills in the plugin model, so (a) is a first-class invocation, not a hack. The
  `Skill` tool takes an `args` parameter, so `$ARGUMENTS` passes through cleanly.
- The invoked skill loads into the same turn and session, so the armed flag and the hook's
  `session_id` binding both remain valid throughout.

Consequence: `project-manager.md` becomes the sole pipeline definition. Future pipeline edits land
in one file and both commands inherit them — the user's stated hard requirement.

---

## 4. Affected files

| File | Change |
| --- | --- |
| `commands/project-manager-auto.md` | **DELETE then recreate.** Old plan-mode content goes entirely; new content is a thin arming wrapper (~25 lines). |
| `agents/architect-auto.md` | **DELETE.** Referenced only by the old `-auto` command and `plugin.json:14`. |
| `.claude-plugin/plugin.json` | Remove `"./agents/architect-auto.md"` (line 14). Add `"hooks": "./hooks/hooks.json"`. |
| `hooks/hooks.json` | **NEW** — wildcard `PreToolUse` matcher + `SessionStart`/`SessionEnd` cleanup. |
| `hooks/permissionless-gate.sh` | **NEW** — arming check, session binding, TTL, deny-list evaluation. `chmod +x`. |
| `hooks/deny-list.json` | **NEW** — the single data structure for deny rules, incl. stable `id` per rule (see §6). |
| `hooks/generate-readme-section.sh` | **NEW** — generates the README deny-list table from `deny-list.json`; wired into CI so docs cannot drift (§6.5). |
| `hooks/session-cleanup.sh` | **NEW** — removes stale/foreign flag files. |
| `.gitignore` | Add the flag-file path. Currently only ignores `.claude/settings.local.json`. |
| `README.md` | Rewrite "Two ways to run it" (currently documents the plan-mode `-auto`); add the generated deny-list section and the per-project overrides section (§6.5 — both required). |
| `CHANGELOG.md` | BREAKING entry for the `-auto` semantic change + architect-auto removal. |

`plugin.json` declares component paths explicitly, so declare `hooks` explicitly too rather than
relying on default-location discovery.

---

## 5. Hook design

### 5.1 Flag file

Path: `${CLAUDE_PROJECT_DIR}/.claude/.pm-permissionless.json`

```json
{
  "session_id": "<from the arming turn>",
  "armed_at": "<ISO8601>",
  "expires_at": "<armed_at + 2h>",
  "command": "project-manager-auto"
}
```

TTL = **2 hours**.

### 5.2 Evaluation order (`permissionless-gate.sh`)

1. Read stdin JSON.
2. Flag file absent → exit 0 (normal prompting). **Every error path exits 0.**
3. Flag `session_id` != stdin `session_id` → exit 0.
4. `now > expires_at` → delete flag, exit 0.
5. Evaluate the deny list (§6) with project overrides applied (§6.4). Any unexempted match →
   **exit 0, i.e. prompt as normal.** Do NOT hard-block via exit 2.
6. Otherwise emit `permissionDecision: "allow"`.

**Deny-hit behaviour is deliberately a prompt, not a block.** The consequence is explicit and
accepted: a genuinely unattended run that hits a deny-listed command **pauses indefinitely** until
the user returns, rather than failing or routing around it. The stall is judged the safer failure
mode — a blocked-and-continued agent may improvise something worse than waiting. Projects that
prefer otherwise use the override mechanism (§6.4) to exempt the rule. This trade-off is a required
README item (§6.5); it must not surprise anyone.

Fail-closed on malformed JSON, missing `jq`, or unreadable flag. Never print anything to stdout
except the contract JSON — stray output breaks the hook.

### 5.3 Disarm layers

Four layers, because the model deleting the file is the least reliable of them:

1. Model deletes at the scope boundary (before GATE 2 for "Implementation only"; at DONE for
   "Entire process"; on GATE 2 "No"; on any observed abort).
2. TTL self-expiry (2h) — hook deletes on read.
3. `session_id` binding — a leftover flag is inert in every other session.
4. `SessionStart` deletes any non-matching flag; `SessionEnd` deletes unconditionally.

Layers 2–4 are harness-enforced and hold even if the session is killed mid-run. Layer 1 alone would
not be safe.

---

## 6. Deny list

**Single source of truth: `hooks/deny-list.json`.** The hook reads it at evaluation time; the
README section is generated from it (or, minimally, the README links to it and a CI check asserts
the rule count matches). Behaviour and docs cannot drift because there is only one list.

Structure — each rule carries its own docs so the README can be generated:

```json
{
  "rules": [
    {
      "id": "git-push",
      "tools": ["Bash"],
      "pattern": "\\bgit\\s+push\\b",
      "category": "Outward publishing",
      "why": "Pushes code off the machine; must stay a human decision."
    }
  ]
}
```

### 6.1 Rules

**Path escape (the only genuinely enforced rule)** — `Edit`/`Write`/`NotebookEdit` whose resolved
target falls outside the project root. Resolve symlinks and `..` first, then prefix-check against
`${CLAUDE_PROJECT_DIR}`. Not a pattern match: a real boundary.

**Outward publishing** — `git push`, `git remote`, `gh pr create`, `gh release`.

**Destructive git** — `git reset --hard`, `git clean -fd`, `git commit`, `git rebase`. Commit is
included at the user's request and matches their global preference that commits happen only when
asked.

**Filesystem** — `rm -rf`.

**Privilege/system** — `sudo`, `systemctl`, `chmod`, `chown`.

**Credentials/secrets** — reads touching `~/.ssh`, `~/.aws`, `.env`; `gh auth`; keychain access.

**Executing network egress** — `curl … | sh`, `wget … | bash` (pipe-to-shell specifically).

**Deploy/infra** — `terraform apply`, `kubectl apply|delete`, `docker compose down -v`,
`docker system prune`, mutating `aws`/`gcloud`/`az` verbs, `eas submit`.

**Global package installs** — `npm i -g` / `npm install -g`, `pip install` outside a venv,
`brew install`, `apt`. The `-g` flag and venv check are load-bearing: patterns MUST anchor on the
global marker so in-project `npm install` / `composer install` pass. Getting this wrong breaks QA
on every run — call it out for QA testing explicitly.

**DB resets** — `migrate:fresh`, `db:wipe`, `prisma migrate reset`, `DROP DATABASE`. See §6.2.

**Deliberately NOT denied** — `kill`/`pkill`, backgrounding dev servers, local git
read/branch/checkout/stash, in-project installs.

### 6.2 DB reset tension — proposed resolution

Laravel QA legitimately runs `migrate:fresh` against a test database, so a blanket deny makes QA
prompt on every run and defeats the feature.

**Proposal: deny by default, exempt on an explicit test-environment marker.** The rule gains an
`unless` pattern; a command matching it passes. Markers: `--env=testing`, `--database=testing`,
`--env=test`, a leading `APP_ENV=testing`, or invocation via `php artisan test` / `pest` /
`phpunit`. So `php artisan migrate:fresh --env=testing` runs unattended; a bare
`php artisan migrate:fresh` prompts.

This keeps the dangerous default (bare command hits the dev DB) while unblocking the legitimate
path, and it is self-documenting — the exemption is visible in the command the agent wrote. It is
still pattern matching, with the §8 caveats.

Projects for which this exemption is wrong use the override mechanism (§6.4) to exempt the
`db-reset` rule id outright, or to replace it with a project-specific pattern.

### 6.3 WebFetch — explicit recommendation

**Recommend NOT denying WebFetch.** It is read-only, already domain-scopable via normal permission
rules, and the architect and QA legitimately use it for docs lookups — this very plan was written
using it. The actual egress risk in scope is *executing* fetched content, which is separately
denied via the pipe-to-shell rules. Denying WebFetch wholesale would break research for no real
safety gain. Residual risk, recorded honestly: WebFetch can exfiltrate data via URL query strings.
Given the agents operate only on the user's own repo and the user accepts the pattern-matching
limits, this is judged acceptable.

### 6.4 Per-project overrides

**Location: `.claude/pm-deny-overrides.json`** (confirmed — project-local, sits beside the other
`.claude/` config, requires no plugin edit, and is checked into the project so the whole team
inherits it). Absent file = shipped list applies unchanged.

```json
{
  "exempt": ["db-reset", "git-commit"],
  "add": [
    {
      "id": "project-deploy-script",
      "tools": ["Bash"],
      "pattern": "\\./deploy\\.sh\\b",
      "category": "Project-specific",
      "why": "Wrapper that pushes to staging."
    }
  ]
}
```

#### Rule ids

Ids are the public API of this mechanism and **must be stable** — an exemption referencing a
renamed id silently stops exempting, re-arming a rule the project thought it had turned off. So:

- Every rule in `hooks/deny-list.json` carries a permanent `id`. Ids are never renamed or reused;
  a retired rule keeps its id reserved.
- Ids appear in the **generated** README deny-list section, so the overrides docs and the rule
  table cross-reference by the same strings and cannot drift.
- Unknown ids in `exempt` are a **loud no-op**: the hook cannot print to stdout, so it writes a
  warning to stderr, and the `-auto` arming step validates the overrides file up front and reports
  unknown ids to the user before the pipeline starts. Silent typos are the main failure mode here.

#### Precedence — unambiguous

Deny-first, mirroring Claude Code's own model:

1. `exempt` applies **only** to shipped rule ids. It removes those rules from evaluation.
2. `add` rules are then evaluated. They **cannot** be exempted — a project exempting its own rule
   should delete it instead.
3. **Any surviving match denies (prompts).** If an `add` rule and an exempted shipped rule both
   match the same command, the `add` rule wins and the command prompts. Exempting never forces an
   allow; it only withdraws one shipped rule from consideration.

Stated as one sentence for the README: *an exemption can only ever remove a shipped rule, never
override a rule that still matches.*

#### Path-escape exemption — flagged implication

The `path-escape` rule is the only genuinely enforced boundary in the entire design (§8). Allowing
it to be exempted by a one-line config entry would quietly convert the feature into unrestricted
filesystem write access for every agent in the pipeline, with nothing left that actually contains
anything.

**Decision: `path-escape` is not exemptible by `exempt` alone.** Listing it there is rejected with a
stderr warning and reported by the arming step. A project that genuinely needs cross-root writes
must set both:

```json
{ "exempt": ["path-escape"], "acknowledge_unsafe": ["path-escape"] }
```

The redundant second field exists purely to make the choice deliberate rather than copy-pasted.
When it is set, the arming confirmation states in plain language that writes outside the project
root are auto-approved for this run. Better alternative for most cases, and the one the README
should recommend first: use `--add-dir` or `permissions.additionalDirectories` to widen the project
boundary legitimately, rather than disabling the check.

### 6.5 Documentation deliverables (required, not optional)

`README.md` gains two linked sections:

1. **Deny list** — generated from `hooks/deny-list.json`, one row per rule showing `id`, `category`,
   what it matches, and `why`. Plus the §8 honesty note that Bash matching is a speed bump, and the
   §5.2 note that a deny hit **pauses an unattended run indefinitely rather than failing it**.
2. **Per-project overrides** — file location, full schema, worked examples in **both** directions
   (exempt a shipped rule; add a project rule), the precedence sentence above, the
   `path-escape` / `acknowledge_unsafe` caveat, and a pointer to the rule-id column in section 1.

Generation must be part of the build/check, not a manual step, or the two sections drift the first
time a rule changes.

---

## 7. Command bodies

### 7.1 `commands/project-manager-auto.md` (new, thin)

```
---
name: project-manager-auto
description: End-to-End Dev Loop (permissionless — auto-approves tool calls except the deny list)
---

# Task: $ARGUMENTS

1. ARM: write the flag file (session_id, armed_at, expires_at = +2h). This write prompts once —
   expected and harmless, you are present.
2. Confirm to the user: armed, TTL, deny list location, and that deny/ask rules still apply.
3. Invoke the `chrismou-project-manager:project-manager` skill with $ARGUMENTS and follow it in
   full. Do not restate or reinterpret the pipeline — it is defined there.
4. DISARM (delete the flag) at the scope boundary, on GATE 2 "No", or on any abort.
```

### 7.2 `commands/project-manager.md` — conditional disarm lines

Confirmed approach. The scope boundaries are only observable from inside the pipeline body, so
`project-manager.md` gains two posture-neutral lines:

- At **GATE 2**, before printing the gate question, when `UNATTENDED_SCOPE == "Implementation only"`
  (or unset): *"If a permissionless flag file is armed for this session, delete it now."*
- At **DONE**, after `STAGE_COMPLETE: documenter`, when `UNATTENDED_SCOPE == "Entire process"`:
  the same line.

**Both must be strict no-ops when no flag is armed** — phrased as "if armed, delete", never as an
unconditional delete or a check that emits output. The plain `/project-manager` command must behave
exactly as it does today, including producing no extra tool calls and no mention of permissions in
its transcript. QA must diff a plain-command run against current behaviour to confirm this.

The four disarm layers in §5.3 all stand regardless; these lines are layer 1 only, and the TTL,
session binding, and SessionStart/SessionEnd cleanup remain the backstop that holds when the model
skips or forgets them.

---

## 8. Honesty note — record this, do not let future readers over-trust it

**Bash deny-listing is pattern matching. It is a speed bump against careless agent behaviour, not
containment.** It is trivially evaded by:

- compound commands — `cd /elsewhere && git push`
- wrapper scripts — `./deploy.sh` that pushes internally
- indirection — `npm run release`, `make deploy`, a Composer script
- aliases, `eval`, variable-built command strings, unusual whitespace/quoting
- any subprocess that does the same work via a language runtime rather than a shell command

`docs/en/permissions` makes the analogous point about deny rules: they "don't apply to arbitrary
subprocesses that read or write files indirectly, like a Python or Node script that opens files
itself."

**The path-escape check on Edit/Write is the only genuinely enforced rule** in the list, because it
resolves and boundary-checks rather than pattern-matches. For real containment the answer is
OS-level sandboxing (`docs/en/sandboxing`), which is out of scope here.

The user has been told this and accepts it. Do not present the deny list as a security boundary in
the README — present it as a guardrail against agent carelessness.

---

## 9. Assumptions

1. `project-manager.md` remains the canonical pipeline; `-auto` never diverges behaviourally.
2. Deleting the plan-mode `-auto` is acceptable as a breaking change; CHANGELOG gets a BREAKING
   entry and the minor version bumps (0.1.0 → 0.2.0) via the existing
   `.github/workflows/version-bump.yml`.
3. `architect-auto` has no external consumers. Coordinator verified: referenced only by the old
   `-auto` command and `plugin.json:14`.
4. `jq` is available; if absent the hook fails closed (normal prompting), which is safe but silently
   disables the feature — the arming step should check for `jq` and warn.
5. The plugin is installed from the user's own marketplace, so shipping an auto-approving hook is
   acceptable. This would need a louder opt-in for wide distribution.
6. No `allowManagedHooksOnly` or `strictPluginOnlyCustomization` in this environment.

---

## 10. Non-obvious side effects for QA

- **Global-install patterns are the highest-risk regression.** If `npm i -g` matching is too loose
  it catches in-project `npm install` and QA prompts on every run. Test both explicitly, plus
  `composer install`, `pip install -r requirements.txt` inside a venv, and `yarn add`.
- **Subagents inherit the hook.** coder/qa-tester/reviewer/documenter share the session and
  `session_id`, so all five agents' tool calls are auto-approved. Blast radius is their union.
- **The documenter is the highest-risk auto-approved agent** under "Entire process" — it edits
  README/CHANGELOG unattended with nothing behind it.
- **Skill-invocation nesting** — verify `$ARGUMENTS` survives the `Skill` call intact, including
  quotes, newlines, and shell metacharacters in the task description.
- **Verify `-auto` still stops at GATE 2** when the user's phrasing does not imply unattended
  execution. Arming must not leak into gate behaviour — this is the single most important
  regression test, since the old `-auto` conflated the two.
- **Parallel sessions in one repo** share the flag path; session-id binding is the only thing
  preventing cross-contamination. Test two concurrent sessions.
- **Worktrees / subdirectory launches** — `${CLAUDE_PROJECT_DIR}`, git root, and cwd can diverge.
  `settings.local.json` resolves from git root on 2.1.211+, but `CLAUDE_PROJECT_DIR` may not match.
  Confirm the hook and the model resolve the flag path identically.
- **Flag file must be gitignored** before first run, or an armed run may commit its own
  permissiveness marker. `.gitignore` currently covers only `.claude/settings.local.json`.
- **Hook stdout hygiene** — `set -e`, no debug echoes; stray output breaks the contract.
- **Pre-existing `ask` rules still prompt**, so a user with them configured will think the feature
  is broken. Arming confirmation should say so.
- **README currently documents `-auto` as the plan-mode/accept-edits flow** in the "Two ways to run
  it" section — it will be actively wrong until rewritten, not merely stale.
- **TTL expiry mid-run** — a >2h pipeline silently reverts to prompting and stalls. Acceptable, but
  the arming message should state the 2h limit so the user can plan.
- **Plain-command regression is the highest-priority test.** Run `/project-manager` with no flag
  armed and diff against current behaviour: the conditional disarm lines must produce zero extra
  tool calls, zero output, and no change to gate wording.
- **Overrides file handling** — test all of: absent file (shipped list applies), malformed JSON
  (fail closed to full prompting, warn), unknown id in `exempt` (loud no-op, reported at arming),
  `add` rule overlapping an exempted shipped rule (must still prompt — deny-first), and
  `path-escape` in `exempt` without `acknowledge_unsafe` (must be rejected, not honoured).
- **Exemption precedence is easy to implement backwards.** The natural but wrong reading is
  "exempt forces allow". It must only withdraw a shipped rule from evaluation; any other matching
  rule still denies.
- **`db-reset` exemption markers** — verify `php artisan migrate:fresh --env=testing` passes while
  a bare `php artisan migrate:fresh` prompts, and that exempting the `db-reset` id disables both.
- **README generation must be verified in CI**, not just run once. A rule added without
  regenerating should fail the build, otherwise the overrides section references ids that no
  longer exist.

---

## 11. Open questions

None. All clarifications resolved:

- Disarm ownership → conditional, inert-when-unarmed lines in `project-manager.md` (§7.2), with
  TTL / session-binding / SessionStart+SessionEnd retained as backstops.
- Deny-list hit → prompt as normal (§5.2). Indefinite stall on an unattended run is accepted as
  the safer failure mode and is a required README disclosure.
- Per-project overrides → `.claude/pm-deny-overrides.json`, both directions, deny-first precedence,
  `path-escape` exemptible only with explicit `acknowledge_unsafe` (§6.4), full README section
  required (§6.5).
- Command name → stays `project-manager-auto`, echoing Claude's auto mode, per the user.
