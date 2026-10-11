#!/usr/bin/env bash
# Claude Code Stop hook. Opt-in structural backstop (unlazy-style).
#
# Disabled by default. Enabled when a marker exists:
#   .claude/.verify-on-stop        -> run `ruff check .` before allowing stop
#   .claude/.verify-on-stop-full   -> also run full `pytest -q` (slower)
# If lint/tests are red, exit 2 blocks stopping (Claude sees stderr and keeps working).
# Progress guard: after MAX consecutive blocks for a session, release (never wedge).
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
MARKER="$PROJECT_DIR/.claude/.verify-on-stop"
[ -f "$MARKER" ] || exit 0

INPUT=$(cat)
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
[ -z "$SESSION" ] && SESSION="unknown"

GUARD_DIR="$PROJECT_DIR/.claude/.stop-guard"
mkdir -p "$GUARD_DIR"
GUARD="$GUARD_DIR/$SESSION"
COUNT=$(cat "$GUARD" 2>/dev/null || echo 0)
case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac
MAX=5

if [ "$COUNT" -ge "$MAX" ]; then
  echo "verify-on-stop: releasing after $MAX consecutive blocks (progress guard). Fix the repo manually." >&2
  exit 0
fi

RUFF="$PROJECT_DIR/.venv/bin/ruff"
[ -x "$RUFF" ] || RUFF="ruff"
PY="$PROJECT_DIR/.venv/bin/python"
[ -x "$PY" ] || PY="python3"

FAIL=0

if command -v "$RUFF" >/dev/null 2>&1; then
  if ! OUT=$("$RUFF" check "$PROJECT_DIR" 2>&1); then
    echo "verify-on-stop: ruff check failed — fix before finishing:" >&2
    printf '%s\n' "$OUT" | head -n 30 >&2
    FAIL=1
  fi
fi

if [ -f "$PROJECT_DIR/.claude/.verify-on-stop-full" ]; then
  if ! OUT=$(cd "$PROJECT_DIR" && "$PY" -m pytest -q 2>&1); then
    echo "verify-on-stop: pytest failed — fix before finishing:" >&2
    printf '%s\n' "$OUT" | tail -n 30 >&2
    FAIL=1
  fi
fi

if [ "$FAIL" -ne 0 ]; then
  echo $((COUNT + 1)) > "$GUARD"
  exit 2
fi

rm -f "$GUARD"
exit 0
