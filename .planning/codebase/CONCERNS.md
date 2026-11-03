---
last_mapped_commit: 2a564d876b35351241cb5efc49ec110591df812d
last_mapped_at: 2026-11-03
---
# Codebase Concerns

**Analysis Date:** 2026-11-03

## Tech Debt

**Broad exception handling in request and task paths:**
- Issue: Many handlers catch bare `Exception` and convert it to a generic message or a `None` result, which hides the failure type from callers and from tests.
- Files: `bp/workout.py` (lines ~256, ~325, ~400, ~429), `bp/plan.py` (~336), `bp/stats.py` (~555), `bp/ops.py` (~47, ~81, ~93), `tasks.py` (~85, ~96, ~115, ~179), `helpers.py` (~83)
- Impact: Real bugs (for example a `KeyError` in plan normalisation) surface as "Не удалось..." messages and are only visible in logs. Failed analyses end up in `analysis_status='failed'` without a reason stored.
- Fix approach: Narrow the caught types at the AI boundary (`ai_generator` errors, `requests`/Gemini client errors) and let programming errors propagate to the global 500 handler, which already renders `templates/error.html`.

**Duplicated workout-analysis logic across sync and async paths:**
- Issue: The inline analysis for extra workouts (`_analyze_extra_inline` in `bp/workout.py`) and the queued analysis (`_analyze_workout` in `tasks.py`) build the same `analyze_and_advise` call with different argument sets and different post-processing (`_clean_analysis`, `update_prs`).
- Files: `bp/workout.py` (~421-438), `tasks.py` (~140-210)
- Impact: Fixes applied to one path (for example history filtering or the `user_data` shape) are easily missed on the other.
- Fix approach: Move the shared "call model and build analysis payload" step into one helper in `ai_analysis.py` and have both paths call it.

**Synchronous fallback duplicated for the job queue:**
- Issue: Every long AI endpoint branches on `USE_JOB_QUEUE` (`bp/plan.py` `api_regenerate_plan`, `api_generate_plan`, plan-day and workout paths). The inline branch and the task branch each repeat the error and quota handling.
- Files: `bp/plan.py` (~276-342), `bp/workout.py` (~161-260), `tasks.py`
- Impact: Behaviour differs between dev (inline, often `USE_JOB_QUEUE=1` in `.env`) and prod, so bugs can appear in only one mode.
- Fix approach: Route both modes through a single `run_or_enqueue(func, args)` helper that returns the same response shape.

**Large modules approaching the limit:**
- Issue: `tests/test_module_sizes.py` enforces a 600-line ceiling. `helpers.py` (589), `validation.py` (576), `bp/stats.py` (570), `bp/workout.py` (566), `bp/plan.py` (561) are within a few lines of it.
- Files: `helpers.py`, `validation.py`, `bp/stats.py`, `bp/workout.py`, `bp/plan.py`
- Impact: Any feature addition in these files will trip the size test and force a split under deadline pressure.
- Fix approach: Split `helpers.py` by concern (PR/records, share tokens, formatting) and `bp/workout.py` into submission vs. analysis-rendering modules before adding features.

**Module-level singletons in `ai_generator.py`:**
- Issue: `_EXECUTOR`, `_REDIS_CACHE`, `_CACHE`, `_CACHE_LOCK`, `_INFLIGHT_LOCKS` (a `WeakValueDictionary`) and `_CALL_META` are created at import time, with a Redis `ping()` at import (2 s timeout).
- Files: `ai_generator.py` (~84-100, ~130-160)
- Impact: Import of `ai_generator` blocks on Redis connectivity; tests that import the module pick up the environment at import time.
- Fix approach: Initialise the Redis cache lazily on first use (inside `_cache_get`/`_cache_set`) and expose a reset hook for tests.

## Known Bugs

**Silent AI analysis failure leaves no user-visible reason:**
- Symptoms: A workout saved with `analysis_status='failed'` shows the fallback analysis without an explanation or retry action.
- Files: `tasks.py` (`_mark_analysis_failed`, ~170-180), `bp/workout.py` (`_analysis_state`, ~444-462)
- Trigger: Gemini timeout, quota exhaustion (`ai_quota.consume` returns a message that is not stored), or an invalid JSON response after fallback models.
- Workaround: Edit and resave the workout, which resets the status to `'none'` and re-queues analysis.

**Job status endpoint collapses failures into one generic message:**
- Symptoms: When an RQ job fails, `/api/job/<job_id>` returns the same "Не удалось выполнить задачу" message whatever the cause.
- Files: `bp/plan.py` (`api_job_status`, ~366-384)
- Trigger: Any exception inside `tasks.task_regenerate_plan` or `tasks.task_generate_plan`, including quota or validation errors that the inline path would report specifically.
- Workaround: Check `ai_worker` logs for the job id.

**Quota counters diverge across processes when Redis is not configured:**
- Symptoms: Per-user daily AI limits are enforced per process, so with `gunicorn -w 2` a user can make up to twice the configured number of calls.
- Files: `ai_quota.py` (`_limiter`, ~26-32), `config.py` (`RATELIMIT_STORAGE_URI`, line ~151)
- Trigger: `RATELIMIT_STORAGE_URI` left at its `memory://` default. `docs/operations.md` says prod uses Redis, so the risk applies only to a misconfigured environment.
- Workaround: Set `RATELIMIT_STORAGE_URI` to the Redis URI in `/etc/ai_trainer.env`.

## Security Considerations

**Development secret key persisted to the instance directory:**
- Risk: If `SECRET_KEY` is unset in a non-production environment, a key is generated and stored in `instance/.secret_key`. Anyone with read access to `instance/` can forge session cookies and share or password-reset tokens.
- Files: `config.py` (`_dev_secret_key`, ~209-242)
- Current mitigation: Production refuses to start without `SECRET_KEY` (`config.py` ~237-240). `instance/` is denied to agents in `.claude/settings.json`.
- Recommendations: Never deploy with `FLASK_ENV` other than production on a shared host. Consider failing closed on a non-loopback bind when the key is auto-generated.

**Share and password-reset tokens signed with the application secret:**
- Risk: `make_share_token` (`bp/history.py` ~24) and `make_reset_token` (`bp/auth.py` ~94) use the same `SECRET_KEY` with different salts. Rotating `SECRET_KEY` invalidates all share links, and a leaked key compromises both.
- Files: `bp/history.py` (~20-38), `bp/auth.py` (~84-110)
- Current mitigation: Distinct salts, `SHARE_TOKEN_MAX_AGE` and `PASSWORD_RESET_TTL` expiry, and the reset token is bound to a password/session fingerprint (`_password_fingerprint`).
- Recommendations: Document that rotating `SECRET_KEY` revokes share links. Keep the reset fingerprint logic covered by tests.

**Telegram webhook authentication depends on one shared secret:**
- Risk: `/telegram/webhook` (`bp/telegram.py` ~59-80) is CSRF-exempt and trusts only the `X-Telegram-Bot-Api-Secret-Token` header. If `TELEGRAM_WEBHOOK_SECRET` is empty the route returns 404, which is safe, but a weak secret is not validated.
- Files: `bp/telegram.py`, `config.py` (line ~133), `telegram_bot.py` (`api_call`, `send_message`)
- Current mitigation: Constant-time comparison (`hmac.compare_digest`), rate limit `120/minute`.
- Recommendations: Validate minimum length of `TELEGRAM_WEBHOOK_SECRET` at startup.

**Internal monitoring endpoints rely on nginx for protection:**
- Risk: `/healthz` and `/ai_metrics` (`bp/ops.py` ~87-115) are public in Flask. If the nginx snippet `/etc/nginx/snippets/ai_trainer-internal.conf` is removed or misconfigured, metrics and Redis/RQ status leak to the internet.
- Files: `bp/ops.py`, `docs/operations.md`
- Current mitigation: nginx restricts both to `127.0.0.1`.
- Recommendations: Add an in-app check on `request.remote_addr` for `/ai_metrics` as defence in depth.

**Redis-backed AI cache stores prompts' hash keys and full responses, including health data:**
- Risk: The cache key is the SHA-256 of the full prompt (`ai_generator.py` `_cache_key`, ~113), and the value is the model output. Prompts contain age, health conditions and limitations. Anyone with Redis access can read cached responses.
- Files: `ai_generator.py` (~97-150)
- Current mitigation: Redis listens on localhost (`REDIS_URL` default `redis://127.0.0.1:6379/0`); `_redis_host` avoids logging the full URL.
- Recommendations: Bind Redis to localhost only with a password (`requirepass`), and keep TTL (`GEMINI_CACHE_TTL`) short.

**Unauthenticated CSRF exemption outside the webhook:**
- Risk: `@csrf.exempt` is used on the Telegram webhook. It is the only exemption found in `bp/`, but any future exemption on a state-changing route would bypass CSRF.
- Files: `bp/telegram.py` (~59)
- Current mitigation: Route-level header check described above.
- Recommendations: Add a test that asserts the exempt list is exactly the webhook.

**Admin gate based on email list:**
- Risk: `/admin/metrics` (`bp/ops.py` ~125-133) is authorised by `ADMIN_EMAILS` in env. Changing the email of an admin account grants or revokes access without an audit trail.
- Files: `bp/ops.py`, `config.py` (line ~138)
- Current mitigation: Non-admins receive 404.
- Recommendations: Add a role column to `User` in a migration, or log admin access through `log_event`.

## Performance Bottlenecks

**Blocking Gemini calls in request threads when the queue is off:**
- Problem: With `USE_JOB_QUEUE=0`, plan generation and analysis run in the gunicorn worker. The worker is held for up to the Gemini timeout multiplied by the fallback model count.
- Files: `ai_generator.py` (`_call_with_fallback`, ~202-290; `_timed_call`, ~292), `bp/plan.py` (`perform_generation`, ~190), gunicorn config `-w 2 --timeout 240`
- Cause: Two gunicorn workers and a 240 s timeout means two concurrent generations saturate the service.
- Improvement path: Keep `USE_JOB_QUEUE=1` in production, and bound `GEMINI_MAX_WORKERS` against the worker count.

**Full-table history scans for statistics:**
- Problem: `_history_query` (`bp/history.py` ~44) and stats aggregations in `bp/stats.py` load all completed workouts for the user, then compute PRs and charts in Python.
- Files: `bp/history.py` (~44-70), `bp/stats.py`, `helpers.py` (`update_prs`)
- Cause: No aggregated columns or indexes beyond the primary key, and `Workout.results` is a JSON blob.
- Improvement path: Add an index on `Workout(user_id, completed, id)` in a migration generated through `flask db migrate`, and cache per-user PR maps.

**SQLite write contention:**
- Problem: The default database is SQLite with `connect_args timeout=30` (`config.py` ~73-80). Concurrent writes from gunicorn workers and the RQ worker serialise.
- Files: `config.py`, `tasks.py`, `bp/workout.py`
- Cause: AI analysis writes to `Workout` from the RQ worker while requests write to the same tables.
- Improvement path: Keep WAL mode enabled (documented in `AGENTS.md`), keep write transactions short in `tasks.py`, and plan a PostgreSQL move if write volume grows.

## Fragile Areas

**Patch-target coupling for AI functions:**
- Files: `ai_generator.py` (re-exports), `ai_analysis.py`, `ai_plan_gen.py`, `bp/plan.py`, `bp/workout.py`, `tests/test_ai_pipeline.py`
- Why fragile: `ai_analysis` and `ai_plan_gen` call `_generate`, `_extract_json` and `_normalize_plan` through `ai_generator` at call time (documented in `CLAUDE.md`). Tests must patch `ai_generator.<name>` or `bp.plan.<name>`. Patching the wrong module silently calls the real model.
- Safe modification: Patch the name in the module that uses it. Run `tests/test_module_sizes.py::test_facade_reexports` after any move.
- Test coverage: Re-export contract is tested; behavioural patching is not checked automatically.

**Circular import discipline:**
- Files: `tasks.py` (imports `app` lazily inside each function), `bp/*` (must not import `app`), `cli.py`
- Why fragile: A top-level `from app import ...` in a blueprint or in `tasks.py` causes an import cycle that appears only at worker start.
- Safe modification: Keep `from app import app, db` inside task functions. Check `tests/test_module_sizes.py::test_split_modules_import_standalone` after adding imports to the split modules.
- Test coverage: Standalone import tests cover seven modules only (`ai_plan_gen`, `ai_analysis`, `ai_normalize`, `ai_prompts`, `ai_safety`, `validation_options`, `plan_insights`).

**Plan JSON shape shared by two creation paths:**
- Files: `ai_generator.py`, `bp/constructor.py`, `bp/plan.py` (`save_workout_plan`, ~53), `validation.py`
- Why fragile: AI and manual constructor write the same `WorkoutPlan.data` shape (`week{N}` → `day{M}` → exercises). Any change to exercise keys (`exercise`, `sets`, `reps`, `weight`, `comment`) must be applied to both writers and to the readers in `bp/workout.py` and `report.py`.
- Safe modification: Validate with `validation.py` before saving, and extend `tests/test_workout_result.py` for any new key.
- Test coverage: Format is covered for the AI path; constructor round-trips need checking when the format changes.

**Telegram and mailer use background threads:**
- Files: `mailer.py` (~56), `ai_quota.py` (~66), `telegram_bot.py`
- Why fragile: Daemon threads are lost on worker restart, and failures are only logged. Reset emails and quota alerts can be silently dropped.
- Safe modification: Keep `background=False` for flows where delivery must be confirmed (for example the password reset confirmation in tests).
- Test coverage: `tests/conftest.py` stubs `no_weekly_debrief`; no test checks delivery failure handling.

## Scaling Limits

**Single SQLite file:**
- Current capacity: One writer at a time, WAL mode, 30 s busy timeout (`config.py` ~73-80).
- Limit: Write throughput degrades when AI analysis, workout saves and reminders run concurrently.
- Scaling path: Move `DATABASE_URL` to PostgreSQL. `config.py` already reads `DATABASE_URL`, so the change is configuration-only, but migrations and `ARRAY`/JSON usage need verification.

**Gemini quota and per-user daily limit:**
- Current capacity: `AI_DAILY_USER_LIMIT` per user and a global daily cap, counted in `ai_quota.py`.
- Limit: The global cap is a single fixed window, so one heavy user can exhaust it for everyone before the daily reset.
- Scaling path: Add a per-minute window in `ai_quota.consume`, and surface the global limit state on `/ai_metrics`.

**Exercise catalog in memory:**
- Current capacity: About 876 exercises loaded from `data/*.json` into `exercise_catalog.py` at import time.
- Limit: Each gunicorn worker and the RQ worker hold a full copy. Adding media metadata grows memory linearly per process.
- Scaling path: Serve the catalog from the `Exercise` table with an in-process LRU instead of loading every field into memory.

## Dependencies at Risk

**Gemini SDK and model fallback chain:**
- Risk: `ai_generator._call_with_fallback` depends on a hard-coded or configured chain of model IDs. Model deprecations cause fallbacks and latency spikes before any hard failure.
- Impact: Plan generation latency increases and fallback counts rise in `/ai_metrics`.
- Migration plan: Keep the model list in `config.py` (env-driven), and alert on `fallback_count` in `ai_metrics`.

**`pyTelegramBotAPI`-free Telegram client:**
- Risk: `telegram_bot.py` calls the Bot API with `urllib.request` directly (`api_call`, ~37-44). It does not use a maintained client, so error handling and retry behaviour are custom.
- Impact: Protocol changes in Bot API must be handled manually.
- Migration plan: Keep the current code but add retry on 429 with `retry_after`.

**Vendored Chart.js:**
- Risk: `static/vendor/chart.umd.min.js` is committed, so security updates require a manual replacement.
- Impact: Known vulnerabilities in the vendored version are not tracked by dependency tooling.
- Migration plan: Record the vendored version in `docs/operations.md` and check it on each release.

## Missing Critical Features

**No automated database backup verification:**
- Problem: `scripts/backup_db.py` exists, but no scheduled restore test is documented.
- Blocks: Confident recovery after an SQLite corruption or a bad migration.

**No admin-facing failure view for AI jobs:**
- Problem: Failed analyses and jobs are visible only in logs and `analysis_status`.
- Blocks: Triage of AI quality problems without SSH access to the server.

## Test Coverage Gaps

**Job queue failure paths:**
- What's not tested: `api_job_status` for `failed` RQ jobs and the user-facing message on failure.
- Files: `bp/plan.py` (~366-384), `tasks.py`, `tests/test_ai_pipeline.py`
- Risk: Regressions in the job status contract go unnoticed until the frontend polls.
- Priority: High

**Quota enforcement across processes:**
- What's not tested: `ai_quota.consume` with a shared Redis storage backend (tests use `memory://`).
- Files: `ai_quota.py`, `tests/`
- Risk: The multi-worker over-spend described above is not caught by CI.
- Priority: Medium

**Telegram webhook negative cases:**
- What's not tested: Requests with a wrong or empty secret header, and updates that carry no `message` key.
- Files: `bp/telegram.py`, `telegram_bot.py`
- Risk: Authentication regressions on the only CSRF-exempt route.
- Priority: High

**E2E suite is opt-in:**
- What's not tested: The Playwright suite under `tests/e2e` runs only with `pytest -m e2e` and is excluded from the CI gate.
- Files: `tests/e2e`, `pytest.ini`
- Risk: Front-end regressions in the constructor drawer and swipe handling (recent commits `f78a108`, `2a564d8`) reach production.
- Priority: Medium

**Forbidden-exercise filtering:**
- What's not tested: Behaviour when `EXERCISE_CATALOG_ENFORCE=0` and the model returns exercises outside the catalog.
- Files: `ai_normalize.py`, `ai_safety.py`, `config.py` (line ~176)
- Risk: A health-restricted exercise can reach a user plan if the enforcement flag is turned off.
- Priority: High

---

*Concerns audit: 2026-11-03*
