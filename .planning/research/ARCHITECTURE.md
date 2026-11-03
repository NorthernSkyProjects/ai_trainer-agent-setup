# Architecture Research

**Domain:** Flask monolith with Gemini-backed AI features, RQ/Redis async jobs, SQLite (brownfield hardening)
**Researched:** 2026-11-03
**Confidence:** HIGH for current-state facts (read from code at commit 2bcf4b2); MEDIUM for target design (design judgement, not yet prototyped); MEDIUM for PROD config (`/etc/ai_trainer.env` is not readable, so `USE_JOB_QUEUE=1` in PROD is inferred from `docs/operations.md` and CONCERNS.md)

This document does not repeat `.planning/codebase/ARCHITECTURE.md`, `STRUCTURE.md` or `CONCERNS.md`. It answers one question: how do the five hardening targets land on the existing blueprint / facade / RQ architecture, and in what order can they be built without breaking the PROD auto-deploy.

## What the Code Actually Looks Like Today (facts that drive the design)

These were verified by reading the code, and several differ from what the concerns doc implies.

1. **There is no shared "AI failure" concept.** `_call_with_fallback` (`ai_generator.py`) swallows every error and returns `None`. `generate_full_plan`, `regenerate_plan_with_comment`, `analyze_and_advise` and `generate_weekly_debrief` return `None` for five different causes (no API key, all models timed out, 429/503, invalid JSON, normalisation rejected the plan). The only reason string anywhere is the generic Russian text the caller picks.
2. **The tests' patch seam is "`_call_with_fallback` returns `str | None`" and "public AI functions return `None` on failure".** About 12 tests assert `generate() is None`, and about 20 patch `ai._call_with_fallback` with fakes returning text or `None`. Changing these return contracts is the most expensive move available; carrying the failure reason out-of-band avoids it.
3. **Three "perform" functions already exist and are already the single implementation** for plan generation, regeneration and weekly debrief (`bp.plan.perform_generation`, `bp.plan.perform_regeneration`, `bp.stats.perform_weekly_debrief`). `tasks.py` entries for those three are already thin shells. What is duplicated there is only the `if USE_JOB_QUEUE: enqueue ... else: perform` branch plus quota handling in each endpoint (`bp/plan.py` x2, `bp/stats.py`, `bp/workout.py` x2).
4. **Workout analysis is the one operation with a real duplicate implementation.** There is no `perform_analysis`. The sync path is inline in `workout_today` (`bp/workout.py` ~241-267) and `_analyze_extra_inline`; the async path is `tasks._analyze_workout`. They differ in ways that matter:
   - Sync builds `previous_plan` from the display-enriched `plan_exercises` minus swapped cards; async re-reads raw `plan_obj.data[weekN][dayM]` after swaps were applied.
   - Sync commits workout + plan advance + `next_weights` suggestions in one transaction; async saves a fallback first, then applies suggestions in a second commit.
   - History query differs (`_history_for_ai` vs an inline copy in `tasks.py`).
   - Only async calls `update_prs` a second time.
   - `tasks.py` imports `_apply_suggestions_to_plan`, `_clean_analysis`, `_process_suggestions` from `bp.workout`, which merely re-imports them from `workout_logic.py` (an earlier split). A worker module reaching into a blueprint module for pure logic is the wrong dependency direction.
5. **Enqueue failure is handled inconsistently.** The workout paths catch it and set `failed`; `api_generate_plan`, `api_regenerate_plan` do not wrap `enqueue` at all, so Redis being down yields a 500. `api_weekly_debrief` returns a specific 503.
6. **Failure state is stored in three different shapes:** `Workout.analysis_status` (`none|pending|ready|failed|skipped`, no reason), `WeeklyReport.status` (`pending|ready|error`, no reason), and RQ job state (generic message on `failed`, but task functions that *return* `{'status': 'error', 'message': ...}` already pass a specific message through `job.result`).
7. **Quota denial in the workout flow is stored as `failed`** (`bp/workout.py` ~232) with the reason only in a one-shot `flash`. After a reload the user sees the same "could not get analysis" text as for a Gemini outage and gets no retry.
8. **`google.genai.errors.APIError` carries an integer `.code`** (verified in `.venv`; `ClientError` and `ServerError` subclass it). `_call_with_fallback` currently classifies by substring-matching `'429'` / `'503'` in `str(e)`. `rq.exceptions.NoSuchJobError` exists (verified), so `jobs.get_job` can distinguish "missing job" from "Redis unreachable".
9. **Hot-file overlap:** the files the AI work must edit (`bp/plan.py` 561, `bp/workout.py` 566, `bp/stats.py` 570, `tasks.py` 210) are the same files within ~35 lines of the 600-line ceiling (`tests/test_module_sizes.py` globs root `*.py` and `bp/*.py`). The unification extracts code out of them; adding the retry endpoint and reason plumbing into them first would trip the size test.

## Target Architecture

### System Overview (delta only; unchanged layers omitted)

```
┌────────────────────────────────────────────────────────────────────────────┐
│ Route layer (bp/*)            thin: validate -> dispatch -> shape response │
│  plan.api_generate_plan / api_regenerate_plan / api_job_status             │
│  stats.api_weekly_debrief   workout.workout_today / workout_extra /        │
│  workout.api_workout_analysis / NEW workout.api_analysis_retry             │
└──────────────┬─────────────────────────────────────────────────────────────┘
               │ dispatch(op, inline, task_path, args, user_id)
               ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ NEW ai_dispatch.py  (Flask-aware, imports NO bp.*, NO app)                 │
│   1. ai_quota.consume  -> Failure('quota_user'|'quota_global')             │
│   2. USE_JOB_QUEUE ?  jobs.enqueue(...)  -> Dispatch(queued, job_id)       │
│                       inline()           -> Dispatch(ok | error, reason)   │
│   3. enqueue exception -> Failure('queue_unavailable')                     │
└───────┬───────────────────────────────┬────────────────────────────────────┘
        │ inline (request context)      │ RQ worker (app_context in tasks.py)
        ▼                               ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ ONE implementation per operation ("perform_*"); tasks.py = thin shells     │
│   bp.plan.perform_generation / perform_regeneration                        │
│   weekly_debrief.perform_weekly_debrief   (extracted from bp.stats)        │
│   NEW workout_analysis.perform_analysis   (extracted from bp.workout+tasks)│
└───────┬────────────────────────────────────────────────────────────────────┘
        │ with ai_errors.capture() as cap:  result = ai_generator.<fn>(...)
        ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ ai_generator.py facade (contracts unchanged: str|None / dict|None)         │
│   SDK boundary classifies failures -> ai_errors.note(reason)               │
│   Redis cache client initialised lazily, with a down-cooldown              │
│ NEW ai_errors.py  (leaf module, stdlib only)                               │
│   reason codes, AIFailure(str), reason_text(), is_retryable(),             │
│   capture() context manager over a thread-local, task_result()             │
└────────────────────────────────────────────────────────────────────────────┘
        durable state:  Workout.analysis_status + NEW analysis_error
                        WeeklyReport.status    + NEW error_reason
                        RQ job.result {'status','message','reason'}
```

### Component Boundaries

| Component | Responsibility | Communicates With | Status |
|-----------|----------------|-------------------|--------|
| `ai_errors.py` | Single vocabulary of failure reasons; maps reason to Russian user text and a `retryable` flag; thread-local capture of the reason noted at the SDK boundary; builds the RQ task result envelope. Stdlib only, no Flask, no models. | imported by `ai_generator`, `ai_dispatch`, `workout_analysis`, `jobs`, `tasks`, blueprints | NEW |
| `ai_generator.py` | Gemini client, model fallback, response cache, `_extract_json`. Classifies SDK errors and calls `ai_errors.note(...)`. Redis cache client becomes lazy. Public function return contracts do NOT change. | `ai_errors`, `config`, `ai_metrics`; re-exports submodules | MODIFIED |
| `ai_dispatch.py` | The only place that reads `USE_JOB_QUEUE`. Charges quota, enqueues or runs inline, converts any outcome into one `Dispatch` value; renders the JSON response for request/response endpoints. | `ai_quota`, `jobs`, `ai_errors`, `flask.current_app` | NEW |
| `workout_analysis.py` | `perform_analysis(workout, ...)`: build history, call `ai_generator.analyze_and_advise` (looked up at call time), clean result, write `analysis` / `analysis_status` / `analysis_error`, optionally apply `next_weights` to the plan. Also `history_for_ai`. | `ai_generator`, `ai_errors`, `workout_logic`, `models`, `helpers` | NEW (extracted) |
| `weekly_debrief.py` | Debrief aggregation + `perform_weekly_debrief` + `debrief_context` moved out of `bp/stats.py`; writes `error_reason`. | `ai_generator`, `ai_errors`, `models`, `helpers` | NEW (extracted) |
| `tasks.py` | Thin RQ shells: load entities, call `perform_*`, return `ai_errors.task_result(...)`. No domain logic. Imports `app` lazily; imports from the service modules, never from `bp.workout`. | service modules, `ai_errors` | SHRINKS ~210 -> ~90 lines |
| `jobs.py` | enqueue / fetch / `describe(job)` -> `{status, message, reason}`; `get_job` narrowed to `NoSuchJobError`. | `rq`, `redis`, `ai_errors` | MODIFIED |
| `bp/plan.py` | Plan routes + `perform_generation` / `perform_regeneration` / `save_workout_plan` (stay here: tests and `tasks` patch/import them by this path). Pure view helpers and the plan_insights re-export block move to `plan_view.py`. | `ai_dispatch`, `ai_generator`, `plan_view`, `plan_insights` | MODIFIED |
| `bp/workout.py` | Workout form routes + result page + analysis polling + retry endpoint. Form parsing / token helpers move to `workout_form.py`; analysis moves to `workout_analysis.py`. | `ai_dispatch`, `workout_analysis`, `workout_form` | MODIFIED |
| `bp/stats.py` | Pages and APIs only; debrief logic moved out; pure metric calculators optionally to `stats_calc.py`. | `weekly_debrief`, `ai_dispatch` | MODIFIED |
| `models.py` | `Workout.analysis_error` (String(24), nullable), `WeeklyReport.error_reason` (String(24), nullable). One Alembic autogenerate migration. | — | MODIFIED |
| `helpers.py`, `validation.py` | Split by existing seams, public names re-exported so no importer changes. | see Split Plan | MODIFIED (late) |

### Failure reason vocabulary (`ai_errors.py`)

Codes are stored (String(24)); user text is derived at render time, so copy can change without a data migration. Never store provider messages: `APIError.message` includes response details and could echo prompt content (health data).

| Code | Raised where | Retryable | User-facing meaning (RU copy lives in `ai_errors`) |
|------|-------------|-----------|-----------------------------------------------------|
| `quota_user` | `ai_quota.consume` | no (until tomorrow) | personal daily limit reached |
| `quota_global` | `ai_quota.consume` | no (until tomorrow) | service-wide daily cap reached |
| `rate_limited` | SDK `APIError.code == 429` on all models | yes, later | provider busy |
| `unavailable` | `APIError.code >= 500`, network errors (`httpx.HTTPError`, `OSError`) | yes | provider temporarily down |
| `timeout` | `concurrent.futures.TimeoutError` budget exhausted; stale `pending` row; RQ `JobTimeoutException` | yes | took too long |
| `invalid_response` | empty text, `MAX_TOKENS`, `_extract_json` is `None`, normaliser rejected plan | yes (once or twice) | model returned something unusable |
| `not_configured` | `_get_client` raises (no `GOOGLE_API_KEY`) | no | AI features unavailable (operator problem) |
| `queue_unavailable` | `enqueue` raised | yes | could not start the task |
| `internal` | unexpected exception at a transactional boundary | yes | unexpected error (logged with traceback) |

## Data Flow

### Unified request/response flow (plan generate, regenerate, weekly debrief)

```
POST /api/generate_plan
  bp.plan: profile check -> dispatch(op='generate_plan',
                                      task='tasks.task_generate_plan', args=(user.id, weeks),
                                      inline=lambda: perform_generation(user, weeks))
    ai_dispatch:
      quota_error? ──yes──> Dispatch(error, reason=quota_*)  -> 429 {'status':'error','message','reason'}
      USE_JOB_QUEUE ──yes─> jobs.enqueue(..., meta={'user_id':id})
                              ok    -> Dispatch(queued, job_id) -> {'status':'queued','job_id'}
                              raise -> Dispatch(error, 'queue_unavailable') -> 503
      else inline() -> (ok, AIFailure|None) -> {'status':'ok'} | {'status':'error','message','reason'}

RQ worker: tasks.task_generate_plan -> app_context -> perform_generation(...)
           -> returns {'status':'ok'} | {'status':'error','message','reason'}      (job.result)
           unexpected exception -> propagates -> RQ marks job failed (traceback in job.exc_info)

GET /api/job/<id>  (bp.plan.api_job_status)
  jobs.get_job -> None (NoSuchJobError) -> 404 ;  RedisError -> 503
  jobs.describe(job):
     queued/started/deferred/scheduled -> {'status':'pending'}
     finished                          -> job.result passthrough (status/message/reason)
     failed                            -> {'status':'error','reason':'internal'|'timeout', 'message': reason_text}
```

Response shape stays additive: existing `my_plan.js` / `onboarding_generating.js` read `status`, `job_id`, `message` only, so a new `reason` key needs no frontend change in the first pass. Keep HTTP 200 for "AI failed" (existing behaviour; the JS ignores the code for that case) and 429/503 for quota/queue.

### Workout analysis: save first, then dispatch (replaces the sync/async fork)

```
POST /workout/today  (and /workout/extra)
  validate form, consume form token                         (unchanged)
  create Workout(analysis=fallback, analysis_status='pending'), advance plan day,
  apply plan swaps, flag_modified, COMMIT                   (one commit, as today)
  update_prs, ensure_cycle_summary, log_event               (unchanged)
  dispatch(op='analyze_workout', task='tasks.task_analyze_workout',
           args=(workout.id, user_id, saved_week, saved_day, cw, cd),
           inline=lambda: perform_analysis(workout, saved_week, saved_day, cw, cd, apply_to_plan=True))
     quota denied  -> workout.analysis_status='failed', analysis_error='quota_*'   (flash kept)
     queued        -> nothing more; result page polls /api/workout/<id>/analysis
     inline ok     -> perform_analysis already wrote 'ready'
     inline failure-> perform_analysis wrote 'failed' + analysis_error
     inline raises -> boundary catch (documented, deliberate): rollback, mark failed/'internal',
                      log exception, do NOT 500 — the workout is already saved
  redirect to /workout/result/<id> (303)

GET /api/workout/<id>/analysis -> _analysis_state(workout) -> html (now includes reason text + retry button)
POST /api/workout/<id>/analysis/retry  (NEW, limiter 10/hour)
  owner + status=='failed' + is_retryable(analysis_error) -> status='pending', analysis_error=None, COMMIT
  -> dispatch(..., apply_to_plan=False)
```

Decision that needs explicit sign-off: **retry analyses the workout text only and never mutates the plan** (`plan_week/plan_day/cw/cd` of the original save are not stored, and applying `next_weights` against a plan that has since advanced would target the wrong day). The cost is that a first-attempt failure permanently loses the `next_weights` plan adjustment for that workout. Storing the four integers on `Workout` would remove that limitation but adds columns and edge cases; not recommended now.

Convergence direction: **canonicalise on the async implementation.** PROD runs it (`USE_JOB_QUEUE=1`), so moving the sync path onto it means zero behaviour change in PROD and a bug-for-bug-compatible dev/test environment. The visible behaviour changes only on the `USE_JOB_QUEUE=0` path: two commits instead of one, and `previous_plan` comes from the stored plan day rather than the display-enriched copy.

### State machine (durable)

```
Workout.analysis_status:  none --save--> pending --ok--> ready
                                   │ \--fail--> failed(analysis_error=code) --retry--> pending
                                   │ \--quota--> failed(quota_*)  (no retry offered)
                                   └ worker lost > JOB_TIMEOUT+300s -> failed(timeout) [existing stale logic]
                          history edit resets to none and clears analysis_error  (bp/history.py:230)
                          extra workout without AI: skipped
```

`history_edit` must also clear `analysis_error` (one-line change that is easy to forget; otherwise a stale reason shows on a re-analysed row).

## Patterns to Follow

### Pattern 1: Out-of-band failure reason, unchanged return contracts
**What:** `_call_with_fallback` and the extract/normalise steps call `ai_errors.note('rate_limited')` etc. Callers wrap the AI call in `with ai_errors.capture() as cap:` and read `cap.failure(default='invalid_response')` only when the result is falsy.
**When:** every orchestration function that calls a public AI function.
**Why this and not exceptions:** the existing tests fake `_call_with_fallback` and assert `None`; raising from `_generate` would force rewriting ~30 tests and every `generate() is None` assertion in one step. The thread-local is safe because classification runs in the *calling* thread (the `ThreadPoolExecutor` only runs `generate_content`; its exceptions surface through `future.result()` in the caller). `capture()` resets on entry so a stale reason from a previous cache-hit call cannot leak.
**Trade-off:** implicit data flow. Mitigation: `capture()` is the only reader, and a default (`invalid_response` if nothing was noted, `internal` if the callee raised) means a missed `note()` degrades to a generic reason instead of a wrong one.
```python
# ai_errors.py (leaf: stdlib only)
_state = threading.local()

class AIFailure(str):                     # behaves as the message, carries the code
    def __new__(cls, reason, message=None):
        obj = super().__new__(cls, message or reason_text(reason)); obj.reason = reason; return obj

@contextmanager
def capture():
    _state.reason = None
    cap = _Capture()
    yield cap                              # cap.failure(default) reads _state.reason

# bp/plan.py
with ai_errors.capture() as cap:
    plan_data = generate_full_plan(...)
if not plan_data:
    return False, cap.failure(default='invalid_response')
```
`(ok, error)` stays a 2-tuple and `error` is a `str` subclass, so existing fakes (`lambda u, w: (False, 'ИИ недоступен')`) and `ok, error = perform_generation(...)` unpacking keep working; `getattr(error, 'reason', 'internal')` extracts the code.

### Pattern 2: One dispatcher, perform_* stays the single implementation
**What:** `ai_dispatch.dispatch(...)` is the only reader of `USE_JOB_QUEUE`; endpoints pass the inline callable (a closure over `perform_*` in the request's app context) and the task path string.
**When:** all five long-AI call sites.
**Why the inline callable is passed, not resolved:** `ai_dispatch` must not import `bp.plan` (cycle: `bp.plan` imports `ai_dispatch`). And inline must NOT call `tasks.task_*` directly: each task opens `app.app_context()`, which creates a second SQLAlchemy session inside a request that already holds one, a real "database is locked" / stale-read risk on SQLite.
**Invariant to document and test:** commit first, enqueue second (the worker must be able to see the row). All existing call sites already do this; the dispatcher must not reorder it.

### Pattern 3: Expand-then-contract schema change
**What:** add the two nullable columns in a migration that ships and deploys BEFORE any code writes them.
**Why:** PROD pipeline runs `db upgrade` then restarts services; old code keeps running between the two steps and ignores nullable columns. SQLite `ADD COLUMN` nullable is a cheap non-rewriting operation (existing migration `c4c53cbdc16a` used batch mode for a NOT NULL add; this one does not need it). Generate with `flask --app app db migrate` (project rule), never by hand.

### Pattern 4: Extract-with-re-export (existing project idiom)
**What:** move code to a new sibling module, re-export names from the old module with `# noqa: F401` so importers and `monkeypatch.setattr(old_module, name, ...)` keep working.
**Caveat, load-bearing:** a re-export preserves *import* paths but not *patch effectiveness*. A patch on `bp.plan.generate_full_plan` only takes effect for code that looks the name up in `bp.plan`'s globals. Therefore `perform_generation` / `perform_regeneration` / `save_workout_plan` **stay physically in `bp/plan.py`** (tests patch `plan_bp.generate_full_plan`, `plan_bp.regenerate_plan_with_comment`, `plan_bp.perform_generation`, `plan_bp.perform_regeneration`). Only code that tests do not patch moves out (view helpers, the re-export block, form parsing).
**Same caveat for analysis:** 13 tests patch `workout_bp.analyze_and_advise`; the sync path moves to `workout_analysis`, which must call `ai_generator.analyze_and_advise` at call time (the async tests already patch `ai_generator.analyze_and_advise`). Those 13 patches need a mechanical migration to the `ai_generator` target; budget it explicitly in the analysis-unification phase. Add a regression test that asserts the real model is not reachable (patch `ai_generator._call_with_fallback` to raise in the test fixture default) so a missed patch fails loudly instead of silently calling Gemini, which CONCERNS lists as a fragile point.

### Pattern 5: Lazy Redis cache with cooldown
**What:** replace the import-time `ping()` block with `_redis_cache()` that initialises on first `_cache_get/_cache_set`, under a lock, and after a failure records `_REDIS_DOWN_UNTIL = monotonic() + 60` so requests do not each pay the 2 s connect timeout.
**Why the cooldown matters:** lazy init alone moves the 2 s stall from import time into the first request, and a Redis that dies mid-run already costs 2 s per cache operation today (`socket_timeout=2` on every command). Without a circuit breaker the lazy change would be a regression in request latency.
**Test hook:** `reset_cache_state()` clears client, down flag and `_CACHE`. Keep `_CACHE` as a module-level dict (tests call `ai._CACHE.clear()` and assert `ai._CACHE == {}`); keep `_EXECUTOR` at module level (threads are created on first `submit`, so there is no import-time cost or fork hazard under gunicorn).

### Pattern 6: Exception policy by layer (what "narrowed" means)
| Layer | Policy |
|-------|--------|
| SDK boundary (`_call_with_fallback`) | Catch `genai.errors.APIError` (classify by `.code`), `concurrent.futures.TimeoutError`, `httpx.HTTPError`, `OSError`. Delete the substring matching on `'429'`/`'503'`. Final tail clause during rollout, see Build Order phase 2/5. |
| AI helpers (`_extract_json`, normalisers) | Already catch `(ValueError, TypeError)`; leave. Programming errors (`KeyError` in normalisation) must propagate. |
| Orchestration (`perform_*`, `perform_analysis`) | No `except Exception`. Return `(ok, AIFailure)`. |
| Transactional boundary after commit (workout save inline dispatch; `task_analyze_workout`) | One deliberate `except Exception`: roll back, set `failed`/`internal`, `logger.exception`; the task **re-raises** so RQ records the traceback; the request does **not** (workout already saved). |
| Best-effort side effects (`log_event`, mailer, Telegram alert, `ai_quota` fail-open) | Keep a catch, narrowed to `SQLAlchemyError` / `OSError` / limits-storage errors where the type is knowable; annotate with `# noqa: BLE001` and a reason where it must stay broad. |
| Probes (`bp/ops.py` Redis/RQ checks) | Narrow to `redis.exceptions.RedisError, OSError`. Not AI-critical; do last. |

Ratchet: once the above is done, add `BLE` (at least `BLE001`) to `ruff.toml` `select`. The code already carries `# noqa: BLE001` in `ai_quota.py`, `jobs.py`, `ai_generator.py`, which shows the intent; enabling it makes any new broad catch a lint failure and the CI gate keeps it from regressing.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Raising typed exceptions out of `_generate` in one step
**What people do:** convert every `return None` to `raise AIError` across `ai_generator`, `ai_plan_gen`, `ai_analysis`.
**Why it's wrong:** breaks ~30 tests and every patched fake at once, and the change lands in the safety-critical generation path (core value: no forbidden exercises) with no incremental checkpoint.
**Do this instead:** Pattern 1; consider exceptions only for *new* code paths (`queue_unavailable`).

### Anti-Pattern 2: Inline dispatch via `tasks.task_*`
**What:** calling the RQ task function directly for the non-queue branch "to share code".
**Why wrong:** nested `app.app_context()` -> second session -> SQLite locking/stale reads inside a request.
**Instead:** both branches call `perform_*`; tasks are shells.

### Anti-Pattern 3: Enqueue before commit / quota consumed before cheap validation
**What:** reordering for convenience inside the dispatcher.
**Why wrong:** worker may run before the row is visible; quota is burnt (the `limits` fixed-window API has no refund) on requests that fail validation.
**Instead:** validate -> commit -> `dispatch` (which consumes quota first, then enqueues). Accept that an enqueue failure after quota consumption burns one unit; it is the existing behaviour and rare.

### Anti-Pattern 4: New service modules importing `bp.*` or `app`
**What:** `workout_analysis.py` doing `from bp.workout import ...` to reuse helpers.
**Why wrong:** reproduces the existing `tasks -> bp.workout` smell and risks the cycle that appears only at worker start.
**Instead:** shared pure logic lives in `workout_logic.py` / service modules; blueprints import services, never the reverse. Add the new leaf/service modules to `test_split_modules_import_standalone`.

### Anti-Pattern 5: Auto-falling back to inline when the queue is down
**What:** on `enqueue` failure, run the 20-120 s Gemini call in the gunicorn worker.
**Why wrong:** `-w 2 --timeout 240` means two such requests starve the site. Return `queue_unavailable` (503) for generation/regeneration/debrief; for workout analysis degrade to `failed` + retry button (the workout is already saved).

### Anti-Pattern 6: Storing or displaying provider error text
**Why wrong:** may include prompt fragments (age, health conditions, limitations) and leaks internals. Store the code only.

### Anti-Pattern 7: Splitting by moving an endpoint to a new blueprint
**What:** moving `api_update_plan_day` etc. into `bp/plan_edit.py` with its own blueprint.
**Why wrong:** endpoint names change (`plan.x` -> `plan_edit.x`), which breaks `url_for`, the `base.html` nav list and `PAGE.*_url` values in JS. Prefer extracting non-route code. If routes must move, register them on the existing `plan.bp` object from the new module (imported at the bottom of `bp/plan.py`) to keep endpoint names.

## Split Plan (module-size ceiling, behaviour-preserving)

| Module (lines) | Seam | New module (approx. lines moved) | Notes |
|----------------|------|----------------------------------|-------|
| `bp/workout.py` (566) | form parsing, token issue/consume, `_already_saved`, `_empty_workout` (lines ~35-142) | `workout_form.py` (~110) | Uses `request`/`flash`, so it is Flask-aware but imports no `bp.*`. |
| `bp/workout.py` | analysis: `_history_for_ai`, `_analyze_extra_inline`, inline sync block | `workout_analysis.py` (~80 out, plus ~130 from `tasks.py`) | Part of the unification, not a separate extraction. `_analysis_state` / `_render_analysis_body` / `api_workout_analysis` stay (they render). |
| `bp/plan.py` (561) | `_split_plan_by_progress`, `_plan_visible_weeks`, `_null_plan_weights`, 25-line plan_insights re-export block | `plan_view.py` (~110) | Re-export plan_insights names from `bp.plan` unchanged (existing tests import them there). `perform_*` and `save_workout_plan` stay. |
| `bp/stats.py` (570) | debrief block: `last_full_week` ... `debrief_context` (lines ~363-525) | `weekly_debrief.py` (~160) | Re-export `perform_weekly_debrief` in `bp.stats` (1 test patches it; `tasks` imports it from there). Optionally the pure metrics block (lines ~22-262) -> `stats_calc.py`. |
| `helpers.py` (589) | PR/records block (`best_set` ... `get_last_weights`, ~130 lines); plan enrichment/schedule block (`_enrich_*`, `_user_data`, `_plan_frequency`, `plan_day_schedule`, ~155 lines) | `records.py`, `plan_helpers.py` | Re-export from `helpers` (`from records import ...  # noqa: F401`). New modules must not import `helpers` (one-way). Keep `update_prs` looked up through `helpers` in `tasks`/`workout_analysis` at call time so the one `helpers.update_prs` monkeypatch stays effective. |
| `validation.py` (576) | primitives `clean_*` (lines ~73-170) and plan/exercise/constructor validators (lines ~283-565) | `validation_clean.py` (~100), `validation_plan.py` (~280) | Dependency order must be one-way: `validation_options` <- `validation_clean` <- `validation_plan`; `validation` only re-exports. Putting the primitives in a third module is what avoids the circular import (`validation_plan` needs `clean_*`, `validation` re-exports `validation_plan`). Follows the existing `validation_options` precedent. |

Do not add new code to `helpers.py` / `validation.py` before their split; put new logic in the new service modules.

## Scalability Considerations

| Concern | Today (tens of users) | ~10K users | Notes |
|---------|----------------------|------------|-------|
| Long AI calls | One `rq worker ai`, jobs serialise; PROD gunicorn is `-w 2` | Run N RQ workers (systemd template unit), keep `GEMINI_MAX_WORKERS` <= worker count; inline mode is unusable here | Dispatcher keeps queue as the only long-call path in PROD |
| AI failure visibility | reason code on rows + `ai_metrics` counter per reason | counters survive restarts only if moved to Redis/DB; add per-reason aggregation to `product_metrics` | Adds the "admin-facing failure view" from CONCERNS cheaply |
| SQLite write contention | two-commit analysis flow adds one short write per workout | PostgreSQL (out of scope now) | Keep transactions short in `perform_analysis`: read, call model with NO open write transaction, then write. Do not hold a transaction across the Gemini call. |
| Quota across gunicorn workers | needs Redis `RATELIMIT_STORAGE_URI` | same | Guard with a startup warning/test, see Defence-in-depth |

Important implementation detail for the SQLite item: in `perform_analysis` the model call (up to ~20 s per model, `timeout=20` in `ai_analysis`) must happen between the read and the write commits; do not `db.session.add(...)` pending changes before the call.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Gemini (`google-genai>=2,<3`) | `ai_generator._get_client`, called inside `_EXECUTOR` threads | Classify with `APIError.code` (int). Exceptions from `generate_content` surface in the caller thread via `future.result()`. |
| Redis (cache, RQ, limiter, quota) | cache lazy (Pattern 5); RQ via `jobs.py`; limiter/quota via `limits` storage | One Redis serves four roles; the cache cooldown must not affect RQ/limiter. |
| RQ 1.16 | `Job.fetch`, `job.get_status()`, `job.result`, `job.exc_info` | Do not expose `exc_info` to clients (traceback). Map `JobTimeoutException` in `exc_info` to `timeout` (string match; MEDIUM confidence, verify against a real failed job in a test). |
| Telegram | unchanged | out of scope for this dimension |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `bp.*` -> `ai_dispatch` | direct call, passes closure + task path | blueprints never call `jobs.enqueue` directly after the change (grep-checkable invariant) |
| `ai_dispatch` -> `jobs` / `ai_quota` | direct | `ai_quota` already uses `current_app`; `ai_dispatch` is Flask-aware by design |
| `tasks` -> service modules | lazy import inside task body | `from app import app, db` stays inside functions; service modules imported lazily too |
| `perform_*` -> `ai_generator` | call by facade name, wrapped in `ai_errors.capture()` | patch targets stay `bp.plan.generate_full_plan` / `ai_generator.<name>` |
| `bp.workout` -> template | `_analysis_fallback.html` gets `reason`, `reason_text`, `can_retry` | keep copy in `ai_errors` (use the `copy-check` skill for RU text); no inline JS: retry button uses `data-*` + delegated listener in `static/ui.js`, per project convention |
| JS pollers (`my_plan.js`, `onboarding_generating.js`, `debrief.js`) | JSON `{status, message, reason?}` | already show `data.message`; no change needed for first pass |

## Build Order

Ordering principle: each phase must leave `main` green and deployable (every push to `main` reaches PROD), prefer additive steps first, and do the riskiest behaviour change (workout save flow) only after its dependencies have been in PROD for a deploy cycle.

**Phase 1: Safety net + extract-only splits of hot files (no behaviour change).**
- Add the missing tests that the later phases would otherwise break silently: `api_job_status` for a `failed` RQ job and for a finished job with an error result (CONCERNS gap, High); enqueue-failure for `/api/generate_plan` and `/api/regenerate_plan` (currently an unhandled 500, characterise it); a sync-vs-async parity test for analysis (same inputs, compare resulting `Workout.analysis`, plan weights, status); a fixture default that makes any unpatched Gemini call raise.
- Extract `workout_form.py`, `plan_view.py`, `weekly_debrief.py` with re-exports. Verify `tests/test_module_sizes.py`, then confirm patched names still work (`plan_bp.*`, `stats_bp.perform_weekly_debrief`).
- Why first: it buys ~100-180 lines of headroom in each hot file, so later phases do not hit the 600-line ceiling mid-change, and the parity test pins behaviour before it is unified.
- Independent track (can run any time, touches no AI orchestration): Telegram webhook negative-case tests, forbidden-exercise filtering with `EXERCISE_CATALOG_ENFORCE=0` (High, safety-relevant, do not postpone indefinitely), quota-with-shared-storage test.

**Phase 2: `ai_errors` + SDK-boundary classification + lazy Redis (additive).**
- New leaf module; `_call_with_fallback` classifies by `APIError.code`, notes reasons; `_generate`/extract/normalise sites note `invalid_response`. Keep a tail `except Exception` that notes `internal`, logs `logger.exception` (not just `warning`), and continues the fallback loop exactly as today, so behaviour is unchanged.
- Lazy Redis cache with cooldown + `reset_cache_state()`.
- `ai_metrics.record_failure(reason)`; surface on `/ai_metrics`.
- Add `ai_errors` to `test_split_modules_import_standalone`.
- Both `ai_generator.py` edits land together (same file, same test module, `tests/test_ai_generator.py`, `tests/test_ai_pipeline.py`).
- Deploy and let it run: the `internal` counter shows which unexpected exception types the SDK really produces, which is the input Phase 5 needs.

**Phase 3: Migration + dispatcher + request/response endpoints.**
- Alembic autogenerate for `Workout.analysis_error` and `WeeklyReport.error_reason` (one migration, nullable, expand-only). Ship this commit alone first so `db upgrade` runs before code depends on it.
- `ai_dispatch.dispatch`; convert `api_generate_plan`, `api_regenerate_plan`, `api_weekly_debrief`. `perform_*` return `AIFailure`; tasks return `task_result(...)`; `jobs.describe` + narrowed `get_job`; `api_job_status` returns `reason`; fix the missing `enqueue` guard on generate/regenerate (now 503 `queue_unavailable`).
- `weekly_debrief` writes `error_reason`; `_debrief_card.html` shows it.
- Why before workout: these endpoints share the dispatcher but have no transactional-flow subtlety, so the dispatcher is proven on lower-risk paths first. Update `test_tasks_jobs.py` fakes (they keep working thanks to the `str` subclass) and `test_api.py` (~line 386, queue path).

**Phase 4: Workout analysis unification (highest risk).**
- `workout_analysis.perform_analysis`; `tasks.task_analyze_workout` becomes a shell (boundary catch + re-raise); `workout_today` / `workout_extra` switch to save-then-dispatch; delete `_analyze_extra_inline` and the inline sync block; `tasks` stops importing from `bp.workout`.
- Migrate the 13 `workout_bp.analyze_and_advise` patches (plus `test_load_adaptation.py:151`) to `ai_generator.analyze_and_advise`.
- UI: reason text in `_analysis_fallback.html`, retry endpoint + button, `history_edit` clears `analysis_error`; quota-denied now stored as `failed` + `quota_*` with no retry offered.
- Why after Phase 3: needs `analysis_error` column deployed and the dispatcher proven; the parity test from Phase 1 is the acceptance gate.

**Phase 5: Narrow the exceptions.**
- Remove the Phase 2 tail clause in `_call_with_fallback` once `/ai_metrics` shows no (or only understood) `internal` classifications; remove `except Exception` from `bp/plan.py:336`, `bp/workout.py` (4 sites), `tasks.py` (replaced by the boundary pattern); narrow `jobs.get_job`, `ops.py`, `helpers.log_event`; enable ruff `BLE001`.
- Why last among the AI items: it is only safe once callers no longer rely on swallowing, and once there is production evidence of which SDK exception types exist. Done earlier it risks turning a transient SDK quirk into user-visible 500s.

**Phase 6: Remaining splits + defence-in-depth (independent of AI work).**
- `helpers.py` and `validation.py` splits (pure re-export moves). Then `/ai_metrics` in-app `remote_addr` check, `TELEGRAM_WEBHOOK_SECRET` minimum-length validation at config load, startup warning when `RATELIMIT_STORAGE_URI` is `memory://` while `AI_QUOTA_ENABLED`, and the admin role column. The admin role needs its own migration; keep it separate from Phase 3's migration so a rollback does not couple them.

**Dependency summary**
```
P1 tests+extract ──> P2 ai_errors/lazy redis ──> P3 migration+dispatcher ──> P4 workout unification ──> P5 narrowing
                                                                                      │
P6 helpers/validation split + defence-in-depth  (any time after P1; do not add code to helpers/validation before it)
Independent test-gap track (Telegram, enforce-off safety, quota storage): any time
```

## Open Questions the Roadmap Should Flag

- **Phase 4 needs a `/gsd-research-phase`-level look at the sync/async parity.** The retry-doesn't-mutate-plan decision, the two-commit transaction shape and the `previous_plan` source change are product-visible; confirm them against `docs/plan-eval.md` and the existing `test_workout.py` expectations before coding.
- **PROD `USE_JOB_QUEUE` value is inferred, not read** (`/etc/ai_trainer.env` is off-limits). If PROD actually runs inline, the convergence direction (canonicalise on async) still holds, but the Phase 4 behaviour change becomes visible in PROD.
- **`JobTimeoutException` detection** via `exc_info` string match is MEDIUM confidence; the Phase 3 test should force a timeout or construct a failed job to pin it.
- **RQ result TTL:** finished-job results expire (RQ default 500 s), after which `Job.fetch` raises `NoSuchJobError` and the poller sees 404 "Задача не найдена". Pollers run up to 10 min (`tries > 300` at 2 s). Verify `result_ttl` handling in `jobs.enqueue` when touching it; a short TTL plus a slow client reads as a spurious failure.
- **Redis cooldown value (60 s)** is a judgement call, make it a config constant.

## Sources

- Code read (HIGH): `bp/plan.py`, `bp/workout.py`, `bp/stats.py` (debrief block), `tasks.py`, `jobs.py`, `ai_generator.py`, `ai_analysis.py`, `ai_plan_gen.py`, `ai_quota.py`, `models.py` (`Workout`, `WeeklyReport`), `bp/history.py` (edit resets analysis), `static/pages/my_plan.js` (`pollJob`), `templates/_analysis_fallback.html`, `tests/test_module_sizes.py`, `tests/test_tasks_jobs.py`, `tests/test_workout_result.py`, `tests/ai_fixtures.py`, `deploy/systemd/ai_trainer.service`.
- Test-seam census (HIGH): grep of `tests/` for `monkeypatch.setattr(<bp module>, ...)` targets (13x `workout_bp.analyze_and_advise`, 3x `plan_bp.generate_full_plan`, 3x `plan_bp.perform_generation`, 2x `plan_bp.regenerate_plan_with_comment`, 1x `stats_bp.perform_weekly_debrief`, 1x `helpers.update_prs`; `ai._CACHE.clear()` used in `test_ai_generator.py` / `test_ai_pipeline.py`).
- Library facts verified in the project `.venv` (HIGH): `google.genai.errors.APIError.__init__` sets `.code` (int); `ClientError`/`ServerError` subclass `APIError`; `rq.exceptions.NoSuchJobError` exists; `rq==1.16.2`, `httpx==0.28.1`.
- `.planning/codebase/ARCHITECTURE.md`, `STRUCTURE.md`, `CONCERNS.md`, `.planning/PROJECT.md` (context; not re-derived).

---
*Architecture research for: Kachlog AI-hardening milestone (brownfield)*
*Researched: 2026-11-03*
