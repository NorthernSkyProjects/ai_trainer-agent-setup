# CLAUDE.md

@AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

IronMind — Flask app for gym workout tracking with AI-generated plans (Google Gemini). Project docs are in Russian; `AGENTS.md` and `README.md` hold more detail.

Two environments, one repo: **PROD** — nginx + gunicorn `ai_trainer.service` + RQ `ai_trainer_worker.service`, env outside the repo; **DEV** — dev stand (`.venv`, local redis, RQ worker) where Claude Code runs. Push to `main` auto-deploys to PROD via CI (`test` → `deploy-prod`); the `test` stage blocks deploy on red.

## Commands

```bash
pip install -r requirements-dev.txt     # prod deps + pytest, ruff, playwright
cp .env.example .env                    # set GOOGLE_API_KEY, SECRET_KEY
python app.py                           # dev server on :5000
gunicorn -w 2 --timeout 240 -b 127.0.0.1:5000 app:app   # prod-style

pytest                                  # all tests (testpaths=tests)
pytest tests/test_workout.py::test_name # single test
ruff check .                            # lint (CI runs ruff + pytest on Python 3.10)

flask --app app db upgrade              # apply migrations
flask --app app db migrate -m "msg"     # autogenerate after editing models.py (never hand-write migrations)
flask --app app create-user --email ... --name ...   # no admin is auto-created
flask --app app import-exercises        # load exercise catalog into DB
flask --app app import-exercise-media --manifest data/exercise_media_manifest.json
python scripts/build_exercise_seed.py   # rebuild data/exercises_seed.json from ru_catalog + exercises_ru overlays
```

Tests set up an isolated temp SQLite DB and env in `tests/conftest.py` *before* importing `app`; keep that ordering. Use the `app` fixture (drops/creates tables per test, CSRF off).

## Architecture

- **`app.py` is no longer "the file with all routes"** (~250 lines): it only creates the app, initialises extensions, registers blueprints, and holds Flask-Login handlers, security headers, error handlers and the `static_url` helper. Timezone is forced to `Europe/Moscow`. Entry points are unchanged: `app:app` for gunicorn/flask, and the RQ worker imports `app` lazily from `tasks.py`.
- **Routes live in blueprints under `bp/`** (all registered without a URL prefix, so endpoints are `<bp>.<func>`, e.g. `url_for('plan.my_plan')`): `auth` (login/register/logout), `ops` (`/healthz`, `/ai_metrics`), `profile`, `stats` (metrics + stats), `onboarding` (step1..10, mode, generating), `constructor` (page + `/api/constructor/*`), `plan` (`/my_plan`, generate/regenerate, job status, day edit), `workout` (`/workout/today`, exercise media/API), `main` (`/`), `history` (history CRUD, report, public `/share/<token>`). CLI commands (`create-user`, `import-exercises`, `import-exercise-media`) are in **`cli.py`** (a blueprint with `cli_group=None`).
- **Shared objects** (`csrf`, `limiter`, `login_manager`, `migrate`) are in `extensions.py`; **shared helpers** used by several blueprints or by `app.py` are in `helpers.py`. Blueprints import from `extensions`/`models`/`forms`/`helpers`/`validation`/`ai_generator`/`report` — never from `app` (circular import).
- **Orchestration** functions `perform_generation` / `perform_regeneration` / `save_workout_plan` are in `bp/plan.py`; `tasks.py` imports them from there. Tests that stub AI calls must patch the name in the module that uses it (e.g. `bp.plan.generate_full_plan`, `bp.workout.analyze_and_advise`).
- `templates/base.html` picks the active nav item by `request.endpoint` — update that list when renaming or moving an endpoint.
- **Two plan-creation paths** share one storage format: AI flow (`ai_generator.py`) and manual constructor (`/constructor`, `/api/constructor/*`). Both write `WorkoutPlan.data` (JSON: `week{N}` → `day{M}` → list of exercises `{exercise, sets, reps, weight, comment}`); manual drafts use `status='draft'`; origin is recorded in `User.plan_mode` / `WorkoutPlan.mode`.
- **`ai_generator.py`**: builds prompts (age, health conditions, equipment, focus areas, limitations), calls Gemini with model fallback (`_call_with_fallback`), caches responses (optionally Redis, `AI_CACHE_REDIS`), extracts/validates JSON, then **post-normalizes** the plan (`_normalize_plan` → `ensure_focus_exercises`) against the exercise catalog — forbidden-by-limitation/age/health exercises are filtered and the model output is not trusted as-is. Generation is restricted to the catalog when `EXERCISE_CATALOG_ENFORCE` is on.
- **`validation.py`**: pure Flask-free functions and the enum constants (goals, equipment, limitations, health conditions, focus areas, with RU labels); ranges mirror the onboarding sliders in templates. Add new profile options here first.
- **Exercise catalog**: `exercise_catalog.py` (in-memory lookup/metadata from `data/*.json`) and `exercise_store.py` + `Exercise`/`ExerciseMedia` models (DB + files in `instance/exercise_media/`). RU names are curated (`data/ru_catalog.json`) or Gemini-translated (`data/exercises_ru.json`). See `docs/exercise_media.md`.
- **Async AI jobs**: with `USE_JOB_QUEUE=1`, long Gemini calls run in an RQ worker (`rq worker ai`) via `jobs.py` (enqueue/fetch) and `tasks.py`. Task functions must be top-level and import `app` (and `bp.plan`) lazily inside the function to avoid circular imports. Without the flag, generation runs inline in the request.
- **`report.py`**: pure functions producing text workout reports (short/full) for Telegram sharing.
- **`config.py`**: all settings from env (prod env is provided outside the repo, not via `.env`); app refuses to start in production without `SECRET_KEY`.

## Conventions

- Templates extend `templates/base.html` (blocks `title`, `body_class`, `body`, `scripts`). No inline `<style>` and no inline JS handlers (`onclick`) — use `data-*` attributes with delegated listeners in `static/ui.js`.
- Styling uses CSS variables in `static/style.css`; dark theme via `[data-theme="dark"]`, stored in `User.theme`. Chart.js is vendored (no CDN).
- CSRF is global; JS must send the token via the helper in `static/ui.js`. `/api/*` errors return JSON, HTML errors render `templates/error.html`.
- Ruff: line length 120, rules E4/E7/E9/F, E501 ignored.
- `scripts/legacy/` is an archive — don't extend it.

## Агентская инфраструктура (.claude/)
- Права и hooks — `.claude/settings.json` (в git): `.env`/`/etc/app.env`/`instance/` закрыты на чтение,
  `git push`/`systemctl restart`/`db upgrade` требуют подтверждения.
- Hooks: `protect-files.sh` (блок правок секретов и `.git/`), `lint-python.sh` (ruff --fix после правки `.py`),
  `verify-on-git.sh` (ruff + pytest перед `git commit`/`git push`; красное блокирует),
  `verify-on-stop.sh` (Stop-hook, **по умолчанию выключен** — включается маркером `.claude/.verify-on-stop`,
  `+ .verify-on-stop-full` для pytest; не даёт завершить ход при красном; с progress-guard).
- Rules с `paths:` в `.claude/rules/` (python, templates) — грузятся лениво при работе с этими файлами.
- Скиллы в `.claude/skills/`: `ship-check` (ruff + pytest + статус pipeline), `new-migration`, `new-route`,
  `e2e-smoke`, `quality-check` (проверка ИИ-артефактов), `copy-check` (живой русский для UI/отчётов),
  `gates` (приёмка + Stop-hook). Eval-рубрика планов — `docs/plan-eval.md`.
- Чинить до критерия: `/goal pytest зелёный и ruff чистый`. Планы — `docs/plans/` (plansDirectory),
  handoff между сессиями — `docs/plan.md` + `docs/memory.md`.

## Окружение (dev-стенд на этом сервере)
- Python: используй venv .venv (.venv/bin/...)
- Redis локальный; RQ-воркер запущен (очередь ai)
- .env присутствует (FLASK_ENV=development, USE_JOB_QUEUE=1, AI_CACHE_REDIS=1)

## Команды (dev-стенд)
- Тесты: .venv/bin/python -m pytest -q
- Линт: .venv/bin/ruff check .
- Запуск: .venv/bin/flask --app app run

## Критические правила
- Перед КАЖДЫМ коммитом запускать pytest и ruff. Если красное — НЕ коммитить и НЕ пушить.
- Пуш в ветку main АВТОМАТИЧЕСКИ деплоит в ПРОД (CI обновляет код, ставит зависимости,
  применяет миграции и перезапускает сервисы).
  Поэтому в main пушим только проверенный код.
- Большие правки — сначала краткий план (план-режим), затем реализация.
- Модель по умолчанию — Sonnet; между задачами /compact.
- Сообщения коммитов — на английском, осмысленные.

## CI / Deploy
- Стадии: test (pytest + ruff) → deploy (только main, needs: [test]).
- Прод-деплой: CI на прод-хосте обновляет код, ставит зависимости, применяет миграции и
  перезапускает сервисы.
- Правило: НЕ пушить в main сломанный код; перед push всегда pytest + ruff.
