# Модуль 2. Агентно-ориентированный пайплайн (GSD)

Документ описывает, как на DEV-стенде собрано окружение для проекта **Kachlog / ai_trainer**
и как проверить каждый пункт задания. Скриншоты и артефакты лежат в репозитории.

## 1. Что установлено и где

| Компонент | Версия | Расположение |
|---|---|---|
| Node.js | 24.22.2 | `/usr/local/lib/nodejs/node-v24.22.2-linux-x64`, симлинк `/usr/local/bin/node` |
| npm | 11.19.1 | вместе с Node |
| GSD Core | 1.20.0 | `.claude/gsd-core/`, команды `.claude/commands/gsd-*.md` |
| claude-mem | 15.9.0 | `~/.claude/plugins/cache/thedotmack/claude-mem/15.9.0`, база `~/.claude-mem/claude-mem.db` |
| Python (проект) | 3.12.3 | `.venv` в клоне проекта |
| ruff / pytest | 0.17.3 / 9.2.0 | `.venv/bin/` |

Установка GSD:

```bash
npx @opengsd/gsd-core@1.20.0 --claude --local --relative-includes
```

Установка памяти:

```bash
npx claude-mem@15.9.0 install --ide claude-code --provider claude --no-auto-start
npx claude-mem start
npx claude-mem doctor
```

> GSD 1.20 требует Node ≥24 и npm ≥10. Локальная установка сначала пишет hooks в
> `.claude/settings.local.json`; в этом репозитории они перенесены в версионируемый
> `.claude/settings.json`, а `settings.local.json` очищен, чтобы hooks не дублировались.

## 2. Discovery

Discovery выполнялся на реальном коде `ai_trainer` (клон `/root/ai_trainer-gsd`, main
`2a564d8`), а не на пустом шаблоне.

### Шаги

1. `/gsd-map-codebase` — 4 параллельных mapper-агента, 7 документов в `.planning/codebase/`,
   коммит `2c47005` (`docs: map existing codebase`).
2. `/gsd-onboard --fast --text` — проверка карты и маршрутизация к инициализации;
   повторный запуск после создания планирования дал `.planning/onboarding/SUMMARY.md`
   (коммит `827d071`).
3. `/gsd-new-project --auto @README.md` — интервью заменено извлечением из README:
   `PROJECT.md`, `REQUIREMENTS.md` (36 требований), `ROADMAP.md` (4 фазы), `STATE.md`,
   `config.json`, `research/{STACK,FEATURES,ARCHITECTURE,PITFALLS,SUMMARY}.md`.
4. `/gsd-discuss-phase 1 --auto` — `01-CONTEXT.md` (решения D-01..D-16) и
   `01-DISCUSSION-LOG.md`.
5. `01-PATTERNS.md` — карта аналогов и паттернов для 22 файлов Phase 1.
6. `01-01-PLAN.md` — план Phase 1 (toolchain → test net → module splits).

### Что нашёл Discovery

- `scripts/yandex_art.py` импортирует `requests`, которого нет в `requirements*.txt`.
- Нет lockfile; CI/DEV/PROD могут ставить разные версии.
- Нет error-tracking SDK; ошибки ИИ теряются в `except Exception`.
- `verify-on-git.sh` запускался на любых Bash-командах: Claude Code игнорирует per-hook
  `if`-фильтр. Хук исправлен — теперь сам проверяет `.tool_input.command`.
- `ai_generator` создаёт Redis-клиент на импорте; тесты зависят от окружения.
- Квота ИИ при `memory://` считается на процесс, а не на всех воркеров.
- Внутренние `/healthz` и `/ai_metrics` закрыты только nginx, без in-app проверки.
- Telegram webhook не валидирует длину секрета; при не-ASCII заголовке возможен 500.

### Артефакты

```text
.planning/
  PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md, config.json
  SECURITY-CHECKLIST.md
  onboarding/SUMMARY.md
  codebase/{STACK,ARCHITECTURE,STRUCTURE,CONVENTIONS,TESTING,INTEGRATIONS,CONCERNS}.md
  research/{STACK,FEATURES,ARCHITECTURE,PITFALLS,SUMMARY}.md
  phases/01-safety-net-module-structure/
    01-CONTEXT.md, 01-DISCUSSION-LOG.md, 01-PATTERNS.md, 01-01-PLAN.md
  reports/PROGRESS-2026-11-03.md
```

`gsd-tools progress` после создания плана:

```json
{
  "phases": [
    {"number": "01", "name": "safety net module structure", "plans": 1, "summaries": 0, "status": "Planned"}
  ],
  "total_plans": 1,
  "total_summaries": 0,
  "percent": 0
}
```

## 3. Память агента

### claude-mem

- Провайдер: Anthropic plan (`--provider claude`), без регистрации и облачной синхронизации.
- База: `~/.claude-mem/claude-mem.db`; worker: `http://127.0.0.1:37700`.
- Данные: 100 наблюдений и 18 промптов по проекту (на 2026-11-03).
- Поиск: `npx claude-mem search "Kachlog"` → 118 результатов.
- Recall после `/clear`: новая сессия видит наблюдения предыдущей; живой кадр —
  `screenshots/module2/11-memory-live.png` (инструкция ниже).

> **Эксплуатационная заметка (2026-11-03).** После Discovery воркер остановлен
> (`npx claude-mem stop`), плагин временно отключён (`claude plugin disable claude-mem@thedotmack`),
> чтобы фоновые суммаризации не расходовали 5-часовой лимит Claude. 38 наблюдений остаются
> в буфере; включить обратно: `claude plugin enable claude-mem@thedotmack && npx claude-mem start`.

### GSD native memory

- `STATE.md` — позиция, решения, блокеры, следующий шаг.
- `01-CONTEXT.md` / `01-PATTERNS.md` — решения и паттерны фазы.
- `HANDOFF.json` + `continue-here.md` — создаются `/gsd-pause-work`, читаются
  `/gsd-resume-work`.
- `docs/plan.md`, `docs/memory.md` — handoff модуля 1, дополнен записью о модуле 2.

## 4. Быстрые команды

72 команды GSD + 4 проектные:

| Команда | Назначение |
|---|---|
| `/gsd-onboard` | Первичный onboarding существующего репозитория |
| `/gsd-map-codebase` | Карта стека, архитектуры, конвенций, рисков |
| `/gsd-new-project` | PROJECT / REQUIREMENTS / ROADMAP / STATE + research |
| `/gsd-plan-phase N` | Research + plan + проверка плана |
| `/gsd-execute-phase N` | Исполнение плана волнами в свежих субагентах |
| `/gsd-verify-work N` | UAT/верификация выполненной фазы |
| `/gsd-secure-phase N` | Security-аудит фазы |
| `/gsd-progress` | Где мы, что дальше |
| `/gsd-pause-work` / `/gsd-resume-work` | Чек-пойнт и восстановление после `/clear` |
| `/ctx` | Контекст + прогресс + следующее действие |
| `/handoff` | Чек-пойнт + запись в `docs/memory.md` |
| `/check` | ruff + pytest перед коммитом |
| `/discover` | Карта + onboarding одной командой |

## 5. Auto hooks

`.claude/settings.json` содержит 23 hook-блока на событиях `SessionStart`, `PreToolUse`,
`PostToolUse`, `Stop`, `SubagentStop`, `PreCompact`, `FileChanged`.

Модуль 1:

- `protect-files.sh` — PreToolUse, блокирует `*.env`, `.git/`, `instance/`.
- `lint-python.sh` — PostToolUse, `ruff check --fix` и возврат оставшихся ошибок агенту.
- `verify-on-git.sh` — PreToolUse, ruff + pytest перед `git commit`/`git push`;
  сам фильтрует не-git команды.
- `verify-on-stop.sh` — Stop, включается маркером `.claude/.verify-on-stop`.

GSD:

- `gsd-secret-read-guard.js` — не даёт читать секреты.
- `gsd-prompt-guard.js`, `gsd-read-guard.js`, `gsd-read-injection-scanner.js` — защита контекста.
- `gsd-context-monitor.js` — предупреждения о контексте на `PostToolUse`, `Stop`, `PreCompact`.
- `gsd-statusline.js` — statusline с процентом контекста.
- `gsd-validate-commit.sh`, `gsd-workflow-guard.js`, `gsd-write-guard.js` и др.

## 6. Управление контекстом

- Statusline: модель, текущая задача, каталог, шкала контекста.
- Context monitor: WARNING при ≤35% остатка, CRITICAL при ≤25%; после `PreCompact`
  состояние сбрасывается, чтобы новый цикл начинался с чистого листа.
- Автосжатие: `/compact` или автоматическая компакция Claude Code. Сравнение
  «usage до/после» — `08-context-before.png` и `09-context-after.png`.
- Чек-пойнты: `/gsd-pause-work` пишет `HANDOFF.json` и `continue-here.md`;
  `/gsd-resume-work` восстанавливает позицию после `/clear`.
- Порог можно переопределить в `.planning/config.json`:
  `hooks.context_warning_threshold`, `hooks.context_critical_threshold`.

## 7. Безопасность

`.planning/SECURITY-CHECKLIST.md` содержит 10 разделов и статусы. Ключевое:

- секреты только в `/etc/ai_trainer.env` и dev `.env`; `.env`/`instance/**` запрещены агенту;
- CSRF глобально, webhook — единственное исключение (проверяется тестом FND-08);
- `/healthz` и `/ai_metrics` закрыты nginx на localhost; SEC-01 добавит in-app проверку;
- Telegram webhook: SEC-02 (длина секрета, bytes compare, безопасное отключение);
- AI boundary: AIE-01..08 (закрытый набор reason code, без provider text);
- квота: SEC-04 (предупреждение при `memory://` и >1 воркере);
- agent layer: deny/ask/allow, hooks, отсутствие секретов в git и на скриншотах.

## 8. Как проверить

См. `docs/module2/verification.md`. Коротко:

```bash
node .claude/gsd-core/bin/gsd-tools.cjs progress
node .claude/gsd-core/bin/gsd-tools.cjs planning inspect
npx claude-mem doctor
npx claude-mem search "Kachlog" | head
jq -r '.hooks | keys[]' .claude/settings.json
.venv/bin/ruff check . && .venv/bin/python -m pytest -q
```

## 9. Ограничения

- Планировщик GSD остановился на лимите сессии Claude Code после `01-PATTERNS.md`.
  `01-01-PLAN.md` собран из `CONTEXT`/`PATTERNS`/`ROADMAP` и является планом, а не
  выполненной фазой. Перегенерация: `/gsd-plan-phase 1 --auto --skip-research`.
- `/gsd-execute-phase 1` не запускался: он меняет код. Следующий шаг — отдельная ветка.
- `/gsd-secure-phase 1` требует выполненной фазы; `SECURITY-CHECKLIST.md` — baseline.
- Исходный код и `tests/e2e` — в приватном GitLab; здесь только снимок окружения.
