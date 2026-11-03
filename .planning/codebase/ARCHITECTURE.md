---
last_mapped_commit: 2a564d876b35351241cb5efc49ec110591df812d
last_mapped_at: 2026-11-03
---
<!-- refreshed: 2026-11-03 -->
# Architecture

**Analysis Date:** 2026-11-03

## System Overview

```text
┌──────────────────────────────────────────────────────────────────────┐
│  Browser / PWA  (templates/*.html extend templates/base.html,        │
│  static/ui.js + static/pages/*.js + static/sw.js)                    │
└───────────────┬──────────────────────────────────────┬───────────────┘
                │ HTTP (nginx on PROD)                 │ Telegram webhook
                ▼                                      ▼
┌──────────────────────────────────────────────────────────────────────┐
│  app.py  — Flask app factory-less singleton `app`                    │
│  (Flask-Login, CSRF, Limiter, security headers, error handlers,      │
│   consent gate `before_request`, blueprint registration)             │
└───────┬──────────────────────────────────────────────────────────────┘
        │ register_blueprint (no URL prefix)
        ▼
┌──────────────────────────────────────────────────────────────────────┐
│  bp/  route layer                                                     │
│  auth ops profile stats onboarding constructor plan workout main    │
│  history legal telegram                                              │
└───────┬───────────────────────────┬──────────────────────────────────┘
        │ domain helpers            │ long AI calls
        ▼                           ▼
┌──────────────────────────┐  ┌───────────────────────────────────────┐
│ helpers.py, validation*, │  │ ai_generator.py (client, cache,       │
│ plan_insights, report,   │  │ fallback)  ← ai_safety, ai_prompts,   │
│ periodization, exercise_ │  │ ai_normalize, ai_analysis, ai_plan_gen│
│ swap, data_export, mailer│  │ ai_quota, ai_metrics                  │
└───────┬──────────────────┘  └───────┬───────────────────┬───────────┘
        │                             │ USE_JOB_QUEUE=1   │ inline
        ▼                             ▼                   ▼
┌──────────────────────────┐  ┌───────────────────────────────────────┐
│ models.py (SQLAlchemy)   │  │ jobs.py → Redis/RQ queue "ai"         │
│ instance/trainer.db      │◄─┤ tasks.py (worker, imports app lazily) │
│ (SQLite, WAL)            │  └───────────────────────────────────────┘
└──────────────────────────┘
```

## Pattern Overview

**Overall:** Layered Flask monolith with blueprint-per-feature route modules, a shared service/helper layer of mostly pure Python modules, and an optional Redis/RQ worker for long-running Gemini calls. Single deployable process (gunicorn) plus an optional RQ worker, both importing the same `app:app`.

**Key Characteristics:**
- Routes are never defined in `app.py`; each feature lives in `bp/<name>.py` and is registered without a URL prefix, so endpoints are `<bp>.<func>` (e.g. `url_for('plan.my_plan')`). Registration happens in `app.py` lines 80–98.
- Pure, Flask-free logic is kept in top-level modules (`validation.py`, `validation_options.py`, `report.py`, `periodization.py`, `ai_*`, `plan_insights.py`, `ai_metrics.py`, `ai_quota.py`), so it can be unit-tested and imported standalone. `tests/test_module_sizes.py` enforces a 600-line ceiling on `*.py` and `bp/*.py` and checks standalone importability of the split `ai_*` modules.
- Single shared SQLite database; no ORM-level multi-tenant separation beyond `user_id` columns.
- Two plan-creation paths (AI generation and manual constructor) write the same `WorkoutPlan.data` JSON format.
- Long AI work is sync by default and async (RQ) when `USE_JOB_QUEUE=1`.

## Layers

**Application shell (`app.py`, `config.py`, `extensions.py`):**
- Purpose: create the Flask app, load config, initialise extensions, wire global hooks.
- Location: `app.py`, `config.py`, `extensions.py`.
- Contains: `_configure_logging`, `_sqlite_pragmas` (SQLite engine event), `load_user`, `unauthorized`, `_security_headers` (after_request), `_refresh_remember_cookie`, `_require_consent` (before_request), `_asset_version`/`_static_url` cache-busting helper, error handlers for `CSRFError`, 400/403/404/405/413/429/500 and `Exception`.
- Depends on: `models`, `forms`, `helpers`, every `bp.*` module, `cli`, `exercise_catalog`, `exercise_store`.
- Used by: gunicorn (`app:app`), `flask --app app ...`, `tasks.py` (lazy import).
- `extensions.py` holds the shared singletons `csrf`, `limiter`, `login_manager`, `migrate`, and `rate_limit_key()`.
- `config.py` reads everything from env; `get_config()` picks the config class. Production refuses to start without `SECRET_KEY`.

**Route layer (`bp/`):**
- Purpose: HTTP parsing, auth/consent checks, form/JSON validation, orchestration, rendering or JSON responses.
- Location: `bp/*.py` (`__init__.py` is empty; each module exposes `bp = Blueprint(...)`).
- Contains: `auth.py` (login/register/logout/forgot/reset), `ops.py` (`/healthz`, `/ai_metrics`), `profile.py`, `stats.py` (metrics and stats), `onboarding.py` (steps 1–10, mode, generating), `constructor.py` (`/constructor`, `/api/constructor/*`, `/profile/plan-mode`), `plan.py` (`/my_plan`, generation/regeneration APIs, job status, day edit, weekday edit, load adaptation), `workout.py` (`/workout/today`, exercise media and swap APIs), `main.py` (`/`, `/sw.js`), `history.py` (history CRUD, report, public `/share/<token>`), `legal.py` (privacy/consent), `telegram.py` (link flow and webhook).
- Depends on: `extensions`, `models`, `forms`, `helpers`, `validation`, `ai_generator`, `report`, `plan_insights`, `periodization`, `ai_quota`, `jobs`.
- Used by: `app.py` registration only.
- Rule: blueprints import from `extensions`/`models`/`forms`/`helpers`/`validation`/`ai_generator`/`report`, never from `app` (would be circular).

**Domain and helper layer (top-level modules):**
- `helpers.py` (~589 lines): timezone setup (`setup_timezone`, forced `Europe/Moscow`), Jinja filters, error rendering (`_render_error`), analytics `log_event`, safe redirect (`_safe_next`), draft plan creation, PR computation (`update_prs`, `recompute_prs`, `get_prs`), set formatting, plan enrichment (`_enrich_plan_data`, `_enrich_exercise_media`), plan-drift checks (`_equipment_drift`, `_age_drift`), weekday schedule helpers.
- `validation.py` (~576 lines) + `validation_options.py` (~368 lines): Flask-free cleaning and validation. Enum constants (goals, equipment, limitations, health conditions, focus areas with RU labels, slider ranges) live in `validation_options.py` and are re-exported by `validation`.
- `plan_insights.py`: cycle summary, history context for prompts, trainer memory, load adaptation. Re-exported from `bp/plan.py`.
- `periodization.py`: deload weeks (`is_deload_week`) and warm-up post-processing.
- `report.py`: pure text workout reports (short/full) for sharing.
- `exercise_swap.py`: alternatives and add-exercise during a workout, filtered by the same rules as generation.
- `data_export.py`: ZIP of CSV/JSON user data.
- `mailer.py`: SMTP for password reset; disabled when `MAIL_SERVER` is unset.
- `telegram_bot.py`: reminder/debrief messaging and bot linking.
- `product_metrics.py`, `plan_eval.py`: offline reporting/eval used by CLI and scripts.

**AI layer (`ai_*.py`):**
- `ai_generator.py` (~407 lines) is the facade and owns only the Gemini client, the model-fallback call (`_call_with_fallback`, `_generate`), the in-process and optional Redis response cache (`AI_CACHE_REDIS`, `_cache_get/_cache_set`, in-flight locks), JSON extraction (`_extract_json`) and the thread pool (`_EXECUTOR`). It re-exports names from the submodules below. Callers and tests patch `ai_generator.<name>`.
- `ai_safety.py`: forbidden-exercise lists by limitation, age, and health condition.
- `ai_prompts.py`: prompt builders (profile, equipment, focus areas, limitations).
- `ai_normalize.py`: `_normalize_plan` and `ensure_focus_exercises` post-normalise model output against the exercise catalog.
- `ai_plan_gen.py`: `generate_full_plan`, `regenerate_plan_with_comment`.
- `ai_analysis.py`: `analyze_and_advise` for per-workout feedback.
- `ai_quota.py`: per-user and global daily AI call quota, stored in the rate-limit storage (Redis in prod).
- `ai_metrics.py`: in-process counters (per gunicorn worker) exposed on `/ai_metrics`.

**Exercise catalog:**
- `exercise_catalog.py`: in-memory lookup and metadata from `data/*.json`, used by generation and validation.
- `exercise_store.py`: DB-backed `Exercise`/`ExerciseMedia` storage and media files under `instance/exercise_media/`.

**Async job layer:**
- `jobs.py`: `enqueue(func_path, ...)`, `get_job`, queue `ai` on Redis via RQ. Uses `BaseConfig.REDIS_URL` and `JOB_TIMEOUT`.
- `tasks.py`: top-level RQ task functions `task_generate_plan`, `task_regenerate_plan`, `task_weekly_debrief`, `task_analyze_workout`. Each imports `app` and `bp.plan` inside the function body to avoid circular imports.

**Data layer (`models.py`):**
- Purpose: SQLAlchemy models; `db = SQLAlchemy()` instance lives here.
- Models: `User` (UserMixin, bcrypt hash, `theme`, `plan_mode`, session token), `WorkoutPlan` (`data` JSON, `status`, `mode`), `Workout`, `BodyMetric`, `Exercise`, `ExerciseMedia`, `AnalyticsEvent`, `PersonalRecord`, `WeeklyReport`, `WorkoutTemplate`, `WorkoutSubmission` (one-time token).
- Schema changes are made only through Alembic migrations in `migrations/versions/`, autogenerated with `flask --app app db migrate`.

**Frontend:**
- Server-rendered Jinja templates in `templates/` extend `templates/base.html` (blocks: `title`, `body_class`, `body`, `scripts`). `base.html` selects the active nav item by `request.endpoint`.
- Vanilla JS in `static/`: `ui.js` (toast, CSRF helper, delegated `data-*` listeners, PWA registration), feature scripts such as `static/workout_*.js`, `static/wheel.js`, and per-page modules in `static/pages/`. Chart.js is vendored in `static/vendor/`.
- No inline `<style>` or `onclick` handlers are allowed; behaviour is bound through `data-*` attributes.
- `static/sw.js` is served from `/sw.js` by `bp/main.py` to keep scope at the root.

## Data Flow

### Primary Request Path (HTML page)

1. Request enters `app` (`app.py`); `before_request` `_require_consent` checks consent (`bp/legal.py:needs_consent`).
2. Flask-Login loads the user via `load_user` (`app.py`), checking the session token.
3. Blueprint view in `bp/<name>.py` validates input through `validation.py` / forms (`forms.py`).
4. View reads or writes via `models.py` objects using `db.session`.
5. View renders `templates/<page>.html`, which extends `templates/base.html`.
6. `after_request` hooks (`_log_api_errors`, `_refresh_remember_cookie`, `_security_headers`) adjust the response.

### AI Plan Generation (sync or async)

1. `POST /api/generate_plan` (`bp/plan.py:api_generate_plan`) is rate-limited and checks AI quota (`ai_quota`).
2. If `USE_JOB_QUEUE=1`, `jobs.enqueue('tasks.task_generate_plan', ...)` returns a job id; the client polls `GET /api/job/<job_id>` (`api_job_status`). Otherwise `perform_generation` (`bp/plan.py:190`) runs inline.
3. The task (`tasks.py:task_generate_plan`) imports `app` and calls `bp.plan.perform_generation`.
4. `perform_generation` calls `ai_generator.generate_full_plan` (`ai_plan_gen.py`), which builds prompts (`ai_prompts`), calls Gemini through `_generate` → `_call_with_fallback` (model fallback, cache), extracts JSON, and post-normalises via `ai_normalize._normalize_plan` and `ensure_focus_exercises` against the catalog. `periodization` adds deloads and warm-ups.
5. `save_workout_plan` (`bp/plan.py:53`) writes `WorkoutPlan.data` (`week{N}` → `day{M}` → exercises) and sets status.

### Manual Constructor Path

1. `/onboarding/mode` sets `User.plan_mode`; `/constructor` renders the editor.
2. `/api/constructor/*` (`bp/constructor.py`) saves drafts with `status='draft'` into the same `WorkoutPlan.data` format.

### Workout Logging and Analysis

1. `/workout/today` (`bp/workout.py`) shows the day; submission uses a one-time `WorkoutSubmission` token to prevent double posts.
2. The workout is stored in `Workout`; PRs are updated by `helpers.update_prs`.
3. Optional AI feedback runs `analyze_and_advise` (`ai_analysis.py`) through `tasks.task_analyze_workout` when queued, or inline otherwise.

### Telegram Reminders

1. Profile links a chat through a one-time token and deep link `t.me/<bot>?start=<token>` (`bp/telegram.py`).
2. The bot webhook (`/telegram/webhook`, `telegram_bot.py`) stores the chat id; scheduled CLI commands (`cli.py:send_reminders`, `send_debriefs`) and systemd timers in `deploy/systemd/` send messages.

**State Management:**
- Server-side state lives in SQLite (`instance/trainer.db`) and, when enabled, Redis (rate limit storage, AI cache, RQ queue, AI quota).
- Client-side state: localStorage drafts for workouts (`static/workout_draft.js`), service worker cache for offline pages (`static/sw.js`).

## Key Abstractions

**Blueprint route module:**
- Purpose: one feature area per module with its own `bp`.
- Examples: `bp/plan.py`, `bp/workout.py`, `bp/onboarding.py`
- Pattern: `bp = Blueprint('<name>', __name__)`, `@bp.route`, registered in `app.py`.

**Plan document:**
- Purpose: the canonical training plan.
- Examples: `WorkoutPlan.data` in `models.py`; builders `ai_plan_gen.py`, `bp/constructor.py`.
- Pattern: nested dict `week{N}` → `day{M}` → list of `{exercise, sets, reps, weight, comment}`.

**AI facade with re-exports:**
- Purpose: stable import surface while implementation is split across modules.
- Examples: `ai_generator.py`, re-exporting `ai_safety`, `ai_prompts`, `ai_normalize`, `ai_analysis`, `ai_plan_gen`.
- Pattern: patch `ai_generator.<name>` in tests; submodules call `_generate`, `_extract_json`, `_normalize_plan` through `ai_generator` at call time so patches apply.

**Validation constants:**
- Purpose: single source for profile options and ranges.
- Examples: `validation_options.py`, re-exported by `validation.py`.
- Pattern: add new profile options to `validation_options.py` first.

**Exercise catalog entry:**
- Purpose: an exercise with RU name, description, media.
- Examples: `exercise_catalog.py`, `exercise_store.py`, `models.py:Exercise`.

## Entry Points

**Web app (gunicorn / flask):**
- Location: `app.py` (`app` object, `app:app`).
- Triggers: `gunicorn -w 2 --timeout 240 -b 127.0.0.1:5000 app:app` (`deploy/systemd/ai_trainer.service`), `python app.py` (dev on :5000), `flask --app app run`.
- Responsibilities: serves all HTTP routes.

**RQ worker:**
- Location: `tasks.py` (task functions); worker process runs `rq worker ai`.
- Triggers: `deploy/systemd/ai_trainer_worker.service`.
- Responsibilities: executes long AI jobs and analysis, debriefs.

**CLI:**
- Location: `cli.py` (blueprint with `cli_group=None`, so commands are top-level `flask --app app <cmd>`).
- Commands: `create-user`, `import-exercises`, `import-exercise-media`, `recompute-prs`, `product-report`, `send-reminders`, `send-debriefs`, `telegram-set-webhook`.

**Scheduled jobs:**
- Location: `deploy/systemd/*.timer` (alert, backup, debriefs, reminders, report, summary). Backup script `scripts/backup_db.py`; alerts `scripts/alerts.py`.

**Migrations:**
- Location: `migrations/env.py`, `migrations/versions/`.

**Offline data scripts:**
- Location: `scripts/build_exercise_seed.py`, `scripts/translate_exercise_seed.py`, `scripts/import_dataset_media.py`, `scripts/generate_exercise_images.py`.

## Architectural Constraints

- **Threading:** gunicorn workers (`-w 2`) are processes; `ai_generator` uses a `ThreadPoolExecutor` (`_EXECUTOR`) and threading locks for cache and in-flight deduplication. `ai_metrics` counters are per process and reset on restart.
- **Global state:** module-level singletons in `app.py` (`app`), `models.py` (`db`), `extensions.py` (`csrf`, `limiter`, `login_manager`, `migrate`), `ai_generator.py` (`_CLIENT`, `_CACHE`, `_REDIS_CACHE`, `_EXECUTOR`, `_CALL_META` thread-local), `ai_metrics.py`, `helpers.py` timezone set on import.
- **Circular imports:** prevented by convention. Blueprints and `tasks.py` must not import `app` at module top level; `tasks.py` and `bp/plan.py` import `app` lazily. `bp/plan.py` is imported by `tasks.py`.
- **Import-time side effects:** `helpers.setup_timezone()` runs on app import, and `tests/conftest.py` sets env vars before importing `app`, so that ordering must be preserved.
- **Blueprint URL space:** all blueprints have no prefix, so endpoint names must stay unique across modules.
- **Module size:** Python modules are capped at 600 lines (`tests/test_module_sizes.py`); larger features are split into sibling modules (as done for `ai_*` and `validation_options.py`).

## Anti-Patterns

### Importing `app` from a blueprint or helper

**What happens:** a module imports `from app import ...` at top level.
**Why it's wrong:** `app.py` imports every blueprint, so this creates a circular import and breaks worker and test startup.
**Do this instead:** import from `extensions`, `models`, `helpers`, or use `current_app` inside the request; in tasks, import `app` inside the function body (see `tasks.py`).

### Patching the submodule instead of the facade

**What happens:** tests patch `ai_plan_gen.generate_full_plan` or a submodule internal while the caller imports from `ai_generator`.
**Why it's wrong:** the patch misses the name the caller actually uses.
**Do this instead:** patch the name in the module that uses it, e.g. `bp.plan.generate_full_plan`, `bp.workout.analyze_and_advise`, or `ai_generator.<name>` for facade-level calls.

### Writing plans with ad hoc shapes

**What happens:** code writes plan dicts that deviate from `week{N}/day{M}`.
**Why it's wrong:** `plan_insights`, `report`, `helpers._enrich_plan_data`, and the frontend assume that shape.
**Do this instead:** build plans through `save_workout_plan` (`bp/plan.py`) or the constructor helpers, and normalise with `ai_normalize`.

### Hand-written migrations

**What happens:** schema edits are made by hand in `migrations/versions/`.
**Why it's wrong:** the chain of revisions and the models drift apart.
**Do this instead:** edit `models.py`, then run `flask --app app db migrate -m "..."` and `db upgrade`.

## Error Handling

**Strategy:** HTML errors render `templates/error.html` via `_render_error`; `/api/*` errors return JSON (`helpers._json_error`, `wants_json`). CSRF errors on HTML flash a message and redirect to the form; on `/api/*` they return JSON 400.

**Patterns:**
- Global handlers in `app.py` for 400/403/404/405/413/429/500 and `Exception`.
- AI failures fall back to the cached or rule-based path and `_mark_analysis_failed` in `tasks.py` marks workouts whose analysis failed.
- HTML responses are sent with `Cache-Control: no-store`.

## Cross-Cutting Concerns

**Logging:** standard `logging` configured in `app.py:_configure_logging` (level from `LOG_LEVEL`); analytics events via `helpers.log_event` into `AnalyticsEvent`; AI call metrics via `ai_metrics`.
**Validation:** `validation.py` (pure) plus WTForms in `forms.py` for login and register.
**Authentication:** Flask-Login session-based (`login_manager`, `load_user` in `app.py`), session token column on `User` (`models.py`), `remember` cookie refresh in `after_request`. Public endpoints: `/login`, `/register`, `/privacy`, `/share/<token>`, `/healthz`, `/ai_metrics` (the last two are blocked at nginx for non-localhost).
**Rate limiting and quotas:** Flask-Limiter (`extensions.py`, `RATELIMIT_STORAGE_URI`) on `/login`, `/register`, `/api/*`; daily AI quota in `ai_quota.py`.
**Security headers and CSP:** set in `app.py:_security_headers` using `CSP_POLICY` from `config.py`.

---

*Architecture analysis: 2026-11-03*
