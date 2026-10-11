# Как в проекте устроена работа с coding-агентом

Репозиторий: `https://github.com/NorthernSkyProjects/ai_trainer-agent-setup`
Агент: **Claude Code** (dev-стенд, Финляндия) + общий `AGENTS.md` для OpenCode/Codex.
Документ для сдачи ДЗ «Настройка AI-ориентированной среды разработки».

## 1. Стек и суть проекта

IronMind — Flask-приложение для ведения тренировок с ИИ-генерацией планов (Google Gemini).
Python 3.10, Flask + SQLAlchemy + Flask-Migrate (SQLite), Jinja2-шаблоны; менеджер пакетов — pip,
тестовый раннер — pytest, линтер — ruff; фон через RQ/Redis. Прод — gunicorn + nginx,
деплой автоматический из CI: **push в `main` = деплой в прод**.

Инструкции агента: `AGENTS.md` (стек/команды/конвенции/правила), `CLAUDE.md` (импортирует
`@AGENTS.md`), `.claude/rules/*.md`, `.claude/skills/*`.

## 2. Правило с ограничением по путям и как проверено

Правило: **`.claude/rules/templates.md`** с frontmatter

```yaml
paths:
  - "templates/**"
  - "static/**"
```

Оно подгружается в контекст **только когда агент читает/правит файл под этими путями**, а не на
старте сессии (в отличие от `CLAUDE.md`/`AGENTS.md`). Второе правило — `.claude/rules/python.md`
с `paths: ["**/*.py"]`.

**Как проверили, что работает только для своих файлов:**
1. Запустили Claude Code с отладкой: `claude --debug` (в логе видно, какой `.claude/rules/*.md`
   загружается в момент доступа к файлу).
2. Дали агенту задачу в «своей» папке — поправить `templates/login.html`: в логе грузится
   `rules/templates.md`.
3. Дали задачу в «соседней» — поправить `bp/auth.py`: в логе `rules/templates.md` **не**
   грузится, зато применяется `rules/python.md`.
4. Поведение подтверждается косвенно: правки в шаблонах идут по конвенции `data-*` + `static/ui.js`
   (из `templates.md`), а правки Python — по правилам ruff/фикстур (из `python.md`).

Скриншот сравнения — `screenshots/agent/paths-rule.png`.

## 3. Навыки (skills)

| Навык | Назначение (одна строка) |
|---|---|
| `ship-check` | Проверка перед пушем в `main`: ruff + pytest + статус CI-пайплайна (запускается вручную). |
| `new-migration` | Создать миграцию Alembic после правки `models.py` (вручную). |
| `new-route` | Добавить маршрут/страницу по конвенциям проекта (self-invoked, агент вызывает сам). |
| `e2e-smoke` | Playwright-смоук логина/регистрации на dev-стенде (вручную). |
| `quality-check` | Структурная проверка ИИ-артефактов (план/отчёт): факты, источники, скоринг D/L/C/P (self-invoked). |
| `copy-check` | Очеловечивание русскоязычного UI/отчётного текста, удаление канцелярита (вручную). |
| `gates` | Приёмка задачи: `docs/GATES.md` + опциональный Stop-hook, не даёт завершить ход при красном (вручную). |

Правила (rules): `python.md`, `templates.md`. Рубрика качества ИИ-планов — `docs/plan-eval.md`.

## 4. Права доступа (permissions)

Три уровня в `.claude/settings.json`:
- `allow` — `pytest`, `ruff`, `git status/diff/log/add/commit`, чтение/правка файлов.
- `ask` (человек подтверждает) — `git push`, `systemctl restart`, `flask db upgrade`, `pip install`.
- `deny` — чтение `.env`, `/etc/app.env`, `instance/**`; `rm -rf /*`; `git push --force`.
Режим по умолчанию — `acceptEdits` (скорость правок; риск-команды всё равно под `ask`/`deny`).
Личное — вне git (`.claude/settings.local.json`, `CLAUDE.local.md`).

## 5. Hooks

- `.claude/hooks/lint-python.sh` (PostToolUse `Edit|Write`) — `ruff check --fix` после правки `.py`.
- `.claude/hooks/protect-files.sh` (PreToolUse `Edit|Write`) — блок правок `.env`, `.git/`, `instance/`.
- `.claude/hooks/verify-on-git.sh` (PreToolUse `Bash` для `git commit`/`git push`) — ruff + pytest.
- `.claude/hooks/verify-on-stop.sh` (Stop, опционально) — не даёт завершить ход при красном.

## 6. Память между сессиями

Handoff-файлы: `docs/plan.md` (план с чекбоксами) и `docs/memory.md` (журнал: сделано / решение /
дальше / ловушка). Новая сессия начинает с «прочитай `docs/plan.md` и `docs/memory.md`, продолжи
с задачи N» — агент подхватывает контекст, а не начинает с нуля.

## 7. Проверка UI в браузере

E2E-смоук на **Python Playwright** (`tests/e2e/test_smoke.py`): поднимает тестовое приложение,
проходит сценарий (регистрация → логин), проверяет консоль и сохраняет скриншот
(`screenshots/agent/e2e-smoke.png`). Запуск на dev-стенде (есть chromium):

```bash
.venv/bin/python -m pytest -m e2e tests/e2e -q
```

## 8. Скриншоты

| Файл | Что показывает |
|---|---|
| `screenshots/agent/env-block.png` | Слой прав: правило `deny` не даёт править `.env` («File is covered by a Read deny rule…»). |
| `screenshots/agent/hook-protect.png` | Слой hook: `protect-files.sh` (PreToolUse) блокирует запись в секретный `*.env`. |
| `screenshots/agent/linter.png` | Линтер-гейт: `verify-on-git.sh` останавливает коммит с ошибкой ruff (`F821`). |
| `screenshots/agent/memory.png` | Продолжение работы во второй сессии по `docs/plan.md`/`docs/memory.md`. |
| `screenshots/agent/e2e.png` | Зелёный прогон e2e-теста Playwright (`1 passed`). |
| `screenshots/agent/e2e-smoke.png` | Скриншот страницы, сохраняемый самим e2e-тестом (авто). |
| `screenshots/agent/paths-rule.png` | Ленивая загрузка `rules/templates.md` только для своих файлов. |

`.env` защищён двумя слоями: правилом `deny` (permissions) и хуком `protect-files.sh` (см. `env-block.png` и `hook-protect.png`).
