# Technical Design Doc — Shorten slash-command names to `pm` / `pm-auto`

Date: 2026-07-21
Status: Approved — all clarifications resolved, ready to implement
Repo: `/home/mou/dev/claude/claude-project-manager-workflow`
Branch: `refactor/shorten-command-names` (already cut from `hotfix/plugin-root-env-var`)

---

## 1. Problem

The slash-command picker renders each entry as
`<plugin>:<command> (<command>)  (<plugin>) <description>` inside a fixed ~49-cell column.
The command name is printed twice, so the effective fit rule is
`len(plugin) + 2 × len(command) ≤ 45`.

Current cost:

| plugin | command | cost | fits |
| --- | --- | --- | --- |
| `chrismou-project-manager` (24) | `project-manager` (15) | 54 | no |
| `chrismou-project-manager` (24) | `project-manager-auto` (20) | 64 | no |

Both truncate on a 1080p terminal. The `description` that follows on the same line is also
oversized for `project-manager-auto` (84 chars), so it is shortened here too — see §6.

## 2. Decisions (settled — do not re-open)

1. Plugin name stays `chrismou-project-manager`. Renaming it changes install identity and forces
   existing users to reinstall.
2. `project-manager` → `pm` (cost 24 + 4 = 28/45).
3. `project-manager-auto` → `pm-auto` (cost 24 + 14 = 38/45).
4. **Clean break.** No alias files, no deprecation shims. A shim file would reappear in the picker
   and reinstate the exact truncation this change removes, plus lengthen the list.
5. **Base branch:** `refactor/shorten-command-names`, already cut from
   `hotfix/plugin-root-env-var` @ b96a6f2. This branch therefore *carries* the
   `CLAUDE_PLUGIN_DIR` → `CLAUDE_PLUGIN_ROOT` hotfix commits and starts at version 0.2.1.
   **No git operations against `main` or PR #2.** PR #2 stays open; the user reconciles it after
   merge. Do not rebase, merge, cherry-pick, or push anything to those refs.
6. **Version 0.3.0**, bumped from 0.2.1. New `## [0.3.0]` CHANGELOG section above the existing
   `## [0.2.1]` entry, framed as `### Breaking Changes`, matching the 0.2.0 style. The `[0.2.1]`
   and older entries stay verbatim.
7. **Descriptions shortened** for both commands (§6) — in scope.
8. `plans/**` is untouched, including this file's predecessors. Historical audit records.
9. The marketplace repo `chrismou/claude-plugins` is **out of scope** — see §9.5.

## 3. Verified starting state

```
branch:            refactor/shorten-command-names
HEAD:              b96a6f2 "Bump to 0.2.1"
plugin.json:       "version": "0.2.1"
CHANGELOG.md:      top entry is "## [0.2.1] - 2026-07-21"
hooks/hooks.json:  all 3 commands already use ${CLAUDE_PLUGIN_ROOT}
working tree:      clean except this untracked plan file
```

## 4. How command names are derived

Claude Code derives a plugin slash command's name from the **markdown filename** in the directory
pointed at by `plugin.json`'s `"commands"` field (here `"./commands/"`). There is no per-file
manifest to update. Both command files additionally carry a `name:` frontmatter key that currently
agrees with the filename:

- `commands/project-manager.md` L2 — `name: project-manager`
- `commands/project-manager-auto.md` L2 — `name: project-manager-auto`

It is not settled whether the frontmatter `name` is honoured, ignored, or takes precedence.
**Rename the file and update the frontmatter `name` in the same edit** so both agree under any
interpretation. Never rename one without the other.

## 5. Blocker check: does the rename break the live session? — NO

This plan is being produced *inside* a running `project-manager-auto` pipeline, which is itself a
live smoke test. The renamed command must not invalidate the armed permissionless flag.

**Verified by reading both hook scripts end to end:**

- `hooks/permissionless-gate.sh` reads exactly two keys from `.claude/.pm-permissionless.json`:
  `jq -r '[.session_id // "", .expires_at // ""] | @tsv'`.
  It then compares `session_id` against the incoming hook payload's `session_id` and checks the
  TTL. **It never reads `.command` and never matches on any command name.**
- `hooks/session-cleanup.sh` reads only `.session_id` and `.expires_at` (SessionStart) and deletes
  unconditionally (SessionEnd). **No command-name matching.**
- `hooks/hooks.json` registers scripts by path via `${CLAUDE_PLUGIN_ROOT}`, with matcher `*`.
  **No command-name matching.**
- `hooks/deny-list.json` contains no command-name strings.

**Conclusion: not a blocker.** The armed flag is keyed to the session UUID alone and survives the
rename intact. Renaming the command files cannot disarm, invalidate, or confuse the running gate.

Corollary: flag files already on disk (including this session's, which carries
`"command": "project-manager-auto"`) remain fully functional after the rename. No migration, no
compatibility shim, no cleanup step.

## 6. Description rewrite

Current:

| command | description | len |
| --- | --- | --- |
| `project-manager` | `Interactive End-to-End Dev Loop` | 31 |
| `project-manager-auto` | `End-to-End Dev Loop (permissionless — auto-approves tool calls except the deny list)` | 84 |

The description shares the terminal line the rename is decluttering, so the 84-char string
half-undoes the fix. Replace both — keep them a matched pair so the distinction is legible at a
glance, and do not drop the auto-approval fact, compress it.

**Use these:**

| command | new description | len |
| --- | --- | --- |
| `pm` | `Interactive dev loop (Plan > Code > QA > Review > Docs)` | 55 |
| `pm-auto` | `Auto-approving dev loop (customisable deny list)` | 48 |

Rationale: the pair reads as one system — same noun phrase ("dev loop"), the leading adjective
carries the whole distinction. The `pm` parenthetical maps one-to-one onto the five agents
(architect, coder, qa-tester, reviewer, documenter), so the description doubles as an accurate
contents listing; an earlier draft omitted `Plan >` and undersold the phase that runs first.
`pm-auto` deliberately does NOT repeat the phase chain — it is the same pipeline, and restating it
made the string wordy for no gain. Its parenthetical instead signals that auto-approval has a
safety net and that the net is user-tunable via `.claude/pm-deny-overrides.json`. Note the earlier
candidate "customizable command override" was rejected as inaccurate: there is no command
override, and it would misread as "you can override which command runs" on the one command where
misunderstanding the safety model has a real cost. Full mechanics stay in the README, which is
where a user goes before running a permissionless pipeline for the first time.

Spelling is `-s` ("customisable"), matching `specialised` in the existing plugin description.

Formatting constraint: both strings are plain ASCII — no em dash, en dash, or Unicode minus. The
old `pm-auto` string contained an em dash; it is gone. Do not reintroduce one.

These strings are also what the agent-facing skill listing shows, so they are load-bearing beyond
the picker.

## 7. Affected files

### 7.1 Renames (use `git mv` to preserve history)

| From | To |
| --- | --- |
| `commands/project-manager.md` | `commands/pm.md` |
| `commands/project-manager-auto.md` | `commands/pm-auto.md` |

### 7.2 `commands/pm.md` (was `project-manager.md`)

- L2 frontmatter: `name: project-manager` → `name: pm`.
- L3 frontmatter: `description: Interactive End-to-End Dev Loop` →
  `description: Interactive dev loop (Plan > Code > QA > Review > Docs)`.
- L42, Phase 2 DISARM bullet — prose "(i.e., this run was invoked via `project-manager-auto`)"
  → `pm-auto`.
- Nothing else. The remaining references in this file are to **agents** (`architect`, `coder`,
  `qa-tester`, `reviewer`, `documenter`), which are **not** renamed.

### 7.3 `commands/pm-auto.md` (was `project-manager-auto.md`)

- L2 frontmatter: `name: project-manager-auto` → `name: pm-auto`.
- L3 frontmatter: the long permissionless description → `description: Auto-approving dev loop
  (customisable deny list)` (single line, see §6).
- L55, inside the JSON template written to `.claude/.pm-permissionless.json`:
  `"command":    "project-manager-auto"` → `"command":    "pm-auto"`. Cosmetic only — see §9.1.
- **L74 — the one load-bearing cross-reference. Do this edit first.**

  Current text:

  ```
  Invoke the `chrismou-project-manager:project-manager` skill with `$ARGUMENTS` and follow it in
  full. Do not restate or reinterpret the pipeline — it is defined there.
  ```

  Change the skill id to `chrismou-project-manager:pm`. The pipeline is invoked **by skill name,
  not by file path**, so the rename does not update it implicitly.

  Failure mode if missed: `/pm-auto` completes its pre-flight, **arms the permissionless flag with
  a 2-hour TTL**, writes the confirmation to the user, and then fails to resolve the pipeline
  skill. The pipeline that carries the DISARM instructions never runs, so nothing deletes the flag.
  The session is left permissionless until the TTL expires or SessionEnd fires. This is the
  highest-severity outcome in the whole change and it is silent at arming time.

### 7.4 `README.md`

Edit these lines: 9, 28, 29, 33, 37, 42, 65, 71, 77, 80, 92, 94, 103, 112, 197, 291, 292.

- L9, L65, L71, L77 — fully-qualified invocations → `/chrismou-project-manager:pm` and
  `/chrismou-project-manager:pm-auto`.
- L28, L29, L33, L37, L42, L80, L92, L94, L103, L112, L197 — prose references → `pm` / `pm-auto`.
- L291, L292 — project-structure tree entries → `pm.md`, `pm-auto.md`.

**Leave unchanged:** L1 `# chrismou-project-manager` (plugin title), L50
`claude plugin install chrismou-project-manager@chrismou-claude-plugins`, L56 `git clone …`,
L57 `claude plugin install ./claude-project-manager-workflow` — these are plugin/repo identity,
which is deliberately not changing.

**Hard constraint:** every edit is outside the `<!-- deny-list-generated-start -->` …
`<!-- deny-list-generated-end -->` block. That block is generated from `hooks/deny-list.json` and
is CI-verified (§9.3). Do not touch anything between the markers.

The README prose describes the commands at length; it is not a copy of the `description`
frontmatter, so the §6 rewrite forces no additional README change.

### 7.5 `hooks/permissionless-gate.sh`, `hooks/session-cleanup.sh`

Line 2 header comment in each (`# … for project-manager-auto`) → `pm-auto`. **Comments only.**
No executable line in either script references a command name (§5). Do not modify logic.

### 7.6 `.claude-plugin/plugin.json`

- `"version": "0.2.1"` → `"0.3.0"`.
- Everything else unchanged: `"name"`, `"commands": "./commands/"` (a directory, so the renames
  need no manifest edit), `"agents"`, `"keywords"`, `"description"`. The `description` prose
  ("…orchestrated by a project manager command") describes the plugin, not the command token.

### 7.7 `CHANGELOG.md`

Insert above the existing `## [0.2.1] - 2026-07-21` block, leaving it and all older entries
verbatim:

```markdown
## [0.3.0] - 2026-07-21

### Breaking Changes

- **Commands renamed.** `project-manager` → `pm`, `project-manager-auto` → `pm-auto`. Invoke them
  as `/chrismou-project-manager:pm` and `/chrismou-project-manager:pm-auto`. The old names are
  gone — there are no aliases. The plugin name is unchanged, so no reinstall is required; only the
  command you type changes. Rationale: the slash-command picker prints the command name twice in a
  fixed-width column, so `<plugin>:<command> (<command>)` truncated on standard-width terminals.
  Behaviour, gates, agent roster, deny list, and hook mechanics are unchanged.

### Changed

- Command descriptions shortened so the picker line fits alongside the shorter names: `pm` is
  "Interactive dev loop (Plan > Code > QA > Review > Docs)", `pm-auto` is "Auto-approving dev loop
  (customisable deny list)". The full
  permissionless semantics remain documented in the README.
```

### 7.8 Explicitly NOT touched

- `plans/**` — historical audit records, including this file once written.
- `agents/*.md` — verified: none contain the string `project-manager`.
- `hooks/hooks.json`, `hooks/deny-list.json`, `hooks/generate-readme-section.sh` — no command
  names.
- `.github/workflows/check-readme.yml` — asserts only deny-list/README table sync, never command
  names. It *will* run on this PR (its `paths:` filter includes `README.md`) and must pass.
- `.github/workflows/version-bump.yml` — asserts only `head version > base version`. It does not
  perform the bump; §7.6 is manual and required for the check to pass.
- `.gitignore`, `.claude/settings.local.json`, `.claude/.pm-permissionless.json` — the latter two
  are gitignored local state.
- `main`, PR #2, and any remote branch other than `refactor/shorten-command-names`.

## 8. Implementation order

1. Stay on `refactor/shorten-command-names`. No branch creation, no rebase, no operations against
   `main` or PR #2.
2. `git mv commands/project-manager-auto.md commands/pm-auto.md` and
   `git mv commands/project-manager.md commands/pm.md`.
3. **Fix `commands/pm-auto.md` L74 skill id first** (§7.3) — the highest-severity edit.
4. Update frontmatter `name:` and `description:` in both files (§7.2, §7.3, §6).
5. Update the `"command"` literal in the flag JSON template (`pm-auto.md` L55).
6. Update the prose reference in `pm.md` L42.
7. Update `README.md` (§7.4).
8. Update the two hook header comments (§7.5).
9. Bump `plugin.json` to 0.3.0; insert the CHANGELOG entry (§7.7).
10. Run `bash hooks/generate-readme-section.sh`; confirm `git diff README.md` shows **no**
    generated-section churn.
11. Run the §9.6 grep; confirm only the three expected classes of hit remain.
12. Manual smoke (post-reload, §9.4): reinstall the plugin, restart Claude Code, check the picker
    rendering, run `/chrismou-project-manager:pm` through GATE 1, and run
    `/chrismou-project-manager:pm-auto` through arming → pipeline handoff → disarm.

## 9. Non-obvious side effects and QA notes

### 9.1 The `"command"` field in the flag file is dead data

The arming step writes `"command": "project-manager-auto"`, but **nothing reads it back** —
neither hook script parses that key, and no workflow or agent does either. Changing it to
`"pm-auto"` is diagnostic/cosmetic. QA should confirm the gate behaves identically with a flag
file containing *either* literal; both must work, since stale flags predating this release exist
on users' disks.

### 9.2 The `pm-auto` → `pm` skill invocation is the one hard dependency

See §7.3 for the full failure mode. QA must exercise `/pm-auto` end to end — arming, pipeline
handoff, and disarm — not just `/pm`. A `/pm`-only smoke test would pass while `/pm-auto` is
broken in the worst possible way (flag armed, nothing left to disarm it).

### 9.3 CI runs `check-readme` on this PR

Triggered by the `README.md` path filter. It regenerates the deny-list table and fails if
`README.md` then differs. All README edits are outside the markers, so it should pass — but a
stray edit inside the block, or reflowing a generated row, fails CI. Verify locally before opening
the PR (step 10).

`version-bump.yml` also runs, comparing against `origin/main` (0.2.0). 0.3.0 > 0.2.0 passes.

### 9.4 Plugin reload is required to see the change

Renaming command files has no effect in an already-running Claude Code session — including the
session performing this work. Verifying picker rendering requires reinstalling/reloading the
plugin and restarting. Expected rows afterwards:

```
chrismou-project-manager:pm (pm)  (chrismou-project-manager) Interactive dev loop (Plan > Code > QA > Review > Docs)
chrismou-project-manager:pm-auto (pm-auto)  (chrismou-project-manager) Auto-approving dev loop (customisable deny list)
```

Name-column cost: 28/45 and 38/45.

### 9.5 Marketplace repo — follow-up note only, not a task

`chrismou/claude-plugins` references this plugin by **plugin name**, which is unchanged, so no
marketplace edit is required for installs to keep working. If that repo's README quotes the
command names they will go stale; the user handles that repo separately. Out of scope here.

### 9.6 Closing verification grep

After the change,
`grep -rn "project-manager" --exclude-dir=.git --exclude-dir=plans .`
must return **only**:

1. the plugin name `chrismou-project-manager`,
2. the repo URL / directory `claude-project-manager-workflow`,
3. historical CHANGELOG entries for 0.2.1 and earlier.

Any other hit is a missed reference.

### 9.7 In-flight branch conflicts

`permissionless-auto-command` and `hotfix/plugin-root-env-var` exist locally and remotely. Any
unmerged branch touching `commands/project-manager*.md` will conflict against the renamed paths.
`git mv` preserves history, but rename detection across a conflicting branch is not free. This is
the user's to reconcile (PR #2) — do not attempt it as part of this change.

## 10. Assumptions

1. The `<plugin>:<command> (<command>)` picker format and the `≤ 45` fit rule are taken as given
   from the request; not independently verified against Claude Code's renderer.
2. Command names derive from the filename; the frontmatter `name:` key is at best redundant. Both
   are changed so the outcome is correct either way.
3. `pm` and `pm-auto` do not collide with a command the maintainer already has installed. Not
   verifiable from this repo. If a collision exists, the fully-qualified
   `/chrismou-project-manager:pm` form still resolves — only the bare `/pm` shorthand degrades.
4. Historical CHANGELOG entries stay verbatim; only a new `[0.3.0]` entry is added.
5. Agent names (`architect`, `coder`, `qa-tester`, `reviewer`, `documenter`) are out of scope —
   not slash commands, not in the picker column.
6. No release/tag automation beyond `version-bump.yml` needs updating; nothing else in `.github/`
   references versions or command names.
