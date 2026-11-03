#!/usr/bin/env bash
# Claude Code PreToolUse(Bash) hook.
# Enforces the repo rule: never commit or push with red tests or lint.
# Reads the hook JSON and only runs for `git commit` / `git push`, because
# Claude Code does not honour a per-hook `if` filter for Bash matchers.
# Exit 2 blocks the command and feeds stderr back to Claude.
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
INPUT=$(cat 2>/dev/null || true)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

case "$CMD" in
  *"git commit"*|*"git push"*) ;;
  *) exit 0 ;;
esac

FAIL=0

RUFF="$PROJECT_DIR/.venv/bin/ruff"
[ -x "$RUFF" ] || RUFF="ruff"
PY="$PROJECT_DIR/.venv/bin/python"
[ -x "$PY" ] || PY="python3"

if command -v "$RUFF" >/dev/null 2>&1; then
  if ! OUT=$("$RUFF" check "$PROJECT_DIR" 2>&1); then
    echo "ruff check failed — fix before commit/push:" >&2
    printf '%s\n' "$OUT" | head -n 40 >&2
    FAIL=1
  fi
fi

if ! "$PY" -c "import pytest" >/dev/null 2>&1; then
  echo "verify-on-git: pytest is not installed for $PY — skipping the test gate." >&2
elif ! OUT=$(cd "$PROJECT_DIR" && "$PY" -m pytest -q 2>&1); then
  echo "pytest failed — fix before commit/push:" >&2
  printf '%s\n' "$OUT" | tail -n 40 >&2
  FAIL=1
fi

[ "$FAIL" -ne 0 ] && exit 2
exit 0
