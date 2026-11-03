---
last_mapped_commit: 2a564d876b35351241cb5efc49ec110591df812d
last_mapped_at: 2026-11-03
---
# External Integrations

**Analysis Date:** 2026-11-03

## APIs & External Services

**Google Gemini (primary AI provider):**
- Used for: plan generation and regeneration (`ai_plan_gen.py`), workout analysis (`ai_analysis.py`), weekly debriefs, exercise description translation (`scripts/translate_exercise_seed.py`), optional offline image generation (`scripts/generate_exercise_images.py`).
- SDK/Client: `google-genai` (`from google import genai`), client built in `ai_generator.py::_get_client()`.
- Call path: `ai_generator.py::_call_with_fallback` iterates `BaseConfig.GEMINI_MODELS` (default list in `config.py`: `gemini-3.5-flash`, `gemini-3-flash-preview`, and others), uses a thread pool (`GEMINI_MAX_WORKERS`) with per-model and total timeouts.
- Image models (offline script only): `GEMINI_IMAGE_MODELS` (default `gemini-3-pro-image`, `gemini-3.1-flash-image`, `gemini-2.5-flash-image`).
- Base URL: official `generativelanguage.googleapis.com` by default; overridable with `GEMINI_BASE_URL` (relay/proxy).
- Auth: `GOOGLE_API_KEY` env var.
- Caching: responses cached in memory, or in Redis when `AI_CACHE_REDIS=1` (`ai_generator.py`, TTL `GEMINI_CACHE_TTL`).
- Quota guard: per-user and global daily caps in `ai_quota.py` (`AI_DAILY_USER_LIMIT`, `AI_DAILY_GLOBAL_LIMIT`, stored in the rate-limit storage); exhaustion can trigger a Telegram alert.
- Data sent: profile, training history, health data only with user consent. Email and password are not sent (per `templates/privacy.html`).
- Metrics: `ai_metrics.py` records AI call counters, exposed at `/ai_metrics` (localhost only in nginx).

**YandexART (optional image provider):**
- Used for: exercise illustration generation, offline only (`scripts/yandex_art.py`, selected by `IMAGE_PROVIDER=yandex`).
- Endpoints: `https://ai.api.cloud.yandex.net` (`YANDEX_ART_API_BASE`), submit at `/v1/images/generations`, polling of operations.
- Client: `requests` (not declared in requirements files).
- Auth: `YANDEX_ART_API_KEY` (service account with `ai.imageGeneration.user` role), `YANDEX_FOLDER_ID`, model URI `YANDEX_ART_MODEL_URI` (default `yandex-art-2.0/latest`).

**Telegram Bot API (user reminders and webhook):**
- Used for: linking a user account to a Telegram chat, workout reminders, debriefs.
- Client: stdlib `urllib.request` in `telegram_bot.py` (`api_call(method, payload)` posts to `https://api.telegram.org/bot{token}/{method}`).
- Inbound: `POST /telegram/webhook` in `bp/telegram.py`. Verified by the secret token header matching `TELEGRAM_WEBHOOK_SECRET`. The `/start <token>` deep link (`https://t.me/{TELEGRAM_BOT_USERNAME}?start=...`) links the chat. `/stop` unlinks.
- Registration of the webhook: `flask --app app telegram-set-webhook` (`cli.py`), which calls `setWebhook` with `APP_BASE_URL/telegram/webhook`.
- Auth: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_BOT_USERNAME`, `TELEGRAM_WEBHOOK_SECRET`, `APP_BASE_URL`.
- Operator alerts (separate bot): `scripts/alerts.py` and `ai_quota.py` send messages via `https://api.telegram.org/bot{token}/sendMessage` using `ALERT_TELEGRAM_TOKEN` and `ALERT_TELEGRAM_CHAT_ID`.

**Telegram share links (client-side):**
- `static/ui.js` builds `https://t.me/share/url?...` links for sharing workout reports (`/api/history/<id>/report`, rendered by `report.py`). No server-side API call.

**Exercise dataset (public, downloaded at build/maintenance time):**
- Source: `yuhonas/free-exercise-db` on GitHub (`raw.githubusercontent.com/yuhonas/free-exercise-db/main/...`).
- Used by: `scripts/build_exercise_seed.py`, `scripts/import_dataset_media.py` (images, `IMAGE_BASE`), `scripts/translate_exercise_seed.py`. Downloaded with `httpx`.
- Runtime app does not call GitHub; the catalog is loaded from `data/exercises_seed.json` and the database.

**Content Security Policy reporting:**
- Browsers post violations to `/csp-report` (`bp/ops.py`, `POST`). CSP policy defined in `config.py` (`CSP_POLICY`, `report-uri /csp-report`). Enforcement toggled by `CSP_ENFORCE`.

## Data Storage

**Databases:**
- SQLite (default and production). Path `instance/trainer.db`; overridable with `DATABASE_URL` (must be `sqlite:///...` for backup script).
  - Connection: `DATABASE_URL` (optional), else `config.py` default.
  - Client: Flask-SQLAlchemy (`models.py`), migrations via Flask-Migrate (`migrations/`).
  - Pragmas set in `app.py`: `journal_mode=WAL`, `synchronous=NORMAL`, `busy_timeout=30000`. Engine `connect_args={'timeout': 30}`.
  - Writers: gunicorn workers and the RQ worker share the same file.
- Backups: `scripts/backup_db.py` uses the SQLite online backup API; run by `deploy/systemd/ai_trainer-backup.timer` and the deploy script.

**File Storage:**
- Local filesystem only.
- Exercise media: `instance/exercise_media/` (overridable with `EXERCISE_MEDIA_DIR`), imported with `flask --app app import-exercise-media --manifest data/exercise_media_manifest.json`. Served by the app; see `exercise_store.py`.
- Exercise catalog seed: `data/exercises_seed.json` (override `EXERCISE_CATALOG_PATH`).
- Development secret key file: `instance/.secret_key` (created with mode 0600 when `SECRET_KEY` is unset in development).

**Caching:**
- In-process memory for AI responses by default (`ai_generator.py`).
- Redis (`REDIS_URL`) when `AI_CACHE_REDIS=1`.
- Client-side: service worker `static/sw.js` caches `/my_plan`, `/workout/today`, `/history` (last load) and static assets for offline use.

**Message Queue:**
- Redis + RQ. Queue name `ai`, default job timeout `JOB_TIMEOUT` (600 s). Enqueue and fetch in `jobs.py`; task functions in `tasks.py` (top-level, import `app` and `bp.plan` lazily).
- Enabled with `USE_JOB_QUEUE=1`. Worker: `rq worker ai --url ${REDIS_URL}` (`deploy/systemd/ai_trainer_worker.service`).

## Authentication & Identity

**Auth Provider:**
- Custom, no third-party identity provider.
  - Implementation: Flask-Login session auth (`extensions.py`, `auth` blueprint in `bp/auth.py`). Passwords hashed with bcrypt (`models.py`, `User`).
  - "Remember me" persistent cookie `remember_token` (60 days by default, `REMEMBER_COOKIE_DAYS`); revoked through `User.session_token` on password change.
  - Password reset: token link via email (`mailer.py`, `bp/auth.py`), TTL `PASSWORD_RESET_TTL`.
  - Admin access: email allowlist in `ADMIN_EMAILS` (metrics page `/admin/metrics`).
  - CLI user creation: `flask --app app create-user --email ... --name ...`.
- Rate limiting on `/login`, `/register`, `/api/*` (Flask-Limiter, key by user id when authenticated, else IP).
- Trusted proxy headers: `TRUST_PROXY` (enabled by default in production) so client IPs come from nginx `X-Forwarded-*`.

## Email

**SMTP:**
- Module: `mailer.py` (stdlib `smtplib`, `email.message.EmailMessage`). Sends in a background thread by default.
- Connection: `MAIL_SERVER`, `MAIL_PORT` (default 587), `MAIL_USE_TLS` (STARTTLS) or `MAIL_USE_SSL`, optional `MAIL_USERNAME` / `MAIL_PASSWORD`, `MAIL_FROM`, `MAIL_TIMEOUT`.
- When `MAIL_SERVER` is empty, sending is disabled and the password reset page shows the `PRIVACY_CONTACT` instead.
- No third-party email API (no SendGrid, Mailgun, SES SDK detected).

## Monitoring & Observability

**Error Tracking:**
- None detected (no Sentry or similar SDK). Exceptions are logged with `logging` and surfaced via the app's error handlers (`app.py`, `templates/error.html`).

**Logs:**
- Python `logging` with logger names per module (`ai_generator`, `mailer`, `jobs`, ...). Level from `LOG_LEVEL`. Output goes to journald for systemd units (`journalctl -u ai_trainer`).

**Health and metrics endpoints:**
- `/healthz` (`bp/ops.py`) - used by deploy script (`HEALTHZ_URL`, default `http://127.0.0.1:5000/healthz`) and `scripts/wait_healthy.py`.
- `/ai_metrics` (`bp/ops.py`, `ai_metrics.py`) - AI call metrics.
- Both are blocked from the public internet by nginx (localhost only, per `AGENTS.md`).

**Scheduled alerting and reports:**
- `scripts/alerts.py` (systemd timer `ai_trainer-alert`): host alerts to Telegram (`ALERT_TELEGRAM_*`), `ALERT_HOST_LABEL`, `ALERT_REMIND_MINUTES`. Also checks `/healthz` (`urllib.request` with a 10 s timeout).
- `ai_trainer-summary` timer: summary message.
- `ai_trainer-report` timer: product metrics report (`product_metrics.py`).
- `ai_trainer-reminders` timer: Telegram workout reminders.
- `ai_trainer-debriefs` timer: weekly AI debriefs.

## CI/CD & Deployment

**Hosting:**
- Self-hosted Linux server (production host, referred to as PROD in `AGENTS.md` and `CLAUDE.md`). Public URL `https://iitrainer.duckdns.org` (DuckDNS dynamic DNS). TLS certificates from acme.sh (per `AGENTS.md`).
- Reverse proxy: nginx on 80/443 to gunicorn on `127.0.0.1:5000`. Nginx config is outside this repository (`docs/operations.md`).
- A separate dev stand (`89.125.81.57`) runs the same code with `.venv` and a local Redis.

**CI Pipeline:**
- GitHub Actions: `.github/workflows/ci.yml` (lint and tests on push and pull_request).
- GitLab CI: `.gitlab-ci.yml` on `gitlab.com/ShelkunovES/ai_trainer`. Stages `test` (shell runner tagged `deploy`, `.ci-venv`, pytest + coverage + ruff) and `deploy-prod` (only `main`, `resource_group: production`, runs `deploy/deploy.sh`, installs `deploy/systemd/*` units, enables timers). Environment URL `https://iitrainer.duckdns.org`.
- Deploy trigger: any push to `main` deploys to production.
- GitLab API access for pipeline checks uses `GITLAB_TOKEN` (environment variable; not stored in repo).

## Environment Configuration

**Required env vars (names only):**
- `GOOGLE_API_KEY` - Gemini access; required for AI features (lazy check, app starts without it).
- `SECRET_KEY` - required when `FLASK_ENV=production`.
- `FLASK_ENV` - `development` or `production`.
- `TRUST_PROXY` and `SESSION_COOKIE_SECURE` - set to `1` behind nginx with HTTPS.

**Optional but feature-relevant:**
- `REDIS_URL`, `USE_JOB_QUEUE`, `AI_CACHE_REDIS`, `RATELIMIT_STORAGE_URI` - Redis-backed features.
- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_BOT_USERNAME`, `TELEGRAM_WEBHOOK_SECRET`, `APP_BASE_URL` - user reminders.
- `ALERT_TELEGRAM_TOKEN`, `ALERT_TELEGRAM_CHAT_ID` - operator alerts.
- `MAIL_SERVER` and related `MAIL_*` - password reset emails.
- `ADMIN_EMAILS` - admin metrics access.
- `YANDEX_ART_*`, `IMAGE_PROVIDER` - offline image generation.

**Secrets location:**
- Development: `.env` in the repository root (loaded by `python-dotenv`). Not committed; `.gitignore` covers it. Never read or quoted in documentation.
- Production: `/etc/ai_trainer.env`, loaded by systemd `EnvironmentFile=` in `deploy/systemd/ai_trainer.service` and `ai_trainer_worker.service`.
- Dev-only generated key: `instance/.secret_key`.
- Claude Code permissions deny reads of `.env`, `/etc/ai_trainer.env`, and `instance/` (`.claude/settings.json`).

## Webhooks & Callbacks

**Incoming:**
- `POST /telegram/webhook` - Telegram Bot updates (`bp/telegram.py`), authenticated by `TELEGRAM_WEBHOOK_SECRET`.
- `POST /csp-report` - browser CSP violation reports (`bp/ops.py`). Unauthenticated by design.

**Outgoing:**
- Telegram Bot API calls (`https://api.telegram.org`): `setWebhook` (CLI), `sendMessage` (reminders, debriefs, alerts, quota alerts).
- Gemini API calls (`generativelanguage.googleapis.com` or `GEMINI_BASE_URL`).
- SMTP to `MAIL_SERVER` for password reset.
- Yandex Cloud image API (offline scripts only).
- GitHub raw dataset downloads (offline scripts only).

---

*Integration audit: 2026-11-03*
