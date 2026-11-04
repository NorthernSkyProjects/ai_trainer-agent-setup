# Скриншоты модуля 2

Кадры `01`–`07` — реальные выводы команд/хуков, снятые на DEV-стенде и отрендеренные в PNG
(тёмная терминальная тема). Кадры `08`–`09` — настоящие TUI-скрины Claude Code: `/context`
до сжатия (112.1k / 1m, 11%) и после `/compact` (75k / 1m, 7%). Кадры `10`–`11` опциональны
и для сдачи не требуются (инструкция — `docs/module2/screenshot-guide.md`).

| Файл | Команда/событие |
|---|---|
| `01-env-block.png` | `protect-files.sh` с JSON `{"tool_input":{"file_path":".env"}}` |
| `02-posttool-lint.png` | `lint-python.sh` на файле с `print(undefined_name)` |
| `03-memory-recall.png` | `npx claude-mem search "Kachlog"` |
| `04-discovery.png` | `find .planning ...` + `onboarding/SUMMARY.md` |
| `05-progress.png` | `node .claude/gsd-core/bin/gsd-tools.cjs progress` + ROADMAP |
| `06-commands.png` | версия GSD + список 76 команд |
| `07-hooks-statusline.png` | `jq` по hooks и `statusLine` в `settings.json` |
| `08-context-before.png` | `/context` до сжатия (живая сессия) |
| `09-context-after.png` | `/context` после `/compact` (живая сессия) |
| `10-checkpoint.png` | `/gsd-pause-work` → `HANDOFF.json` (живая сессия) |
| `11-memory-live.png` | recall после `/clear` (живая сессия) |

Скриншоты не должны содержать токены, `.env`, cookies, email или иные персональные данные.
