# Журнал изменений (handoff-память)

> Аппенд-лог решений между сессиями Claude Code. Новые записи — сверху.
> Формат: сделано / решение / дальше / ловушка.

## 2026-10-11
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
