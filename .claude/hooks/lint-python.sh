#!/usr/bin/env bash
# Claude Code PostToolUse(Edit|Write) hook.
# Applies safe ruff autofixes to edited Python files.
# NOTE: `ruff format` is intentionally NOT run (the codebase is not ruff-format'ed).
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE" ] && exit 0

case "$FILE" in
  *.py) ;;
  *) exit 0 ;;
esac
[ -f "$FILE" ] || exit 0

RUFF="$PROJECT_DIR/.venv/bin/ruff"
[ -x "$RUFF" ] || RUFF="ruff"
command -v "$RUFF" >/dev/null 2>&1 || exit 0

"$RUFF" check --fix "$FILE" >/dev/null 2>&1 || true
exit 0
