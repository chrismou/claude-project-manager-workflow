# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-07-18

### Breaking Changes

- **`project-manager-auto` semantics replaced.** The previous plan-mode flow — where planning ran inside Claude Code's plan mode and exiting offered "auto-accept edits" — is removed entirely. `project-manager-auto` is now a thin wrapper that arms a session-bound `PreToolUse` hook, then invokes the standard `project-manager` pipeline. Permission posture (auto-approve vs. prompt) is chosen at invocation time. The gate structure, agent roster, and unattended-scope selection are unchanged — only the permission mechanism differs.
- **`architect-auto` agent removed.** It was used exclusively by the old plan-mode `-auto` flow and has no other consumers.

### Added

- `PreToolUse` hook (`hooks/permissionless-gate.sh`) — evaluates every tool call while a permissionless flag is armed. Session-bound (2-hour TTL), fails closed on any error. Deny-list matches prompt as normal; they do not hard-block.
- `hooks/deny-list.json` — single source of truth for deny rules. Each rule carries a stable `id`, `category`, `what`, and `why`. Ids are the public API for per-project overrides and are never renamed or reused.
- Per-project overrides (`.claude/pm-deny-overrides.json`) — projects can exempt shipped rules by id, add project-specific pattern rules, or double-opt-in to exempting `path-escape` via `acknowledge_unsafe`.
- `SessionStart` / `SessionEnd` hook cleanup (`hooks/session-cleanup.sh`) — stale flag files from crashed or expired sessions are removed automatically at session boundaries.
- `hooks/generate-readme-section.sh` — regenerates the deny-list table in `README.md` from `deny-list.json`; run by CI to keep docs and rules in sync.
- `.github/workflows/check-readme.yml` — CI job that fails if `README.md` is out of sync with `deny-list.json`.
- README: "Two ways to run it" rewritten to document the new `-auto` semantics; deny-list section (generated from `hooks/deny-list.json`); per-project overrides section with worked examples, precedence rules, and `path-escape` / `acknowledge_unsafe` caveat.
- Flag file (`.claude/.pm-permissionless.json`) added to `.gitignore`.

## [0.1.0] - 2026-07-16

### Changed

- Plugin extracted into its own repository (`chrismou/claude-project-manager-workflow`); the marketplace (`chrismou/claude-plugins`) now references it with a github source.
- Plugin renamed from `chrismou-claude-plugins` to `chrismou-project-manager` — commands are now invoked as `/chrismou-project-manager:project-manager` and `/chrismou-project-manager:project-manager-auto`. Existing installs under the old name must be uninstalled and reinstalled.

## [0.0.7] - 2026-07-15

### Changed

- `project-manager` command now implements the full 3-phase pipeline (Plan → Implement → Document) with built-in clarification gating and unattended-scope selection. This promotion replaces the former `project-manager-test` behaviour.
- `architect` agent now runs on `claude-opus-4-8` (upgraded from `claude-sonnet-4-6`) and surfaces structured clarifications: Assumptions, Open Questions, and Non-Obvious Side Effects, with a machine-readable `CLARIFICATIONS_NEEDED:` block for decision-forcing questions before implementation.

### Removed

- `project-manager-test` command — the 3-phase pipeline with clarifications and unattended-scope gating is now the standard `project-manager` flow.
- `architect-test` agent — the clarifications workflow is now built into the base `architect` agent.

## [0.0.6] - 2026-06-30

### Fixed

- `project-manager-test` command now properly gates unattended execution scopes. Added UNATTENDED-SCOPE selection gate that triggers only when GATE 1 response implies unattended execution. Users select either "Entire process" (Implement + Document run back-to-back, skipping GATE 2) or "Implementation only" (Implement runs unattended, then stops at GATE 2 for confirmation before Document). This fixes a bug where unattended phrasing alone was incorrectly interpreted as authorization to skip all remaining gates.

## [0.0.5] - 2026-06-26

### Changed

- `project-manager-test` command now uses a streamlined 3-phase pipeline (Plan → Implement → Document) instead of 4 stages, reducing user confirmation gates from 4 to 2. The Code, QA, and Review agents now iterate automatically within the Implement phase without user interruption; only gates remain after planning and after implementation converges. Clarification questions and internal QA/review loops are preserved.

## [0.0.4] - 2026-06-24

### Added

- CI `version-bump` workflow — every PR into `main` must raise `plugin.json` (and keep `marketplace.json` in sync) to a version strictly greater than the base branch, or the check fails and the merge is blocked.

## [0.0.3] - 2026-06-24

### Added

- `project-manager-test` slash command — an isolated copy of `project-manager` that trials the architect clarifying-questions flow without affecting the existing commands; calls the `architect-test` agent.
- `architect-test` agent — a copy of the base `architect` that surfaces Assumptions, Open Questions, and Non-Obvious Side Effects, and emits a machine-readable `CLARIFICATIONS_NEEDED:` block so the command can gate the pipeline on decision-forcing questions before implementation.

## [0.0.2]

### Added

- `project-manager-auto` slash command — a variant of the dev loop where planning runs inside Claude Code plan mode, so the user reviews the drafted plan and then picks "auto-accept edits" at the plan-mode approval dialog to run the implementation, QA, and review stages unattended.
- `architect-auto` agent — a read-only architect for the plan-mode flow that returns the design doc as text for the project manager to persist, rather than writing the plan file itself.

## [0.0.1] - 2026-06-18

### Added

- `project-manager` slash command — orchestrates the full end-to-end dev loop, routing tasks through planning, implementation, QA, review, and documentation stages.
- `architect` agent — analyses requirements and produces a structured implementation plan saved to a plan file before any code is written.
- `coder` agent — executes the architect's plan with precision, applying `Write`/`Edit` operations and self-correcting on unexpected errors.
- `qa-tester` agent — reviews newly written code for bugs, edge cases, missing error handling, and test-coverage gaps after implementation is complete.
- `reviewer` agent — audits code for security vulnerabilities, performance issues, and best-practice violations.
- `documenter` agent — updates technical documentation and appends a concise entry to `CHANGELOG.md` at closeout.
