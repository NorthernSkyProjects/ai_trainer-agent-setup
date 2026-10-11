# IronMind — окружение для coding-агента

Набор файлов, показывающий, как настроена AI-ориентированная среда разработки для проекта
**IronMind** (Flask-приложение для ведения тренировок с ИИ-генерацией планов). Здесь — только
конфигурация агента (инструкции, правила, навыки, права, hooks, память, скриншоты); исходный
код приложения не входит.

Агент: **Claude Code** (на dev-стенде) + общий `AGENTS.md` (читают также OpenCode/Codex).

## Структура

```
AGENTS.md                 # инструкции: стек, команды, конвенции, правила работы
CLAUDE.md                 # файл для Claude Code (@AGENTS.md + разбивка)
docs/about.md             # отчёт: стек, paths-правило, навыки, права, hooks, скриншоты
docs/plan.md, memory.md   # память между сессиями (handoff)
docs/plan-eval.md         # рубрика оценки ИИ-планов
.claude/settings.json     # permissions (allow/ask/deny) + hooks
.claude/hooks/*.sh        # lint-python, protect-files, verify-on-git, verify-on-stop
.claude/rules/*.md        # правила с paths: (python, templates)
.claude/skills/*          # навыки (SKILL.md)
screenshots/agent/*.png   # доказательства работы
```

## Как агент работает в проекте

**Какие инструкции агент читает**
- `AGENTS.md` — открытый стандарт (стек, команды, конвенции, правила работы), ≤200 строк.
- `CLAUDE.md` — для Claude Code; импортирует `@AGENTS.md`.
- `.claude/rules/*.md` с `paths:` — правила, которые подгружаются **лениво** только для своих
  файлов: `python.md` (для `*.py`), `templates.md` (для `templates/**`, `static/**`).
- `.claude/skills/` — переиспользуемые навыки (см. `docs/about.md`).

**Какие у него права** (`.claude/settings.json`)
- `allow`: `pytest`, `ruff`, `git status/diff/log/add/commit`, чтение и правка файлов.
- `ask` (подтверждает человек): `git push` (**push в `main` = деплой в прод**), `systemctl restart`,
  `flask db upgrade`, `pip install`.
- `deny`: чтение `.env`/прод-секретов, доступ к `instance/`, `rm -rf /*`, `git push --force`.
- Режим по умолчанию — `acceptEdits`: правки файлов идут без лишних подтверждений для скорости,
  но рискованные shell-команды и запись в защищённые пути остаются под контролем (`ask`/`deny`).
- Личные настройки — вне git (`.claude/settings.local.json`, `CLAUDE.local.md`).

**Какие проверки его страхуют** (hooks)
- `.claude/hooks/lint-python.sh` — после правки `.py` прогоняет `ruff check --fix`.
- `.claude/hooks/protect-files.sh` — блокирует правки `.env`, `.git/`, `instance/`.
- `.claude/hooks/verify-on-git.sh` — перед `git commit`/`git push` гоняет ruff + pytest; красное блокирует.
- `.claude/hooks/verify-on-stop.sh` — опциональный Stop-hook (маркер `.claude/.verify-on-stop`).

**Память между сессиями**
`docs/plan.md` (план с чекбоксами) и `docs/memory.md` (журнал: сделано / решение / дальше / ловушка).
Новая сессия продолжает с «прочитай `docs/plan.md` и `docs/memory.md`, продолжи с задачи N».

**Проверка UI в браузере**
E2E-смоук на Python Playwright: `tests/e2e` (в этом наборе кода приложения нет, но тест описан в
`docs/about.md`). Запуск: `.venv/bin/python -m pytest -m e2e tests/e2e -q`.

**Как запустить тесты** (в полном проекте)
```bash
pip install -r requirements-dev.txt
pytest                                 # все тесты; один — pytest tests/test_workout.py::test_name
ruff check .                           # линтер
```
