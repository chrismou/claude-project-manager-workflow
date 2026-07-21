#!/usr/bin/env bash
# permissionless-gate.sh — PreToolUse hook for project-manager-auto
#
# Performance targets (<200ms per call):
#   - No overrides case: 3 jq calls (stdin+subject, flag, deny-rules).
#   - With overrides:    4-5 jq calls.
# Previous implementation spawned ~5-6 jq processes per rule (150-200 total).
#
# STDOUT: only the contract JSON object on allow — stray output breaks the hook.
# STDERR: diagnostic warnings (routed to pm-gate.log, not shown to the user).
# Exit code: always 0 — fail-closed means normal prompting, not a hard block.
#
# Session binding: the flag carries the arming session's CLAUDE_CODE_SESSION_ID.
# The hook compares this against the incoming session_id on every call — a flag
# armed in session A is inert for session B.  TTL and SessionStart/SessionEnd
# cleanup are additional backstop layers.
#
# Security: pattern-based rules are a speed bump against careless agent
# behaviour, not containment.  Only path-escape is a real enforced boundary.

exec 2>>"${TMPDIR:-/tmp}/pm-gate.log"
trap 'exit 0' ERR PIPE

# ── Locate script dir (needed for deny-list.json) ─────────────────────────────
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
fi
[ -z "${SCRIPT_DIR:-}" ] && SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT:+${CLAUDE_PLUGIN_ROOT}/hooks}"
[ -z "${SCRIPT_DIR:-}" ] && exit 0

command -v jq &>/dev/null || { echo "permissionless-gate: jq not available, failing closed" >&2; exit 0; }

# ── jq CALL 1: parse all stdin fields + compute subject in one pass ────────────
#
# Output: 4-column TSV — tool_name, session_id, cwd, subject
# subject is the string we pattern-match against (command for Bash, file_path
# for Read/Edit/Write, notebook_path for NotebookEdit).
INPUT=$(cat) || exit 0
IFS=$'\t' read -r TOOL_NAME SESSION_ID CWD SUBJECT \
    < <(echo "$INPUT" | jq -r '
        .tool_name as $t |
        [
            .tool_name        // "",
            .session_id       // "",
            .cwd              // "",
            (if $t == "Bash" then (.tool_input.command // "")
             elif $t == "Read" or $t == "Edit" or $t == "Write"
                 then (.tool_input.file_path // "")
             elif $t == "NotebookEdit"
                 then (.tool_input.notebook_path // .tool_input.file_path // "")
             else (.tool_input | to_entries[0]?.value? // "")
             end)
        ] | @tsv
    ' 2>/dev/null) || exit 0

# ── Normalize jq @tsv escapes in SUBJECT ──────────────────────────────────────
#
# jq @tsv encodes real newlines as literal \n (backslash-n), tabs as \t, CRs
# as \r, and doubles every backslash.  Without decoding, a multi-line Bash
# command arrives as a single string where the first literal 'n' after '\n'
# merges with the following word, breaking all \b-anchored patterns from line 2
# onward.
#
# Decode order matters: protect \\ with a sentinel FIRST so that the literal
# two-char sequence \n in the original command (stored as \\n by @tsv) is not
# misread as a newline.  Only the four sequences jq actually emits are decoded;
# printf '%b' is NOT used because it also interprets \a, \b (backspace!),
# \xNN, etc., which would mangle legitimate shell arguments.
_pm_s=$'\x01'                               # sentinel byte — won't appear in shell commands
SUBJECT="${SUBJECT//\\\\/${_pm_s}}"         # protect \\ → sentinel
SUBJECT="${SUBJECT//\\n/$'\n'}"             # decode \n  → real newline
SUBJECT="${SUBJECT//\\t/$'\t'}"             # decode \t  → real tab
SUBJECT="${SUBJECT//\\r/$'\r'}"             # decode \r  → real CR
SUBJECT="${SUBJECT//${_pm_s}/\\}"           # restore sentinel → \
unset _pm_s

# ── Flag file ──────────────────────────────────────────────────────────────────
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$CWD}"
[ -z "$PROJECT_DIR" ] && exit 0
FLAG_FILE="${PROJECT_DIR}/.claude/.pm-permissionless.json"
[ -f "$FLAG_FILE" ] || exit 0

# ── jq CALL 2: read flag fields directly (no cat pipe) ────────────────────────
IFS=$'\t' read -r FLAG_NONCE FLAG_EXPIRES_AT \
    < <(jq -r '[.session_id // "", .expires_at // ""] | @tsv' "$FLAG_FILE" 2>/dev/null) || exit 0

# An empty or PENDING nonce means the flag is incomplete / orphaned.
[ -z "$FLAG_NONCE" ]          && exit 0
[ "$FLAG_NONCE" = "PENDING" ] && exit 0

# Session binding: flag must be armed by this exact session.
# A flag written by a different session_id is inert — exit without allowing.
[ "$FLAG_NONCE" != "$SESSION_ID" ] && exit 0

# ── TTL check ──────────────────────────────────────────────────────────────────
[ -z "$FLAG_EXPIRES_AT" ] && exit 0
NOW=$(date -u +%s 2>/dev/null) || exit 0
EXP=$(date -u -d "$FLAG_EXPIRES_AT" +%s 2>/dev/null) || exit 0
if [ "$NOW" -gt "$EXP" ]; then
    rm -f "$FLAG_FILE" 2>/dev/null || true
    exit 0
fi

# ── Locate deny list ───────────────────────────────────────────────────────────
DENY_LIST_FILE="${SCRIPT_DIR}/deny-list.json"
[ -f "$DENY_LIST_FILE" ] || { echo "permissionless-gate: deny-list.json not found at $DENY_LIST_FILE" >&2; exit 0; }

# ── Load per-project overrides ─────────────────────────────────────────────────
OVERRIDES=""
EXEMPT_IDS=()
ACKNOWLEDGE_UNSAFE=()
OVERRIDES_FILE="${PROJECT_DIR}/.claude/pm-deny-overrides.json"

if [ -f "$OVERRIDES_FILE" ]; then
    OVERRIDES=$(cat "$OVERRIDES_FILE" 2>/dev/null) || {
        echo "permissionless-gate: cannot read pm-deny-overrides.json, failing closed" >&2; exit 0
    }
    # jq CALL 3a (overrides): extract exempt and acknowledge_unsafe in one pass
    IFS=$'\t' read -r EXEMPT_CSV UNSAFE_CSV \
        < <(echo "$OVERRIDES" | jq -r '
            if type != "object" then error("not an object") else . end |
            [
                ((.exempt          // []) | join(",")),
                ((.acknowledge_unsafe // []) | join(","))
            ] | @tsv
        ' 2>/dev/null) || {
        echo "permissionless-gate: malformed pm-deny-overrides.json, failing closed" >&2; exit 0
    }
    IFS=',' read -ra EXEMPT_IDS        <<< "$EXEMPT_CSV"
    IFS=',' read -ra ACKNOWLEDGE_UNSAFE <<< "$UNSAFE_CSV"
fi

# ── Helpers ────────────────────────────────────────────────────────────────────
is_exempt() {
    local needle="$1" id
    for id in "${EXEMPT_IDS[@]+"${EXEMPT_IDS[@]}"}"; do
        [ "$id" = "$needle" ] && return 0
    done
    return 1
}

has_ack_unsafe() {
    local needle="$1" id
    for id in "${ACKNOWLEDGE_UNSAFE[@]+"${ACKNOWLEDGE_UNSAFE[@]}"}"; do
        [ "$id" = "$needle" ] && return 0
    done
    return 1
}

# ── Hook-level backstop: warn about unknown exempt ids (plan §6.4) ─────────────
# Fires even if the arming-step validation was skipped or misexecuted.
if [ "${#EXEMPT_IDS[@]}" -gt 0 ] && [ "${EXEMPT_IDS[0]}" != "" ]; then
    # jq CALL 3b (conditional, only when exempt ids present)
    KNOWN_IDS=$(jq -r '[.rules[].id] | join(",")' "$DENY_LIST_FILE" 2>/dev/null) || KNOWN_IDS=""
    for eid in "${EXEMPT_IDS[@]}"; do
        [ -z "$eid" ] && continue
        case ",$KNOWN_IDS," in
            *",$eid,"*) ;;
            *) echo "permissionless-gate: unknown exempt id '${eid}' in pm-deny-overrides.json — no matching rule in deny-list.json (inert)" >&2 ;;
        esac
    done
fi

# ── jq CALL 3 (or 4): extract ALL rule fields in one pass, loop is pure shell ──
#
# Columns (TSV): id  tools(comma-joined)  type  pattern  unless
# Stored in a variable; the while loop uses a here-string — no extra subprocess.
RULES=$(jq -r '.rules[] |
    "\(.id)\t\(.tools | join(","))\t\(.type // "pattern")\t\(.pattern // "")\t\(.unless // "")"
    ' "$DENY_LIST_FILE" 2>/dev/null) \
    || { echo "permissionless-gate: could not read deny-list.json" >&2; exit 0; }

while IFS=$'\t' read -r RULE_ID RULE_TOOLS RULE_TYPE RULE_PATTERN RULE_UNLESS; do
    [ -z "$RULE_ID" ] && continue

    # Tool match — RULE_TOOLS is comma-joined, e.g. "Bash" or "Edit,Write,NotebookEdit"
    case ",$RULE_TOOLS," in
        *",$TOOL_NAME,"*) ;;   # matched
        *) continue ;;
    esac

    # Exemption check (deny-first: exemption only withdraws this shipped rule)
    if is_exempt "$RULE_ID"; then
        if [ "$RULE_ID" = "path-escape" ]; then
            if has_ack_unsafe "path-escape"; then
                continue   # double opt-in satisfied
            else
                echo "permissionless-gate: path-escape in exempt but not in acknowledge_unsafe — not exempting" >&2
                # fall through; rule still applies
            fi
        else
            continue   # rule withdrawn by project override
        fi
    fi

    # ── Boundary rule (path-escape) — realpath, no jq ─────────────────────────
    if [ "$RULE_TYPE" = "boundary" ] && [ "$RULE_ID" = "path-escape" ]; then
        [ -z "$SUBJECT" ] && continue
        RESOLVED=$(realpath -m "$SUBJECT"     2>/dev/null) || continue
        PROJ_ABS=$(realpath -m "$PROJECT_DIR" 2>/dev/null) || continue
        if [ "$RESOLVED" != "$PROJ_ABS" ] && [[ "$RESOLVED" != "${PROJ_ABS}/"* ]]; then
            exit 0   # outside project root — prompt as normal
        fi
        continue
    fi

    # ── Pattern rule — pure grep, no jq ───────────────────────────────────────
    [ -z "$RULE_PATTERN" ] && continue
    [ -z "$SUBJECT" ]      && continue

    if printf '%s\n' "$SUBJECT" | grep -qE -- "$RULE_PATTERN" 2>/dev/null; then
        if [ -n "$RULE_UNLESS" ] && printf '%s\n' "$SUBJECT" | grep -qE -- "$RULE_UNLESS" 2>/dev/null; then
            continue   # unless condition met — allow
        fi
        exit 0   # deny — prompt as normal
    fi

done <<< "$RULES"

# ── Project-added deny rules (cannot be exempted) ─────────────────────────────
if [ -n "$OVERRIDES" ]; then
    # jq CALL 4 (conditional): extract add rules in one pass
    ADD_RULES=$(echo "$OVERRIDES" | jq -r '
        .add[]? | "\(.id)\t\(.tools | join(","))\t\(.pattern // "")"
    ' 2>/dev/null) || ADD_RULES=""

    while IFS=$'\t' read -r _ADD_ID ADD_TOOLS ADD_PATTERN; do
        [ -z "$ADD_PATTERN" ] && continue
        case ",$ADD_TOOLS," in
            *",$TOOL_NAME,"*) ;;
            *) continue ;;
        esac
        [ -z "$SUBJECT" ] && continue
        if printf '%s\n' "$SUBJECT" | grep -qE -- "$ADD_PATTERN" 2>/dev/null; then
            exit 0
        fi
    done <<< "$ADD_RULES"
fi

# ── Allow ──────────────────────────────────────────────────────────────────────
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"permissionless-gate: session-bound flag active, tool cleared deny list"}}\n'
