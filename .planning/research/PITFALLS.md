# Pitfalls Research

**Domain:** Brownfield hardening of a production Flask + RQ + Gemini app (Kachlog) that auto-deploys to PROD on push to `main`
**Researched:** 2026-11-03
**Confidence:** HIGH for repo-specific findings (verified by reading `tasks.py`, `bp/plan.py`, `bp/workout.py`, `bp/telegram.py`, `bp/ops.py`, `ai_generator.py`, `ai_quota.py`, `jobs.py`, `deploy/deploy.sh`, `.gitlab-ci.yml`, `tests/test_module_sizes.py`, `migrations/env.py`). MEDIUM for generic RQ/Alembic/SQLite behaviours (stated from library knowledge, not re-verified against current docs; flagged inline).

Scope: the Active requirements in `.planning/PROJECT.md` (visible AI failure reasons, one sync/async path, narrower excepts, test gaps, module splits, defence-in-depth). Pitfalls are ordered by blast radius, not by item order in CONCERNS.md.

## Suggested phase vocabulary (used in the mapping below)

The roadmapper may rename these. Ordering rationale is in the last section.

- **P1 Safety net** - characterization and negative tests added first; no production-behaviour change.
- **P2 Module splits** - mechanical, behaviour-neutral splits of the near-limit modules.
- **P3 AI error boundary** - typed errors from the AI layer, stored failure reason, narrowed excepts, job-status contract.
- **P4 Sync/async unification** - one implementation for analysis and one `run_or_enqueue` path.
- **P5 Defence-in-depth** - `/ai_metrics` check, webhook secret strength, admin role, Redis hardening.

---

## Critical Pitfalls

### Pitfall 1: "Narrowing `except Exception`" does nothing because the AI layer already swallows the error

**What goes wrong:**
The plan is to narrow `except Exception` in `bp/workout.py`, `tasks.py`, `bp/plan.py`. But the real failure signal is lost one level lower: `ai_generator._call_with_fallback` catches every provider error per model, stores it in a local `last_error`, logs it, and then `return None`. `_generate`, `analyze_and_advise`, `generate_full_plan` all propagate that `None`. The callers' `except Exception` blocks therefore almost never fire for Gemini failures; they fire only for programming bugs (`KeyError`, `TypeError`). Narrowing them to `(GeminiError, requests.RequestException)` would catch nothing, and the user-visible failure stays "Не удалось..." because no reason ever reaches `perform_generation` / `_analyze_workout`.

**Why it happens:**
CONCERNS.md describes the symptom at the call sites (where `except Exception` is grep-able) rather than at the source (`return None` loses the cause). The fix looks like a mechanical grep-and-replace.

**How to avoid:**
Fix the boundary first, then the call sites:
1. Introduce a small typed result or exception hierarchy in the AI layer (for example `AIUnavailable`, `AIQuotaExceeded`, `AIBadResponse`, `AITimeout`) or a `(value, reason_code)` return. `_call_with_fallback` must record the final reason (all models 429 / all timeouts / empty / MAX_TOKENS / invalid JSON) instead of only `last_error` in a log line.
2. Keep ONE broad `except Exception  # noqa: BLE001` inside `_call_with_fallback` (the SDK raises arbitrary types) but convert to the typed reason there. This is the only place broad catching is legitimate (matches the CONVENTIONS.md rule "keep this pattern limited to the AI boundary").
3. Only then change call sites: let programming errors propagate to the global 500 handler, catch only the typed AI errors.
4. Keep the return contract backwards compatible for one phase (`None` still meaning failure for legacy callers) or update all callers and all test stubs in the same commit.

**Warning signs:**
- A PR that edits `except Exception` lines in `bp/*` and `tasks.py` but leaves `ai_generator.py` untouched.
- New tests that monkeypatch `analyze_and_advise` to raise a custom error, but no test that drives the real `_call_with_fallback` with a failing fake client.
- `grep -c "return None" ai_generator.py` unchanged after the phase.

**Phase to address:** P3 (AI error boundary). Must precede P4.

---

### Pitfall 2: Narrowed excepts turn a degraded-but-working request into a 500 for the user, and a wrong narrowing hides a data-loss bug in the RQ task

**What goes wrong:**
Several broad excepts are deliberate *containment* around work that happens after a successful DB write:
- `bp/workout.py` ~256: the workout is already being saved; AI failure falls back to `_build_fallback_analysis`.
- `tasks.py` ~96: `update_prs` failure after a committed analysis; it does `db.session.rollback()` and continues.
- `tasks.py` ~85/115/179 and `_mark_analysis_failed`: the last-resort path that flips `analysis_status` from `pending` to `failed`.
Narrowing these to "AI errors only" means a `KeyError`/`IntegrityError`/`OperationalError: database is locked` now escapes. In `task_analyze_workout` an escaping exception skips `_mark_analysis_failed`, leaving the row `pending` until the stale-timeout heuristic in `_analysis_state` (JOB_TIMEOUT + 300 s) reclassifies it. In the HTTP path an escaping exception after `db.session.commit()` of the workout yields a 500 on a request that actually saved the user's training (and the `WorkoutSubmission` token is consumed, so a retry shows "already saved").

**Why it happens:**
"Let programming errors propagate" is correct for the AI call itself but wrong for the surrounding persistence cleanup. The two roles share the same `try` in many places.

**How to avoid:**
- Split each `try` into two: a narrow `except <AI errors>` around the model call, and, where cleanup/state transition is required, a `try/finally` or an outermost handler that records state and re-raises.
- In `task_analyze_workout`, keep one outermost `except Exception` that (a) logs with `logger.exception`, (b) calls `_mark_analysis_failed` with a stored reason such as `internal_error`, and (c) re-raises or returns an error dict. Never let `pending` survive a task exit.
- Never narrow the `_mark_analysis_failed` handler itself (it must not raise out of the task's failure path).
- Add a test per site: inject `KeyError` into the AI function and assert the final DB state (`analysis_status == 'failed'`, workout row still present).

**Warning signs:**
- After the change, a `pending` workout older than a few minutes in the DEV DB.
- Tests only assert the HTTP status, not `analysis_status` / the persisted workout.

**Phase to address:** P3. Add the characterization tests in P1.

---

### Pitfall 3: Storing the failure reason needs a migration on SQLite, and `migrations/env.py` has no batch mode

**What goes wrong:**
`Workout.analysis_status` is `String(10)`, so a reason cannot be stuffed into it (and `'timeout'`-style codes combined with status would overflow). The natural fix is a new column (`analysis_error`/`analysis_reason`). On PROD this runs automatically through `deploy/deploy.sh` (`flask db upgrade` after a pre-deploy backup). Problems:
- `migrations/env.py` has no `render_as_batch` / `compare_type` configuration (grep found none). SQLite supports only `ADD COLUMN` natively; any autogenerated `ALTER COLUMN`, `DROP COLUMN`, constraint change or type change will either fail or be silently skipped (MEDIUM confidence on exact Alembic behaviour; SQLite's `ALTER` limits are well known).
- A new `NOT NULL` column without `server_default` fails on a populated table (`Cannot add a NOT NULL column with default value NULL`).
- Project rule: migrations are autogenerated, never hand-written. An autogenerate run on the DEV DB can also pick up unrelated drift (index/constraint differences between models and the real schema) and bundle it into the same migration.
- The deploy script does not auto-roll back: "миграция могла примениться частично, решение — за человеком". A bad migration on `main` means a red deploy with the app on old code in memory but new code on disk.

**Why it happens:**
Small column adds feel safe; the autogenerated file is not reviewed line by line; the migration is tested only against a fresh test DB (`db.create_all()` in the `app` fixture never runs Alembic).

**How to avoid:**
- Make the new column `nullable=True` (no `NOT NULL`), String/Text, no default needed. This is a pure `ADD COLUMN`, safe on SQLite and fast.
- Review the autogenerated file and delete any operation that is not the intended `add_column` (drift ops). Do not hand-write; regenerate after fixing models.
- Run `flask db upgrade` against a *copy of a PROD-shaped DB* on DEV (`scripts/backup_db.py` output restored on Finland) before pushing; also run `flask db downgrade` / re-upgrade to confirm it is reversible or at least idempotent on the copy.
- Add a test that runs `alembic upgrade head` on an empty SQLite file and then asserts `flask db migrate` produces an empty diff (catches model/migration divergence). `tests/conftest.py` currently bypasses Alembic entirely, so no existing test notices a broken migration.
- Ship the migration in a commit that contains *no other behaviour change*, and make the new reads tolerant of NULL (old rows and the window where the old worker code is still running).

**Warning signs:**
- Autogenerated migration contains `batch_alter_table`, `drop_`, `alter_column`, or touches tables unrelated to the change.
- Model has `nullable=False` on the new column.
- No evidence the migration ran against a non-empty DB.

**Phase to address:** P3 (reason storage). Verification step in the phase's success criteria: migration upgrade on a restored PROD-shaped backup.

---

### Pitfall 4: Splitting `helpers.py` / `bp/workout.py` / `bp/plan.py` silently breaks test patches and the lazy-import contract

**What goes wrong:**
The repo's mocking rule is "patch the name in the module that uses it" (`bp.plan.generate_full_plan`, `bp.workout.analyze_and_advise`, `workout_bp._apply_suggestions_to_plan`...). When a function moves to a new module:
- Existing `monkeypatch.setattr(workout_bp, 'analyze_and_advise', fake)` still *succeeds* (module attribute exists via re-export or leftover import) but no longer affects the new location that actually calls it. The real Gemini client is invoked (the key is a dummy, so it returns `None` quickly) and tests that assert on fake output fail confusingly, OR worse, tests that assert only "no crash" keep passing while testing nothing. CONCERNS.md notes this: "Patching the wrong module silently calls the real model" and "behavioural patching is not checked automatically".
- `monkeypatch.setattr` with `raising=True` (default) only fails if the attribute is *missing*; a re-exported name always exists, so the guard never trips.
- `tasks.py` does `from bp.workout import _apply_suggestions_to_plan, _clean_analysis, _process_suggestions` and `from helpers import _plan_frequency, _user_data` lazily. Moving those names without re-exporting breaks only at worker runtime (the import is inside the function), so the full test suite can stay green while PROD's RQ worker fails every analysis task with `ImportError`. `tests/test_tasks_jobs.py` stubs `ai_generator.analyze_and_advise` but `_analyze_workout` still performs the real lazy imports, so some coverage exists, but only along the paths it exercises.
- The `test_split_modules_import_standalone` list covers 7 modules only. New split modules (`helpers_*`, `bp/workout_*`) are not in it, so a circular import (new module imports from `bp.workout` that imports the new module) is not caught until a cold start.
- Facade re-exports: `bp/plan.py` re-exports `plan_insights`; templates and `base.html` use `request.endpoint` for nav highlighting. Moving a *view function* to a new blueprint module changes its endpoint name (`workout.x` to `workout_analysis.x`) and breaks `url_for` everywhere plus the nav list.
- Splitting while shifting lines: the 600-line ceiling test passes, but the "extract" often leaves the old module at 590 lines again after the next feature, because the split moved only leaf helpers.

**Why it happens:**
Python re-exports make imports keep working, which hides that the *binding used at call time* moved. Tests that stub by name look correct after the move.

**How to avoid:**
- Do P1 characterization tests *before* splitting. For each function being moved, add (or confirm) a test whose assertion depends on the stub being hit (for example the fake returns a distinctive payload and the test asserts that payload is persisted), so a mis-targeted patch fails loudly.
- Move code, then grep tests for every moved name: `grep -rn "<name>" tests/ tasks.py bp/ helpers.py`. Update each `monkeypatch.setattr` target to the new consuming module. Keep a thin re-export in the old module only for names imported by `tasks.py` and other modules, and note in a comment that tests must patch the consuming module.
- Keep Flask view functions (the routes) in the original blueprint module; move only pure helpers. Do not change endpoint names. If a route must move, update the `base.html` nav list and run a grep for `url_for('old.`.
- Extend `test_split_modules_import_standalone` with each new module in the same commit that creates it.
- Add one smoke test that imports every `tasks.task_*` and executes the lazy import block (call the task with a missing user id, which returns `{'status': 'error'}` before AI) so an ImportError in `tasks.py` fails CI.
- One split per commit/PR (`helpers`, then `workout`, then `plan`...) so a red pipeline points to one move.

**Warning signs:**
- A test that passes both before and after a stub target is changed to a nonsense module.
- Gemini-related log lines (`Клиент Gemini недоступен`, `Все модели исчерпаны`) in the pytest output after a split.
- Worker log on DEV shows `ImportError` / `cannot import name` after a split while pytest is green.

**Phase to address:** P1 (tests that make patches load-bearing) then P2. Run `quality-check`/code review at the end of P2.

---

### Pitfall 5: Unifying the sync and async paths changes the response contract that the frontend and PWA depend on

**What goes wrong:**
`api_regenerate_plan` and `api_generate_plan` return different shapes by mode: queued returns `{'status': 'queued', 'job_id': ...}` (frontend then polls `/api/job/<id>`), inline returns `{'status': 'ok'}` or `{'status': 'error'}, 200` (note: inline failure is HTTP 200 with `status:error`, while the unexpected-exception branch returns 500). `static/*.js` and the service worker branch on those shapes. A `run_or_enqueue()` helper that "returns the same shape" will break one of the consumers unless the JS is audited. Also:
- Inline mode throws away `current_user` context assumptions: `_analyze_extra_inline` uses `current_user` (`_user_data(current_user)`), while the task path loads the `User` by id. A shared helper must take a `user_id`/`User` argument, not read `current_user`, or the RQ worker (no request context) crashes. Tests under `USE_JOB_QUEUE=0` would not reveal it.
- The task path commits `analysis_status='ready'` + plan suggestions in one commit as an *idempotency* mechanism (comment in `tasks.py`: a rerun sees `ready` and does not apply `next_weights` twice). A "shared implementation" that applies suggestions in the inline path before saving the workout, or applies them in two commits, loses that guarantee on RQ retry or double enqueue.
- Sync path: analysis is computed inside the request *before* the workout row is committed and uses `history_data` from `_history_for_ai(user_id)`; async path builds its own 30-day history in `tasks.py` with different filters (`Workout.date >= month_ago`, limit 30, `id != workout_id`). Unifying silently changes which history the model sees in one mode, i.e. a behaviour change disguised as a refactor. Plan-quality eval (`docs/plan-eval.md`) will not catch it.
- Dev vs prod divergence is the original motivation (`.env` on DEV has `USE_JOB_QUEUE=1`, tests use `0`). A unified helper that is only tested with `0` keeps the queue branch untested.

**Why it happens:**
The two paths evolved separately; each has accumulated small intentional differences (history window, idempotency, request-context use) that look like duplication.

**How to avoid:**
- Before refactoring, write a table of differences between the two analysis paths (history source/window, user_data shape, `_clean_analysis`, `update_prs`, commit boundaries, idempotency) and decide each difference explicitly: keep, unify to the better one, or intentionally change. Record decisions in the phase plan.
- The shared function should be pure of Flask context: `(workout_id, user_id, ...) -> AnalysisOutcome(reason|None)`, called by the task directly and by the request path inline. The commit boundary and the `pending`-guard stay in the caller.
- Keep the HTTP response contract unchanged in the first iteration; add the new reason field as an *additive* key (`reason`/`code`) alongside `message`. Update JS in a separate commit only after the field is deployed.
- Test both modes against the same assertion set (parametrize `USE_JOB_QUEUE` 0/1; in mode 1 monkeypatch `jobs.enqueue` and execute the task function inline).
- Add a test that runs the task twice for the same `workout_id` and asserts plan weights are applied once.

**Warning signs:**
- Helper imports `current_user` or `request`.
- Diff removes the `if workout.analysis_status != 'pending'` guard or the single-commit block.
- JS files and templates unchanged while the JSON shape of an endpoint changes.

**Phase to address:** P4. P3 must land first (the unified function needs the typed error contract).

---

### Pitfall 6: `/api/job/<id>` "specific reason" leaks internals or becomes unreachable because of RQ result lifetimes

**What goes wrong:**
Three separate traps in the same endpoint (`api_job_status`):
1. **Leaking exception text.** The tempting fix for "one generic message" is to return `job.exc_info` or `str(exc)`. That exposes stack traces, SQL, file paths, and possibly prompt fragments (health data) to the browser. The existing design returns Russian user messages only; keep it.
2. **Two failure channels.** Task functions return `{'status': 'error', 'message': ...}` for handled errors (RQ status `finished`), while uncaught exceptions give RQ status `failed`. Users see specific messages only on the first channel. Test coverage for `failed` is exactly the gap named in CONCERNS.md (High). If the fix only improves the `finished` branch, the case that actually motivates the change (uncaught exception in task) is unchanged.
3. **TTL expiry.** RQ keeps finished results for a short default (`result_ttl` 500 s) and failed jobs much longer (`failure_ttl` default about a year) (MEDIUM confidence, RQ defaults from library knowledge; verify in the installed version). `jobs.get_job` swallows every fetch error as `None` and the endpoint then answers 404 "Задача не найдена". A user who closes the tab and returns after the TTL sees "not found" for a plan that was actually generated successfully, and Redis `failed` registry grows with user-linked job data. `meta.user_id` ownership is stored in job meta; if meta is lost (Redis flush), every poll 404s.
Also `get_job`'s `except Exception` makes a Redis outage indistinguishable from a missing job (returns 404 instead of a 503 "retry").

**How to avoid:**
- Define a closed set of reason codes with fixed Russian messages (`ai_timeout`, `ai_quota`, `ai_bad_response`, `internal_error`) and map exceptions to codes in the task wrapper; return only the code + mapped message. Log the real exception server-side with the job id.
- Wrap task bodies so uncaught exceptions are converted to a returned error dict (or `finished` with `status: error`) for *expected* AI failures, and let RQ mark `failed` only for unexpected ones; give `api_job_status` a distinct, tested message for `failed` / `stopped` / `canceled` states.
- Set `result_ttl` and `failure_ttl` explicitly in `jobs.enqueue` and document them. Consider persisting the final outcome in the DB (for analysis: the new reason column) so status survives Redis TTL.
- Distinguish "Redis unreachable" (503, `retry`) from "job not found" (404) in `jobs.get_job`.
- Test: fake Redis/Job with each RQ status; assert exact JSON and that `exc_info` content never appears in the response.

**Warning signs:**
- `job.exc_info` or `str(e)` appears in a JSON response/test fixture.
- No test that forces `get_status()` to return `failed`.
- Frontend polling loop has no terminal branch for unknown statuses (polls forever).

**Phase to address:** P3 (contract + tests); P1 can add the characterization test for the current generic message.

---

### Pitfall 7: Every push to `main` ships to PROD, and the DB migration, the gunicorn app and the RQ worker are not updated atomically

**What goes wrong:**
`deploy/deploy.sh` does backup, pip install, `db upgrade`, then restarts `ai_trainer` and `ai_trainer_worker`. Hardening refactors are exactly the kind of change that is sensitive to the gap:
- **Mixed-version window.** Between `db upgrade` and the restart, old app code runs against the new schema; between the app restart and the worker restart, new web code enqueues tasks that the *old* worker (old code in memory) executes, and vice versa. `enqueue('tasks.task_analyze_workout', current.id, user_id, None, None, None, None, meta=...)` passes a positional argument list; changing a task signature (new parameter, reordered args, renamed function) while jobs are queued makes old queued jobs raise `TypeError` in the new worker, or new jobs fail in the old worker. Because arguments are positional, adding a parameter in the middle is the classic break.
- **Queued/in-flight jobs lost on restart.** `systemctl restart ai_trainer_worker` kills a running Gemini call; the row stays `pending` until the 15-minute stale heuristic. Hardening that renames `analysis_status` values or adds a terminal state must keep reading old values.
- **CI gate is weaker than it looks.** `test` runs `pytest` (no e2e), `ruff` with only `E4,E7,E9,F`, on the CI shell runner on the *prod host* in `.ci-venv`; the e2e/Playwright suite and the Alembic path are not part of the gate. The first real exercise of a migration, a lazy `tasks.py` import, or a service-unit change is the production deploy itself.
- **Stuck-red recovery is manual** (no auto rollback by design). A red deploy after a successful migration leaves PROD in a partial state needing a human; a fast sequence of pushes is serialised by `resource_group` but each one still deploys.
- **Startup-time validation can crash-loop PROD.** See Pitfall 9 (webhook secret length at startup).

**How to avoid:**
- Work on a branch and merge to `main` only completed, individually-green increments; one behaviour change per merge. Prefer merging at a time when the queue is empty (check `/healthz` queue depth on localhost before merge).
- Treat task signatures as a public API: add new parameters as keyword arguments with defaults at the END, keep the old signature working for one deploy cycle, then remove. Never rename a `tasks.task_*` function without leaving an alias.
- Expand/contract schema changes: deploy the nullable column and tolerant reads first; start writing it in a later push; make reads strict only after.
- Keep new status values additive; update `_analysis_state` to treat unknown values as `failed`/fallback rather than raising.
- Run the full local gate (`pytest`, `ruff`, plus `-m e2e` on DEV for UI-touching changes) and a DEV dry run of `deploy/deploy.sh` with the overrides it already documents (`DEPLOY_VENV`, `INSTALL_UNITS=0`, `HEALTHZ_URL`).
- After push, watch the pipeline (GitLab API per CLAUDE.md) and `scripts/wait_healthy.py`; have the revert command ready (`git revert <SHA>` then push passes the normal pipeline).

**Warning signs:**
- Diff changes a `tasks.py` function signature or an `enqueue(...)` argument list in one commit.
- Migration and the code that requires it in the same commit with `NOT NULL` or strict reads.
- Plan to "just push to see CI".

**Phase to address:** Every phase (process rule). Put it in each phase's success criteria: "merged increment keeps old task signature working; migration additive".

---

### Pitfall 8: New failure-path tests that do not fail when the code is broken (mock-everything and wrong patch target)

**What goes wrong:**
The test suite sets `USE_JOB_QUEUE=0`, `AI_QUOTA_ENABLED=0`, `AI_CACHE_REDIS=0`, `RATELIMIT_STORAGE_URI=memory://`, `RATELIMIT_ENABLED=0` in `conftest.py`. New tests for the failure paths named in CONCERNS.md tend to:
- **Stub the function whose error handling is under test.** E.g. testing `api_job_status` with a `MagicMock` job that returns whatever the assertion wants, or patching `perform_generation` to return `(False, 'msg')` (already done in `tests/test_tasks_jobs.py`) and concluding "failure path covered". The code between the stub and the response is what is untested.
- **Test quota "across processes" against `memory://`.** The gap is explicitly Redis-shared counters; a test that uses `memory://` and calls `consume` twice proves nothing about two processes. A real test needs a shared backend (fakeredis or a second `FixedWindowRateLimiter` instance on one `MemoryStorage`) or a subprocess. Also `AI_QUOTA_ENABLED=0` in conftest means the quota branch is skipped unless the test re-enables it and clears `app.extensions['ai_quota']` (as `tests/test_ai_quota.py` does). Forgetting to pop the cached limiter leaks state between tests (counters persist, order-dependent failures).
- **Rate limiter disabled.** `RATELIMIT_ENABLED=0` means the `120/minute` limit on the webhook and `/api/job` limits are never exercised.
- **Webhook negative tests that pass for the wrong reason.** Wrong, empty or missing secret all return 404; the test can pass because `telegram_bot.bot_enabled()` is False (no `TELEGRAM_BOT_TOKEN` in test env) rather than because the secret check rejected the request. The existing positive test uses `monkeypatch.setitem(app.config, 'TELEGRAM_WEBHOOK_SECRET', SECRET)`, so a negative test must enable the bot AND set the secret AND then send the wrong header, and must also assert that `handle_update` was *not* called (spy), otherwise a regression that processes the update but still returns 404 would pass.
- **Forbidden-exercise test with enforcement off still passes through the catalog.** With `EXERCISE_CATALOG_ENFORCE=0`, `ai_normalize` line ~231 bypasses the equipment/catalog allow-list; the test must use exercise names that exist in the catalog AND names that do not, with a user whose limitation/age/health forbids them, and assert on the *final persisted plan*. Using `Упр{d}-{e}` placeholder names from `plan_data` (not in the real catalog) tests nothing about forbidden filtering. Config must be patched on the class (`monkeypatch.setattr(BaseConfig, 'EXERCISE_CATALOG_ENFORCE', False)`), not via env after import (documented in TESTING.md).
- **RQ is never run.** TESTING.md says "Do not start an RQ worker in tests". Fine, but then the serialization boundary is untested: `job.meta`, positional args and return-value JSON-serializability (task returns dicts; a task that returns a non-serializable value fails only in a real worker).

**How to avoid:**
- For each new test, do a *mutation check*: temporarily break the code under test (flip the `compare_digest`, remove the `abort(404)`, return the wrong status) and confirm the test goes red. Record this in the phase verification.
- Spy on side-effects (`handle_update`, `enqueue`, `send_message`, `analyze_and_advise`) to prove the guarded work did not happen.
- Use a Redis-faithful fake (fakeredis, or `RQ`'s `SimpleWorker` with `fakeredis` / `is_async=False`) for at least one end-to-end job test: enqueue through `jobs.enqueue`, run synchronously, read back through `api_job_status`.
- Re-enable the specific feature flag in the test and clean the cached singleton (`app.extensions.pop('ai_quota')`, `ai._CACHE.clear()`).
- Assert on persisted DB state with `db.session.expire_all()` (as in existing tests), not on the response alone.

**Warning signs:**
- Test passes both with and without the production change under test.
- Negative-webhook test never sets `TELEGRAM_BOT_TOKEN`/`TELEGRAM_BOT_USERNAME`.
- Fake/mocked object is constructed with the exact expected output.

**Phase to address:** P1 (write them first) and again as acceptance criteria in P3/P5.

---

### Pitfall 9: Fail-closed startup validation that takes PROD down (webhook secret length, admin role, in-app IP check)

**What goes wrong:**
Defence-in-depth items are the most likely to cause an outage because they reject *current* production inputs:
- **Webhook secret length at startup.** If `app.py`/`config.py` raises when `TELEGRAM_WEBHOOK_SECRET` is shorter than N, and the live secret in `/etc/ai_trainer.env` (which agents cannot read: denied in `.claude/settings.json`) is shorter, the new code deploys, `systemctl restart` fails, `wait_healthy` goes red, and the *old* process is gone. The worker (`rq worker ai`) imports the app too and crash-loops with `Restart=always`. Telegram's `secret_token` also has a format limit (1-256 chars, `A-Za-z0-9_-`; MEDIUM confidence, verify against Bot API docs), so a "strength" rule that demands other characters would make `set-telegram-webhook` (`cli.py`) fail to register.
- **`/ai_metrics` in-app `remote_addr` check.** `app.py` applies `ProxyFix(x_for=1)`, so `request.remote_addr` is the client IP from `X-Forwarded-For`, which nginx sets. An in-app allow-list on `127.0.0.1` therefore works only if nginx forwards the real client IP; if the internal location block omits the XFF header the check sees `127.0.0.1` for everyone and gives zero protection; if the check is applied to `/healthz` too, then external probes or `scripts/wait_healthy.py` / `scripts/alerts.py` that go through a different path (public hostname, IPv6 `::1`, Docker/other bind) get 403 and the deploy gate goes red. Tests using Flask's test client report `127.0.0.1` by default, so the unit test passes regardless.
- **Admin role column.** A new `User.role` column with `ADMIN_EMAILS` removed in the same change locks the admin out of `/admin/metrics` (non-admins get 404, indistinguishable from "page missing"), and the existing admin row has no role until a data step runs. Migration autogenerate cannot backfill.
- **Redis `requirepass`.** Setting a password in Redis without simultaneously updating `REDIS_URL`/`RATELIMIT_STORAGE_URI` in `/etc/ai_trainer.env` (and the DEV `.env`) breaks rate limiting, AI cache, quota (silently: `ai_quota.consume` catches storage errors and *allows* the call, so over-spend appears with only a log line), and the RQ queue. This requires server-side ops outside the git deploy.

**How to avoid:**
- Prefer degrade-safe checks: if the secret is too short, log an error and make the webhook return 404 (feature disabled) instead of refusing to boot. Validate in `set-telegram-webhook` (CLI) where a human sees the error, not at web/worker import time.
- Ask the owner to verify the live secret length out-of-band before turning on any hard enforcement; document it as a manual prerequisite in the phase plan. Never read `/etc/ai_trainer.env` from the agent.
- For `/ai_metrics`: keep nginx as the primary control; add the in-app check as *log + deny only for `/ai_metrics`* (not `/healthz`), test with explicit `environ_overrides={'REMOTE_ADDR': ...}` and `X-Forwarded-For` header cases (spoofed header from external client, `::1`, missing), and verify the nginx location sets `X-Forwarded-For` via `$proxy_add_x_forwarded_for` (so the last hop is trusted).
- For admin role: migration adds nullable column; code treats `role == 'admin' or email in ADMIN_EMAILS` for one release; remove the env list in a later release.
- Treat Redis hardening as an ops runbook step in `docs/operations.md` with an explicit sequence (update env, restart, check `/healthz`), not as a code-only change.

**Warning signs:**
- A `raise`/`sys.exit` in config import for an optional integration.
- Test for IP restriction that never sets `REMOTE_ADDR` or `X-Forwarded-For`.
- Change touching `/healthz` in the same PR as `/ai_metrics`.

**Phase to address:** P5. Keep each item in a separate merge.

---

## Moderate Pitfalls

### Pitfall 10: Making failures visible, but exposing health data or raw model output

**What goes wrong:**
Storing a "reason" and showing it can pull in model text, prompt fragments or exception messages. Prompts contain age, health conditions and limitations (flagged in CONCERNS.md for the Redis cache). A `reason` column holding `str(e)` from the Gemini SDK may include request payload snippets; surfacing it in `_analysis_fallback.html` or `/admin` view exposes it.
**Prevention:** store a code from a closed enum (+ optional short, server-generated detail without model/prompt content), not free text; map to Russian copy via `copy-check` guidelines; never log `prompt`/`response.text` at INFO.
**Phase:** P3.

### Pitfall 11: Retry button / "specific reason and retry" bypasses quota, token and idempotency guards

**What goes wrong:**
A new "retry analysis" action must go through `ai_quota.consume`, the `pending` guard in `task_analyze_workout`, and rate limits; otherwise retrying creates unlimited AI calls, or two concurrent retries (double click, offline PWA replay) enqueue two tasks and apply `next_weights` twice. The existing workaround (edit + resave resets status to `'none'` and requeues) is idempotent because the submit flow uses a one-time `WorkoutSubmission` token; a standalone retry endpoint has no such token.
**Prevention:** retry endpoint does an atomic compare-and-set `failed -> pending` in one UPDATE (`UPDATE ... WHERE id=? AND analysis_status='failed'`, check rowcount) before enqueueing; consume quota; add a per-workout cooldown; test double-submit. CSRF via the `ui.js` helper; JSON errors via `_json_error`.
**Phase:** P3 (UI/endpoint) with P4 reuse.

### Pitfall 12: Lazy import-time singletons are "fixed" and tests/worker start order changes

**What goes wrong:**
Moving `_REDIS_CACHE` init (Redis `ping()` at import, 2 s timeout) to lazy init changes behaviour: first request in each gunicorn worker pays the connect, a failed lazy init can be retried on every call (log storm and 2 s stall per call) unless failure is memoized, and tests relying on `ai._CACHE` / `ai._REDIS_CACHE` attributes break. Daemon-thread-based `_EXECUTOR` creation changes when the thread pool is created relative to gunicorn's fork (pre-fork import vs post-fork use): objects created at import before fork and shared across workers is a classic bug; moving creation lazily is actually safer, but only if the lock around lazy creation is correct.
**Prevention:** lazy init with a memoized negative result and a retry-after interval; expose `reset_for_tests()` and call it in an autouse fixture; keep names patched by `tests/test_ai_pipeline.py` (`ai._CACHE`) stable. This item is optional for this milestone (not in Active requirements); do not bundle it with P3/P4.
**Phase:** Out of the main path; only if scheduled.

### Pitfall 13: `ruff` passes, but narrowed excepts leave `# noqa: BLE001` dead and `BLE` is not even enabled

**What goes wrong:**
`ruff.toml` selects only `E4,E7,E9,F`; `BLE001` is not enforced, so `# noqa: BLE001` comments are decorative and nothing stops new broad excepts from creeping back. Conversely, enabling `BLE`, `B`, or `TRY` rules globally to "enforce the hardening" produces hundreds of unrelated findings, fails CI, and blocks PROD deploys.
**Prevention:** do not widen the global ruleset in this milestone. Optionally add a scoped test (grep-style, like `tests/test_module_sizes.py`) that counts `except Exception` in `bp/` and `tasks.py` against an allow-list of file:function pairs, so the number can only go down. Remove stale `noqa` as you narrow.
**Phase:** P3.

### Pitfall 14: Splitting modules inflates the 600-line guard evasion instead of reducing coupling

**What goes wrong:**
Splitting to satisfy `test_python_modules_under_limit` by moving the *tail* of the file into `xxx_extra.py`, or raising `MAX_LINES`, passes CI but leaves the same coupling. New modules named `helpers2.py`/`misc` become the next dumping ground; `helpers.py` becomes a facade that re-exports everything, so blueprints keep importing the whole thing.
**Prevention:** split by concern as CONCERNS.md suggests (PR/records, share tokens, formatting for `helpers.py`; submission vs analysis rendering for `bp/workout.py`); aim for roughly 400 lines per resulting module to leave headroom; never change `MAX_LINES`; add the new module to the standalone import test.
**Phase:** P2.

### Pitfall 15: Quota fix "for multiple processes" fails open and hides itself

**What goes wrong:**
`ai_quota.consume` catches every storage error and returns `None` (allows the call). Making the limiter Redis-backed by default means a Redis outage silently disables the quota (only a log line), reproducing the over-spend. Also the check-then-hit sequence (`test` x2 then `hit` x2) is not atomic: two concurrent requests from one user both pass `test` and both `hit`, so the daily limit can be exceeded by the concurrency level. The global 'single fixed window' behaviour is documented; adding a per-minute window changes semantics for the Telegram reminder path (`telegram_bot.py` line ~195 consumes quota for weekly debrief).
**Prevention:** decide explicitly fail-open vs fail-closed per tier (fail-open for user experience, but emit an alert/metric when storage is down); assert at startup in production that `RATELIMIT_STORAGE_URI` is not `memory://` (log error, do not crash, see Pitfall 9); use a single `hit` and compare the result where possible; add a test with two limiter instances sharing storage.
**Phase:** P1 (test) + P5 (startup warning).

---

## Minor Pitfalls

### Pitfall 16: Telegram webhook negative tests forget non-dict JSON and missing `message`

**What goes wrong:** `request.get_json(silent=True) or {}` returns a list/str/int for non-object JSON (`[]` falls to `{}` but `"x"` or `[1]` is truthy), then `update.get('message')` raises `AttributeError` -> 500 to Telegram, which retries with backoff and can queue a retry storm.
**Prevention:** add tests for `[1]`, `"x"`, `{}`, `{'message': None}`, `{'message': {'chat': None}}`; coerce non-dict to `{}` in the handler; keep returning 200 with `{}` for ignorable updates so Telegram stops retrying.
**Phase:** P1 test, P5 fix.

### Pitfall 17: Exempt-CSRF guard test is brittle

**What goes wrong:** "assert the exempt list is exactly the webhook" implemented by reading private `csrf._exempt_views` (internal attribute, set of dotted names) breaks on a Flask-WTF upgrade; implemented by scanning source for `@csrf.exempt` misses `csrf.exempt(view)` calls.
**Prevention:** assert behaviourally: iterate `app.url_map`, POST every non-GET rule without a token via `csrf_app`, expect 400 except `/telegram/webhook`.
**Phase:** P1/P5.

### Pitfall 18: Thread-based mailer/alerts "fix" changes test determinism

**What goes wrong:** switching to `background=False` or adding retries for mail/alert delivery in tests that currently stub `no_weekly_debrief`/mailer can make real network calls or slow tests (blank tokens in `conftest.py` mask it).
**Prevention:** do not touch delivery semantics in this milestone unless tests assert delivery failure handling; keep tokens blank in tests.
**Phase:** Out of scope unless scheduled.

### Pitfall 19: Documentation drift

**What goes wrong:** `docs/operations.md`, `AGENTS.md`, `CLAUDE.md` state facts that the refactor changes (error semantics, where `perform_*` live, patch targets). Stale docs mislead the next agent session and the `.claude/rules/*`.
**Prevention:** update `CLAUDE.md` patch-target notes and `docs/operations.md` in the same phase that moves code; use `/gsd-docs-update`.
**Phase:** end of P2, P3, P5.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Keep re-exports in old module after a split "just in case" | No test/import churn | Old module never shrinks; patches target the wrong module | Only for names imported by `tasks.py`/other modules; add comment, remove in a later phase |
| Store reason as free text (`str(e)`) | One-line change | Leaks internals/health data; unlocalized UI | Never |
| Return `{'status':'error'}` with HTTP 200 (current inline regenerate failure) | Frontend already handles it | Monitoring/retry logic cannot see failures; inconsistent with the 429/500 cases | Keep until JS audited, then align in P4 |
| Positional args for `enqueue(...)` | Short call sites | Signature changes break queued jobs across deploys | Switch new params to kwargs-with-defaults; never reorder |
| `USE_JOB_QUEUE=0` as the only tested mode | Simple tests | Queue branch (prod) untested | Never for code that is shared; parametrize both |
| Single mega-commit "hardening" to main | Fewer pipelines | Cannot bisect/revert a prod regression; mixed migration + behaviour | Never (each push deploys) |
| Raising `MAX_LINES` in `test_module_sizes.py` | Unblocks a feature | Guard becomes meaningless | Never |
| Fail-open quota on storage error | Product keeps working | Silent over-spend | Acceptable only with alert + startup warning |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Gemini SDK (`google-genai`) | Parsing `str(e)` for `429`/`503` (current code) and treating all other errors as equal | Use SDK exception classes/`status_code` where available (check installed version, verify via docs) at the single boundary; keep string fallback; map to reason codes |
| Gemini fallback chain | Treat MAX_TOKENS/empty/invalid JSON as "model unavailable" | Distinguish `ai_bad_response` from `ai_unavailable`; do not cache invalid output (already done via `validator`) |
| RQ | Assuming `finished` means success; assuming results live forever | Inspect returned dict status; set `result_ttl`/`failure_ttl`; persist outcome in DB |
| RQ worker | Restart kills running jobs; code in memory is old until restart | Idempotent tasks, additive signatures, status guard (`pending`) already exists, keep it |
| Redis | One password/URL change breaks cache, limits, quota and queue at once | Change env on both servers first, restart, check `/healthz`; code unchanged |
| Telegram Bot API | Returning non-200 from the webhook (Telegram retries); no `retry_after` handling on outbound 429 | Always 200 for ignorable updates; add `retry_after` backoff in `telegram_bot.api_call` only if scheduled |
| nginx + ProxyFix | In-app IP checks assume `remote_addr` is the peer; with `ProxyFix(x_for=1)` it is the forwarded client | Test with XFF cases; keep nginx allow/deny as the primary control |
| SQLite + Alembic | `ALTER`/drop assumptions; autogenerate drift | Additive nullable columns only; review generated file; test on PROD-shaped copy |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Writing the failure reason inside the same long transaction as the AI result | `database is locked` for web requests while the worker writes | Short transactions in `tasks.py`; commit reason in its own tiny transaction in the failure path | 2 gunicorn workers + RQ worker writing concurrently; visible with a few concurrent users |
| Unified helper loading full history per call | Slower analysis, bigger prompts | Keep the existing `limit(30)`/30-day window; do not "unify" to the unbounded `_history_for_ai` without checking | Users with hundreds of workouts |
| `api_job_status` polling plus extra DB lookup for reason | 60/min limit per user hit by the poller, DB load | Reason from job result; DB only on terminal state | Many users polling after a regenerate burst |
| Adding Redis round-trip (quota/alerts) to every request path | Latency, and the Redis outage turns into request errors | Keep storage errors contained at the quota boundary | Redis restart/outage |
| Running a real `rq` worker or Playwright in the CI gate | Slower, flaky red blocks deploy | Keep e2e opt-in; add fakeredis-based tests instead | Immediately (CI runs on the PROD host) |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Returning `exc_info`/`str(e)` in `/api/job` or admin views | Information disclosure, health data in prompts | Closed reason-code set with fixed copy |
| New CSRF exemption for a retry/webhook-like route | CSRF bypass on a state-changing route | Behavioural exempt-list test (Pitfall 17) |
| `hmac.compare_digest` with non-ASCII `str` headers | `TypeError` -> 500 instead of 404 (compare_digest on `str` requires ASCII) | Encode both sides to bytes before comparing; add a test with a non-ASCII header value |
| Rate limit disabled in tests so the webhook limit is untested | Regressions unnoticed | One test with `RATELIMIT_ENABLED` on and in-memory storage |
| In-app admin role without audit trail | Silent privilege grants | Log access via `log_event`; nullable role column first |
| Share/reset tokens share `SECRET_KEY` | Rotating key revokes links; leak compromises both | Document (CONCERNS.md); do not rotate during hardening; out of scope to split secrets |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Technical reason text ("Gemini 429") shown | Confusion, no action possible | Short Russian copy per code with an action ("Повторить", "Попробуйте через минуту"); run `copy-check` |
| Retry button always visible | Users hammer it during outage | Show only for retriable codes; disable for quota codes and show when to come back |
| Inline mode returns 200 + error while queued mode shows polling spinner then error | Inconsistent feedback between environments | Same shape and same terminal states in both modes (P4) |
| Offline PWA replays a retry POST later | Duplicate AI call/double apply | CAS on status + idempotent endpoint; service worker must not cache these POSTs |
| `stale pending` shown as `failed` after 15 min with no reason | User thinks AI "broke" | Store `timeout`/`worker_lost` reason when the stale heuristic fires |

## "Looks Done But Isn't" Checklist

- [ ] **Reason shown to the user:** often missing the `failed` RQ state path (uncaught exception) - verify by forcing an exception inside `task_regenerate_plan` and polling `/api/job/<id>` with a fake failed job.
- [ ] **Narrowed excepts:** often missing a test that a programming error now yields the global 500 page/JSON (and that DB state is consistent) - verify with an injected `KeyError`.
- [ ] **Shared sync/async analysis:** often only tested with `USE_JOB_QUEUE=0` - verify both modes plus double-run idempotency.
- [ ] **Module split:** often missing standalone-import entry and updated patch targets - verify the new module is in `test_split_modules_import_standalone`, grep tests for old patch targets, run `python -c "import tasks; ..."` lazy-import smoke.
- [ ] **Webhook negative tests:** often missing bot-enabled setup and the "handler not called" assertion - verify via mutation check.
- [ ] **Forbidden-exercise with enforcement off:** often uses non-catalog placeholder names - verify with real catalog names in each forbidden class (limitation, age, health) and assert on the persisted plan.
- [ ] **Quota across processes:** often tested on `memory://` single instance - verify two limiter instances on one shared storage.
- [ ] **Migration:** often only run on empty test DB - verify upgrade on a restored copy of a PROD backup and a clean `flask db migrate` diff afterwards.
- [ ] **Defence-in-depth:** often breaks `/healthz`/deploy gate - verify `scripts/wait_healthy.py` and `scripts/alerts.py` against the changed endpoints on DEV with `deploy/deploy.sh` overrides.
- [ ] **Docs:** `CLAUDE.md`/`docs/operations.md` updated for moved names and new reason codes.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Bad deploy after green CI (logic regression) | LOW | `git revert <SHA>` + push (normal pipeline); check queue depth first |
| Worker `ImportError` after split | LOW | Revert, or hotfix re-export in the old module; restart worker; stuck `pending` rows self-heal via stale heuristic (15 min), or run a one-off script to mark `failed` |
| Partially applied migration | HIGH | Follow `deploy.sh` rollback block: stop services, restore the `predeploy` backup (`gunzip -c BACKUP > instance/trainer.db`), `git reset --hard PREV`, reinstall, restart, `wait_healthy.py` |
| Startup validation crash-loop | MEDIUM | Server-side: fix env value or `git revert`; `Restart=always` will keep flapping until fixed; use `journalctl -u ai_trainer` |
| Queued jobs with old signature fail | LOW-MEDIUM | Let them fail (they land in RQ failed registry), re-enqueue by user retry; keep back-compat signature in the next deploy |
| Duplicate `next_weights` applied | MEDIUM | Plan weights corrected by the user via plan edit; no automatic repair; prevent via single-commit guard |
| Redis password mismatch | MEDIUM | Revert env on the server, restart app + worker; quota silently failed open in the meantime, check `AI_DAILY_*` spend |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1 Narrowing does nothing (AI layer returns `None`) | P3 | Test drives real `_call_with_fallback` with failing fake client and asserts reason code |
| 2 Containment excepts narrowed too far | P1 tests, P3 | Injected `KeyError` leaves `analysis_status='failed'` and workout row saved |
| 3 Migration on SQLite without batch mode | P3 | Upgrade on restored PROD-shaped backup; empty `flask db migrate` diff; nullable column |
| 4 Split breaks patches / lazy imports | P1 then P2 | Stub-dependent assertions; new modules in standalone import test; task lazy-import smoke test |
| 5 Sync/async unification changes contract | P4 | Behaviour-difference table in plan; parametrized `USE_JOB_QUEUE`; double-run idempotency test |
| 6 `/api/job` reason leaks / TTL / failed state | P3 | Fake Job per RQ status; no `exc_info` in JSON; explicit TTLs |
| 7 Push-to-main deploy mixed-version window | All phases | Additive migrations; task signatures backward compatible; DEV dry-run of `deploy.sh`; pipeline watched |
| 8 Failure-path tests that cannot fail | P1 (and P3/P5 acceptance) | Mutation check recorded per new test |
| 9 Fail-closed startup/IP/role/Redis changes | P5 | Degrade-safe behaviour; XFF test cases; `wait_healthy` green on DEV |
| 10 Reason leaks health data | P3 | Closed enum column; grep for `str(e)` stored |
| 11 Retry bypasses guards | P3/P4 | Atomic CAS test; quota consumed; double-click test |
| 12 Lazy singleton changes | Deferred | Only if scheduled; reset hook + memoized failure |
| 13 Ruff/noqa drift | P3 | Allow-list test for `except Exception` count |
| 14 Split by tail instead of concern | P2 | Module sizes < ~450 lines; no `*_extra.py` |
| 15 Quota fail-open / non-atomic | P1 test, P5 warning | Two limiter instances shared storage; startup warning on `memory://` |
| 16 Webhook odd JSON | P1 test, P5 fix | Parametrized bad payloads return 200/404, never 500 |
| 17 CSRF exempt guard brittle | P1/P5 | Behavioural test over `url_map` |
| 19 Docs drift | P2, P3, P5 end | Docs diff reviewed |

## Phase ordering implied by the pitfalls

1. **P1 Safety net first.** Tests are additive, do not change prod behaviour, and make P2-P4 detectable. Includes: `api_job_status` failed/finished/unknown states, webhook negatives with bot enabled, forbidden-exercise filtering with `EXERCISE_CATALOG_ENFORCE=False`, quota with shared storage, tasks lazy-import smoke, behavioural CSRF-exempt test. Apply mutation checks.
2. **P2 Module splits before behaviour changes.** `helpers.py`, `bp/workout.py`, `bp/plan.py`, `bp/stats.py`, `validation.py` are within 11-35 lines of the ceiling; P3/P4 add code to exactly these files (reason handling, shared helper), so splitting first avoids a size-test failure mid-refactor. Mechanical, one module per commit.
3. **P3 AI error boundary** (typed errors, additive nullable column, job-status contract, narrowed excepts). Depends on P1 tests, benefits from P2 headroom.
4. **P4 Sync/async unification** after P3 so the shared function uses the typed contract and the stored reason.
5. **P5 Defence-in-depth** last and each item separately; it carries the highest outage risk per line changed and needs owner-provided ops facts (live webhook secret length, nginx XFF config, Redis password rollout).

## Sources

Repo evidence (HIGH): `/root/ai_trainer-gsd/tasks.py`, `bp/plan.py` (`perform_generation`, `api_regenerate_plan`, `api_job_status`), `bp/workout.py` (`_analyze_extra_inline`, `_analysis_state`), `bp/telegram.py`, `bp/ops.py`, `ai_generator.py` (`_call_with_fallback`, `_generate`), `ai_quota.py`, `jobs.py`, `app.py` (ProxyFix), `deploy/deploy.sh`, `deploy/systemd/ai_trainer_worker.service`, `.gitlab-ci.yml`, `migrations/env.py`, `tests/test_module_sizes.py`, `tests/test_tasks_jobs.py`, `.planning/codebase/CONCERNS.md`, `CONVENTIONS.md`, `TESTING.md`, `.planning/PROJECT.md`.

Library behaviour from general knowledge (MEDIUM, not re-verified with current docs in this session; confirm during phase research): RQ default `result_ttl`/`failure_ttl` and failed-job semantics; SQLite `ALTER TABLE` limits and Alembic batch mode; Telegram `secret_token` character constraints; `hmac.compare_digest` on non-ASCII `str`.

---
*Pitfalls research for: brownfield hardening of Flask + RQ + Gemini app with auto-deploy to PROD*
*Researched: 2026-11-03*
