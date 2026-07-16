# project-manager

> **Note:** This plugin is currently in daily use and in active development/testing. The interface, agent prompts, and workflow structure may change before a 1.0.0 release. Use with that in mind.

A Claude Code plugin that implements an end-to-end AI dev loop, orchestrating a team of specialised agents through a structured plan → implement → review → document cycle.

## What it does

Running `/project-manager:project-manager <task description>` spins up a coordinated pipeline of agents:

1. **Architect** — analyses your codebase, writes a technical design doc to `plans/YYYYMMDD-slug.md`, then pauses so you can review and edit it before anything is touched.
2. **Coder** — executes the plan precisely: creates/modifies files, runs syntax checks, and self-corrects minor blockers.
3. **QA** — reviews the implementation for bugs, edge cases, missing error handling, and test coverage gaps. If it finds issues, it sends work back to the Coder.
4. **Reviewer** — audits for security issues, performance problems, and style consistency. Loops back to the Coder if changes are required.
5. **Documenter** — updates `README.md`, docstrings, and `CHANGELOG.md` to reflect the changes made.

There are two human checkpoints built in:

- After planning, so you can review and tweak the design doc before code is written.
- After review, so you can accept the result or request changes.

Plan files are never deleted — they're kept in `plans/` for audit and version history.

### Two ways to run it

The plugin ships two commands that share the same five-agent pipeline:

- **`project-manager`** — the standard flow. The Architect analyses your project and surfaces any clarification questions you need to answer before coding starts. After you review/edit the plan, implementation runs through a 3-phase pipeline: Plan (with clarification gating), Implement (Code + QA + Review iterate automatically), then Document. Only two user confirmation gates: after planning (where you answer clarifications and approve scope if needed) and after implementation converges (before documentation).
- **`project-manager-auto`** — the same pipeline, but planning runs in Claude Code's **plan mode** so it stays attended while you review the design. When you start implementation you're shown the native approval dialog — choose **"auto-accept edits"** to let the Coder, QA, and Reviewer stages run unattended without a permission prompt on every file change.

## Requirements

- [Claude Code](https://claude.ai/code) with plugin support enabled

## Installation

### Option A: Install from marketplace

```bash
claude plugin marketplace add chrismou/claude-plugins
claude plugin install project-manager@chrismou-claude-plugins
```

### Option B: Install from source / local dev

```bash
git clone https://github.com/chrismou/claude-project-manager-workflow
claude plugin install ./claude-project-manager-workflow
```

## Usage

From within any Claude Code session in your project:

```
/project-manager:project-manager <description of your task>
```

Or, to run planning in plan mode with auto-accept for the implementation stages:

```
/project-manager:project-manager-auto <description of your task>
```

**Example:**

```
/project-manager:project-manager Add rate limiting to the public API endpoints
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

1. The Architect analyses your project and drafts a plan in plan mode.
2. Review the drafted plan, make any edits you want.
3. Type `GO` to kick off implementation. You'll get the plan-mode approval dialog — pick **"auto-accept edits"** to run the rest unattended. The approved plan is then saved to `plans/YYYYMMDD-slug.md` for audit.
4. The Coder, QA, and Reviewer agents run in sequence (looping back as needed).
5. You'll be asked to confirm the final result. Type `Yes` to proceed to documentation, or `No` to provide feedback and restart the loop.

## Agents

| Agent          | Model             | Role                                                          |
| -------------- | ----------------- | ------------------------------------------------------------ |
| architect      | claude-opus-4-8   | Writes technical design docs, surfaces clarifications and open questions |
| architect-auto | claude-sonnet-4-6 | Returns the design doc as text for plan mode, no code changes |
| coder          | claude-sonnet-4-6 | Implements the plan                                          |
| qa-tester  | claude-sonnet-4-6 | Tests for bugs, edge cases, coverage gaps     |
| reviewer   | claude-sonnet-4-6 | Security, performance, and style audit        |
| documenter | claude-haiku-4-5  | Updates docs and CHANGELOG                    |

## Project structure

```
.
├── .claude-plugin/
│   └── plugin.json
├── .github/workflows/
│   └── version-bump.yml
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
├── plans/
└── CHANGELOG.md
```

## License

MIT
