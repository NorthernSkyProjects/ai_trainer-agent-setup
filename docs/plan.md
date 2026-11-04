# План: AI-ориентированная среда разработки (Kachlog / ai_trainer)

> Handoff-файл между сессиями Claude Code. Детали — в `docs/memory.md`.
> Новая сессия: «прочитай docs/plan.md и docs/memory.md, продолжи с незакрытой задачи».

## Цель
Собрать окружение, в котором coding-агент знает проект, ограничен в правах и сам проверяет
результат. Критерий готовности: pytest зелёный, ruff чистый, e2e зелёный, hooks и память работают.

## Модуль 1 — базовая среда агента
- [x] 1. AGENTS.md (≤200 строк): стек, команды (вкл. одиночный тест и линтер), конвенции, правила работы.
- [x] 2. Rules с `paths:` — `.claude/rules/python.md`, `templates.md`.
- [x] 3. Skills: `ship-check`, `new-migration`, `new-route`, `e2e-smoke`, `quality-check`, `copy-check`, `gates`.
- [x] 4. Permissions: allow / ask (`git push`) / deny (`.env`, `rm -rf`), режим `acceptEdits`.
- [x] 5. Hooks: линтер после правки + защита файлов (+ verify-on-git, verify-on-stop).
- [x] 6. Память: `docs/plan.md`, `docs/memory.md`.
- [x] 7. e2e-тест Playwright (opt-in, вне CI-гейта).
- [x] 8. Демо на dev-стенде и скриншоты: блок `.env`, линтер, продолжение по памяти, зелёный e2e, paths-rule.
- [x] 9. Вставить скриншоты в `docs/about.md` и запушить.

## Модуль 2 — агентно-ориентированный пайплайн (GSD)
- [x] 10. Node 24 + GSD Core 1.20.0 (`--claude --local`).
- [x] 11. claude-mem 15.9.0 (`--provider claude`, локальная SQLite, worker).
- [x] 12. Discovery: `/gsd-map-codebase`, `/gsd-onboard`, `/gsd-new-project --auto @README.md`.
- [x] 13. Артефакты: `PROJECT`, `REQUIREMENTS`, `ROADMAP`, `STATE`, `codebase/*`, `research/*`, `01-CONTEXT`.
- [x] 14. План Phase 1 (`01-01-PLAN.md`) + `SECURITY-CHECKLIST.md` + progress report.
- [x] 15. Быстрые команды `/ctx`, `/handoff`, `/check`, `/discover` + auto hooks/statusline.
- [x] 16. Документация модуля 2 (`docs/module2.md`, `verification.md`, `screenshot-guide.md`).
- [x] 17. Снять обязательные живые кадры: `/context` до (11%) и после `/compact` (7%);
      `10`/`11` (`/gsd-pause-work`, recall) — опциональны, для сдачи не требуются.

## Критерий готовности
`pytest` зелёный + `ruff check .` чистый + `pytest -m e2e` зелёный + hooks воспроизводимы +
Discovery/план/чек-лист/память проверяемы по `docs/module2/verification.md`.

## Как продолжить
«прочитай docs/plan.md и docs/memory.md, продолжи с задачи 17» — затем перегенерировать
`/gsd-plan-phase 1 --auto --skip-research` и приступать к `/gsd-execute-phase 1`.
