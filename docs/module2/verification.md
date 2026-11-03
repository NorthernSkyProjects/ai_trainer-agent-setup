# Проверка модуля 2

Формат: `CHECK` — команда, `EXPECT` — ожидаемый результат. Запускать из корня репозитория.
Часть команд требует установленного GSD и claude-mem; на чистом клоне сначала выполните
`scripts/install-agent-env.sh`.

| # | CHECK | EXPECT |
|---|---|---|
| 1 | `test -f .planning/PROJECT.md && test -f .planning/REQUIREMENTS.md && test -f .planning/ROADMAP.md && test -f .planning/STATE.md` | exit 0 |
| 2 | `test -f .planning/codebase/ARCHITECTURE.md && test -f .planning/codebase/CONCERNS.md` | exit 0 |
| 3 | `test -f .planning/SECURITY-CHECKLIST.md` | exit 0 |
| 4 | `test -f .planning/phases/01-safety-net-module-structure/01-01-PLAN.md` | exit 0 |
| 5 | `test -f .planning/onboarding/SUMMARY.md` | exit 0 |
| 6 | `node .claude/gsd-core/bin/gsd-tools.cjs progress` | Phase 1, `plans: 1`, `status: "Planned"` |
| 7 | `node .claude/gsd-core/bin/gsd-tools.cjs planning inspect` | JSON, `schema_version: 1` |
| 8 | `npx claude-mem doctor` | обязательные проверки зелёные (Bun, uv, plugin, launcher, worker, Claude Code) |
| 9 | `npx claude-mem search "Kachlog" \| head -1` | `Found ... result(s)` |
| 10 | `jq -r '.hooks \| keys[]' .claude/settings.json` | `SessionStart`, `PreToolUse`, `PostToolUse`, `Stop`, `SubagentStop`, `PreCompact`, `FileChanged` |
| 11 | `jq -r '.statusLine.type' .claude/settings.json` | `command` |
| 12 | `grep -q 'protect-files.sh' .claude/settings.json && grep -q 'gsd-context-monitor.js' .claude/settings.json` | exit 0 |
| 13 | `grep -q 'lint-python.sh' .claude/settings.json` | exit 0 |
| 14 | `test -x .claude/hooks/protect-files.sh && test -x .claude/hooks/lint-python.sh` | exit 0 |
| 15 | `git ls-files \| grep -E '(^\|/)\\.env$\|settings\\.local\|instance/'` | пусто |
| 16 | `ls screenshots/module2/*.png` | не менее 7 файлов |
| 17 | `.venv/bin/ruff check .` (в клоне ai_trainer) | `All checks passed!` |
| 18 | `.venv/bin/python -m pytest -q` (в клоне ai_trainer) | все тесты passed |
| 19 | `bash -c 'printf "{\\"tool_input\\":{\\"file_path\\":\\".env\\"}}" \| .claude/hooks/protect-files.sh'` | `Blocked: '.env' ...`, exit 2 |
| 20 | `bash -c 'printf "print(undefined_name)\\n" > /tmp/x.py; printf "{\\"tool_input\\":{\\"file_path\\":\\"/tmp/x.py\\"}}" \| .claude/hooks/lint-python.sh'` | `F821 Undefined name`, exit 2 |

## Скриншоты

Обязательные кадры:

- `01-env-block.png` — блокировка `.env`.
- `02-posttool-lint.png` — PostToolUse ruff.
- `03-memory-recall.png` — память claude-mem.
- `04-discovery.png` — артефакты Discovery.
- `05-progress.png` — progress/roadmap.
- `06-commands.png` — быстрые команды.
- `07-hooks-statusline.png` — hooks/statusline.
- `08-context-before.png` / `09-context-after.png` — usage до/после сжатия.
- `10-checkpoint.png` — `/gsd-pause-work`.
- `11-memory-live.png` — recall после `/clear`.

Живые кадры снимаются по `docs/module2/screenshot-guide.md`.

## Ограничения

- Репозиторий — снимок; GSD-движок (`.claude/gsd-core/`) не вендорится, его ставит
  `scripts/install-agent-env.sh`.
- `01-01-PLAN.md` создан из артефактов Discovery после лимита сессии Claude Code;
  это план, а не выполненная фаза.
- `/gsd-execute-phase 1` и `/gsd-secure-phase 1` не запускались.
