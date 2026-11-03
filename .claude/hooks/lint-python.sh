#!/usr/bin/env bash
# Claude Code PostToolUse(Edit|Write) hook.
# Applies safe ruff autofixes to edited Python files and surfaces what remains.
# `ruff format` is intentionally NOT run (the codebase is not ruff-format'ed).
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
INPUT=$(cat 2>/dev/null || true)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
[ -z "$FILE" ] && exit 0

case "$FILE" in
  *.py) ;;
  *) exit 0 ;;
esac
[ -f "$FILE" ] || exit 0

RUFF="$PROJECT_DIR/.venv/bin/ruff"
[ -x "$RUFF" ] || RUFF="ruff"
command -v "$RUFF" >/dev/null 2>&1 || exit 0

OUT=$("$RUFF" check --fix "$FILE" 2>&1)
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
  echo "ruff check --fix left issues in $FILE:" >&2
  printf '%s\n' "$OUT" >&2
  exit 2
fi
exit 0
