# OpenCode Agent Instructions

## Overview
- This is a Flask web application for tracking gym workouts.
- Entrypoint: `app.py` (`app:app`); роуты — в блюпринтах `bp/` (см. Key Files).
- Authentication: Flask-Login (session-based). Публичные (без входа): `/login`,
  `/register`, публичная ссылка `/share/<token>` и статика. `/healthz` и `/ai_metrics`
  в Flask тоже публичны, но снаружи закрыты в nginx (доступ только с localhost).

## Infrastructure & Operations
- **Два окружения, один репозиторий** (исходники приложения — в приватном репозитории; здесь
  показаны только конфигурационные файлы агента):
  - **PROD** — nginx → gunicorn `ai_trainer.service` (`127.0.0.1:5000`); RQ-воркер
    `ai_trainer_worker.service`; env вне репозитория; SQLite WAL (`instance/trainer.db`).
  - **DEV** — dev-стенд (`~/ai_trainer`, `.venv`, локальный `redis-server`, RQ-воркер);
    именно здесь работает **Claude Code**.
- **Деплой (авто):** push в `main` → пайплайн: стадия `test` (pytest + ruff в изолированном
  окружении) → стадия `deploy-prod` (обновление кода → `pip install` → `flask --app app db upgrade`
  → рестарт сервисов). **Любой push в `main` деплоит в прод** — перед push гоняем тесты
  (CI-гейт не пустит красное).
- **Мониторинг:** `/healthz` и `/ai_metrics` закрыты на уровне веб-сервера (только с localhost).
- Подробности эксплуатации — в приватном раннбуке.

## Development & Execution
- **Setup:** `pip install -r requirements.txt` (или `requirements-dev.txt`).
  Скопировать `.env.example` в `.env`, задать `GOOGLE_API_KEY` и `SECRET_KEY`.
- **Run:** `python app.py` (starts on port 5000).
- **Tests & lint:** `pytest` (все) или один — `pytest tests/test_workout.py::test_name`;
  `ruff check .` (CI гоняет pytest + ruff на Python 3.10). На dev-стенде — `.venv/bin/python -m pytest` / `.venv/bin/ruff check .`.
- **E2E (opt-in):** `.venv/bin/python -m pytest -m e2e tests/e2e` — Playwright, вне CI-гейта
  (нужен chromium, запускать на dev-стенде).
- **Database:** SQLite, located at `instance/trainer.db`.
- **Timezone:** Forced to `Europe/Moscow` via `helpers.setup_timezone()` (called on app import).
- **Dependencies:** см. `requirements.txt`; конфиг — `config.py` (читает env).
- **Migrations:** Flask-Migrate (Alembic). `flask --app app db upgrade` /
  `flask --app app db migrate -m "..."`. Ручные миграции не писать.
  Старая ручная миграция заархивирована в `scripts/legacy/`.
- **Users:** `flask --app app create-user --email ... --name ...`
  (админ автоматически не создаётся).
- **Security:** CSRF (`CSRFProtect`) включён глобально; rate limiting —
  Flask-Limiter (по умолчанию `memory://`, в prod — Redis), лимиты на
  `/login`, `/register` и `/api/*`. Security-заголовки в `after_request`.
  Ошибки: единый `templates/error.html` (400/403/404/405/413/500);
  `CSRFError` на HTML → flash + редирект к форме, на `/api/*` → JSON 400;
  HTML отдаётся с `Cache-Control: no-store`. nginx на 502/503/504 отдаёт
  `/var/www/ai_trainer/50x.html`.
- **Production:** nginx reverse-proxies `http://127.0.0.1:5000` (HTTP 80 и HTTPS 443). App под
  `gunicorn`, юнит `ai_trainer.service`; прод-env — вне репозитория (не `.env`).
  `SESSION_COOKIE_SECURE=1` включён (HTTPS есть).
- **Redis / очередь:** `redis-server` для лимитов (`RATELIMIT_STORAGE_URI`),
  кэша ИИ (`AI_CACHE_REDIS=1`) и очереди RQ (`USE_JOB_QUEUE=1`). Воркер —
  юнит `ai_trainer_worker.service` (`rq worker ai`), задачи в `tasks.py`.

## Conventions
- Python 3.10; линтер ruff (`ruff.toml`: line-length 120, `E4/E7/E9/F`, `E501` ignored). `ruff format` не запускать.
- Роуты — в `bp/*`; общее — `helpers.py`, `extensions.py`, `models.py`, `forms.py`, `validation.py`.
- Шаблоны наследуют `templates/base.html`; без inline `<style>`/`onclick` — `data-*` + `static/ui.js`.
- Тесты — в `tests/`, имена `test_*.py`; общие фикстуры — `tests/conftest.py`.
- Код и сообщения коммитов — на английском; пользовательские тексты интерфейса — на русском.

## Rules of work
- Ветка `main` автоматически деплоится в ПРОД: пушим только зелёное (pytest + ruff).
- Перед коммитом: `.venv/bin/python -m pytest -q` и `.venv/bin/ruff check .`.
- Сообщения коммитов — английские, осмысленные (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`).
- Запрещено: править/коммитить секреты (`.env`, `/etc/app.env`), `git push --force`, трогать прод-сервисы.
- Большие правки — сначала план, затем реализация; миграции — только через Alembic.

## Agent tooling (.claude/)
Claude Code infrastructure is versioned in `.claude/` (picked up on the DEV stand):
- `settings.json` — permission rules (deny `.env`/`/etc/app.env`/`instance/`;
  ask `git push`, `systemctl restart`, `db upgrade`) + hooks + `plansDirectory: docs/plans`.
- `hooks/` — `protect-files.sh` (block edits to secrets/`.git/`), `lint-python.sh`
  (`ruff check --fix` after `.py` edits), `verify-on-git.sh` (ruff + pytest before
  `git commit`/`git push`), `verify-on-stop.sh` (Stop-hook, off by default — opt in with
  `.claude/.verify-on-stop`).
- `rules/*.md` with `paths:` (python, templates) load lazily.
- `skills/` — `ship-check`, `new-migration`, `new-route`, `e2e-smoke`, `quality-check`,
  `copy-check`, `gates`. Plan-quality rubric in `docs/plan-eval.md`.
- Personal, gitignored: `CLAUDE.local.md`, `.claude/settings.local.json`, `docs/plans/*`.
- Handoff across sessions: `docs/plan.md` + `docs/memory.md`. E2E is opt-in
  (`pytest -m e2e tests/e2e`, Playwright), excluded from the CI gate.

## Key Files
- `app.py` (~250 строк): только создание приложения, инициализация расширений, регистрация
  блюпринтов, Flask-Login-хендлеры, security-заголовки и обработчики ошибок. **Роуты — в
  блюпринтах `bp/*`** (`auth, ops, profile, stats, onboarding, constructor, plan, workout,
  main, history`), CLI — в `cli.py`, общие объекты — `extensions.py`, хелперы — `helpers.py`.
  Помимо ИИ-флоу — ручной конструктор (`bp/constructor.py`: `/onboarding/mode`,
  `/constructor`, `/api/constructor/*`, `/profile/plan-mode`). Ручной план лежит в
  `WorkoutPlan.data` (тот же формат), черновик — `status='draft'`, способ —
  `User.plan_mode` / `WorkoutPlan.mode`.
- `config.py`: Конфигурация (env, cookie-флаги, лимиты, БД).
- `models.py`: Database schema (SQLAlchemy), `User` with bcrypt password hash.
- `forms.py`: WTForms login/register forms (CSRF enabled).
- `ai_generator.py`: Logic for workout planning and analysis.
- `report.py`: Генерация текстовых отчётов о тренировке для шаринга
  (краткий/полный, прогресс по упражнениям). Чистые функции; используется
  маршрутом `/api/history/<id>/report`, шаринг в Telegram — deep-link
  `t.me/share` + модалка в `base.html`/`static/ui.js`.
- `exercise_catalog.py`: Каталог упражнений (~876 из открытого датасета
  `yuhonas/free-exercise-db`, Unlicense). Метаданные и фото — public domain;
  RU-названия/описания — курируемые (`data/ru_catalog.json`) или автоперевод
  Gemini (`data/exercises_ru.json`). Генерация по умолчанию ограничена
  каталогом (`EXERCISE_CATALOG_ENFORCE`), описание гарантировано.
- `exercise_store.py` + модели `Exercise` / `ExerciseMedia`: каталог и
  иллюстрации в БД (описания и метаданные) + файлы в
  `instance/exercise_media/`. Импорт: `flask --app app import-exercises` и
  `flask --app app import-exercise-media --manifest data/exercise_media_manifest.json`.
- `scripts/import_dataset_media.py`: скачивание открытых фото датасета
  (start/finish → WebP) и сборка манифеста; инкрементально (`--only/--limit/--force`).
- `scripts/translate_exercise_seed.py`: автоперевод названий/описаний через
  Gemini в `data/exercises_ru.json` (резюмируемый).
- `scripts/generate_exercise_images.py`: опциональная офлайн-генерация
  авторских иллюстраций через Gemini (image-модели, платный ключ), с
  style-anchor и провенансом. Старый SVG-конвейер — в `scripts/legacy/svg/`.
- `data/ru_catalog.json`, `data/exercises_ru.json`, `data/exercises_seed.json`:
  курируемый RU-каталог, оверлей перевода и собранный сид; пересборка —
  `python scripts/build_exercise_seed.py`.
- `docs/exercise_media.md`: как работают описания/медиа, масштабирование,
  пересборка графики.
- `migrations/`: Alembic (Flask-Migrate); `scripts/legacy/` — архив.
- `requirements.txt`, `requirements-dev.txt`, `.env.example`, `README.md`.
- `templates/login.html`, `templates/register.html`: Auth pages.
- `static/style.css`: Единая тема оформления (CSS-переменные `--bg`,
  `--card`, `--text`, `--accent`, `--muted`). Светлая тема — основная,
  тёмная включается атрибутом `[data-theme="dark"]`.

## Theming
- Все шаблоны наследуют `templates/base.html` (`{% extends "base.html" %}`),
  который подключает `static/style.css` и `static/ui.js` (toast + csrf
  helper), flash-регион. В шаблоне задаются блоки `title`, `body_class`,
  `body`, `scripts`. Не добавляйте инлайновые `<style>` и
  inline-JS-обработчики (`onclick`): используйте `data-*` + делегирование
  слушателей.
- Тема хранится в `User.theme` (`light`/`dark`, по умолчанию `light`).
  `base.html` рендерит `data-theme` на `<html>` сразу при загрузке, поэтому
  тема применяется на всех устройствах. Переключается только в профиле
  (`POST /profile/theme`); на остальных страницах и для анонимов — светлая.
- Другие страницы (`history`, `stats` и т.д.) используют переменные, чтобы
  автоматически переключаться между темами.
- `Chart.js` вендорен в `static/vendor/chart.umd.min.js` (без CDN).
