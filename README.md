# chrismou-project-manager

> **Note:** This plugin is currently in daily use and in active development/testing. The interface, agent prompts, and workflow structure may change before a 1.0.0 release. Use with that in mind.

A Claude Code plugin that implements an end-to-end AI dev loop, orchestrating a team of specialised agents through a structured plan → implement → review → document cycle.

## What it does

Running `/chrismou-project-manager:project-manager <task description>` spins up a coordinated pipeline of agents:

1. **Architect** — analyses your codebase, writes a technical design doc to `plans/YYYYMMDD-slug.md`, then pauses so you can review and edit it before anything is touched.
2. **Coder** — executes the plan precisely: creates/modifies files, runs syntax checks, and self-corrects minor blockers.
3. **QA** — reviews the implementation for bugs, edge cases, missing error handling, and test coverage gaps. If it finds issues, it sends work back to the Coder.
4. **Reviewer** — audits for security issues, performance problems, and style consistency. Loops back to the Coder if changes are required.
5. **Documenter** — updates `README.md`, docstrings, and `CHANGELOG.md` to reflect the changes made.

There are two human checkpoints built in:

- After planning, so you can review and tweak the design doc before code is written.
- After implementation converges, so you can accept the result or request changes before documentation.

Plan files are never deleted — they're kept in `plans/` for audit and version history.

### Two ways to run it

The plugin ships two commands that share the same five-agent pipeline:

- **`project-manager`** — the standard flow. The Architect analyses your project and surfaces any clarification questions you need to answer before coding starts. After you review/edit the plan, implementation runs through a 3-phase pipeline: Plan (with clarification gating), Implement (Code + QA + Review iterate automatically), then Document. Two user confirmation gates: after planning and after implementation converges.
- **`project-manager-auto`** — the same pipeline, but armed with a `PreToolUse` hook that auto-approves tool calls. Permission posture is chosen at invocation time. The deny list (see below) still applies — any matched tool call prompts as normal rather than being auto-approved.

The commands are behaviourally identical in every other way. Gate structure, clarification handling, agent roster, and unattended-scope selection are the same. The only difference is whether you are present for each tool call.

## Requirements

- [Claude Code](https://claude.ai/code) with plugin support enabled
- `jq` installed (required for `project-manager-auto`; `brew install jq` / `apt install jq`)

## Installation

### Option A: Install from marketplace

```bash
claude plugin marketplace add chrismou/claude-plugins
claude plugin install chrismou-project-manager@chrismou-claude-plugins
```

### Option B: Install from source / local dev

```bash
git clone https://github.com/chrismou/claude-project-manager-workflow
claude plugin install ./claude-project-manager-workflow
```

## Usage

From within any Claude Code session in your project:

```
/chrismou-project-manager:project-manager <description of your task>
```

Or, to run with auto-approved tool calls (except the deny list):

```
/chrismou-project-manager:project-manager-auto <description of your task>
```

**Example:**

```
/chrismou-project-manager:project-manager Add rate limiting to the public API endpoints
```

### What to expect (`project-manager`)

1. The Architect analyses your project and writes a plan to `plans/YYYYMMDD-slug.md`, surfacing any clarification questions (assumptions, open decisions, edge cases) that need resolution before implementation. You'll see the plan path printed.
2. Open the plan file, review it, and make any edits you want. Answer any clarification questions the Architect raises.
3. Type `Yes` to kick off implementation.
   - If your approval implies unattended execution (e.g., "run it unattended", "just finish it without me"), you'll be asked to choose your scope:
     - **"Entire process"** — Implementation and Documentation run back-to-back with no additional confirmation.
     - **"Implementation only"** — Implementation runs unattended, then you'll confirm before Documentation starts.
4. The Coder, QA, and Reviewer agents run automatically with no user confirmations between them. QA failures and review feedback are resolved in-loop.
5. You'll be asked to confirm once the implementation is complete and all stages have converged (unless "Entire process" was selected). Type `Yes` to proceed to documentation, or `No` to provide feedback and restart planning.
6. Documentation is updated and the plan is retained in `plans/` for audit.

### What to expect (`project-manager-auto`)

`project-manager-auto` is a thin wrapper: it arms a `PreToolUse` hook, then invokes the standard `project-manager` pipeline. The pipeline steps are identical to those above.

1. The command checks for `jq` and validates any per-project overrides file.
2. It reads `$CLAUDE_CODE_SESSION_ID` and writes it to `.claude/.pm-permissionless.json`. This write prompts once; you are present.
3. It confirms arming: session ID, TTL (2 hours), deny list location, and that existing `deny`/`ask` rules still apply.
4. The standard pipeline runs. Tool calls are auto-approved except those matching the deny list, which prompt as normal.
5. The flag is deleted at the scope boundary (after Implementation for "Implementation only" scope, or after Documentation for "Entire process" scope).

**Important limits:**
- **Session-bound.** The flag stores your Claude Code session ID. The hook checks this on every tool call — a flag armed in one session is inert in every other session in the same project directory. Concurrent `project-manager-auto` runs in different sessions do not interfere.
- A deny-list match in an unattended run **pauses indefinitely** — it does not fail or route around. The agent waits for you to return and confirm.
- Existing `deny` or `ask` rules in your Claude Code settings are not affected — the hook cannot override them.
- The flag has a 2-hour TTL. A run longer than 2 hours will silently revert to normal prompting.

## Permissionless mode deny list

> **Note:** Bash deny-listing is pattern matching — a speed bump against careless agent behaviour, not containment. It is trivially evaded by wrapper scripts, compound commands, indirection, and subprocesses that do the same work via a language runtime. The only genuinely enforced rule is `path-escape`, which resolves and boundary-checks rather than pattern-matches. For real containment, use OS-level sandboxing. Do not treat the deny list as a security boundary.

The following rules are evaluated on every tool call while `project-manager-auto` is armed. A match causes the tool call to prompt as normal. The rule ids are stable and are the public API for per-project overrides.

<!-- deny-list-generated-start -->
| Rule ID | Category | What it matches | Why |
| --- | --- | --- | --- |
| `path-escape` | Path containment | `Edit` / `Write` / `NotebookEdit` with a target outside the project root | Prevents writes outside the project boundary. Unlike pattern-match rules this is a real boundary: the hook resolves symlinks and `..` before checking. |
| `git-push` | Outward publishing | `git push` | Pushes code off the machine; must stay a human decision. |
| `git-remote` | Outward publishing | `git remote` | Modifies remote tracking configuration; must stay a human decision. |
| `gh-pr-create` | Outward publishing | `gh pr create` | Opens a pull request on GitHub; must stay a human decision. |
| `gh-release` | Outward publishing | `gh release` | Creates or manages GitHub releases; must stay a human decision. |
| `registry-publish` | Outward publishing | `npm publish` / `yarn publish` / `docker push` / `twine upload` | Publishes artifacts to public registries — the package-ecosystem equivalent of `git push`; must stay a human decision. |
| `git-reset-hard` | Destructive git | `git reset --hard` | Irreversibly discards local changes; must stay a human decision. |
| `git-clean` | Destructive git | `git clean -f` / `git clean -fd` | Irreversibly deletes untracked files; must stay a human decision. |
| `git-commit` | Destructive git | `git commit` | Commits are permanent history once pushed; matches the global preference that commits happen only when explicitly requested. |
| `git-rebase` | Destructive git | `git rebase` | Rewrites commit history; must stay a human decision. |
| `rm-rf` | Filesystem | `rm -r` / `rm -rf` / `rm -Rf` | Recursive deletion is irreversible; must stay a human decision. |
| `sudo` | Privilege / system | `sudo` | Privilege escalation; must stay a human decision. |
| `systemctl` | Privilege / system | `systemctl` | Manages system services; must stay a human decision. |
| `chmod` | Privilege / system | `chmod` | Modifies file permissions; must stay a human decision. |
| `chown` | Privilege / system | `chown` | Changes file ownership; must stay a human decision. |
| `crontab` | Privilege / system | `crontab` | Installs or removes scheduled jobs — a persistence mechanism; must stay a human decision. |
| `credentials-ssh` | Credentials / secrets | Access to `~/.ssh` | Protects SSH private keys from agent access. The `\.ssh/` alternative catches absolute paths such as `/home/user/.ssh/id_rsa` that the Read tool always supplies. |
| `credentials-aws` | Credentials / secrets | Access to `~/.aws` | Protects AWS credentials from agent access. The `\.aws/` alternative catches absolute paths such as `/home/user/.aws/credentials` that the Read tool always supplies. |
| `credentials-env` | Credentials / secrets | `.env` / `.env.*` files | Prevents accidental exposure of secrets stored in `.env` files. |
| `gh-auth` | Credentials / secrets | `gh auth` | Manages GitHub authentication tokens; must stay a human decision. |
| `pipe-to-shell` | Network egress (exec) | `curl … | sh` / `wget … | bash` | Executes remotely fetched code; the most direct remote-code-execution vector in a shell pipeline. |
| `remote-shell` | Network egress (exec) | `ssh user@host` / `scp user@host:path` / `rsync … user@host:path` | Remote shell access and file transfer — vectors for both remote execution and data exfiltration; must stay a human decision. |
| `terraform-apply` | Deploy / infra | `terraform apply` | Mutates cloud infrastructure; must stay a human decision. |
| `kubectl-mutate` | Deploy / infra | `kubectl apply` / `kubectl delete` | Mutates Kubernetes resources; must stay a human decision. |
| `docker-compose-down-v` | Deploy / infra | `docker compose down -v` / `docker-compose down -v` | Destroys Docker volumes; must stay a human decision. |
| `docker-system-prune` | Deploy / infra | `docker system prune` | Irreversibly removes Docker images, containers, and volumes; must stay a human decision. |
| `cloud-mutate` | Deploy / infra | Mutating `aws` / `gcloud` / `az` subcommands | Mutates cloud resources; must stay a human decision. |
| `eas-submit` | Deploy / infra | `eas submit` | Submits a build to app stores; must stay a human decision. |
| `npm-global` | Global package install | `npm install -g` / `npm i -g` | Installs packages globally. In-project `npm install` (without `-g`) is not matched and passes through. |
| `pip-global` | Global package install | `pip install` outside a recognised venv path | Installs packages globally. `pip install` qualified with a venv-relative path (e.g. `.venv/bin/pip install`) is not matched. Note: an activated venv's bare `pip install` cannot be distinguished by path alone. |
| `brew-install` | Global package install | `brew install` | Installs packages system-wide via Homebrew; must stay a human decision. |
| `apt-install` | Global package install | `apt install` / `apt-get install` | Installs system packages; must stay a human decision. |
| `db-reset` | DB reset | `migrate:fresh`, `db:wipe`, `prisma migrate reset`, `DROP DATABASE` | Irreversibly wipes the database. Bare invocations prompt; test-environment markers (`--env=testing`, `APP_ENV=testing`, etc.) pass through automatically. |
<!-- deny-list-generated-end -->

**Deliberately not denied:** `kill`/`pkill`, backgrounding dev servers, local git read/branch/checkout/stash, in-project `npm install` / `composer install` / `yarn add`, WebFetch (read-only; egress risk is the pipe-to-shell rule above).

### Known limitations of pattern-based deny rules

The deny list uses regex pattern matching, which has inherent limitations:

- **`ssh-keygen -t ed25519 -C "you@example.com"`** false-positives as a remote-shell attempt. The pattern `\bssh\b.*@` matches the email-in-comment. If you need to run this unattended, exempt the `remote-shell` rule via `.claude/pm-deny-overrides.json`.
- **`crontab` pattern** (`\bcrontab\b`) matches both `crontab -e` and `crontab -l` (list), catching even read-only operations. Bare `crontab -l` in an unattended run will prompt. If this is blocking legitimate QA, exempt the rule.
- **`pnpm publish`** is not covered by the `registry-publish` rule (which matches `npm publish`, `yarn publish`, `docker push`, and `twine upload`). Add a project-specific rule via `add` in `.claude/pm-deny-overrides.json` if needed.
- **rsync daemon form** (`host::module`) is not caught by the `remote-shell` pattern, which looks for `@` separators. Use explicit exemptions or project-specific rules for this edge case.

## Per-project overrides

Projects can tune the deny list without editing the plugin. Create `.claude/pm-deny-overrides.json` in your project root (beside your other `.claude/` config). The file is checked into source control so the whole team inherits it. Absent file means the shipped list applies unchanged.

### Schema

```json
{
  "exempt": ["<rule-id>", ...],
  "add": [
    {
      "id": "my-rule",
      "tools": ["Bash"],
      "pattern": "\\./deploy\\.sh\\b",
      "category": "Project-specific",
      "why": "Wrapper that pushes to staging."
    }
  ],
  "acknowledge_unsafe": ["<rule-id>", ...]
}
```

All fields are optional.

### `exempt` — remove a shipped rule

```json
{ "exempt": ["git-commit"] }
```

Removes the `git-commit` rule from evaluation. `git commit` will be auto-approved.

Use the **Rule ID** column in the deny list above — ids are stable and are never renamed or reused.

**Unknown ids are a loud no-op.** The hook writes a warning to stderr, and the `project-manager-auto` arming step reports them before the pipeline starts so you catch typos immediately.

### `add` — project-specific deny rules

```json
{
  "add": [
    {
      "id": "project-deploy-script",
      "tools": ["Bash"],
      "pattern": "\\./deploy\\.sh\\b",
      "category": "Project-specific",
      "why": "Wrapper that pushes to staging; must stay a human decision."
    }
  ]
}
```

Adds a new pattern-match rule on top of the shipped list. The `id` field is for documentation only — project-added rules cannot be exempted (delete them from the file instead).

### Precedence — deny-first

1. `exempt` removes specified shipped rules from evaluation.
2. Project `add` rules are then evaluated. They cannot be exempted.
3. **Any surviving match prompts.** Exempting never forces an allow — it only withdraws a shipped rule. If a project `add` rule and an exempted shipped rule both match the same command, the `add` rule wins.

In one sentence: *an exemption can only ever remove a shipped rule, never override a rule that still matches.*

### `path-escape` exemption — double opt-in required

`path-escape` is the only genuinely enforced boundary in the list. Exempting it with a one-line config entry would quietly convert the feature into unrestricted filesystem write access. To prevent copy-paste accidents, exempting `path-escape` requires both fields:

```json
{
  "exempt": ["path-escape"],
  "acknowledge_unsafe": ["path-escape"]
}
```

The `acknowledge_unsafe` field exists only to make the choice deliberate. The arming confirmation states in plain language that writes outside the project root will be auto-approved for the run.

**Better alternative for most cases:** use `--add-dir` or `permissions.additionalDirectories` to widen the project boundary legitimately, rather than disabling the check.

### Worked example — DB resets in a Laravel project

The `db-reset` rule prompts on `php artisan migrate:fresh` but allows `php artisan migrate:fresh --env=testing` automatically (the `unless` clause matches the test-environment marker). If you want bare `migrate:fresh` to always pass (not recommended for production databases), exempt the rule:

```json
{ "exempt": ["db-reset"] }
```

If you want to add an additional project-specific guard on a deployment script:

```json
{
  "exempt": ["git-commit"],
  "add": [
    {
      "id": "staging-deploy",
      "tools": ["Bash"],
      "pattern": "\\bpnpm\\s+run\\s+deploy\\b",
      "category": "Project-specific",
      "why": "pnpm run deploy pushes a build to staging; must stay a human decision."
    }
  ]
}
```

## Agents

| Agent      | Model             | Role                                                                         |
| ---------- | ----------------- | ---------------------------------------------------------------------------- |
| architect  | claude-opus-4-8   | Writes technical design docs, surfaces clarifications and open questions      |
| coder      | claude-sonnet-4-6 | Implements the plan                                                          |
| qa-tester  | claude-sonnet-4-6 | Tests for bugs, edge cases, coverage gaps                                    |
| reviewer   | claude-sonnet-4-6 | Security, performance, and style audit                                       |
| documenter | claude-haiku-4-5  | Updates docs and CHANGELOG                                                   |

## Project structure

```
.
├── .claude-plugin/
│   └── plugin.json
├── .github/workflows/
│   ├── check-readme.yml
│   └── version-bump.yml
├── agents/
│   ├── architect.md
│   ├── coder.md
│   ├── qa.md
│   ├── reviewer.md
│   └── documenter.md
├── commands/
│   ├── project-manager.md
│   └── project-manager-auto.md
├── hooks/
│   ├── deny-list.json
│   ├── generate-readme-section.sh
│   ├── hooks.json
│   ├── permissionless-gate.sh
│   └── session-cleanup.sh
├── plans/
├── .gitignore
├── CHANGELOG.md
├── LICENSE
└── README.md
```

## License

MIT
