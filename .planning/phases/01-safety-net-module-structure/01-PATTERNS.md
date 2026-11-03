# Phase 1: Safety Net & Module Structure - Pattern Map

**Mapped:** 2026-11-03
**Files analyzed:** ~22 (new/modified)
**Analogs found:** 20 / 22

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match |
|---|---|---|---|---|
| `ruff.toml` (py312) | config | n/a | itself (`target-version = "py310"`) | exact |
| `pytest.ini` (socket/markers) | config | n/a | itself (`addopts = -q -m "not e2e"`) | exact |
| `.github/workflows/ci.yml` | config | batch | itself (`python-version: '3.10'`) | exact |
| `.gitlab-ci.yml` test job | config | batch | itself (`python3 -m venv .ci-venv`, cache key `requirements-dev.txt`) | exact |
| `requirements.in` (new), `requirements.txt`, `requirements-dev.txt` | config | n/a | current range-pinned files; dev uses `-r requirements.txt` | role |
| `deploy/deploy.sh` | config | batch | itself (`PY="${VENV}/bin/python"`, `STEP="pip install"`, line ~72-75) | exact |
| `deploy/systemd/ai_trainer*.service` | config | n/a | `ai_trainer_worker.service` (`rq worker ai --url ${REDIS_URL}`) | exact |
| `tests/conftest.py` (socket guard, fakeredis fixture) | test fixture | n/a | itself (`app`, `client`, `no_weekly_debrief` lines 47-62, 151-157) | exact |
| `tests/test_tasks_jobs.py` (job states, enqueue failure, lazy-import smoke) | test | request-response/queue | itself (jobs.py + tasks.py tests) | exact |
| `tests/test_telegram_reminders.py` or new `tests/test_telegram_webhook.py` | test | request-response | `test_webhook_rejects_bad_secret` + `bot` fixture + `_hook` | exact |
| `tests/test_ai_quota.py` (shared-storage quota) | test | CRUD (storage) | `quota` fixture + `test_consume_user_limit` | exact |
| forbidden-exercise tests (new `tests/test_forbidden_plan.py`) | test | transform | `tests/test_ai_generator.py` (`_age_forbidden`, `_health_forbidden`), `tests/test_ai_pipeline.py`, `tests/ai_fixtures.py` | role |
| CSRF-exempt test (new, in `tests/test_csp.py` neighbour or `test_api.py`) | test | introspection | `/telegram/webhook` `@csrf.exempt` in `bp/telegram.py` | partial |
| `tests/test_module_sizes.py` | test | introspection | itself | exact |
| `workout_form.py` (from `bp/workout.py`) | utility | transform | `plan_insights.py` re-exported from `bp/plan.py` | exact |
| `plan_view.py` (from `bp/plan.py`) | utility | transform | same | exact |
| `stats_calc.py` (from `bp/stats.py`) | utility | transform | `validation_options.py` / `plan_insights.py` | exact |
| `bp/workout.py`, `bp/plan.py`, `bp/stats.py` (modified) | route | request-response | self | exact |
| `pytest-socket` autouse fixture | test fixture | n/a | none (no analog) | none |
| `import-linter` contract (optional) | config | n/a | none | none |

## Pattern Assignments

### Toolchain/config files

Current contents to edit in place (all verified):
- `ruff.toml`: `target-version = "py310"` -> `"py312"`; keep `line-length = 120`, `select = ["E4","E7","E9","F"]`, `ignore = ["E501"]`.
- `.github/workflows/ci.yml` lines 14-16: `uses: actions/setup-python@v5` / `python-version: '3.10'` -> `'3.12'`; steps run `pip install -r requirements-dev.txt`, `ruff check .`, `pytest`.
- `.gitlab-ci.yml` test job: `python3 -m venv .ci-venv`, `.ci-venv/bin/pip install -q -r requirements-dev.txt`, `.ci-venv/bin/python -m pytest -q --cov --cov-report=term`, `.ci-venv/bin/ruff check .`; cache key is `requirements-dev.txt`. The venv uses the runner's `python3`, so pin by `python3.12 -m venv` only after D-02 (check PROD venv version via `/root/ai_trainer/.venv/bin/python --version`, path from `deploy/systemd/ai_trainer.service`).
- `requirements.txt` currently ends `redis>=5,<7` / `rq>=1.16,<2` -> `rq>=2.12,<3` (D-06). `requirements-dev.txt` is `-r requirements.txt` plus `pytest>=9,<10`, `pytest-flask`, `pytest-cov`, `ruff`, `playwright`; add `fakeredis`, `pytest-socket` here.
- Lockfile pattern: `requirements.in` (ranges) -> compiled pinned `requirements.txt` (keeps the filename `deploy.sh` installs, `deploy.sh` line ~48 `${PY} -m pip install -r requirements.txt`). Do the dev file the same way (`requirements-dev.in` -> `requirements-dev.txt`) so the `-r requirements.txt` chain and the CI cache key keep working.
- `pytest.ini`: `addopts = -q -m "not e2e"`, `markers = e2e: ...`. Add new markers in the same `markers =` block; socket flags go in `addopts` only if allow-list is global (prefer an autouse fixture in conftest with `--allow-hosts=127.0.0.1` for fakeredis/test client).
- `deploy/systemd/ai_trainer_worker.service` ExecStart: `/root/ai_trainer/.venv/bin/rq worker ai --url ${REDIS_URL}` (RQ 2.x keeps this CLI; verify with a real job on DEV). `deploy.sh` change goes in its own commit (D-04).

### `tests/test_tasks_jobs.py` additions (test, queue)

**Analog:** same file, jobs section.

Imports/shape (lines 1-12):
```python
from unittest.mock import MagicMock, patch
import ai_generator
import bp.plan as plan_bp
import bp.stats as stats_bp
import jobs
import tasks
from models import Workout, WorkoutPlan, db
```
Enqueue test shape (patch `jobs.get_queue`, assert `queue.enqueue.call_args`):
```python
def test_enqueue_passes_timeout_and_meta():
    job = MagicMock(id='job-1', meta={})
    queue = MagicMock()
    queue.enqueue.return_value = job
    with patch('jobs.get_queue', return_value=queue):
        assert jobs.enqueue('tasks.task_generate_plan', 1, 8, meta={'user_id': 1}) == 'job-1'
```
get_job shape: `patch('jobs.get_redis'), patch('rq.job.Job.fetch', side_effect=Exception(...))` returns None.
For new real-state tests use `fakeredis.FakeStrictRedis()` + `patch('jobs.get_redis', return_value=fake)` and `rq.SimpleWorker([jobs.get_queue()], connection=fake).work(burst=True)`. Enqueue-failure: `patch('jobs.get_queue', side_effect=Exception)` and assert the route (`bp.plan` enqueue sites; `bp.workout.enqueue` is already patched with `monkeypatch.setattr('bp.workout.enqueue', fake_enqueue, raising=False)` at `tests/test_workout.py:490`) does not leave state stuck.

Job-status endpoint to pin: `bp/plan.py:365-383` `api_job_status`. Contract: unknown job or `job.meta['user_id'] != current_user.id` -> 404 `{'status':'error','message':'Задача не найдена'}`; `queued/started/deferred/scheduled` -> `{'status':'pending'}`; `finished` -> `result.get('status','ok')`; else (failed) -> error `'Не удалось выполнить задачу. Попробуйте позже.'`. Write one test per RQ status using a MagicMock job via `patch('jobs.get_job')` (the route imports `from jobs import get_job` lazily inside the function, so patch `jobs.get_job`).

**tasks.py lazy-import smoke (D-13):** `tasks.py` lines 13-14, 26-28, 46, 126-130 import lazily:
```python
from bp.workout import _apply_suggestions_to_plan, _clean_analysis, _process_suggestions
from helpers import _plan_frequency, _user_data
from bp.plan import perform_generation, perform_regeneration
from bp.stats import perform_weekly_debrief
```
Smoke test: `importlib.import_module(mod)` then `getattr` each name (parametrized list). Note `perform_weekly_debrief` lives in `bp/stats.py`; it must remain importable from there after the `stats_calc.py` extraction.

### Webhook negative tests

**Analog:** `tests/test_telegram_reminders.py` lines 14-28, 64-66.
```python
@pytest.fixture()
def bot(app, monkeypatch):
    monkeypatch.setitem(app.config, 'TELEGRAM_BOT_TOKEN', '123:abc')
    monkeypatch.setitem(app.config, 'TELEGRAM_BOT_USERNAME', 'kachlog_test_bot')
    monkeypatch.setitem(app.config, 'TELEGRAM_WEBHOOK_SECRET', SECRET)
    monkeypatch.setitem(app.config, 'APP_BASE_URL', 'https://example.com')
    return app

def _hook(client, text, chat_id=555, secret=SECRET):
    return client.post('/telegram/webhook', json={'message': {'chat': {'id': chat_id}, 'text': text}},
                       headers={'X-Telegram-Bot-Api-Secret-Token': secret})
```
Copy these (import or duplicate; a shared helper in conftest is cleaner). Spy: `monkeypatch.setattr('telegram_bot.handle_update', spy)` (route calls `telegram_bot.handle_update`, module attribute, so patching `telegram_bot.handle_update` works). Code under test, `bp/telegram.py:60-75`:
```python
secret = current_app.config.get('TELEGRAM_WEBHOOK_SECRET') or ''
got = request.headers.get('X-Telegram-Bot-Api-Secret-Token', '')
if not telegram_bot.bot_enabled() or not secret or not hmac.compare_digest(secret, got):
    abort(404)
update = request.get_json(silent=True) or {}
reply = telegram_bot.handle_update(update)
chat_id = ((update.get('message') or {}).get('chat') or {}).get('id')
```
Cases: wrong, empty, non-ASCII header (`hmac.compare_digest(str, str)` raises TypeError on non-ASCII -> currently 500; pin with `xfail(strict=True)` expecting 404, or assert 500 and record which), non-dict JSON (e.g. a list: `update.get` would fail -> note current behaviour), bot disabled. Assert `spy.assert_not_called()` in each.

### Quota tests (shared storage)

**Analog:** `tests/test_ai_quota.py` lines 11-23 `quota` fixture and `test_consume_user_limit`.
```python
@pytest.fixture()
def quota(app, monkeypatch):
    monkeypatch.setitem(app.config, 'AI_QUOTA_ENABLED', True)
    monkeypatch.setitem(app.config, 'AI_DAILY_USER_LIMIT', 2)
    monkeypatch.setitem(app.config, 'AI_DAILY_GLOBAL_LIMIT', 3)
    app.extensions.pop('ai_quota', None)
    with app.test_request_context():
        ai_quota._limiter().storage.reset()
    yield
    app.extensions.pop('ai_quota', None)
```
Source `ai_quota._limiter()` builds `FixedWindowRateLimiter(storage.storage_from_string(config['RATELIMIT_STORAGE_URI']))` and caches it in `app.extensions['ai_quota']`. "Shared storage" test: two simulated workers = pop `app.extensions['ai_quota']` between calls (or build two limiters) against one `RATELIMIT_STORAGE_URI`; with fakeredis the `redis://` URI needs the limits storage to accept it (patch `redis.Redis.from_url` or use `memory://` for the in-process variant and document the Redis limit). `consume` swallows storage errors (`except Exception: # noqa: BLE001`) and returns None; test that explicitly (broken storage -> allowed).

### Forbidden-exercise tests (D-11)

**Analog:** `tests/test_ai_generator.py` lines 62-71 (`ai._age_forbidden('Становая тяга','older') is True`, `ai._health_forbidden('Становая тяга',['hernia'])`) for names; `tests/test_ai_pipeline.py` and `tests/ai_fixtures.py` for stubbing the AI layer (patch in consuming module, e.g. `bp.plan.generate_full_plan`; equipment tests patch `plan_bp.perform_generation` at `tests/test_equipment.py:99,121`). Assert on persisted `WorkoutPlan.data` (`week{N}`->`day{M}`->exercises list) after `perform_generation` with a stub that returns a forbidden name, `EXERCISE_CATALOG_ENFORCE=0`. Executor to read `tests/ai_fixtures.py` and `tests/test_ai_pipeline.py` for the exact stub payload shape before writing (not excerpted here).

### CSRF-exempt behavioural test (D-14)

No existing test. Code to pin: `bp/telegram.py` `@bp.route('/telegram/webhook', methods=['POST']) @csrf.exempt @limiter.limit('120/minute')`. Test shape: `csrf_app` fixture exists in `tests/conftest.py:63-67` (CSRF on). Enumerate `app.url_map.iter_rules()`, resolve `app.view_functions[rule.endpoint]`, compare against `csrf._exempt_views` (Flask-WTF stores `module + '.' + name` strings) and assert the set equals `{'bp.telegram.telegram_webhook'}`. Verify the attribute name against the installed Flask-WTF at write time.

### No-real-Gemini guard (D-08)

No analog. Closest precedent for forcing AI stubs: `tests/conftest.py` `no_weekly_debrief` (lines 151-157):
```python
@pytest.fixture()
def no_weekly_debrief(monkeypatch):
    monkeypatch.setattr('bp.stats.generate_weekly_debrief', lambda *args, **kwargs: None)
```
Pattern for guard: autouse fixture in conftest using `pytest-socket` (`disable_socket` with `allow_hosts=['127.0.0.1','::1']`) AFTER the env-before-import block. Also consider an autouse fixture patching `ai_generator._get_client`/`_generate` to raise. Mutation check: remove a stub from one test, confirm red.

### `tests/conftest.py`

Keep ordering: env vars set before `import app` (see top of file); fixtures `app` (lines 47-55, `drop_all/create_all` per test), `client`, `csrf_app`, `user`, `auth_client`, `plan`. Add fakeredis fixture beside them, function-scoped.

### Module extraction (SPL-01/02)

**Analog A: `plan_insights.py` re-exported from `bp/plan.py`** (`bp/plan.py` lines 22-23):
```python
# Аналитика плана — в plan_insights.py (E-02); имена реэкспортируются для прежних импортов.
from plan_insights import (  # noqa: F401
    ...
)
```
**Analog B: `validation_options.py` re-exported by `validation.py`; `ai_*` re-exported by `ai_generator.py`.** The new module must be Flask-free where possible, import standalone, and the old module re-exports with `# noqa: F401`. Add every new module name to the tuple in `tests/test_module_sizes.py::test_split_modules_import_standalone` (currently `'ai_plan_gen','ai_analysis','ai_normalize','ai_prompts','ai_safety','validation_options','plan_insights'`); that test runs `python -c 'import X'` with a minimal env `{'PATH':'', 'DATABASE_URL':'sqlite://', 'SECRET_KEY':'x', 'GOOGLE_API_KEY':'x'}`.

**Patch-target constraint (grep of `tests/`):** the only names tests patch against these three modules are:
- `bp.stats.generate_weekly_debrief` (12 uses: `test_weekly_debrief.py`, `test_telegram_reminders.py` lines 154-174, `conftest.py:157`) -> the call site `perform_weekly_debrief` and the imported name `generate_weekly_debrief` MUST stay in `bp/stats.py`. `perform_weekly_debrief` is also imported by `tasks.py`.
- `bp.workout.enqueue` (`tests/test_workout.py:490`, `raising=False`) -> `enqueue` must be an attribute of `bp.workout`.
- `workout_bp.exercise_swap` (`tests/test_ai_quota.py`/workout tests) -> keep `exercise_swap` imported in `bp/workout.py`.
- `plan_bp.perform_generation` (`tests/test_equipment.py:99,121`) plus docs' `bp.plan.generate_full_plan`, `perform_regeneration`, `save_workout_plan` -> stay in `bp/plan.py` (D-16).
- `tasks.py` also pulls `bp.workout._apply_suggestions_to_plan`, `_clean_analysis`, `_process_suggestions` and `helpers._user_data/_plan_frequency` -> if moved, re-export from `bp.workout`.
Also grep non-`patch(` direct imports of private names (`from bp.stats import ...`, `from bp.workout import ...`) in `tests/` before cutting; tests such as `test_goal_progress.py`, `test_heatmap.py`, `test_load.py` likely import `goal_progress`, `heatmap_*`, `weekly_load`, `sparkline` from `bp.stats`, so they must be re-exported.

**Cut-line candidates (pure, no route/db coupling), from `def` map:**
- `bp/stats.py` (570 lines): `heatmap_range`..`goal_progress` (lines 22-260, ~240 lines: `weekly_load`, `sparkline`, `_strength_*`, `_body_item`, verdict helpers) -> `stats_calc.py`; leave `api_heatmap`, `metrics`, `stats`, debrief section (`last_full_week`..`debrief_context`, `perform_weekly_debrief`, routes) in place. Gives well over 100 lines of headroom.
- `bp/workout.py` (566 lines): form parsing helpers `_parse_sets`, `_collect_results`, `_empty_workout`, token helpers `_consume_token`/`_issue_token`, `_history_for_ai`, `_has_analysis`/`_analysis_state`/`_render_analysis_body` (lines 35-160, 421-470) -> `workout_form.py`. Anything using `request`/`db` stays importable from `bp.workout` via re-export. `_already_saved` / `RESUBMIT_WINDOW` constants may be patched by tests: grep before moving.
- `bp/plan.py` (561 lines): candidates are pure view/helper functions outside the three `perform_*`/`save_workout_plan` functions and routes; executor must run `grep -n "^def " bp/plan.py` and pick >=100 lines.

One module per commit; run `pytest` and `ruff check .` plus `tests/test_module_sizes.py` after each. Endpoint names must not change (the nav list in `templates/base.html` keys on `request.endpoint`).

## Shared Patterns

### Patch in the consuming module
Tests patch the name where used: `bp.stats.generate_weekly_debrief`, `bp.workout.enqueue`, `plan_bp.perform_generation`, `jobs.get_queue`, `telegram_bot.handle_update`. After any move, keep the name bound in the original module.

### Test client and app
`app` fixture (`tests/conftest.py:47`): `app_module.app.config.update(TESTING=True, WTF_CSRF_ENABLED=False)`, `drop_all/create_all` per test. `client = app.test_client()`; `auth_client` logs in `user`. Config overrides use `monkeypatch.setitem(app.config, KEY, value)`.

### Lazy imports in tasks
Task functions are top-level and import `app`, `bp.plan`, `bp.stats`, `bp.workout` inside the function body (blueprints never import `app`).

### Style
Single quotes; `# -*- coding: utf-8 -*-` header plus a Russian docstring with an audit-id (`E-04:`) on test modules; Russian comments, English identifiers; test names `test_<behaviour>`; no new syntax beyond py310 until the toolchain commit lands.

### Mutation check (D-12)
For each new test record in the plan summary: break the code under test, confirm red, restore. No analog; process requirement.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| socket-blocking autouse fixture | test fixture | n/a | no network guard exists; use RESEARCH/STACK.md (`pytest-socket`) |
| CSRF-exempt enumeration test | test | introspection | no existing test; use `csrf_app` fixture + `app.url_map` |
| import-linter contract | config | n/a | not present; optional per D-17 |

## Metadata

**Analog search scope:** `tests/`, `bp/`, `tasks.py`, `jobs.py`, `ai_quota.py`, `deploy/`, CI configs, requirements files
**Files scanned:** ~25 (targeted reads; `tests/ai_fixtures.py`, `tests/test_ai_pipeline.py`, `bp/plan.py` def map not fully read, executor should read before writing)
**Pattern extraction date:** 2026-11-03
