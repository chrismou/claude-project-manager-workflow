#!/usr/bin/env bash
# session-cleanup.sh — SessionStart / SessionEnd cleanup for pm-auto
#
# SessionStart: remove the flag if it is orphaned (PENDING / empty session_id)
#   or expired.  Non-expired flags belonging to another live session are left
#   in place — the hook's session_id binding ensures they are inert in this session.
#
# SessionEnd: delete the flag unconditionally — the session that armed it is done.
#
# Invocation: session-cleanup.sh <start|end>
# Hook stdin is a JSON object; PROJECT_DIR falls back to .cwd from stdin.

exec 2>>"${TMPDIR:-/tmp}/pm-gate.log"
trap 'exit 0' ERR

EVENT="${1:-}"

INPUT=$(cat 2>/dev/null) || INPUT="{}"
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null) || CWD=""

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$CWD}"
[ -z "$PROJECT_DIR" ] && exit 0

FLAG_FILE="${PROJECT_DIR}/.claude/.pm-permissionless.json"
[ -f "$FLAG_FILE" ] || exit 0

case "$EVENT" in
    start)
        if command -v jq &>/dev/null; then
            FLAG_NONCE=$(jq -r '.session_id // ""' "$FLAG_FILE" 2>/dev/null) || FLAG_NONCE=""

            # Delete orphaned/incomplete flags
            if [ -z "$FLAG_NONCE" ] || [ "$FLAG_NONCE" = "PENDING" ]; then
                rm -f "$FLAG_FILE" 2>/dev/null || true
                exit 0
            fi

            # Delete expired flags
            FLAG_EXPIRES_AT=$(jq -r '.expires_at // ""' "$FLAG_FILE" 2>/dev/null) || FLAG_EXPIRES_AT=""
            if [ -n "$FLAG_EXPIRES_AT" ]; then
                NOW=$(date -u +%s 2>/dev/null) || NOW=0
                EXP=$(date -u -d "$FLAG_EXPIRES_AT" +%s 2>/dev/null) || EXP=0
                if [ "$NOW" -gt "$EXP" ]; then
                    rm -f "$FLAG_FILE" 2>/dev/null || true
                fi
            fi
        fi
        # A valid, non-expired flag from another session is left in place.
        # The hook's session_id binding makes it inert in this session anyway.
        ;;
    end)
        # Remove unconditionally — the session that armed is done.
        rm -f "$FLAG_FILE" 2>/dev/null || true
        ;;
    *)
        ;;
esac

exit 0
