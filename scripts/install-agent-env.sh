#!/usr/bin/env bash
# Reproduce the module-2 agent environment (Node 24 + GSD Core + claude-mem).
# Usage: ./scripts/install-agent-env.sh [project-root]
# The project root defaults to the current directory and must be the repo root.
set -euo pipefail

ROOT="${1:-$(pwd)}"
cd "$ROOT"

export PATH="$HOME/.local/bin:$PATH"

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is missing. Install Node 24 LTS from https://nodejs.org/ and re-run." >&2
  exit 1
fi

NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
if [ "$NODE_MAJOR" -lt 24 ]; then
  echo "GSD Core 1.20 needs Node >=24 (found $(node -v)). Install Node 24 LTS and re-run." >&2
  exit 1
fi

echo "==> Node $(node -v), npm $(npm -v)"

echo "==> Installing GSD Core 1.20.0 (local, project-relative includes)"
npx --yes @opengsd/gsd-core@1.20.0 --claude --local --relative-includes

echo "==> Installing claude-mem 15.9.0 (Anthropic plan, local SQLite)"
npx --yes claude-mem@15.9.0 install --ide claude-code --provider claude --no-auto-start

echo "==> Starting the claude-mem worker"
npx --yes claude-mem@15.9.0 start || true

echo "==> Merging GSD hooks/statusline into the tracked .claude/settings.json"
python3 - <<'PY'
import copy
import json
import os

project = ".claude/settings.json"
local = ".claude/settings.local.json"
if not os.path.exists(project):
    raise SystemExit("missing .claude/settings.json")
settings = json.load(open(project))

if os.path.exists(local):
    data = json.load(open(local))

    def dedupe(seq):
        seen, out = set(), []
        for item in seq:
            key = json.dumps(item, sort_keys=True, ensure_ascii=False)
            if key not in seen:
                seen.add(key)
                out.append(item)
        return out

    hooks = settings.setdefault("hooks", {})
    for event, entries in data.get("hooks", {}).items():
        hooks[event] = dedupe(hooks.get(event, []) + entries)

    permissions = settings.setdefault("permissions", {})
    for key in ("allow", "ask", "deny"):
        if key in data.get("permissions", {}):
            permissions[key] = dedupe(permissions.get(key, []) + data["permissions"][key])

    for key, value in data.items():
        if key in ("hooks", "permissions"):
            continue
        settings[key] = value

    for key in ("hooks", "permissions", "worktree", "statusLine"):
        data.pop(key, None)
    with open(local, "w") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")

with open(project, "w") as fh:
    json.dump(settings, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print("merged hooks:", {k: len(v) for k, v in settings.get("hooks", {}).items()})
PY

echo "==> Verifying"
npx --yes claude-mem@15.9.0 doctor || true
node .claude/gsd-core/bin/gsd-tools.cjs progress || true
echo
echo "Done. Next: open Claude Code in this directory and run /gsd-progress"
