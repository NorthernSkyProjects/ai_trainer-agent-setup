# Stack Research

**Domain:** Brownfield hardening of a Flask + RQ + Redis + SQLite + google-genai workout app (Kachlog)
**Researched:** 2026-11-03
**Confidence:** MEDIUM-HIGH (versions and SDK/RQ/Flask behaviour verified against PyPI metadata, installed source in `.venv`, and vendor docs; Gemini model lifecycle is volatile and must be re-checked at pin time)

Scope: this is NOT a re-selection of the stack (Flask, SQLite, vanilla JS stay, see PROJECT.md Out of Scope). It answers: which versions and patterns to adopt for the six hardening areas (AI failure surfacing, sync/async unification, exception narrowing, test gaps, module splitting, security defence-in-depth), and what to avoid.

Confidence tags used below: **HIGH** = verified in installed source / PyPI JSON / vendor docs and cross-checked; **MEDIUM** = single authoritative source or reasoned from verified facts; **LOW** = needs a spike. Note: the GSD `classify-confidence` seam rates `webfetch`/`websearch` provider output LOW regardless of source. Where a claim rests only on a fetched web page it is tagged accordingly; claims verified by reading installed package source or PyPI metadata are tagged HIGH.

## Headline Findings (read these first)

1. **Python 3.10 is end-of-life (Oct 2026) and the ecosystem has started to leave it.** `google-genai 2.34.0` (released 2026-10-29) is `requires-python >=3.11`; `hypothesis`, `time-machine` and SQLAlchemy 2.1.x also require 3.11+. The GitHub workflow pins 3.10, while the dev venv and the GitLab runner use the host `python3` (3.12.3 here). pip on 3.10 silently resolves *older* libraries (e.g. SQLAlchemy 2.0.x, google-genai 2.33) than 3.12 does, so CI can test a different dependency set than prod runs. Fix: one Python (3.12) everywhere + a lockfile. (HIGH)
2. **Requirements are unpinned ranges with no lockfile.** `google-genai` ships roughly weekly (2.0.1 in May 2026 to 2.34.0 in Oct 2026, about 35 releases), so "green today, different tomorrow" is real. (HIGH)
3. **`rq>=1.16,<2` is two majors behind.** RQ 2.12.0 is the safe target. RQ 3.0.0 was released 2026-10-28 with breaking worker/callback internals: do not adopt it yet. (HIGH)
4. **The Gemini fallback chain contains dead/aliased IDs.** Per Google's deprecations page, `gemini-3.5-flash` auto-routes to `gemini-3.6-flash` and `gemini-3.7-flash` to `gemini-3.8-flash`, so those chain entries burn a fallback attempt on the *same* model. `gemini-2.5-flash` and `gemini-2.5-pro` shut down 2026-12-01. (MEDIUM, re-verify before pinning)
5. **`# noqa: BLE001` comments already in the code do nothing**, because ruff only selects `E4/E7/E9/F`. Enabling `BLE` turns the exception-narrowing goal into an enforced ratchet. (HIGH)
6. **Concrete bug found while researching:** `bp/telegram.py` calls `hmac.compare_digest(secret, got)` with two `str`. If the header contains a non-ASCII character this raises `TypeError` (verified), giving HTTP 500 instead of 404 on the only CSRF-exempt route. Compare bytes instead. (HIGH)

## Recommended Stack

### Core Technologies (change set for the hardening milestone)

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| CPython | **3.12.x** (3.13 acceptable) | Runtime for prod, dev, CI | 3.10 is EOL; 3.12 is security-supported to Oct 2028, is what the hosts already run, and unlocks `google-genai >=2.34`, `hypothesis`, `time-machine`. Flask 3.1, Flask-Limiter 4.1, Flask-WTF 1.3 all support it. Set `ruff target-version = "py312"` and change `.github/workflows/ci.yml` from `'3.10'` | HIGH |
| google-genai | `>=2.34,<3` (lock exact) | Gemini client | Already in use. Provides typed errors (`APIError`/`ClientError`/`ServerError` with `.code`, `.status`, `.message`), per-request `http_options.timeout` (ms), `HttpRetryOptions`, `response_schema`/`response_json_schema` with `response.parsed`. All verified in installed 2.34.0 source | HIGH |
| rq | **`>=2.12,<3`** (from `>=1.16,<2`) | Async AI jobs | 2.x requires explicit `connection=` on `Job`/`Queue.all`/`@job` (project already passes it in `jobs.py`), needs Redis server >= 4, Python >= 3.9. Brings `Retry`, `Callback` objects, worker-name-in-logs, redis-py 8 compatibility fixes. Skip 3.0.0 (released 6 days ago, breaking worker internals, `rate_limit` becomes a reserved kwarg of `enqueue`) | HIGH |
| redis (py) | `>=5,<8` (currently resolves 6.4.0) | Cache, queue, limiter storage | `limits[redis]` caps `redis<8.0.0`, so do not float to 8.x even though PyPI has 8.1.0. Keep the cap until limits lifts it | HIGH |
| Flask-Limiter + limits | keep `Flask-Limiter>=4.1,<5` (4.1.1), `limits` 5.8.0 | Rate limits and AI quota | Current; no change needed. Hardening is in configuration (fail closed on `memory://` in prod) and tests, not a library swap | HIGH |
| Flask / Werkzeug | keep `Flask>=3.1,<4` (3.1.3), Werkzeug 3.1.9 | Web | `SECRET_KEY_FALLBACKS` exists in 3.1 (verified in `flask/sessions.py`) for key rotation | HIGH |
| SQLAlchemy | **declare explicitly: `SQLAlchemy>=2.0.16,<2.2`** | ORM | Currently only transitive; 2.1.6 installs on 3.12 and 2.0.x on 3.10. Pin the range deliberately and let the lockfile choose. Flask-SQLAlchemy 3.1.1 (last release 2023) works with 2.1.6 in the dev venv | MEDIUM |
| pydantic | **declare explicitly: `pydantic>=2.11,<3`** | Validate AI JSON, Gemini response schemas | Already installed transitively by google-genai. Declaring it makes the dependency intentional: used for `response_schema` models and `model_validate` of analysis/debrief payloads | HIGH |

### Database

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| SQLite (WAL) | keep | Primary store | Out of scope to replace. `journal_mode=WAL`, `synchronous=NORMAL`, `busy_timeout=30000` already set in the `connect` listener (`app.py` lines 67-69). Keep write transactions short in `tasks.py` | HIGH |
| Alembic via Flask-Migrate | keep `>=4.1,<5` | Migrations (autogenerate only) | New columns for this milestone: `Workout.analysis_error` (short code) and `User.is_admin`. Use `render_as_batch=True` (already set) and a `server_default` so SQLite batch copy works | HIGH |
| `PRAGMA foreign_keys=ON` | optional | Referential integrity | Not currently set (only three pragmas). Enabling it can expose pre-existing orphan rows; do it only after a one-off orphan check. Defer, not part of this milestone's must-haves | MEDIUM |
| `BEGIN IMMEDIATE` for writers | defer | Avoid `SQLITE_BUSY_SNAPSHOT` | Documented SQLAlchemy/pysqlite recipe (own `BEGIN` in event hooks). Adopt only if "database is locked" appears in logs after the RQ worker and web workers write concurrently; 30 s busy timeout masks most contention | MEDIUM |

### Infrastructure

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| uv (as a tool, not a runtime change) | 0.13.x | Generate `requirements.lock` | `uv pip compile requirements.txt -o requirements.lock --python-version 3.12` gives reproducible installs while `deploy/deploy.sh` keeps plain `pip install -r requirements.lock`. `pip-tools` (`pip-compile`) is an equally valid choice; pick whichever the maintainer prefers, but pick one | MEDIUM |
| pip-audit | 2.10.1 | CVE scan of the lock | Add to the GitLab `test` stage against `requirements.lock`; start with `allow_failure: true`, then make it blocking | HIGH |
| Renovate (GitLab) | n/a | Scheduled dependency PRs | GitLab has no Dependabot. Needed because google-genai moves weekly and Chart.js is vendored (record its version in `docs/operations.md`) | MEDIUM |
| gunicorn | keep `>=26,<27` (26.2.0) | WSGI | Optionally `--worker-class gthread --threads 4` so inline AI calls (queue off) do not pin a whole process. Prefer keeping `USE_JOB_QUEUE=1` in prod | MEDIUM |
| Redis server hardening | config only | Protect cached health-data responses | Bind `127.0.0.1`, set `requirepass` or an ACL user, put credentials in `REDIS_URL` in `/etc/ai_trainer.env`, keep `GEMINI_CACHE_TTL` short | HIGH |

### Supporting Libraries (new or newly adopted)

| Library | Version | Purpose | When to Use | Confidence |
|---------|---------|---------|-------------|------------|
| fakeredis | 2.40.0 | In-memory Redis for tests | RQ job-failure tests (`Queue(connection=FakeStrictRedis())`, `SimpleWorker`, or `is_async=False`) and quota-sharing tests; avoids a Redis service in CI | HIGH |
| pytest-socket | 0.8.1 | Block real network in tests | Autouse `--disable-socket`; makes "patched the wrong module, silently called real Gemini" (CONCERNS: Fragile Areas) fail loudly instead of spending quota. Allow localhost only for the e2e marker | HIGH |
| hypothesis | 6.170.x (needs Py >= 3.11) | Property tests | One property: for any model output (including exercises outside the catalog) and any limitation/age/health profile, `_normalize_plan` output never contains a forbidden exercise. Directly guards the Core Value; covers the `EXERCISE_CATALOG_ENFORCE=0` gap | MEDIUM |
| time-machine | 3.6.0 (Py >= 3.11) | Time travel in tests | Quota day-rollover and token expiry tests. `freezegun` 1.5.5 is the fallback. Verify against `limits` in-memory storage, which has its own expiry timer | MEDIUM |
| import-linter | 2.15 | Enforce import layering | Contracts: `bp.*` must not import `app`; `ai_*` leaf modules must not import `bp`; new split modules stay acyclic. Turns the "circular import discipline" convention into a CI check | MEDIUM |
| pytest-randomly | 5.0.0 | Random test order | Optional. Module-level singletons in `ai_generator.py` make order dependence likely; this flushes it out. Add after lazy-init refactor, not before | MEDIUM |
| sentry-sdk[flask,rq] | 2.73.x | Error tracking for unexpected exceptions | Optional/deferred. Once handlers are narrowed, real bugs hit the 500 handler and only appear in logs; Sentry (or self-hosted GlitchTip) makes them visible. RQ 2.0 removed its built-in Sentry hook, so use sentry-sdk's `RqIntegration`. Must set `send_default_pii=False` and scrub request bodies (health data) | MEDIUM |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| ruff 0.17.3 (keep `>=0.6,<1`, raise floor to `>=0.15`) | Lint | Extend `select` to `["E4","E7","E9","F","B","BLE","S110","S112","S104","S105","S106","S324","S608","TRY203","TRY400","RUF100"]`. Introduce `BLE001` with a `per-file-ignores` list of current offenders (`bp/workout.py`, `bp/plan.py`, `bp/stats.py`, `bp/ops.py`, `tasks.py`, `helpers.py`, `ai_generator.py`) and shrink the list phase by phase. `RUF100` flags the stale `# noqa` comments. Keep `E501` ignored; do not run `ruff format` (project rule) |
| pytest 9.2 + pytest-cov 7.1 | Tests/coverage | Add `--cov-fail-under=<current>` as a ratchet (set to today's number, only raise). Keep e2e out of the default gate |
| Playwright (existing `>=1.49,<2`) | E2E | Add a separate GitLab job `e2e` with `allow_failure: true` (nightly script `scripts/nightly_e2e.sh` already exists) to cover the drawer/swipe regressions without blocking deploys |
| bandit | not needed | ruff's `S` rules cover the useful subset; do not add a second scanner |

## Installation

```bash
# 1. Python: bump CI to 3.12 (.github/workflows/ci.yml python-version, ruff.toml target-version = "py312")

# 2. requirements.txt: edit ranges
#    google-genai>=2.34,<3        rq>=2.12,<3        redis>=5,<8
#    SQLAlchemy>=2.0.16,<2.2      pydantic>=2.11,<3
# 3. Generate the lock (maintainer tool, not a prod dependency)
uv pip compile requirements.txt -o requirements.lock --python-version 3.12
uv pip compile requirements-dev.txt -o requirements-dev.lock --python-version 3.12
# CI/deploy then install from the lock files:
pip install -r requirements-dev.lock

# 4. New dev-only dependencies (requirements-dev.txt)
#    fakeredis>=2.40,<3  pytest-socket>=0.8,<1  hypothesis>=6.170,<7
#    time-machine>=3,<4  import-linter>=2.15,<3  pip-audit>=2.10,<3
#    optional: pytest-randomly>=5,<6   sentry-sdk[flask,rq]>=2.73,<3 (prod, only if adopted)
```

Deploying the RQ 2.x upgrade: drain the `ai` queue first (low volume), then restart `ai_trainer_worker`; in-flight 1.16 jobs should not straddle the upgrade.

## Patterns by Hardening Area

### 1. AI failure surfacing (specific reason + retry)

- Add `ai_errors.py` with a small hierarchy: `AIError(Exception)` carrying `code` (stable machine string) and `user_message` (Russian text), subclasses `AIQuotaError`, `AITimeoutError`, `AIUnavailableError` (429/5xx/all models exhausted), `AIInvalidResponseError` (empty, MAX_TOKENS, bad JSON, schema failure), `AIConfigError` (no key/client). (HIGH, pure Python)
- Map SDK failures by **type and attribute**, not substring: replace `'429' in str(e)` / `'RESOURCE_EXHAUSTED' in err` in `ai_generator._call_with_fallback` with `except genai_errors.APIError as e: e.code in (429, 503)` / `e.status`. `ClientError` = 4xx, `ServerError` = 5xx (verified: `ClientError.__mro__` = `ClientError, APIError, Exception`). Treat `httpx.TimeoutException` and `httpx.TransportError` as timeout/unavailable (httpx is a hard dependency of google-genai). (HIGH)
- Persist the reason: new nullable `Workout.analysis_error` (code only, never the raw exception text) via `flask db migrate`. `_analysis_state` in `bp/workout.py` renders a specific message and a "Повторить" action; retry endpoint resets status and re-runs the shared helper. Do not auto-retry AI calls in RQ: `Retry(max=...)` would re-run the whole task and **double-consume the per-user quota** (`ai_quota.consume` is called per attempt). User-initiated retry is the safer UX. (HIGH reasoning)
- RQ side: tasks catch `AIError` and return `{'status': 'error', 'code': ..., 'message': ...}` (job finishes normally, so `api_job_status` returns the specific message just like the inline path). Unexpected exceptions propagate so RQ marks the job failed; register `on_failure=Callback(report_failure)` on `enqueue` with the documented signature `(job, connection, type, value, traceback)` to flip `analysis_status='failed'` and store `analysis_error='internal'` when the worker dies or the job times out. In `api_job_status` branch on `job.is_failed`, log `job.exc_info` server-side, and return only a generic message plus a correlation `job_id`. Never send `exc_info` to the browser. (HIGH, signature verified in RQ docs)
- Set `failure_ttl` (e.g. 7 days instead of the default 1 year) and keep `result_ttl` above the frontend polling window. (HIGH)

### 2. One implementation for sync and async AI

- Add `jobs.run_or_enqueue(task_path, *args, meta=None)`: if `USE_JOB_QUEUE` is on, enqueue and return `{'job_id': ...}`; otherwise import the same top-level task function and call it in-process, returning the same `{'status': ...}` dict shape. Both branches execute the *same* `tasks.task_*` function, so `_analyze_extra_inline` (`bp/workout.py`) and `tasks._analyze_workout` collapse into one `ai_analysis.analyze_and_build_payload(...)` helper. (HIGH, no new library)
- Alternative that needs no custom helper: `Queue(..., is_async=False)` makes RQ run the job inline on `enqueue`. It still needs a Redis connection (job state is stored in Redis), so it is only attractive in tests with fakeredis. Prefer the custom helper in the app. (MEDIUM)
- Make dev mirror prod: dev `.env` already has `USE_JOB_QUEUE=1`; add one parametrised test fixture that runs the endpoint tests under both modes (inline and fakeredis+`SimpleWorker`) so the branches cannot diverge again.

### 3. Narrowing `except Exception`

- Boundary rule: only `ai_generator` (client, fallback loop) may catch `genai_errors.APIError`, `httpx.HTTPError`, `concurrent.futures.TimeoutError`, `json.JSONDecodeError`, `pydantic.ValidationError`, and re-raise as `AIError`. Everything above it catches `AIError` only. Programming errors (`KeyError`, `TypeError`) propagate to the global 500 handler. (HIGH)
- Replace the thread pool: pass `config=types.GenerateContentConfig(..., http_options=types.HttpOptions(timeout=<ms>))` per call (field verified in installed SDK; unit is **milliseconds**). Removes `_EXECUTOR`, `future.cancel()` and the orphaned-thread comment in `_call_with_fallback`. Caveat: httpx timeouts are per-phase, not a hard total, so keep the `GEMINI_TOTAL_TIMEOUT` budget check between models. (MEDIUM)
- Do not stack retries: keep the model-chain fallback as the retry mechanism. If a same-model retry is wanted, use the SDK's own `HttpRetryOptions(attempts=2, http_status_codes=[503])` rather than adding `tenacity` (tenacity is already a transitive dep of the SDK, but a second retry layer multiplies latency inside the 240 s gunicorn timeout). (MEDIUM)
- Structured outputs: for fixed-shape payloads (workout analysis, weekly debrief) pass `response_schema=<PydanticModel>` and read `response.parsed`/`model_validate`; on failure raise `AIInvalidResponseError`. For the plan JSON (dynamic `week{N}` -> `day{M}` keys) keep `_extract_json` + `ai_normalize`: schema support for dynamic keys is unverified, so treat it as a spike. (MEDIUM / LOW for the plan)
- Lazy singletons: initialise the Redis cache (and its `ping()`) on first use inside `_cache_get`/`_cache_set` with a `reset_for_tests()` hook; no library needed. (HIGH)
- Enforcement: the `BLE` ruff ratchet above.

### 4. Gemini model chain (config, not code)

Per Google's deprecations page (fetched 2026-11-03, no date shown on the page, re-verify at pin time): `gemini-3.8-flash` (2026-09-02, newest stable), `gemini-3.6-flash` (2026-07-21), `gemini-3.5-flash-lite` (2026-07-21) have no shutdown date; `gemini-3.5-flash` and `gemini-3.7-flash` are no longer selectable and route to 3.6/3.8; `gemini-2.5-flash` and `gemini-2.5-pro` shut down 2026-12-01.

Recommended `GEMINI_MODELS` default: `gemini-3.8-flash,gemini-3.6-flash,gemini-3.5-flash-lite` (three *distinct* models). Drop the `*-latest` aliases from a safety-relevant chain (silent behaviour drift on a health-adjacent prompt) and drop alias entries that route to a model already in the list. Alert on `fallback_count` in `/ai_metrics` as CONCERNS suggests. (MEDIUM)

### 5. Test coverage gaps

| Gap (CONCERNS) | Tooling | Approach |
|----------------|---------|----------|
| Job failure paths | fakeredis + RQ `SimpleWorker` | Enqueue a task that raises; assert `api_job_status` returns the error shape for `failed`, specific message for `AIError` result, 404 for another user's job. Construct SDK errors directly: `errors.ClientError(429, {'error': {'status': 'RESOURCE_EXHAUSTED', 'message': 'x'}})` (constructor `APIError(code, response_json, response=None)` verified) |
| Telegram webhook negatives | Flask test client | wrong, empty, missing, over-long and **non-ASCII** secret header all -> 404 (never 500); update without `message`; webhook disabled when secret empty; test that the set of `csrf.exempt` views is exactly `{telegram.telegram_webhook}` |
| Forbidden exercise with `EXERCISE_CATALOG_ENFORCE=0` | hypothesis + parametrised fixtures | Property test described above, plus a fixed regression table of (limitation -> forbidden exercise) |
| Quota across processes | `limits` storage shared between two `FixedWindowRateLimiter` instances; fakeredis for Redis semantics | Prove the counter is shared when storage is shared; add a startup test that `ProductionConfig` with `memory://` and `>1` worker fails closed |
| Wrong-module patching | pytest-socket + an autouse fixture that unsets `GOOGLE_API_KEY` | Any un-patched model call raises immediately |
| E2E not in gate | Playwright, separate non-blocking job | Promote to blocking after stability is shown |

Known limitation (MEDIUM): `ai_quota.consume` does `test` then `hit`, which is not atomic across processes; worst case is a small overshoot of the cap. Acceptable; document rather than rewrite.

### 6. Splitting near-limit modules

- No library. Prefer **extracting non-route logic into sibling service modules** (for example `helpers.py` -> `records.py` (PR logic), `share_tokens.py`, `formatting.py`; `bp/workout.py` analysis rendering -> `workout_analysis.py`) and leaving route functions and the single `Blueprint` object where they are. Keep `helpers.py` as a re-export facade, the same pattern the repo already uses for `ai_generator`. (HIGH)
- Avoid turning `bp/workout.py` into a package of route files. Tests patch `bp.workout.<name>` (documented in CLAUDE.md); moving a function changes the patch target and the failure mode is a silent real-model call. If a route split is unavoidable, move tests and patches in the same commit and run `pytest-socket` to catch misses. (HIGH)
- Add `import-linter` contracts before the split, then extend `tests/test_module_sizes.py::test_split_modules_import_standalone` to every new module. (MEDIUM)
- Do the splits *before* the AI-error refactor touches the same files (see Phase notes below).

### 7. Security defence-in-depth

- **`/ai_metrics` in-app check:** `ipaddress.ip_address(request.remote_addr).is_loopback` OR a logged-in admin; otherwise `abort(404)` (not 403, same as `/admin/metrics`). This is only meaningful because prod enables `ProxyFix(x_for=1)` when `TRUST_PROXY` (default true in production; verified `app.py` lines 57-58), which makes `remote_addr` the real client rather than nginx's loopback address. Test with `environ_overrides={'REMOTE_ADDR': ...}`, and confirm the nginx snippet *overwrites* rather than appends client-supplied `X-Forwarded-For`. Alternative for machine callers: a `METRICS_TOKEN` header checked with `hmac.compare_digest` on bytes. Keep `/healthz` minimal and public (no Redis/RQ detail). (HIGH)
- **Webhook secret:** Telegram allows `secret_token` of 1-256 chars from `A-Z a-z 0-9 _ -` (official Bot API docs). Enforce in `config.py` production startup: regex `^[A-Za-z0-9_-]{32,256}$`, fail closed otherwise; generate with `secrets.token_urlsafe(32)`. Compare as bytes: `hmac.compare_digest(secret.encode(), got.encode('utf-8', 'ignore'))` (fixes the TypeError 500). Add the 429 `retry_after` handling to `telegram_bot.api_call` while there. (HIGH)
- **Admin role:** `User.is_admin` Boolean (`server_default` false) via Alembic autogenerate, a `flask --app app promote-admin --email` CLI command in `cli.py`, `log_event('admin_access', ...)` on `/admin/metrics`. Keep `ADMIN_EMAILS` only as a one-time bootstrap. Do not add Flask-Security/Flask-Principal/RBAC libraries for a single role. (HIGH)
- **Key rotation without killing share links:** use `SECRET_KEY_FALLBACKS` (Flask 3.1, verified: fallbacks first, current key last) and pass the same list to the `URLSafeTimedSerializer` instances in `bp/history.py` and `bp/auth.py` (itsdangerous accepts a key list, newest last). Document the procedure in `docs/operations.md`. Keep distinct salts. (MEDIUM; spike the serializer change in one test)
- **Config fail-closed checks** (all in `get_config()`): production + `RATELIMIT_STORAGE_URI` startswith `memory://` and workers > 1; webhook secret too weak; `SECRET_KEY` from `instance/.secret_key` while bound to a non-loopback address.
- **Redis cache with health data:** `requirepass`/ACL, localhost bind, short TTL. Optional: key the cache with an HMAC of the prompt under a server secret instead of plain SHA-256 so a Redis reader cannot confirm guesses; do not encrypt values (no key-management story to justify it). (MEDIUM)
- **Do not add Flask-Talisman**: the app already sets CSP and security headers in `after_request` with a report endpoint; a second header layer would conflict. (HIGH)

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| RQ 2.12 | RQ 3.0.0 | After 2-3 weeks of upstream patch releases and a clean run of `tests/test_tasks_jobs.py`; not needed for any hardening goal |
| RQ 2.12 | Celery / Dramatiq / arq / Huey | Only if you outgrow one queue and one worker; migration cost far exceeds this milestone's value |
| Custom `run_or_enqueue` | `Queue(is_async=False)` | In tests with fakeredis, where inline-in-Redis semantics are convenient |
| Domain `AIError` hierarchy | Return `(ok, error_string)` tuples (current) | Never for new code: strings lose type and cannot drive retry/UX decisions; keep the tuple shape only at the `perform_*` boundary until callers are migrated |
| SDK `HttpOptions.timeout` | ThreadPoolExecutor + `future.result(timeout)` (current) | If a future SDK/transport ignores request timeouts; today the thread approach only adds orphan threads |
| uv or pip-tools lockfile | Poetry/PDM migration | Never here: forces deploy-script and CI rewrites for no hardening gain |
| fakeredis | Real Redis service in CI | If tests need Lua/streams parity; GitLab shell runner has no service containers anyway |
| Sentry/GlitchTip (deferred) | Admin "failed jobs" page built on `FailedJobRegistry` | If health-data egress to a third party is unacceptable; this is the better first step and matches the CONCERNS item "admin-facing failure view" |
| import-linter | Convention + `test_module_sizes.py` only | If the contract set stays under ~3 rules, a plain test that parses imports is enough |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Python 3.10 in CI/prod | EOL Oct 2026; `google-genai 2.34`, `hypothesis`, `time-machine`, SQLAlchemy 2.1 need >= 3.11; CI resolves a different dependency set than prod | Python 3.12 everywhere + lockfile |
| RQ 3.0.0 right now | Released 2026-10-28; breaking changes to worker methods, callback execution, dependent-job states | `rq>=2.12,<3` |
| redis-py 8.x | `limits[redis]` caps `<8` | `redis>=5,<8` |
| `rq-scheduler` | Superseded by RQ's built-in scheduling; the project already uses systemd timers | systemd timers (existing) |
| `rq-dashboard` exposed on the web | Job args/results include health-profile data; extra attack surface | Small admin page over `FailedJobRegistry`, behind `is_admin` |
| `rq.Retry` on AI tasks | Re-runs consume quota again and can duplicate side effects | User-initiated retry button |
| `tenacity` or another retry wrapper around Gemini calls | SDK has `HttpRetryOptions`; stacking with model fallback multiplies latency | Model-chain fallback (+ optional SDK retry for 503) |
| `*-latest` Gemini aliases and routed legacy IDs in the chain | Silent model changes; duplicates burn fallback attempts | Explicit, distinct model IDs from the deprecations page |
| String-matching error codes (`'429' in str(e)`) | Fragile, locale/format dependent | `errors.APIError.code`/`.status` |
| `hmac.compare_digest(str, str)` on request headers | `TypeError` on non-ASCII input -> 500 | Compare bytes |
| `request.remote_addr` loopback check **without** ProxyFix | Behind nginx every request looks like 127.0.0.1, so the check always passes | Confirm `TRUST_PROXY`/ProxyFix is active, or use a token |
| Flask-Talisman | Duplicates the existing CSP/header layer | Existing `after_request` |
| Flask-Security / Flask-Principal / casbin for the admin gate | One boolean role does not justify a framework | `User.is_admin` column |
| Hand-written Alembic migrations | Project rule | `flask --app app db migrate` |
| Moving routes into `bp/<name>/` packages as the first split step | Changes patch targets, silent real-model calls | Extract service modules, keep route modules and facade re-exports |
| Enabling `foreign_keys=ON` or Postgres in this milestone | Orphan-data risk / explicitly out of scope | Revisit if write contention appears |

## Stack Patterns by Variant

**If `USE_JOB_QUEUE=1` (prod):**
- Web process only enqueues and polls `/api/job/<id>`; the RQ worker calls the shared task; quota is consumed once at enqueue (or once in the task, but pick one place and test it).
- Because failures are rendered from the finished-job result, user-visible reasons work identically to inline mode.

**If `USE_JOB_QUEUE=0` (dev without Redis, tests):**
- `run_or_enqueue` calls the task function directly; gunicorn needs threads or more workers so one AI call does not saturate a 2-worker service. Never use this mode in prod.

**If the model returns plan JSON for a profile with limitations (always):**
- Keep post-normalisation as the safety boundary even when a response schema is added. A schema constrains shape, not medical safety; the property test guards this.

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| google-genai 2.34.0 | Python >= 3.11 | 2.33.0 is the last release supporting 3.10 (`requires-python >=3.10` through 2.33.0) |
| rq 2.12.0 | redis-py >= 5.0.1 (RQ 2.9.1+ works with redis-py 8), Redis server >= 4 | RQ 2.3.3 disallowed redis-py 6.0.0; irrelevant at 2.12 |
| limits 5.8.0 (via Flask-Limiter 4.1.1) | `redis<8` | Caps redis-py at 7.x |
| Flask-SQLAlchemy 3.1.1 | SQLAlchemy 2.0.16-2.1.x | Library last released Sept 2023; works in dev venv with 2.1.6; keep an eye on it |
| hypothesis 6.170 / time-machine 3.6 | Python >= 3.11 | Another reason to leave 3.10 |
| Flask 3.1.3 | itsdangerous list-of-keys serializers | `SECRET_KEY_FALLBACKS` lists old keys first, current key last |
| ruff 0.17.3 | Python target `py312` | Config change in `ruff.toml` |

## Phase Ordering Implications (for roadmap)

1. **Foundation first:** Python 3.12 + lockfile + CI alignment + RQ 2.12 + pytest-socket/fakeredis scaffolding. Everything else benefits and it is low-risk and revertible.
2. **Splits before refactors:** extract service modules from `helpers.py`, `bp/workout.py`, `bp/plan.py`, `bp/stats.py`, `validation.py` while the code is unchanged semantically, with import-linter in place.
3. **AI boundary:** `ai_errors.py`, SDK-type-based mapping, per-request timeouts, lazy singletons, shared analysis helper, `run_or_enqueue`, `analysis_error` column, specific job status, user retry. Turn on `BLE` ratchet as each file is converted.
4. **Tests for the gaps** are written alongside (3), not after: failure-path tests are how the boundary is proven.
5. **Security defence-in-depth** is independent and small: webhook secret validation + bytes compare, `/ai_metrics` guard, `is_admin`, config fail-closed checks, key-fallbacks.

Needs deeper research at plan time: response-schema support for the dynamic-key plan JSON (spike); `SECRET_KEY_FALLBACKS` + `URLSafeTimedSerializer` key-list behaviour for share/reset tokens; whether the prod venv is really 3.12 (confirm on the Amsterdam host before bumping CI); live re-check of the Gemini model list at the moment of pinning.

## Sources

- PyPI JSON API (queried 2026-11-03): google-genai 2.34.0 (`>=3.11`, 2.33.0 `>=3.10`), rq 2.12.0 / 3.0.0, redis 8.1.0, Flask 3.1.3, Flask-Limiter 4.1.1, limits 5.8.0 (`redis<8.0.0` extra), Flask-SQLAlchemy 3.1.1, SQLAlchemy 2.1.6, fakeredis 2.40.0, pip-audit 2.10.1, ruff 0.17.3, hypothesis 6.170.14, time-machine 3.6.0, import-linter 2.15, pytest-socket 0.8.1, sentry-sdk 2.73.0, uv 0.13.7 - HIGH
- Installed source in `/root/ai_trainer-gsd/.venv/lib/python3.12/site-packages/google/genai` (`errors.py`, `types.py`: `APIError`, `ClientError`, `ServerError`, `HttpRetryOptions`, `HttpOptions.timeout` in ms, `GenerateContentConfig.http_options`) and `flask/sessions.py` (`SECRET_KEY_FALLBACKS`) - HIGH
- RQ changelog https://raw.githubusercontent.com/rq/rq/master/CHANGES.md (2.x / 3.0 breaking changes) - MEDIUM (web fetch, summarised)
- RQ docs https://python-rq.org/docs/ (callback signatures), https://python-rq.org/docs/exceptions/ (`Retry` requires `--with-scheduler` for intervals, exception handlers), https://python-rq.org/docs/jobs/ (`result_ttl`, `failure_ttl`, `exc_info`) - MEDIUM
- Telegram Bot API `setWebhook` https://core.telegram.org/bots/api#setwebhook (`secret_token` 1-256 chars, `A-Z a-z 0-9 _ -`) - MEDIUM
- Google Gemini deprecations https://aistudio.google.com/docs/deprecations (redirected from ai.google.dev/gemini-api/docs/deprecations; undated, volatile) - LOW per seam, first-party; re-verify
- Python 3.10 EOL coverage via web search (python.org devguide lists "October 2026"; HeroDevs, discuss.python.org thread) - MEDIUM
- SQLite WAL / `BEGIN IMMEDIATE` guidance via blogs/wikis (no official doc fetched) - LOW; hence the "defer" recommendation
- Local code read: `ai_generator.py`, `ai_quota.py`, `tasks.py`, `jobs.py`, `bp/plan.py`, `bp/telegram.py`, `app.py`, `config.py`, `.env.example`, `ruff.toml`, `pytest.ini`, CI files; Python behaviour of `hmac.compare_digest` with non-ASCII `str` verified by execution - HIGH

---
*Stack research for: Flask + RQ + Redis + SQLite + google-genai brownfield hardening*
*Researched: 2026-11-03*
