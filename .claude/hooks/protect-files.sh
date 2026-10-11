#!/usr/bin/env bash
# Claude Code PreToolUse(Edit|Write) hook.
# Blocks edits to secrets, git internals and the local DB/data directory.
set -euo pipefail

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE" ] && exit 0

# Normalize Windows backslash separators so the patterns below match.
FILE="${FILE//\\//}"

case "$FILE" in
  .env|*/.env|*.env|*.env.local|*.env.production|*.env.staging)
    echo "Blocked: '$FILE' is a secrets file. Use .env.example for templates; prod env is /etc/app.env." >&2
    exit 2 ;;
  /etc/app.env|*/etc/app.env)
    echo "Blocked: prod env /etc/app.env must not be edited by the agent." >&2
    exit 2 ;;
  .git/*|*/.git/*)
    echo "Blocked: '$FILE' is inside .git/." >&2
    exit 2 ;;
  instance/*|*/instance/*)
    echo "Blocked: '$FILE' is inside instance/ (local DB / exercise media)." >&2
    exit 2 ;;
esac

exit 0
