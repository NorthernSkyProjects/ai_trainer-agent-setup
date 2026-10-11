# План: AI-ориентированная среда разработки (IronMind)

> Handoff-файл между сессиями Claude Code. Детали — в `docs/memory.md`.
> Новая сессия: «прочитай docs/plan.md и docs/memory.md, продолжи с незакрытой задачи».

## Цель
Собрать окружение, в котором coding-агент знает проект, ограничен в правах и сам проверяет
результат. Критерий готовности: pytest зелёный, ruff чистый, e2e зелёный, hooks и память работают.

## Задачи
- [x] 1. AGENTS.md (≤200 строк): стек, команды (вкл. одиночный тест и линтер), конвенции, правила работы.
- [x] 2. Rules с `paths:` — `.claude/rules/python.md`, `templates.md`.
- [x] 3. Skills: `ship-check`, `new-migration`, `new-route`, `e2e-smoke`, `quality-check`, `copy-check`, `gates`.
- [x] 4. Permissions: allow / ask (`git push`) / deny (`.env`, `rm -rf`), режим `acceptEdits`.
- [x] 5. Hooks: линтер после правки + защита файлов (+ verify-on-git, verify-on-stop).
- [x] 6. Память: `docs/plan.md`, `docs/memory.md`.
- [x] 7. e2e-тест Playwright (opt-in, вне CI-гейта).
- [ ] 8. Демо на dev-стенде и скриншоты: блок `.env`, линтер, продолжение по памяти, зелёный e2e, paths-rule.
- [ ] 9. Вставить скриншоты в `docs/about.md` и запушить.

## Критерий готовности
`pytest` зелёный + `ruff check .` чистый + `pytest -m e2e` зелёный + hooks воспроизводимы.

## Как продолжить
«прочитай docs/plan.md и docs/memory.md, продолжи с задачи 8».
