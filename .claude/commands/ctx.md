---
description: Show context usage, GSD progress and the next action
---
Report the current working context in under 15 lines:

1. If `.planning/` exists, run `node .claude/gsd-core/bin/gsd-tools.cjs query planning inspect` and read `.planning/STATE.md`.
2. State the active milestone, phase and status.
3. State the next concrete action from `STATE.md` or `docs/plan.md`.
4. If a context percentage is available, report it.
