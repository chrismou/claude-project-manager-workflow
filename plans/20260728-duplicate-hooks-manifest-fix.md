# Technical Design Doc — Fix "Duplicate hooks file detected" plugin load error

Date: 2026-07-28
Status: Ready for implementation
Revision: 2 (incorporates user decisions on branch/version, manifest cleanup scope, and release steps)

**Branch base:** `main` (fetch/pull first — see §4.2)
**Version:** `0.3.1` → `0.3.2`

---

## 1. Problem statement

Claude Code 2.1.220 emits a load error whenever the plugin is active:

```
Failed to load hooks from .../chrismou-project-manager/0.3.0/hooks/hooks.json:
Duplicate hooks file detected: ./hooks/hooks.json resolves to already-loaded file
.../chrismou-project-manager/0.3.0/hooks/hooks.json. The standard hooks/hooks.json is
loaded automatically, so manifest.hooks should only reference additional hook files.
```

## 2. Root cause (confirmed)

`/home/mou/dev/claude/claude-project-manager-workflow/.claude-plugin/plugin.json` line 20 declares:

```json
  "hooks": "./hooks/hooks.json"
```

Claude Code auto-discovers and loads `hooks/hooks.json` from the plugin root. The manifest
`hooks` key is intended for *additional* hook files only. Pointing it at the standard path makes
the loader resolve the same absolute path twice, which the duplicate guard rejects.

Verification performed against the CLI bundle
`/home/mou/.local/share/claude/versions/2.1.220`:

- The error string and its guidance exist verbatim in the bundle. The message is authoritative on
  the intended contract: the standard file is loaded automatically.
- Standard-directory auto-discovery is confirmed present for all three component types — the
  bundle contains the path joins `join(e,"agents")`, `join(e,"commands")`, and
  `join(e,"hooks","hooks.json")`.
- Grepping for `Duplicate <x> file detected` yields **only** the hooks variant. There is no
  equivalent duplicate guard for `commands` or `agents`, which is why the analogous
  `"commands": "./commands/"` and `"agents": [...]` manifest keys are equally redundant but do not
  error.
- The one other conflict message in the bundle ("...both plugin.json and marketplace manifest
  entries for commands/agents/skills/hooks/outputStyles/themes/syntaxHighlighting. This is a
  conflict.") concerns `plugin.json` vs. the *marketplace* manifest, not `plugin.json` vs. the
  standard directories. It does not apply here — `chrismou-claude-plugins`'s `marketplace.json`
  declares no components.

Git history: the `hooks` key was introduced in commit `b588130` ("Replace plan-mode
project-manager-auto with permissionless hook variant", v0.2.0). It has been redundant since the
day it was added; only recent Claude Code versions treat it as a hard error, which is why this
surfaced now.

The hook *content* is correct. `hooks/hooks.json` uses `${CLAUDE_PLUGIN_ROOT}` correctly (fixed in
0.2.1) and registers `PreToolUse`, `SessionStart`, `SessionEnd`. Nothing about the hooks
themselves needs to change.

## 3. Affected files

| File | Change |
| --- | --- |
| `/home/mou/dev/claude/claude-project-manager-workflow/.claude-plugin/plugin.json` | Remove the `hooks`, `agents`, and `commands` keys. Bump `version` to `0.3.2`. |
| `/home/mou/dev/claude/claude-project-manager-workflow/CHANGELOG.md` | Add a `## [0.3.2] - 2026-07-28` section with `### Fixed` and `### Changed` subsections. |

No other file changes. Specifically **not** changed:

- `hooks/hooks.json` — content is correct, path is the standard auto-discovered one.
- `hooks/permissionless-gate.sh`, `hooks/session-cleanup.sh`, `hooks/deny-list.json` — untouched.
- `agents/*.md`, `commands/*.md` — untouched. They stay exactly where they are; only the manifest
  stops naming them.
- `README.md` — the file-tree section at line ~293 lists `hooks/hooks.json`, `agents/`, and
  `commands/` as files/directories, which remains accurate. The README never documents the
  manifest keys, so there is no doc drift.
- `.github/workflows/*` — no change needed.
- The `chrismou/claude-plugins` marketplace repo — **no tag, no re-index, no version pin update.**
  Confirmed with the user as not required.

## 4. Logic changes

### 4.1 `.claude-plugin/plugin.json`

Target end state:

```json
{
  "name": "chrismou-project-manager",
  "version": "0.3.2",
  "description": "End-to-end AI dev loop with architect, coder, QA, reviewer, and documenter agents orchestrated by a project manager command.",
  "repository": "https://github.com/chrismou/claude-project-manager-workflow",
  "license": "MIT",
  "author": {
    "name": "Chris Chrisostomou",
    "url": "https://github.com/chrismou"
  },
  "keywords": ["project-management", "workflow", "agents", "dev-loop"]
}
```

All three component keys are dropped. Every component is picked up by standard-directory
auto-discovery instead: `agents/` (5 files), `commands/` (2 files), `hooks/hooks.json`.

`"keywords"` becomes the last key and must lose its trailing comma.

### 4.2 Branch base and version (CI gate)

`.github/workflows/version-bump.yml` runs on every PR to `main` and **fails the PR** unless
`.claude-plugin/plugin.json`'s `version` sorts strictly greater (`sort -V`) than the same field on
the base branch.

State as of `git fetch` on 2026-07-28: `origin/main` is at commit `c908d20` ("Merge pull request
#5 from chrismou/chore/architect-opus-5") with version **`0.3.1`**. The architect-opus-5 work is
already merged, so `chore/architect-opus-5` is no longer a concern and must **not** be used as a
base.

Implementer steps:

1. `git checkout main && git pull` — do not skip; the local `main` was stale at `0.3.0` and this
   plan's version target depends on the pulled state.
2. Re-confirm with `jq -r .version .claude-plugin/plugin.json` → expect `0.3.1`. If it is
   anything else, stop and re-derive the bump target rather than blindly writing `0.3.2`.
3. Branch (e.g. `hotfix/duplicate-hooks-manifest`), apply the change with `version` set to
   `0.3.2`.

Note that `origin/main` at `c908d20` still contains all three redundant keys, so the defect is
live on `main` right now.

### 4.3 `CHANGELOG.md`

Insert immediately below the header block and above `## [0.3.1] - 2026-07-27`. Match the prose
density of the 0.2.1 entry — this repo's CHANGELOG writes full explanatory paragraphs, not terse
bullets. Suggested wording:

```md
## [0.3.2] - 2026-07-28

### Fixed

- Plugin failed to load its hooks on Claude Code 2.1.x with `Duplicate hooks file detected`. The
  manifest declared `"hooks": "./hooks/hooks.json"`, but Claude Code already auto-loads the
  standard `hooks/hooks.json` from the plugin root; the manifest key is only for *additional*
  hook files. The redundant declaration made the loader resolve the same absolute path twice and
  abort, so the `PreToolUse` permissionless gate and the `SessionStart` / `SessionEnd` flag
  cleanup were not registered at all. Removed the key from `.claude-plugin/plugin.json`. Hook
  behaviour is otherwise unchanged. The key had been redundant since 0.2.0; only recent Claude
  Code versions treat it as an error.

### Changed

- `.claude-plugin/plugin.json` no longer declares `agents` or `commands` either. Both were
  redundant with Claude Code's standard-directory auto-discovery of `agents/` and `commands/`,
  and unlike `hooks` they were tolerated rather than rejected. The manifest is now metadata only.
  No agent, command, or hook was added, removed, or renamed.
```

## 5. QA / verification plan

### 5.1 Static checks

1. `jq . .claude-plugin/plugin.json` exits 0 (catches the trailing-comma mistake).
2. `jq -r '.hooks, .agents, .commands' .claude-plugin/plugin.json` returns three `null`s.
3. `jq -r '.version' .claude-plugin/plugin.json` is `0.3.2`, and is strictly greater than the PR
   base's version under `sort -V`.
4. `git diff --name-only origin/main` lists exactly `.claude-plugin/plugin.json` and
   `CHANGELOG.md`.
5. `ls agents/ commands/ hooks/` confirms no component file was moved or deleted — the five agent
   markdown files, `pm.md`, `pm-auto.md`, and the three hook scripts plus `hooks.json` and
   `deny-list.json` are all still present.

### 5.2 Functional checks (must be done in a live Claude Code session)

The bug is a load-time error and this change now removes *three* declarations, so static checks
prove nothing. Verification requires actually loading the plugin from the fix branch.

1. Install/refresh the plugin from the fix branch and start a fresh Claude Code session.
2. Confirm no `Failed to load hooks` error appears at startup, and no new load errors of any kind.
3. **Confirm the hooks are still registered, not merely silent.** This is the critical regression
   risk — a "successful" fix that simply removes the hooks would also make the error disappear.
   Check via `/hooks` (or equivalent) that this plugin contributes `PreToolUse`, `SessionStart`,
   and `SessionEnd` entries, and that their commands point at
   `${CLAUDE_PLUGIN_ROOT}/hooks/*.sh` paths that resolve.
4. **Confirm all five agents register.** `architect`, `coder`, `qa-tester`, `reviewer`,
   `documenter` must all still appear in the agent roster under the
   `chrismou-project-manager:` namespace. This is the new risk introduced by removing the
   `agents` key.
5. **Confirm both commands register.** `/chrismou-project-manager:pm` and
   `/chrismou-project-manager:pm-auto` must both appear in the slash-command picker with their
   existing descriptions. This is the new risk introduced by removing the `commands` key.
6. Behavioural smoke test of the permissionless gate: run `/chrismou-project-manager:pm-auto`,
   confirm `.claude/.pm-permissionless.json` is written, confirm ordinary tool calls
   auto-approve, and confirm a deny-list-matching command still prompts.
7. Session lifecycle: end the session and confirm `.claude/.pm-permissionless.json` is cleaned up
   (proves `SessionEnd` fired).
8. End-to-end: run `/chrismou-project-manager:pm` on a trivial task and confirm the pipeline can
   actually dispatch to the architect and coder agents (proves agent registration is functional,
   not just cosmetically listed).

Steps 3, 4, and 5 are **release-blocking**. Do not merge on a green `jq` alone.

### 5.3 Cache-state check on the reporting machine

`/home/mou/.claude/plugins/cache/chrismou-claude-plugins/chrismou-project-manager/` currently
holds `0.1.0`, `0.2.0`, `0.2.1`, `0.3.0`, `0.3.1`. `0.3.0` is marked `.orphaned_at` yet still has
live `.in_use` markers, which is why the reported error names `0.3.0` rather than the newest
cached copy. Both `0.3.0` and `0.3.1` contain the defective manifest.

After releasing the fix, verify the active cache directory's manifest:

```
jq -r '.hooks, .agents, .commands' \
  ~/.claude/plugins/cache/chrismou-claude-plugins/chrismou-project-manager/0.3.2/.claude-plugin/plugin.json
```

Expect three `null`s. If the old error persists after the update, it is a stale-cache artefact
from a long-lived session pinning an orphaned version — restart all Claude Code sessions before
concluding the fix failed.

## 6. Assumptions

1. **Auto-discovery is universal, not version-gated.** The whole change rests on Claude Code
   loading `hooks/hooks.json`, `agents/`, and `commands/` automatically. All three path joins are
   present in the 2.1.220 bundle and the hooks error message states the contract explicitly, but
   the repo declares no minimum Claude Code version anywhere, so I could not establish a support
   floor. Steps 5.2.3–5.2.5 exist to confirm this empirically before merge.
2. **Agent and command discovery keys off directory contents, not manifest order.** The `agents`
   key listed files in a specific order (architect, coder, qa, reviewer, documenter). I am
   assuming nothing depends on that ordering — agents are addressed by name throughout
   `commands/pm.md` and `commands/pm-auto.md`, never by index. Worth a quick confirming grep
   during implementation.
3. **Agent names are derived identically either way.** The registered names (e.g. `qa-tester`
   from `agents/qa.md`) come from each file's frontmatter, not from the manifest path, so
   removing the manifest list cannot rename anything. Step 5.2.4 checks the actual names, not
   just the count.
4. **No consumer depends on the removed keys.** `marketplace.json` in
   `chrismou/claude-plugins` references this repo by `{source: github, repo: ...}` with no ref or
   version pin and restates no component paths.
5. **CHANGELOG is expected for every release.** Every prior version has an entry.

## 7. Open questions

None outstanding. The three prior questions (branch base/version, manifest cleanup scope,
marketplace release steps) were answered by the user and are reflected above.

## 8. Non-obvious side effects and traps

- **Trailing comma.** Deleting the last keys of a JSON object is the single most likely way to
  break this change. `"keywords": [...]` must lose its comma. Validate with `jq`.
- **Stale local `main`.** The local `main` was at `0.3.0` before fetching; `origin/main` is at
  `0.3.1`. Branching without pulling would produce a `0.3.1` bump that the version-bump CI
  rejects as not strictly greater. Pull first.
- **Version-bump CI is a hard gate**, not advisory. A PR that fixes the bug but forgets the bump
  is blocked.
- **`check-readme.yml` is not triggered** by this change (its path filter covers
  `hooks/deny-list.json`, `README.md`, `hooks/generate-readme-section.sh`). Do not run
  `generate-readme-section.sh` as part of this work — it would introduce unrelated diff noise.
- **Silent-removal regression is the real danger, and this revision widens it.** If auto-discovery
  does not fire for hooks, the error disappears *and so do the hooks* — permissionless mode would
  silently stop gating tool calls, which is security-relevant, since the `PreToolUse` gate is what
  enforces the deny list under `pm-auto`. Removing the `agents` and `commands` keys extends the
  same failure mode to the agent roster and the slash commands: a broken result looks like "no
  error" plus quietly missing components. Every one of steps 5.2.3–5.2.5 is mandatory.
- **`PreToolUse` matcher is `*`.** These hooks run in *every* project for *every* tool call, so a
  regression here has blast radius well beyond this repo. Treat any hook misbehaviour found in QA
  as release-blocking.
- **Stale orphaned cache versions will keep reporting the old error** until sessions holding
  `.in_use` markers on `0.3.0` exit. Expect a confusing window where the fix is released but the
  error still appears in an old session. Restart sessions before re-testing.
- **`revert-3-refactor/shorten-command-names` exists on the remote.** A new remote branch appeared
  during the fetch that appears to revert the command-rename work. If it ever merges it will touch
  `commands/` and likely `plugin.json`. Not this change's problem, but if it lands first,
  re-verify that `plugin.json` on `main` still lacks the three keys before assuming the fix
  survived.
- **Other unmerged branches carry the defect** (`hotfix/plugin-root-env-var`,
  `permissionless-auto-command`, plus the revert branch above). None should reintroduce the keys
  unless they touch `plugin.json`; if one does, resolve conflicts by keeping the higher version
  and the *absence* of `hooks`/`agents`/`commands`.

## 9. Handoff

Implementer: `coder` agent. The change is two files and roughly a dozen deleted lines; effectively
all the effort is in the live-session verification in §5.2, which cannot be delegated to static
checks.
