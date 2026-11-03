---
last_mapped_commit: 2a564d876b35351241cb5efc49ec110591df812d
last_mapped_at: 2026-11-03
---
# Testing Patterns

**Analysis Date:** 2026-11-03

## Test Framework

**Runner:**
- pytest 9.x (`requirements-dev.txt`: `pytest>=9,<10`)
- Plugins: `pytest-flask>=1.3,<2`, `pytest-cov>=5,<8`, `playwright>=1.49,<2` (e2e only)
- Config: `pytest.ini` (`testpaths = tests`, `addopts = -q -m "not e2e"`, registers the `e2e` marker)

**Assertion Library:**
- Plain `assert` statements (pytest rewriting). No assertion library beyond pytest.

**Linting of tests:**
- Tests are linted by the same ruff config as the app (`ruff.toml`); they are not excluded.

**Run Commands:**
```bash
.venv/bin/python -m pytest -q                              # Run all tests (e2e excluded by default)
.venv/bin/python -m pytest tests/test_workout.py::test_auto_prefill_applies_suggestion   # Single test
.venv/bin/python -m pytest -q --cov --cov-report=term      # Coverage (as in CI)
.venv/bin/ruff check .                                     # Lint (required before commit)
.venv/bin/python -m pytest -m e2e tests/e2e                # Playwright e2e (opt-in, needs chromium)
```

Without the venv: `pytest -q`, `ruff check .`.

**CI:**
- GitLab CI `test` stage (`.gitlab-ci.yml`) installs `requirements-dev.txt` into `.ci-venv`, runs `pytest -q --cov --cov-report=term`, then `ruff check .`. The `coverage:` regex reads the `TOTAL` line.
- GitHub Actions (`.github/workflows/ci.yml`) runs `ruff check .` and `pytest` on Python 3.10.
- `deploy-prod` requires `test` to pass (`needs: [test]`), so any red test blocks deploy to production.

## Test File Organization

**Location:**
- All unit/integration tests live in `tests/` flat (no subdirectories except `tests/e2e/`).
- Browser tests live in `tests/e2e/` and are excluded from the default run via `addopts = -m "not e2e"`.
- Shared fixtures: `tests/conftest.py`. Shared AI test data: `tests/ai_fixtures.py` (imported as a module, not a fixture).

**Naming:**
- Files: `test_<feature>.py` matching a product feature or module: `test_ai_generator.py`, `test_ai_pipeline.py`, `test_workout_submit.py`, `test_constructor.py`, `test_history_context.py`.
- E2E files: `test_<feature>_e2e.py` (for example `tests/e2e/test_workout_result_e2e.py`) or `test_<feature>.py` where the file is already in `tests/e2e/` (`test_pwa_offline.py`, `test_smoke.py`).
- Functions: `test_<expected behaviour>` (about 625 test functions across 51 files).

**Structure:**
```
tests/
├── conftest.py            # env isolation, app/client/user/plan fixtures, running_server
├── ai_fixtures.py         # synthetic Gemini responses (plan_json, valid_response, ...)
├── test_*.py              # unit + integration (Flask test client, SQLite temp DB)
└── e2e/
    └── test_*.py          # opt-in browser tests (module-level `pytestmark = pytest.mark.e2e`), use root `running_server`
```

## Test Environment Isolation (critical)

`tests/conftest.py` sets environment variables **before** `import app`. Keep this ordering. Changing it makes tests hit the dev-stand database, Redis or Telegram.

Key settings forced by the conftest:
- `DATABASE_URL` → a temp SQLite file under `tempfile.mkdtemp(prefix='ai_trainer_tests_')`.
- `RATELIMIT_ENABLED=0`, `RATELIMIT_STORAGE_URI=memory://`.
- `ALERT_TELEGRAM_TOKEN=''`, `ALERT_TELEGRAM_CHAT_ID=''` (no real Telegram messages).
- `AI_QUOTA_ENABLED=0`, `AI_CACHE_REDIS=0`, `USE_JOB_QUEUE=0` (in-memory cache, inline generation).
- `SECRET_KEY` and `GOOGLE_API_KEY` default to dummy values via `setdefault`.

Do not rely on values from `.env` in tests. Use `os.environ.setdefault` only for values a test genuinely needs.

## Test Structure

**Core fixtures (`tests/conftest.py`):**

| Fixture | Purpose |
|---------|---------|
| `app` | Sets `TESTING=True`, `WTF_CSRF_ENABLED=False`; `drop_all` + `create_all` per test; tears down. |
| `client` | `app.test_client()` on the `app` fixture. |
| `csrf_app` | Same `app`, with CSRF enabled (for CSRF tests). |
| `user` | Confirmed user (`test@example.com`, password `secret1`, onboarding complete, consents set). |
| `other_user` | Second user for ownership/isolation tests (`other@example.com`, password `secret2`). |
| `auth_client` | `client` with a Flask-Login session injected via `session_transaction()`. |
| `plan` | `WorkoutPlan` for `user` with 8 weeks x 3 days x 5 exercises. |
| `plan_data` | Factory `plan_data(duration=8, freq=3, n_ex=5)` returning a plan dict. |
| `running_server` | Live Werkzeug server on a free port, for e2e tests. |

**Suite Organization:**
```python
# tests/test_workout.py (abridged)
import bp.workout as workout_bp
from models import db, Workout, WorkoutPlan


def test_auto_prefill_applies_suggestion(auth_client, plan, monkeypatch):
    monkeypatch.setattr(
        workout_bp, 'analyze_and_advise',
        lambda *a, **k: {'analysis': {'exercises': [], 'summary': 'ok'},
                         'next_weights': {'Упр1-1': {'weight': 60.5, 'reps': 8}}})

    auth_client.get('/workout/today')
    token = _current_token()
    r = auth_client.post('/workout/today', data={
        'weight_0_0': '50', 'reps_0_0': '10', 'workout_token': token})
    assert r.status_code == 303

    db.session.expire_all()
    data = db.session.get(WorkoutPlan, plan.id).data
    assert data['week1']['day3'][0]['weight'] == 60.5
```

**Patterns:**
- **Setup:** request fixtures (`auth_client`, `plan`, `user`) compose; tests add ad-hoc rows with `db.session.add_all(...)` + `commit()`.
- **Teardown:** handled by the `app` fixture (`db.session.remove()`, `db.drop_all()`). Tests do not clean up manually.
- **Assertions:** check both the HTTP status (`303`, `200`, `403`) and the persisted DB state after `db.session.expire_all()` / `db.session.get(...)`.
- **Request context for direct helper calls:** `with app.test_request_context(): helper(...)` (see `tests/test_workout.py::test_fatigue_sets_advice_without_touching_comment`).
- **Module-level helpers in tests:** small private helpers prefixed with `_` (e.g. `_current_token()`).

## Mocking

**Framework:** `pytest` `monkeypatch` (preferred) and `unittest.mock` where a spy is needed.

**Key rule: patch the name where it is used.** Blueprints and tasks import names directly, so stub the consuming module:
- `monkeypatch.setattr(workout_bp, 'analyze_and_advise', fake)` where `workout_bp` is `bp.workout`.
- `bp.plan.generate_full_plan` for plan generation.
- Gemini calls: patch `ai._call_with_fallback` where `ai` is `ai_generator` (`tests/test_ai_pipeline.py`).

**AI pipeline pattern (`tests/test_ai_pipeline.py`):**
```python
import ai_generator as ai
from tests.ai_fixtures import valid_response, truncated_response, NO_JSON_RESPONSE

@pytest.fixture(autouse=True)
def clean_cache():
    ai._CACHE.clear()
    yield
    ai._CACHE.clear()

def test_unknown_names_dropped_when_catalog_enforced(gemini, monkeypatch):
    monkeypatch.setattr(BaseConfig, 'EXERCISE_CATALOG_ENFORCE', True)
    ...
```
- Use `tests/ai_fixtures.py` builders (`plan_json`, `valid_response`, `fenced_response`, `truncated_response`, `ELLIPSIS_RESPONSE`, `NO_JSON_RESPONSE`) to build realistic Gemini replies. Never call the real API from tests.
- Clear `ai._CACHE` around each test that touches the cache (autouse fixture).
- Exercise names in fake responses must exist in the real catalog (`SAFE_GYM` in `ai_fixtures.py`) if the test depends on catalog matching.

**Other mocking used:**
- `tests/test_telegram_reminders.py`, `tests/test_password_reset.py`, `tests/test_tasks_jobs.py`, `tests/test_product_metrics.py`, `tests/test_weekly_debrief.py` replace outbound calls, RQ enqueue functions and mailers. Most use `monkeypatch`; a few use `unittest.mock` directly.
- `tests/test_healthz.py` uses a hand-written `FakeRedis` class instead of a mock library.

**What to Mock:**
- Gemini / any AI client call (`ai_generator._call_with_fallback`, `analyze_and_advise`, `generate_full_plan`, `generate_weekly_debrief`).
- Outbound HTTP (Telegram, mail). Real tokens are blanked in `conftest.py`.
- Job queue enqueue when `USE_JOB_QUEUE` would otherwise dispatch to RQ.
- Time-dependent or randomness-dependent functions when the result must be deterministic.

**What NOT to Mock:**
- The database. Tests use real SQLite (temp file) through the `app` fixture.
- Flask request handling, Flask-Login session, CSRF helpers when the test is about them (use `csrf_app`).
- Pure validation and report functions (`validation.py`, `report.py`, `periodization.py`); test them directly.

## Fixtures and Factories

**Test Data:**
- Plan factory: `make_plan_data(duration, freq, n_ex)` in `tests/conftest.py` builds `week{w}/day{d}` dicts with Russian placeholder exercise names (`Упр{d}-{e}`). Use the `plan_data` fixture or import the factory when you need a custom shape.
- AI response builders: `tests/ai_fixtures.py` (see above).
- Users: create inline with `User(...)` + `set_password(...)` + `db.session.add/commit`, as in the `user` fixture. Consent fields (`privacy_accepted_at`, `health_consent_at`, `health_completed=True`) must be set, or onboarding redirects will interfere.

**Location:**
- Shared fixtures: `tests/conftest.py`.
- Shared AI data: `tests/ai_fixtures.py`.
- Per-test data: inside the test module.

## Coverage

**Requirements:** No minimum threshold is enforced in the repo. Coverage is reported in CI (`--cov --cov-report=term`); the total is shown on the pipeline and MR via the `coverage:` regex.

**Configuration:** `.coveragerc`:
- `source = .`; omits `tests/*`, `scripts/*`, `migrations/*`, `.venv/*`, `.ci-venv/*`.
- Report: `skip_covered = True`, `sort = Cover`.

**View Coverage:**
```bash
.venv/bin/python -m pytest -q --cov --cov-report=term
```

## Architectural Test Guards

- `tests/test_module_sizes.py`: fails if any module in the repo root or `bp/` exceeds **600 lines**. Also checks that the split AI modules (`ai_plan_gen`, `ai_analysis`, `ai_normalize`, `ai_prompts`, `ai_safety`, `validation_options`, `plan_insights`) import standalone in a clean interpreter, and that the `ai_generator` facade still re-exports its public names. When you split a module, keep these re-exports working.
- `tests/test_csp.py`: scans every `templates/**/*.html` for inline `<script>`/handlers and checks the CSP header.
- `tests/test_branding.py`: checks that the product name comes from `APP_NAME` (`config.py`) in visible places (templates, static, reports), not hard-coded.
- `tests/test_healthz.py` / `tests/test_wait_healthy.py`: health endpoint (Redis/RQ checks with fakes) and deploy wait logic.
- `tests/test_templates.py` is not a template-lint test: it covers constructor day-template validation and `/api/templates`.

## Test Types

**Unit Tests:**
- Pure functions: `validation.py`, `report.py`, `periodization.py`, `plan_insights.py`, `ai_normalize.py`, `ai_safety.py`, `exercise_catalog.py`. Call directly, no client needed.
- Use the `app` fixture only when the function reads `current_app.config` or the DB.

**Integration Tests:**
- Route tests via `client` / `auth_client`: status codes, redirects (`303` after POST), JSON shape of `/api/*`, DB side effects. Examples: `tests/test_workout_submit.py`, `tests/test_constructor.py`, `tests/test_history_context.py`.
- AI pipeline tests with stubbed Gemini: `tests/test_ai_generator.py`, `tests/test_ai_pipeline.py`.

**E2E Tests:**
- Framework: Playwright (Python), via the `running_server` fixture (live Werkzeug server, `SESSION_COOKIE_SECURE=False`, CSRF off).
- Location: `tests/e2e/`. Each file sets `pytestmark = pytest.mark.e2e` at module level. There is no `tests/e2e/conftest.py`; the shared `running_server` fixture comes from the root `tests/conftest.py`.
- Opt-in, not in the CI gate. Run on the dev stand (needs chromium): `.venv/bin/python -m pytest -m e2e tests/e2e`.
- Covers workout result, submit flow, constructor drawer, rest timer, PWA offline, CSP, templates, visual snapshots.

## Common Patterns

**Async / background work:**
- With `USE_JOB_QUEUE=0` (the test default) generation runs inline, so tests can assert results directly after the request.
- For job-queue code, test the enqueue/fetch functions in `jobs.py` and the task functions in `tasks.py` with monkeypatched queue objects (`tests/test_tasks_jobs.py`). Do not start an RQ worker in tests.
- Background-thread work is avoided in unit tests; e2e uses a daemon thread for the live server only.

**Error Testing:**
```python
# Abridged shape of tests/test_ai_pipeline.py::test_plan_rejected_if_too_few_known_names
def test_plan_rejected_if_too_few_known_names(gemini, monkeypatch):
    monkeypatch.setattr(BaseConfig, 'EXERCISE_CATALOG_ENFORCE', True)
    # arrange a response with mostly unknown names, then assert the pipeline
    # rejects it instead of returning the plan (see the file for the exact assertion)
```
- For HTTP errors assert the status code and, for `/api/*`, the JSON body `{'status': 'error', 'message': ...}`.
- For HTML errors assert that the error page renders (`templates/error.html`) rather than a traceback.
- For CSRF, use `csrf_app` and post without a token; expect 400 (JSON on `/api/*`, flash + redirect on HTML forms).

**Config-driven behaviour:**
- Patch the config class attribute with `monkeypatch.setattr(BaseConfig, 'NAME', value)` (see `tests/test_ai_pipeline.py`), not environment variables, after the app has been imported.

**Adding a new test (checklist):**
1. Create or extend `tests/test_<feature>.py`. Name the function `test_<behaviour>`.
2. Use the `app` / `client` / `auth_client` / `user` / `plan` fixtures; do not create a new engine or DB.
3. Stub AI and outbound calls with `monkeypatch` on the consuming module.
4. Assert both the HTTP response and the persisted state.
5. Run `.venv/bin/python -m pytest -q <file>` then the full suite and `ruff check .`.

---

*Testing analysis: 2026-11-03*
