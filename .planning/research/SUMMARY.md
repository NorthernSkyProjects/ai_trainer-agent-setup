# Project Research Summary

**Project:** Kachlog (brownfield hardening milestone)
**Domain:** AI-assisted gym workout tracking and planning (Flask + RQ + Redis + SQLite + Gemini), auto-deployed to PROD on push to `main`
**Researched:** 2026-11-03
**Confidence:** MEDIUM-HIGH

## Executive Summary

Kachlog is a working Flask monolith that generates and analyses workout plans with Gemini. Core Value: plans never contain exercises forbidden by the user's limitations, age or health conditions, on both the AI and manual paths. This milestone is hardening, not re-platforming. The stack stays (Flask, SQLite, vanilla JS, RQ, Redis). Mainstream trackers (Fitbod, Hevy, JEFIT) use deterministic progression and treat the LLM as optional, so Kachlog should keep deterministic safety and progression rules as the backbone and use the LLM for composition and narrative only.

The central finding: the AI layer swallows every failure. `_call_with_fallback` returns `None` for five different causes, so narrowing `except Exception` at call sites alone achieves nothing. Fix the boundary first. Architecture and Stack research disagree on how. Architecture recommends an out-of-band reason (`ai_errors.note()` / `capture()` over a thread-local) that keeps `str | None` return contracts, because about 30 tests fake those contracts. Stack recommends a typed `AIError` hierarchy mapped from `genai_errors.APIError.code`. Recommendation: use the typed hierarchy at the SDK boundary, with a closed code vocabulary, but introduce it through the compatibility shim (reason noted out-of-band, return contracts unchanged) so P3 does not rewrite the test suite in one commit. Store reason codes only, never provider text (health data can leak). Pair that with one `ai_dispatch` for sync/async, one `perform_analysis`, a retry endpoint, and a labelled degraded fallback.

Main risks: every push to `main` deploys to PROD (mixed web/worker/schema window, positional RQ task args, no auto-rollback), and refactors silently break test patches (re-exports keep imports alive but not patch effectiveness). Mitigate with a characterization-test phase first, additive nullable migrations, backward-compatible task signatures, one behaviour change per merge, and degrade-safe (not crash-on-boot) defence-in-depth checks. Two concrete bugs surfaced: `hmac.compare_digest` on `str` in `bp/telegram.py` gives 500 on non-ASCII headers, and the Gemini fallback chain holds aliased or soon-dead model IDs.

## Key Findings

### Recommended Stack

Keep the stack; change versions and patterns. Python 3.10 is EOL and the ecosystem is leaving it (`google-genai 2.34` needs 3.11+). CI pins 3.10 while the dev venv and the runner use 3.12, so CI can resolve different dependencies than prod. Requirements are unpinned with no lockfile, and google-genai ships weekly. Details in `STACK.md`.

**Core technologies:**
- CPython 3.12 everywhere plus a lockfile (uv or pip-tools): removes CI/prod dependency drift. Confirm the prod venv is 3.12 on the Amsterdam host first.
- google-genai `>=2.34,<3`: typed `APIError.code`/`.status`, per-request `HttpOptions.timeout` (ms), `response_schema` for fixed-shape payloads.
- rq `>=2.12,<3`: skip 3.0.0 (released 2026-10-28, breaking). Drain the `ai` queue before restart. No `rq.Retry` on AI tasks (re-consumes quota).
- redis-py `>=5,<8`: `limits[redis]` caps `<8`.
- Gemini chain: distinct models only (`gemini-3.8-flash`, `gemini-3.6-flash`, `gemini-3.5-flash-lite`); drop aliases and `*-latest`; 2.5 models shut down 2026-12-01. Re-verify at pin time.
- Test tooling: fakeredis, pytest-socket, hypothesis (one property: normalised plans never contain forbidden exercises), time-machine, import-linter. Ruff: add `BLE` as a per-file-ignore ratchet.
- Security: `User.is_admin` column plus CLI, `SECRET_KEY_FALLBACKS`, webhook secret regex and bytes compare. No Flask-Talisman, no RBAC framework.

### Expected Features

**Must have (table stakes, v1):**
- Typed AI failure taxonomy and reason codes, with specific Russian messages for analysis and job status
- Retry for failed analysis and plan jobs (retryable classes only; not for quota)
- Single run-or-enqueue path and a shared analysis helper
- Labelled degraded fallback analysis ("Базовый анализ (ИИ недоступен) [Повторить]")
- Always-on deterministic safety filter, independent of `EXERCISE_CATALOG_ENFORCE`, with tests (focus areas and favourites must not override limitations)
- Safety parity on the manual constructor (warn-on-add or block; owner decision needed)
- Onboarding health disclaimer acknowledgement plus physician notice (wording needs owner/counsel sign-off)
- Job-failure and Telegram webhook negative tests

**Should have (v1.x differentiators):**
- Plan restriction snapshot and "plan out of date" banner
- Safety report: what was removed and why
- Swap-for-safe-alternative; visible quota remaining; CSV export
- Deterministic plateau detection and return-from-break reduction
- Admin AI failure view (needs the admin role)

**Defer (v2+):**
- Per-exercise more/less/never feedback; explainable-suggestion UI; muscle-volume dashboard refinements; Telegram failure-recovery messages
- Anti-features, never build: prompt-only safety, preferences overriding limitations, rehab advice, free-form AI chat, social, wearables, multi-provider LLM, silent retry loops

### Architecture Approach

Delta on the existing blueprint/facade/RQ design. `perform_generation`, `perform_regeneration` and the weekly debrief already have one implementation each. The real duplicate is workout analysis (inline sync block plus `_analyze_extra_inline` vs `tasks._analyze_workout`). Differences include history window, commit boundaries, `previous_plan` source, and a second `update_prs` call. Canonicalise on the async implementation because PROD runs it (inferred; `/etc/ai_trainer.env` is unreadable). Full detail in `ARCHITECTURE.md`.

**Major components:**
1. `ai_errors.py` (new leaf, stdlib only) — reason codes, RU text, retryable flag, capture helper, RQ result envelope
2. `ai_dispatch.py` (new) — only reader of `USE_JOB_QUEUE`; quota, then enqueue or inline; never falls back inline when the queue is down
3. `workout_analysis.py` / `weekly_debrief.py` (extracted) — one `perform_*` per operation; `tasks.py` becomes thin shells that import services, not `bp.workout`
4. `jobs.py` — `describe(job)`, `get_job` narrowed to `NoSuchJobError`, explicit result/failure TTLs
5. Schema: nullable `Workout.analysis_error`, `WeeklyReport.error_reason`; `User.is_admin` in a separate migration

Patterns: out-of-band reason with unchanged contracts; both dispatch branches call `perform_*`, never `tasks.task_*` (nested app context locks SQLite); expand-then-contract migrations; extract-with-re-export, but keep patched functions physically in their module; lazy Redis cache with a cooldown; exception policy per layer (one deliberate broad catch at transactional boundaries, which log and re-raise or mark failed).

### Critical Pitfalls

1. **Narrowing excepts at call sites does nothing** — the AI layer returns `None`. Fix the boundary in `ai_generator` first; keep one legitimate broad catch there.
2. **Over-narrowing containment excepts** — a workout is already saved when analysis fails, and escaping exceptions leave `pending` rows or 500 a saved request. Keep an outermost handler that records state; test with an injected `KeyError`.
3. **Split breaks patches and worker lazy imports** — re-exports keep imports alive but not patch effectiveness. Make patches load-bearing in tests first, move only non-route code, keep endpoint names, and add a lazy-import smoke test for `tasks.py`.
4. **Push-to-main deploy window** — mixed schema/web/worker versions and positional RQ args. Use additive nullable migrations, new args as trailing kwargs, one behaviour change per merge, and a DEV dry run of `deploy/deploy.sh`.
5. **Sync/async unification silently changes behaviour** — document the differences table (history window, idempotency, commit boundaries, `previous_plan`), keep the HTTP shape additive, test both modes, and test double-run idempotency.
6. **Defence-in-depth can crash-loop PROD** — webhook secret length, the `/ai_metrics` IP check under ProxyFix, the admin role and the Redis password must degrade safely and ship separately; the live secret length needs an owner check.

Also: `/api/job` must never return `exc_info`; retry needs an atomic compare-and-set `failed -> pending` plus quota; new tests need mutation checks.

## Implications for Roadmap

Architecture and Pitfalls agree on this ordering: tests, then splits, then AI boundary, then unification, then narrowing, then defence-in-depth.

### Phase 1: Foundation and safety net
**Rationale:** Additive and low-risk. It makes every later refactor detectable and removes dependency drift.
**Delivers:** Python 3.12 plus lockfile and CI alignment, RQ 2.12, pytest-socket and fakeredis scaffolding, a default fixture that makes unpatched Gemini calls fail, characterization tests (job `failed`/`finished` states, enqueue failure for generate/regenerate, sync-vs-async analysis parity, tasks lazy-import smoke), Telegram webhook negatives (bot enabled, non-ASCII, handler-not-called spies), forbidden-exercise tests with `EXERCISE_CATALOG_ENFORCE=0` using real catalog names (plus focus-area override check), quota with shared storage, behavioural CSRF-exempt test.
**Addresses:** safety-filter tests and job/webhook test gaps.
**Avoids:** Pitfalls 4, 8, 15, 16, 17.

### Phase 2: Module splits (behaviour-neutral)
**Rationale:** The files the AI work must edit are within 11-35 lines of the 600-line ceiling.
**Delivers:** `workout_form.py`, `plan_view.py`, `weekly_debrief.py` (and `stats_calc.py` optionally) with re-exports; import-linter contracts; new modules added to the standalone import test. One split per commit. Defer the `helpers.py`/`validation.py` splits to Phase 6 unless headroom is needed.
**Avoids:** Pitfalls 4, 14.

### Phase 3: AI error boundary, migration and dispatcher
**Rationale:** Everything user-visible depends on the failure taxonomy. Ship the migration first as its own commit.
**Delivers:** `ai_errors.py`, SDK-type classification (`APIError.code`), a corrected Gemini chain, lazy Redis cache with cooldown, `analysis_error`/`error_reason` columns, `ai_dispatch`, a guarded `enqueue` (503 `queue_unavailable`), `jobs.describe` with a closed code set, explicit TTLs, and additive `reason` in JSON. A tail `except Exception` stays in place and logs, so behaviour is unchanged this phase.
**Uses:** google-genai errors, RQ 2.x `Callback`/`on_failure`, Alembic autogenerate.
**Implements:** `ai_errors`, `ai_dispatch`, `jobs.describe`.
**Avoids:** Pitfalls 1, 3, 6, 10, 13.

### Phase 4: Workout analysis unification and retry UX
**Rationale:** Highest risk (the workout save flow), so it comes after the dispatcher and `analysis_error` have been in PROD for a deploy cycle.
**Delivers:** `workout_analysis.perform_analysis`, save-then-dispatch, retry endpoint (atomic CAS, quota, limiter, never mutates the plan), reason text and retry button (`data-*` plus `ui.js`, copy-check), labelled degraded fallback, `history_edit` clears `analysis_error`, migration of the 13 `workout_bp.analyze_and_advise` patches, parametrized `USE_JOB_QUEUE` 0/1 tests, double-run idempotency test.
**Addresses:** retry, specific messages, degraded fallback.
**Avoids:** Pitfalls 2, 5, 11.

### Phase 5: Narrow exceptions and enforce
**Rationale:** Safe only after `/ai_metrics` shows which SDK exception types occur as `internal`.
**Delivers:** Removal of the tail catch, narrowed excepts in `bp/plan.py`, `bp/workout.py`, `tasks.py`, `jobs.py`, `ops.py`, `helpers.log_event`, and a `BLE001` ratchet with per-file ignores that shrink.
**Avoids:** Pitfalls 2 and 13.

### Phase 6: Safety features and defence-in-depth
**Rationale:** Independent of the AI work; each item ships as a separate merge. The safety features are table stakes for Core Value.
**Delivers:** Always-on safety filter plus manual-constructor parity, health disclaimer, restriction snapshot and out-of-date banner, safety report (v1.x if time-boxed); `/ai_metrics` in-app loopback or admin check, webhook secret validation with bytes compare (degrade-safe), `User.is_admin` plus CLI (separate migration, with `ADMIN_EMAILS` kept as a transition), `SECRET_KEY_FALLBACKS`, startup warning on `memory://` quota storage, and the `helpers.py`/`validation.py` splits.
**Avoids:** Pitfall 9.

### Phase Ordering Rationale

- Tests pin behaviour before code moves, and splits create line headroom before AI code is added.
- Taxonomy comes before retry and unification, because retryability is a property of the failure class and two divergent paths double the bug surface.
- The riskiest change (analysis unification) lands after its dependencies have deployed. Narrowing comes last because it needs production evidence.
- Every phase must leave `main` green and deployable. Migrations are additive, and task signatures keep old call shapes for one deploy cycle.

### Research Flags

Needs `/gsd-plan-phase --research-phase`:
- **Phase 3:** typed exceptions vs out-of-band reason decision, RQ `JobTimeoutException` detection, `result_ttl` behaviour.
- **Phase 4:** the sync/async differences table and the product-visible decisions (retry does not mutate the plan, two-commit shape, `previous_plan` source) need sign-off against `docs/plan-eval.md`.
- **Phase 6:** manual-constructor enforcement (hard vs soft block), disclaimer wording, snapshot storage (column vs derived), and the `SECRET_KEY_FALLBACKS` plus `URLSafeTimedSerializer` key-list spike.

Standard patterns (skip research):
- **Phase 1:** fixtures, fakeredis, pytest-socket, Python 3.12 and lockfile.
- **Phase 2:** mechanical extract-with-re-export.
- **Phase 5:** mechanical once the Phase 3 metrics exist.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM-HIGH | Versions verified against PyPI and installed source; Gemini model lifecycle is volatile and undated; SQLite `BEGIN IMMEDIATE` guidance is LOW |
| Features | MEDIUM | Competitor claims are vendor-authored; no independent evidence on plateau accuracy or clinical and regulatory guidance; disclaimer wording needs counsel |
| Architecture | HIGH (current state) / MEDIUM (target) | Read from code at commit 2bcf4b2; PROD `USE_JOB_QUEUE=1` inferred, not read |
| Pitfalls | HIGH (repo-specific) / MEDIUM (generic RQ, Alembic, SQLite) | Generic behaviours not re-verified against current docs |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **Typed exceptions vs out-of-band reason (Stack vs Architecture):** decide in Phase 3 planning. Recommended: typed codes with the compatibility shim.
- **PROD facts that agents cannot read:** `USE_JOB_QUEUE` value, live webhook secret length, nginx `X-Forwarded-For` handling, Python version on the Amsterdam host. Ask the owner before the related phases.
- **Constructor safety enforcement:** research did not verify whether `bp/constructor` filters forbidden exercises. Check the code first, since it decides bug fix vs new feature.
- **Disclaimer wording and sign-off:** the owner decides; PAR-Q material is vendor and jurisdiction specific.
- **Plan JSON `response_schema`:** dynamic `week{N}`/`day{M}` keys are unverified; treat as a spike and keep `_extract_json` plus normalisation regardless.
- **RQ result TTL vs poller window:** pollers run up to 10 minutes; verify `jobs.enqueue` TTLs to avoid spurious 404s.
- **Gemini model IDs:** re-check live at pin time; 2.5 models shut down 2026-12-01.

## Sources

### Primary (HIGH confidence)
- Project code at commit 2bcf4b2 (`ai_generator.py`, `tasks.py`, `jobs.py`, `bp/*`, `ai_quota.py`, `config.py`, `deploy/deploy.sh`, `.gitlab-ci.yml`, tests) and the `.planning/codebase/*` docs
- PyPI metadata and installed `.venv` source (google-genai errors and `HttpOptions`, `flask/sessions.py`, `rq.exceptions`)

### Secondary (MEDIUM confidence)
- RQ docs and changelog (callbacks, TTLs, 2.x and 3.0 changes); Telegram Bot API `setWebhook`; Fitbod help center; Jefit comparison; Python 3.10 EOL coverage

### Tertiary (LOW confidence)
- Google Gemini deprecations page (undated, volatile; re-verify)
- Vendor and affiliate blogs on competitor features, AI plan risks, PAR-Q templates; LLM failure-UX practitioner guides; SQLite WAL blog guidance

---
*Research completed: 2026-11-03*
*Ready for roadmap: yes*
