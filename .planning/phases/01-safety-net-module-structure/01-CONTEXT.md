# Phase 1: Safety Net & Module Structure - Context

**Gathered:** 2026-11-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Pin the runtime (Python 3.12, lockfile, RQ 2.x), build a test net that makes later refactors detectable (job states, enqueue failure, webhook negatives, forbidden-exercise filtering, shared-storage quota, CSRF-exempt set, `tasks.py` lazy imports, no accidental real Gemini calls), and extract non-route code from `bp/workout.py`, `bp/plan.py`, `bp/stats.py` so each has at least 100 lines of headroom under the 600-line ceiling. No user-visible behaviour change. Requirements: FND-01..09, SPL-01, SPL-02.

</domain>

<decisions>
## Implementation Decisions

All decisions below were auto-selected (`--auto`, recommended defaults from research). Nothing was confirmed interactively.

### Toolchain and lockfile
- **D-01:** Target Python 3.12 everywhere: `ruff.toml` `target-version = "py312"`, CI (`.github/workflows/ci.yml`, `.gitlab-ci.yml` venv) on 3.12. Dev venv already runs 3.12.3 — **Reversibility:** reversible — config only.
- **D-02:** Before changing anything, verify the Python version of the PROD venv on the Amsterdam host (agents cannot read the env file, but can run `python --version` in the venv path from `deploy/systemd/ai_trainer.service`). If PROD is not 3.12, stop and surface it; do not bump CI past what PROD runs.
- **D-03:** Lockfile via pip-tools (`requirements.in` → compiled pinned file) or `uv pip compile`; planner picks whichever is already available on the DEV venv. Keep `requirements.txt` and `requirements-dev.txt` as the files `deploy.sh` and CI install from, so deploy commands do not change shape. — **Reversibility:** costly — deploy installs depend on the file contents.
- **D-04:** Any change to `deploy/deploy.sh` goes in its own commit and is dry-run on DEV first; it deploys to PROD on push to `main`.
- **D-05:** `pip-audit` in CI is optional for this phase; add only if it does not make CI flaky.

### RQ 2.x upgrade
- **D-06:** Bump to `rq>=2.12,<3` (explicitly not 3.x). Verify with a real queued job through a worker on DEV (enqueue → worker picks up → completes) and with `fakeredis` + `SimpleWorker` in tests. Drain the `ai` queue before the PROD worker restart (note in the plan, do not run it).
- **D-07:** Do not use `rq.Retry` on AI tasks (re-consumes quota). Task signatures stay positional-compatible.

### Test net
- **D-08:** Add `pytest-socket` (or equivalent autouse fixture) so any test reaching an unpatched Gemini call fails. Allow-list only what existing tests need (Redis via fakeredis, localhost).
- **D-09:** Add `fakeredis` for job-failure and shared-quota tests. `tests/conftest.py` keeps its env-before-import ordering.
- **D-10:** Webhook negative tests must enable the bot in the test env and assert `handle_update` was not called (spy), covering wrong, empty and non-ASCII secret header and non-dict JSON. Known bug: `hmac.compare_digest` on `str` raises for non-ASCII; the test should be written to document current behaviour, and the fix itself belongs to Phase 4 (SEC-02). Mark the test `xfail(strict=True)` for the not-yet-fixed case, or assert the current 500, and record which.
- **D-11:** Forbidden-exercise tests use real catalog names, `EXERCISE_CATALOG_ENFORCE=0`, and assert on the persisted plan. Include the case where a focus area requests a forbidden exercise.
- **D-12:** Every new test gets a recorded mutation check (break the code, confirm red, restore) noted in the plan summary.
- **D-13:** A smoke test imports every symbol `tasks.py` lazy-imports (`bp.workout._apply_suggestions_to_plan`, `_clean_analysis`, `_process_suggestions`, `helpers._user_data`, plus `bp.plan` perform functions) so a broken worker import fails CI.
- **D-14:** CSRF-exempt test is behavioural: enumerate `app.url_map` and assert only the Telegram webhook view is exempt.

### Module splits
- **D-15:** Extract-only, no behaviour change, one module per commit, endpoint names and URLs unchanged. Candidates (from research): `workout_form.py` (from `bp/workout.py`), `plan_view.py` (from `bp/plan.py`), `stats_calc.py` (from `bp/stats.py`). Final names and cut lines are the planner's call, targeting at least 100 lines headroom each.
- **D-16:** `perform_generation`, `perform_regeneration`, `save_workout_plan` stay physically in `bp/plan.py` (tests patch `plan_bp.*`). Anything that tests patch by module name stays where it is; moved helpers are re-exported.
- **D-17:** New modules are added to the standalone-import test in `tests/test_module_sizes.py`. Consider `import-linter` contracts only if cheap; otherwise defer.
- **D-18:** `helpers.py` and `validation.py` splits are deferred to Phase 4 (SPL-03).

### Ordering inside the phase
- **D-19:** Toolchain first, then test net, then splits last (so tests make patches load-bearing before code moves). Each step leaves `main` green.

### Claude's Discretion
- Exact lockfile tool, test file names, new module names and cut lines, whether to add `pip-audit`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project planning
- `.planning/ROADMAP.md` §Phase 1 — goal, success criteria, planning notes
- `.planning/REQUIREMENTS.md` — FND-01..09, SPL-01, SPL-02
- `.planning/research/SUMMARY.md` — phase rationale and pitfalls mapping
- `.planning/research/STACK.md` — Python 3.12, lockfile, RQ 2.12, test tooling
- `.planning/research/PITFALLS.md` — split/patch traps, deploy window, tests that cannot fail
- `.planning/research/ARCHITECTURE.md` — split plan per module

### Codebase maps
- `.planning/codebase/TESTING.md`, `.planning/codebase/CONVENTIONS.md`, `.planning/codebase/STRUCTURE.md`, `.planning/codebase/CONCERNS.md`

### Project rules
- `CLAUDE.md`, `AGENTS.md` — pytest + ruff before every commit; push to `main` deploys to PROD; no hand-written migrations
- `tests/test_module_sizes.py` — 600-line ceiling and standalone-import checks
- `deploy/deploy.sh`, `.gitlab-ci.yml`, `.github/workflows/ci.yml`, `ruff.toml`, `pytest.ini`, `requirements*.txt`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `tests/conftest.py` and `tests/ai_fixtures.py`: isolated temp SQLite, env set before importing `app`, `app` fixture.
- `tests/test_tasks_jobs.py`, `tests/test_ai_pipeline.py`, `tests/test_ai_quota.py`: closest existing homes for job, pipeline and quota tests.
- `tests/test_module_sizes.py`: size ceiling and standalone-import test to extend.

### Established Patterns
- Facade/re-export modules; tests patch the name in the consuming module (`bp.plan.generate_full_plan`, `bp.workout.analyze_and_advise`).
- `tasks.py` imports `app` and `bp.plan` lazily inside task functions.

### Integration Points
- Current sizes: `helpers.py` 589, `bp/workout.py` 566, `bp/plan.py` 561, `bp/stats.py` 570, `validation.py` 576 lines.
- Dev venv and this host run Python 3.12.3; CI config still says 3.10.

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches.

</specifics>

<deferred>
## Deferred Ideas

- `helpers.py` / `validation.py` splits — Phase 4 (SPL-03)
- Fix for non-ASCII webhook header — Phase 4 (SEC-02); Phase 1 only pins the behaviour
- Typed AI error boundary, dispatcher, lazy Redis — Phase 2

</deferred>

---

*Phase: 1-Safety Net & Module Structure*
*Context gathered: 2026-11-03*
