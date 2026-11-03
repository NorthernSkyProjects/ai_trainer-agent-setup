# Журнал изменений (handoff-память)

> Аппенд-лог решений между сессиями Claude Code. Новые записи — сверху.
> Формат: сделано / решение / дальше / ловушка.

## 2026-11-03 — модуль 2 (GSD)
- Сделано: Node 24.22.2, GSD Core 1.20.0 (локально), claude-mem 15.9.0 (`--provider claude`).
  На клоне `ai_trainer` пройден Discovery: `/gsd-map-codebase` (7 документов),
  `/gsd-onboard` (`SUMMARY.md`), `/gsd-new-project --auto @README.md` (36 требований, 4 фазы),
  `01-CONTEXT.md`, `01-PATTERNS.md`, `01-01-PLAN.md`, `SECURITY-CHECKLIST.md`.
- Решение: GSD-движок не вендорим (15 МБ); в репозитории — settings, hooks, команды,
  артефакты `.planning/` и install-скрипт. GSD-hooks перенесены из `settings.local.json`
  в версионируемый `.claude/settings.json`.
- Квота: claude-mem observer сделал 39 фоновых сессий (~846k output + ~933k cache-write)
  и вместе с Discovery исчерпал 5-часовой лимит Claude. Воркер остановлен, плагин временно
  отключён; 38 наблюдений остаются в буфере до следующего включения.
- Дальше: снять живые кадры `/context` до/после (`/compact`), опционально recall.
  Затем перегенерировать план Phase 1 и выполнять фазу на отдельной ветке.
- Ловушка: Claude Code игнорирует per-hook `if` для Bash, поэтому `verify-on-git.sh` сам
  проверяет `.tool_input.command`; иначе он срабатывает на любой Bash-команде. GSD 1.20
  требует Node ≥24. Лимит сессии Claude Code остановил планировщик после `01-PATTERNS.md`.

## 2026-10-11 — модуль 1
- Сделано: инфраструктура агента в `.claude/` — permissions (allow/ask/deny, `acceptEdits`),
  hooks (`lint-python.sh`, `protect-files.sh`, `verify-on-git.sh`, `verify-on-stop.sh`),
  rules с `paths:` (`python.md`, `templates.md`), 7 навыков, `docs/plan-eval.md`.
  Handoff-файлы `docs/plan.md` и `docs/memory.md`.
- Решение: не вендорить внешний `humanizer-ru` (98 КБ) — сделан лёгкий `/copy-check`.
  Браузерная проверка — Python Playwright (Node/npx на dev-стенде нет).
- Дальше: задача 8 из `docs/plan.md` — снять скриншоты на dev-стенде и вставить в `docs/about.md`.
- Ловушка: `verify-on-stop.sh` включается **только** маркером `.claude/.verify-on-stop`; иначе
  бездействует. Правки `.env` блокирует hook `protect-files.sh` ещё до записи.

## Шаблон (для будущих записей)
- Сделано:
- Решение:
- Дальше:
- Ловушка:
