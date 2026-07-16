# Technical Design Doc: Split plugin into its own repo; this repo becomes marketplace-only

**Date:** 2026-07-16
**Status:** Revised — clarification answers baked in (see "Resolved decisions")

## Summary

Split `chrismou/claude-plugins` into two repos:

1. **This repo** (`chrismou/claude-plugins`) becomes a tiny, near-frozen marketplace index: `.claude-plugin/marketplace.json` + `README.md`.
2. **A new repo** (`chrismou/claude-project-manager-workflow`) holds the `project-manager` plugin — agents, commands, `plugin.json`, `CHANGELOG.md`, `version-bump.yml`, and `plans/` — referenced from the marketplace with a `github` source. Created **fresh with a single initial commit** (no history migration).

The plugin entry is renamed from `chrismou-claude-plugins` to `project-manager`, so commands read as `/project-manager:project-manager ...`. Command namespacing follows the **plugin name**, not the repo name, so the `-workflow` repo suffix has no effect on how commands are invoked.

## Resolved decisions

Answered by the user on 2026-07-16:

- **D1. Plugin repo name:** `chrismou/claude-project-manager-workflow`. The old redirect name (`chrismou/claude-project-manager` → `claude-plugins`) is **not** reclaimed and remains intact. The plugin `name` in both `plugin.json` and the marketplace entry stays `project-manager`, so command triggers are `/project-manager:project-manager` and `/project-manager:project-manager-auto` regardless of the repo name.
- **D2. History:** fresh start — single initial commit in the new repo, no `git filter-repo`. Install-safety considerations for this are covered in Phase 1 and Side Effects (S1).
- **D3. `plans/`:** moves to the new plugin repo (all plans relate to the plugin, not the marketplace). The new repo also gets a `.gitignore` that includes `.claude/settings.local.json`.
- **D4. Version:** plugin bumps to `0.1.0` in the new repo; the marketplace entry drops its `version` field entirely (marketplace stays unversioned/frozen — the plugin repo's `plugin.json` is the single source of truth).

## Verified current state (corrections to the task brief)

The task brief assumed this repo is named `claude-project-manager` on GitHub and suggested renaming it. **That is not the case:**

- The GitHub remote is `git@github.com:chrismou/claude-plugins.git` — the repo is **already** named `claude-plugins`, matching the marketplace name. Only the **local directory** (`/home/mou/dev/claude/claude-project-manager`) still carries the old name.
- `gh repo view chrismou/claude-project-manager` resolves to `claude-plugins` — i.e. the repo **was previously named** `claude-project-manager` and GitHub maintains a rename redirect from the old name to the current repo.

Consequences:

- **No marketplace-repo rename is required.** The "repo rename sequence" from the brief collapses to: (a) optionally rename the local working directory, (b) create the new plugin repo.
- Because the new repo is named `chrismou/claude-project-manager-workflow` (D1), the existing redirect from `chrismou/claude-project-manager` to the marketplace repo is **left intact** — old links/clones keep resolving to `chrismou/claude-plugins` as before. No redirect is retired.

Other verified facts:

- Tracked files: `README.md`, `CHANGELOG.md`, `plans/` (3 files), `.claude-plugin/marketplace.json`, `.github/workflows/version-bump.yml`, `project-manager/` (plugin.json, 2 commands, 6 agents). `.claude/settings.local.json` is **untracked** (local only — does not move).
- Command files reference agents by **bare names** (`architect`, `coder`, `qa-tester`, `reviewer`, `documenter`) — no `chrismou-claude-plugins:` prefixes anywhere in the plugin content. The only occurrences of the old plugin name are in `project-manager/plugin.json` (`name`, `repository`) and `.claude-plugin/marketplace.json`. So the plugin rename requires **no changes to command/agent markdown**.
- One git tag exists locally: `0.1`. CHANGELOG compare links point at `chrismou/claude-plugins` and reference `v0.0.x` tags that do not actually exist on the remote (pre-existing inconsistency; noted, not blocking).
- `version-bump.yml` header says it should be a required status check on `main` branch protection. Whether it actually is must be checked in repo settings during migration (Step 3.4).

## Target state

### New plugin repo: `chrismou/claude-project-manager-workflow` (public)

```
claude-project-manager-workflow/
├── .claude-plugin/
│   └── plugin.json          # moved from project-manager/plugin.json (standard location)
├── .gitignore                # new — includes .claude/settings.local.json (D3)
├── agents/
│   ├── architect.md
│   ├── architect-auto.md
│   ├── coder.md
│   ├── qa.md
│   ├── reviewer.md
│   └── documenter.md
├── commands/
│   ├── project-manager.md
│   └── project-manager-auto.md
├── plans/                    # moved (incl. this plan file — D3)
│   ├── 20260626-loosen-test-stage-gates.md
│   ├── 20260630-unattended-scope-gate.md
│   ├── 20260715-promote-test-to-project-manager.md
│   └── 20260716-split-plugin-into-own-repo.md
├── .github/workflows/
│   └── version-bump.yml      # moved + updated (see below)
├── CHANGELOG.md              # moved + new entry for the split/rename
└── README.md                 # new — bulk of current README, updated names
```

The plugin **root is the repo root** (`.claude-plugin/plugin.json` is the standard discoverable location). The existing relative paths in `plugin.json` (`./agents/*.md`, `./commands/`) remain correct because they resolve against the plugin root, which is now the repo root.

### Marketplace repo: `chrismou/claude-plugins` (this repo)

```
claude-plugins/
├── .claude-plugin/
│   └── marketplace.json      # updated (see below)
└── README.md                 # rewritten as a marketplace index
```

Removed from this repo (after they land in the plugin repo): `project-manager/`, `CHANGELOG.md`, `plans/`, `.github/workflows/version-bump.yml`.

## File changes in detail

### 1. `plugin.json` (new repo, at `.claude-plugin/plugin.json`)

```json
{
  "name": "project-manager",
  "version": "0.1.0",
  "description": "End-to-end AI dev loop with architect, coder, QA, reviewer, and documenter agents orchestrated by a project manager command.",
  "repository": "https://github.com/chrismou/claude-project-manager-workflow",
  "license": "MIT",
  "author": {
    "name": "Chris Chrisostomou",
    "url": "https://github.com/chrismou"
  },
  "keywords": ["project-management", "workflow", "agents", "dev-loop"],
  "agents": [
    "./agents/architect.md",
    "./agents/architect-auto.md",
    "./agents/coder.md",
    "./agents/qa.md",
    "./agents/reviewer.md",
    "./agents/documenter.md"
  ],
  "commands": "./commands/"
}
```

Changes: `name` → `project-manager` (kept independent of the repo name so command triggers stay `/project-manager:...` — D1); `repository` → new repo URL; `version` → `0.1.0` (D4 — the rename is breaking for anyone installed under the old name).

### 2. `marketplace.json` (this repo)

```json
{
  "name": "chrismou-claude-plugins",
  "owner": {
    "name": "Chris Chrisostomou"
  },
  "metadata": {
    "description": "Chris Chrisostomou's Claude Code plugin marketplace."
  },
  "plugins": [
    {
      "name": "project-manager",
      "source": {
        "source": "github",
        "repo": "chrismou/claude-project-manager-workflow"
      },
      "description": "End-to-end AI dev loop orchestrating a team of specialised agents through a plan → implement → review → document cycle.",
      "author": {
        "name": "Chris Chrisostomou"
      },
      "license": "MIT"
    }
  ]
}
```

Changes:

- Plugin entry `name`: `chrismou-claude-plugins` → `project-manager` (D1 — this, not the repo name, drives command namespacing).
- `source`: `"./project-manager"` → github source object pointing at `chrismou/claude-project-manager-workflow`.
- Marketplace `metadata.description` currently describes the *plugin*; replace with a marketplace-level description.
- **`version` field dropped from the entry** (D4). With a github source, the authoritative version lives in the plugin repo's `plugin.json`; keeping a copy here would require a marketplace PR on every plugin release, defeating the "near-frozen index" goal. Fallback: if marketplace validation rejects the entry without a `version` (verify in Phase 3.1), reinstate it at `0.1.0` and accept the sync cost.

### 3. `version-bump.yml` (moves to plugin repo, updated)

- `PLUGIN_FILE` changes from `project-manager/plugin.json` to `.claude-plugin/plugin.json`.
- **Delete everything referencing `MARKET_FILE`** (`head_market` extraction, the echo, and the plugin/marketplace agreement check) — `marketplace.json` no longer coexists with the plugin, so the "both files must agree" invariant no longer applies. What remains: head version must be strictly greater than base version (the `sort -V` comparison), same as today.
- Header comment updated to drop the marketplace mention.

### 4. `CHANGELOG.md` (moves to plugin repo)

Add a `## [0.1.0] - 2026-07-16` entry at the top, under `### Changed`, roughly:

- Plugin extracted into its own repository (`chrismou/claude-project-manager-workflow`); the marketplace (`chrismou/claude-plugins`) now references it with a github source.
- Plugin renamed from `chrismou-claude-plugins` to `project-manager` — commands are now invoked as `/project-manager:project-manager` and `/project-manager:project-manager-auto`. Existing installs under the old name must be uninstalled and reinstalled.

**Remove the compare links at the bottom** (`[Unreleased]`, `[0.0.x]`): they point at `chrismou/claude-plugins` and reference `v0.0.x` tags that don't exist, and with a fresh-history repo (D2) they cannot be made to work. Pre-0.1.0 entries themselves stay as historical record; the old history remains browsable in the marketplace repo.

### 5. Plugin repo `README.md` (new file)

Derived from the current README (lines 3–101 essentially move wholesale), with:

- Title: `# project-manager`; keep the "active development" note.
- Every `/chrismou-claude-plugins:project-manager...` → `/project-manager:project-manager...`.
- Installation:
  - Option A (marketplace): `claude plugin marketplace add chrismou/claude-plugins` then `claude plugin install project-manager@chrismou-claude-plugins`.
  - Option B (from source / local dev): `git clone https://github.com/chrismou/claude-project-manager-workflow` then `claude plugin install ./claude-project-manager-workflow` — the dev loop is unchanged apart from the path no longer having the `project-manager/` subdirectory segment.
- "Project structure" section updated to the new layout (plugin at repo root, `.claude-plugin/plugin.json`, no `marketplace.json`).

### 5b. `.gitignore` (new file in plugin repo)

```
.claude/settings.local.json
```

Required by D3 so local permission grants accumulated while dogfooding the plugin in its own repo never get committed. (This repo currently has no `.gitignore`; the marketplace repo does not need one since no local settings file will live there once dev moves to the plugin repo, but adding the same one-liner there is harmless and optional.)

### 6. Marketplace repo `README.md` (rewritten, small)

- Title: `# chrismou-claude-plugins` — "Marketplace index for Chris Chrisostomou's Claude Code plugins."
- Usage: `claude plugin marketplace add chrismou/claude-plugins`.
- A plugin table: | Plugin | Description | Repo | — one row for `project-manager` linking to `chrismou/claude-project-manager-workflow` (new plugins get added as rows).
- Install example: `claude plugin install project-manager@chrismou-claude-plugins`.
- License: MIT.

## Migration sequence

### Phase 1 — Create and populate the plugin repo

1.1. Create `chrismou/claude-project-manager-workflow` on GitHub (public — required for the github marketplace source to be installable by others): `gh repo create chrismou/claude-project-manager-workflow --public`. The existing rename redirect from `chrismou/claude-project-manager` to the marketplace repo is untouched (D1).

1.2. Populate it **fresh** (D2): create a new local directory (e.g. `/home/mou/dev/claude/claude-project-manager-workflow`), `git init`, copy the current files into the new layout:

- `project-manager/plugin.json` → `.claude-plugin/plugin.json`
- `project-manager/agents/` → `agents/`
- `project-manager/commands/` → `commands/`
- `CHANGELOG.md` → `CHANGELOG.md`
- `plans/` → `plans/` (all four plan files, including this one — D3)
- `.github/workflows/version-bump.yml` → `.github/workflows/version-bump.yml`
- new: `.gitignore` (section 5b), `README.md` (section 5)

Per-file history is not migrated; it remains permanently browsable in the marketplace repo's git history. **Install-safety notes for the fresh start:**

- Plugin installs are not tied to git history — a github-source install fetches the repo's current default-branch state, so a fresh-history repo behaves identically to a migrated-history one at install time. What breaks installs is the plugin *rename*, not the history choice (see S2).
- Ordering is what matters: the new repo's `main` must be fully populated and pushed **before** the marketplace change (Phase 2) merges. If marketplace.json pointed at an empty or half-populated repo, `claude plugin marketplace update` / `install` would fetch a broken plugin. Phase 1 completes entirely before Phase 2 merges.
- The single initial commit must include everything (manifest, agents, commands, workflow, docs) so there is no window where the default branch lacks `.claude-plugin/plugin.json`.

1.3. Apply the content changes from "File changes in detail" before that initial commit: plugin.json (name/version/repository), version-bump.yml (paths, drop marketplace check), CHANGELOG entry + link cleanup, new README, `.gitignore`.

1.4. Single initial commit, push `main`; configure branch protection on the new repo with `verify-version-bump` as a required status check (mirroring the intent of the workflow header).

1.5. Optional: tag `v0.1.0`.

### Phase 2 — Convert this repo to marketplace-only

2.1. Branch (e.g. `split-plugin-into-own-repo`).

2.2. Update `.claude-plugin/marketplace.json` per section 2 above.

2.3. Rewrite `README.md` per section 6 above.

2.4. `git rm -r project-manager/ plans/ CHANGELOG.md .github/workflows/version-bump.yml`. (These are *moves*, not deletions — the content now lives in the plugin repo per D2/D3, and full history remains in this repo's git history, satisfying the "never delete plan files" audit rule. Only run this after Phase 1 is pushed and verified.)

2.5. **Before merging:** if `verify-version-bump` is a required status check on `main`'s branch protection, remove it — otherwise this PR (and all future PRs) can never merge, because the deleted workflow will never report the required check.

2.6. PR + merge. Note the PR itself cannot rely on the version-bump gate (the files it checks are being removed) — consistent with 2.5.

### Phase 3 — Verify and migrate installs

3.1. On a machine/session with the marketplace already added: `claude plugin marketplace update chrismou-claude-plugins` (or remove/re-add), confirm `project-manager` appears with the github source.

3.2. Uninstall the old plugin (`claude plugin uninstall chrismou-claude-plugins@chrismou-claude-plugins`), install the new one (`claude plugin install project-manager@chrismou-claude-plugins`).

3.3. Smoke test: `/project-manager:project-manager` and `/project-manager:project-manager-auto` appear and launch; the architect/coder/qa/reviewer/documenter agents resolve.

3.4. Confirm branch protection state on both repos matches 1.4 / 2.5.

3.5. Optional local hygiene: rename the working directory `/home/mou/dev/claude/claude-project-manager` → `/home/mou/dev/claude/claude-plugins` so it matches the remote; the plugin repo working copy from Phase 1.2 lives alongside it at `/home/mou/dev/claude/claude-project-manager-workflow`. Note the untracked `.claude/settings.local.json` in this repo contains absolute-path permission entries (`git -C /home/mou/dev/claude/claude-project-manager ...`) that would go stale after a directory rename — harmless (they just stop matching), but worth knowing. It stays untracked here and is gitignored in the new repo (D3).

## Assumptions

- A1. The new plugin repo will be **public** — the marketplace github source must be fetchable by anyone installing the plugin.
- A2. The marketplace **name** stays `chrismou-claude-plugins` (only the plugin entry is renamed), so existing `claude plugin marketplace add chrismou/claude-plugins` registrations keep working after an update.
- A3. There are no external consumers pinned to the old plugin name that need a deprecation window — the brief states no external contributors and this is in personal daily use.
- A4. The stale feature branches on the remote (`architect-improvements`, `ci-version-bump-gate`, etc.) stay where they are; they are not part of this migration.
- A5. The user (not this plan's executor) performs the GitHub-side actions that need account authority: repo creation and branch-protection changes. The coder agent can prepare everything else.
- A6. Dropping the marketplace entry's `version` field is accepted by marketplace validation (D4). Verified in Phase 3.1; fallback documented in section 2 if it is rejected.

## Open Questions

None. The four questions raised in the first draft (repo name, history migration, `plans/` destination, versioning) were answered by the user and are baked in as D1–D4 under "Resolved decisions".

## Non-Obvious Side Effects

- S1. **Fresh history (D2):** per-file history for agents/commands/plans does not exist in the new repo — `git log`/`git blame` there start at the initial commit. The full pre-split history stays permanently in the marketplace repo. This has **no effect on installs**: github-source installs fetch current default-branch state, not history. The real install-safety constraint is ordering (Phase 1 fully pushed before Phase 2 merges) and a complete initial commit — both handled in Phase 1.2.
- S2. **Breaking install/command rename:** every existing install of `chrismou-claude-plugins@chrismou-claude-plugins` becomes orphaned — a marketplace update replaces the entry, so users must uninstall/reinstall, and all invocations change from `/chrismou-claude-plugins:project-manager...` to `/project-manager:project-manager...`. This includes the user's own machines (this very session shows the plugin installed under the old name). Any scripts, notes, or muscle memory using the old command prefix break. Note this is caused by the plugin **name** change, which per D1 is fixed at `project-manager` — the repo name plays no part.
- S3. **Branch-protection deadlock:** if `verify-version-bump` is a required check on this repo's `main` and the workflow file is deleted without updating protection, no PR can ever merge again (required check never reports). Must be handled in Phase 2.5 *before* merging the split PR.
- S4. **`plugin.json` `repository` field is currently wrong-ish already** (`chrismou/claude-plugins` — the marketplace repo); after the split it must point at `chrismou/claude-project-manager-workflow` or the metadata misleads.
- S5. **Marketplace `metadata.description`** currently describes the plugin ("End-to-end AI dev loop…"); left unchanged it would misdescribe a multi-plugin marketplace. Updated in section 2.
- S6. **CHANGELOG compare links** reference `v0.0.x` tags that don't exist on the remote (only `0.1` exists locally, unpushed), and with fresh history (D2) they can never resolve in the new repo — so they are removed as part of section 4 rather than carried over broken.
- S7. **The github source changes the update path:** with the local `./project-manager` source, editing this repo updated the installed plugin on marketplace update; after the split, released changes must be pushed to the plugin repo's default branch before `claude plugin update` picks them up. Local dev instead uses a direct local install of the plugin-repo checkout (README Option B).
- S8. **This plan file itself** is written to `plans/` in the marketplace repo but describes plugin-lifecycle work; per D3 it travels to the plugin repo with the others (and is then removed here in Phase 2.4, remaining in this repo's git history).
- S9. **Old repo-name redirect is a squatting risk left open (accepted):** by not reclaiming `chrismou/claude-project-manager` (D1), that name continues to redirect to the marketplace repo; if it were ever deliberately reclaimed later for another purpose, the redirect would silently break at that point. No action now — just recorded.

## QA notes (for the qa-tester agent)

- Validate both JSON files parse (`jq . .claude-plugin/marketplace.json`, `jq . .claude-plugin/plugin.json` in the plugin repo).
- Confirm the plugin repo layout: `.claude-plugin/plugin.json` at repo root; all six agent files and both command files present at the paths `plugin.json` references; `.gitignore` present and containing `.claude/settings.local.json`; all four plan files present under `plans/`.
- Confirm `plugin.json` `name` is `project-manager` and the marketplace entry `name` matches — the repo name (`claude-project-manager-workflow`) must appear only in the `source.repo` and `repository` URL fields, never as the plugin name.
- Confirm the marketplace entry has no `version` field and that `claude plugin marketplace update` accepts it (D4 fallback check).
- Grep both repos for `chrismou-claude-plugins` — after the split it should appear **only** as the marketplace name (marketplace.json `name`, README install strings `...@chrismou-claude-plugins`), never as a plugin name.
- Confirm `version-bump.yml` in the plugin repo references `.claude-plugin/plugin.json` and contains no `marketplace.json` references.
- Confirm no application/plugin content was modified beyond the enumerated changes (agents/commands markdown should be byte-identical to pre-split, since no name prefixes exist in them).
- End-to-end: marketplace update → install → both slash commands resolve and each of the five agents can be invoked.
