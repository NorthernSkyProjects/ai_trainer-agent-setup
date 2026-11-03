---
last_mapped_commit: 2a564d876b35351241cb5efc49ec110591df812d
last_mapped_at: 2026-11-03
---
# Technology Stack

**Analysis Date:** 2026-11-03

## Languages

**Primary:**
- Python 3.10 - all application code (`app.py`, `config.py`, `bp/*.py`, `ai_*.py`, `models.py`, `tasks.py`, `cli.py`). CI pins `python-version: '3.10'` (`.github/workflows/ci.yml`); ruff targets `py310` (`ruff.toml`).

**Secondary:**
- JavaScript (vanilla, no build step) - front-end logic in `static/ui.js`, service worker `static/sw.js`, Chart.js vendored at `static/vendor/chart.umd.min.js`.
- HTML/Jinja2 templates - `templates/*.html`, all extending `templates/base.html`.
- CSS - single theme file `static/style.css` with CSS variables.
- Bash - deploy and CI helpers `deploy/deploy.sh`, `scripts/nightly_e2e.sh`.
- JSON - exercise catalog and seed data in `data/` (`data/exercises_seed.json`, `data/ru_catalog.json`, `data/exercises_ru.json`, `data/exercise_media_manifest.json`).

## Runtime

**Environment:**
- CPython 3.10 (production venv at `/root/ai_trainer/.venv`, per `deploy/systemd/ai_trainer.service`; dev stand uses `.venv`).
- Served by gunicorn: `gunicorn -w 2 --timeout 240 -b 127.0.0.1:5000 app:app` (`deploy/systemd/ai_trainer.service`).
- Background worker: `rq worker ai --url ${REDIS_URL}` (`deploy/systemd/ai_trainer_worker.service`).
- Scheduled jobs via systemd timers in `deploy/systemd/ai_trainer-*.timer` (backup, alert, summary, report, reminders, debriefs).

**Package Manager:**
- pip with unpinned-upper-bound requirement files: `requirements.txt` (prod), `requirements-dev.txt` (adds test/lint tooling via `-r requirements.txt`).
- Lockfile: Not detected (no `requirements.lock`, `poetry.lock`, or `Pipfile.lock`). Versions are resolved at install time within the ranges below.

## Frameworks

**Core:**
- Flask >=3.1,<4 - web framework; app factory-style module in `app.py`, blueprints in `bp/`.
- Flask-SQLAlchemy >=3.1,<4 - ORM layer; models in `models.py`.
- Flask-Migrate >=4.1,<5 - Alembic migrations in `migrations/` (`render_as_batch=True` for SQLite, set in `app.py`).
- Flask-Login >=0.6,<1 - session auth; `login_manager.login_view = 'auth.login'` in `extensions.py`.
- Flask-WTF >=1.3,<2 - forms and global CSRF (`csrf = CSRFProtect()` in `extensions.py`); forms in `forms.py`.
- Flask-Limiter >=4.1,<5 - rate limiting; storage URI from `RATELIMIT_STORAGE_URI` (`config.py`, default `memory://`).
- WTForms (transitive, via Flask-WTF) - form field definitions in `forms.py`.
- Jinja2 (transitive, via Flask) - templates.

**Testing:**
- pytest >=9,<10 - test runner; config in `pytest.ini` (`testpaths = tests`, default `-m "not e2e"`).
- pytest-flask >=1.3,<2 - Flask test integration.
- pytest-cov >=5,<8 - coverage (`--cov` in CI, `.coveragerc`).
- Playwright >=1.49,<2 - opt-in browser E2E tests in `tests/e2e/` (`pytest -m e2e`), not in the CI gate.

**Build/Dev:**
- ruff >=0.6,<1 - linter; config in `ruff.toml` (line-length 120, rules `E4/E7/E9/F`, `E501` ignored). Formatting is not enforced.
- Flask CLI (`flask --app app ...`) - custom commands in `cli.py` (`create-user`, `import-exercises`, `import-exercise-media`, `telegram-set-webhook`).
- Pillow >=10,<13 - image handling for exercise media, used in `scripts/generate_exercise_images.py` and `scripts/generate_data_flow_diagram.py`.

## Key Dependencies

**Critical:**
- google-genai >=2,<3 - Google Gemini SDK. Client created lazily in `ai_generator.py` (`genai.Client(api_key=..., http_options=types.HttpOptions(...))`). Central to plan generation, workout analysis, weekly debriefs and exercise translation.
- bcrypt >=5,<6 - password hashing for `User` (`models.py`).
- redis >=5,<7 - Redis client; used by `jobs.py` (`redis.Redis.from_url(BaseConfig.REDIS_URL)`), AI response cache (`AI_CACHE_REDIS=1`), and rate-limit storage.
- rq >=1.16,<2 - Redis Queue for long AI jobs (queue name `ai`, `jobs.py`; tasks in `tasks.py`).
- gunicorn >=26,<27 - production WSGI server.

**Infrastructure:**
- python-dotenv >=1.0,<2 - loads `.env` (`config.py`, `ai_generator.py`). Note: production reads `/etc/ai_trainer.env` via systemd `EnvironmentFile`, not `.env`.
- SQLAlchemy (transitive, via Flask-SQLAlchemy) - `db` object in `models.py`; SQLite pragmas applied via an Engine `connect` listener in `app.py` (`journal_mode=WAL`, `busy_timeout=30000`).
- Alembic (transitive, via Flask-Migrate) - migration engine.
- google-genai transitive dependency `httpx` - used by `scripts/build_exercise_seed.py`, `scripts/import_dataset_media.py`, `scripts/translate_exercise_seed.py` for dataset downloads.

**Used but not declared in requirements files:**
- `requests` - imported by `scripts/yandex_art.py` (YandexART image generation, optional provider). Not listed in `requirements.txt`; must be installed separately if the Yandex provider is used.
- Standard library only for Telegram HTTP calls (`urllib.request` in `telegram_bot.py`, `ai_quota.py`, `scripts/alerts.py`) and SMTP (`smtplib` in `mailer.py`).

## Configuration

**Environment:**
- All settings are read from environment variables in `config.py` (class `BaseConfig`, with `DevelopmentConfig` and `ProductionConfig`). Selected via `FLASK_ENV` (`development` default, or `production`/`prod`).
- Template for variables: `.env.example` (documents every variable, grouped: Gemini, Flask/session, rate limits, AI quota, CSP, Telegram, mail, Redis/queue, exercise catalog, image generation, YandexART, alerts). Do not copy values from production env files into docs.
- Production refuses to start without `SECRET_KEY` (`config.py: get_config()`). In development, a persistent key is stored under `instance/.secret_key`.
- Key categories of env vars (names only):
  - Gemini: `GOOGLE_API_KEY`, `GEMINI_BASE_URL`, `GEMINI_MODELS`, `GEMINI_MAX_WORKERS`, `GEMINI_PER_MODEL_TIMEOUT`, `GEMINI_TOTAL_TIMEOUT`, `GEMINI_HTTP_TIMEOUT_MS`, `GEMINI_MAX_OUTPUT_TOKENS`, `GEMINI_THINKING_BUDGET`, `GEMINI_CACHE_TTL`, `GEMINI_IMAGE_MODELS`.
  - Database: `DATABASE_URL` (default `sqlite:///instance/trainer.db`).
  - Queue/cache: `REDIS_URL` (default `redis://127.0.0.1:6379/0`), `USE_JOB_QUEUE`, `JOB_TIMEOUT`, `AI_CACHE_REDIS`, `RATELIMIT_STORAGE_URI`, `RATELIMIT_ENABLED`.
  - Security/session: `SECRET_KEY`, `SESSION_COOKIE_SECURE`, `TRUST_PROXY`, `CSP_ENFORCE`, `WTF_CSRF_TIME_LIMIT`, `REMEMBER_COOKIE_DAYS`.
  - App: `APP_NAME` (default `Kachlog`), `APP_TIMEZONE`, `APP_BASE_URL`, `LOG_LEVEL`, `ADMIN_EMAILS`, `PRIVACY_CONTACT`, `DEFAULT_DURATION_WEEKS`.
  - Mail: `MAIL_SERVER`, `MAIL_PORT`, `MAIL_USERNAME`, `MAIL_PASSWORD`, `MAIL_FROM`, `MAIL_USE_TLS`, `MAIL_USE_SSL`, `MAIL_TIMEOUT`, `PASSWORD_RESET_TTL`.
  - Telegram: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_BOT_USERNAME`, `TELEGRAM_WEBHOOK_SECRET`, `ALERT_TELEGRAM_TOKEN`, `ALERT_TELEGRAM_CHAT_ID`, `ALERT_HOST_LABEL`, `ALERT_REMIND_MINUTES`.
  - AI quota: `AI_QUOTA_ENABLED`, `AI_DAILY_USER_LIMIT`, `AI_DAILY_GLOBAL_LIMIT`.
  - Exercise catalog/media: `EXERCISE_MEDIA_ENABLED`, `EXERCISE_CATALOG_ENFORCE`, `EXERCISE_CATALOG_PATH`, `EXERCISE_MEDIA_DIR`, `EXERCISE_IMAGE_DELAY`, `IMAGE_PROVIDER`.
  - YandexART: `YANDEX_ART_API_KEY`, `YANDEX_FOLDER_ID`, `YANDEX_ART_MODEL_URI`, `YANDEX_ART_API_BASE`, `YANDEX_ART_POLL_INTERVAL`, `YANDEX_ART_MAX_ATTEMPTS`.
- Timezone is forced to `Europe/Moscow` at import time (`helpers.setup_timezone()`, per `AGENTS.md`).

**Build:**
- No build step. Static assets are served as-is from `static/`.
- Build-related config files: `ruff.toml`, `pytest.ini`, `.coveragerc`, `opencode.json`, `.gitignore`.
- PWA: `static/manifest.json`, `static/sw.js`, icons in `static/img/icons/` (generated by `scripts/build_pwa_icons.py`).
- Migrations: `migrations/` (Alembic, generated via `flask --app app db migrate`).

## CI and Deploy Tooling

- GitHub Actions: `.github/workflows/ci.yml` - Python 3.10, `pip install -r requirements-dev.txt`, `ruff check .`, `pytest`, on push and pull_request.
- GitLab CI: `.gitlab-ci.yml` - stage `test` (venv `.ci-venv`, pytest with coverage, ruff) then stage `deploy-prod` on `main` (runs `deploy/deploy.sh`, installs systemd units, enables timers). Both stages use runner tag `deploy`.
- Deploy script: `deploy/deploy.sh` - backup, venv + pip install, `flask db upgrade`, systemd unit install, restart, `/healthz` wait.

## Platform Requirements

**Development:**
- Python 3.10+ with a virtualenv (`.venv`).
- `pip install -r requirements-dev.txt`.
- Redis server reachable at `REDIS_URL` when `USE_JOB_QUEUE=1` or `AI_CACHE_REDIS=1` (dev stand runs a local `redis-server`).
- Optional: Playwright Chromium for `tests/e2e`.
- Gemini API key (`GOOGLE_API_KEY`) for AI features; image generation requires a paid tier per `.env.example`.

**Production:**
- Linux host with nginx (reverse proxy on 80/443 to `127.0.0.1:5000`), gunicorn under systemd (`ai_trainer.service`), RQ worker (`ai_trainer_worker.service`), Redis.
- Environment file `/etc/ai_trainer.env` (EnvironmentFile for both services).
- SQLite database with WAL mode at `instance/trainer.db`; backed up by `scripts/backup_db.py` through a systemd timer.
- Deployment target: GitLab runner (shell executor) on the production host; app URL `https://iitrainer.duckdns.org` (from `.gitlab-ci.yml`).

---

*Stack analysis: 2026-11-03*
