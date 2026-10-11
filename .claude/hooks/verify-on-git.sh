#!/usr/bin/env bash
# Claude Code PreToolUse(Bash) hook, registered for `git commit`/`git push`.
# Enforces the repo rule: never commit or push with red tests or lint.
# Exit 2 blocks the command and feeds stderr back to Claude.
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
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

if ! OUT=$(cd "$PROJECT_DIR" && "$PY" -m pytest -q 2>&1); then
  echo "pytest failed — fix before commit/push:" >&2
  printf '%s\n' "$OUT" | tail -n 40 >&2
  FAIL=1
fi

[ "$FAIL" -ne 0 ] && exit 2
exit 0
