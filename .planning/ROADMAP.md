# Roadmap: Kachlog

## Overview

Kachlog is a deployed Flask app, so this milestone hardens it instead of adding product surface. The 36 v1 requirements fall into four delivery boundaries, ordered so that every later change lands on a safer base. Phase 1 pins the toolchain, builds the test net and creates line headroom in the near-limit modules, so refactors become detectable. Phase 2 fixes the AI failure boundary (the root cause: `_call_with_fallback` returns `None` for five different causes) and introduces a single dispatcher. Phase 3 builds the user-visible payoff on that boundary (one analysis implementation, specific reasons, retry) and then narrows the broad `except Exception` handlers once the reason codes make real failures visible. Phase 4 delivers the Core Value protections (always-on exercise safety, disclaimer) and the defence-in-depth items, each shipped as its own merge.

**Delivery rules for every phase** (a push to `main` deploys to PROD):
- `pytest` and `ruff check .` are green before every commit; one behaviour change per merge
- Migrations are additive and nullable, via Alembic autogenerate only
- New RQ task arguments are trailing keyword arguments with backward-compatible defaults
- Defence-in-depth checks degrade safely (warn and disable); they never crash the app on boot

**Granularity note:** config is `coarse`, so the six phases suggested by research are compressed to four. Research phases 1+2 form Phase 1, and research phases 4+5 form Phase 3. The intra-phase ordering from research is kept in each phase's planning notes.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Safety Net & Module Structure** - Pin Python/RQ, add characterization tests, and create headroom in near-limit modules
- [ ] **Phase 2: AI Error Boundary & Dispatch** - Classify every AI failure into a closed reason code behind one run-or-enqueue dispatcher
- [ ] **Phase 3: Workout Analysis, Retry & Exception Hardening** - One analysis implementation with specific reasons and user retry, then narrowed exceptions enforced by ruff
- [ ] **Phase 4: Safety Guarantees & Defence-in-Depth** - Always-on exercise safety on every plan path, health disclaimer, internal-endpoint and secret hardening

## Phase Details

### Phase 1: Safety Net & Module Structure
**Goal:** As a maintainer, I want to pin runtimes, build a hard test net and make modules roomy, so that every later refactor is caught before it deploys to PROD.
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: FND-01, FND-02, FND-03, FND-04, FND-05, FND-06, FND-07, FND-08, FND-09, SPL-01, SPL-02
**Success Criteria** (what must be TRUE):
  1. CI, DEV and PROD run the same Python version (3.12) and install from one lockfile, so a green CI run resolves the same dependencies PROD gets
  2. After the RQ 2.x upgrade (`>=2.12,<3`) and a worker restart, a queued AI job on the `ai` queue is picked up and completed end to end
  3. A test that reaches an unpatched Gemini call fails instead of calling the real API
  4. Breaking any pinned behaviour turns CI red: `/api/job/<id>` failed, finished-with-error and unknown states; the generate/regenerate enqueue-failure path; Telegram webhook rejection of wrong, empty and non-ASCII secrets and non-dict JSON (with `handle_update` provably not called); forbidden exercises persisted with `EXERCISE_CATALOG_ENFORCE=0` (real catalog names, including focus-area requests); AI quota on shared storage; the CSRF-exempt route set being exactly the Telegram webhook; a broken `tasks.py` lazy import
  5. `bp/workout.py`, `bp/plan.py` and `bp/stats.py` each sit at least 100 lines under the 600-line ceiling, with endpoint names, URLs and test patch targets unchanged and every new module covered by the standalone-import test
**Plans**: TBD
**Planning notes**: Standard patterns, skip research. Confirm the Python version on the Amsterdam host before FND-01. Intended order: toolchain, then test net, then splits last (one split per commit, after tests make patches load-bearing).

### Phase 2: AI Error Boundary & Dispatch
**Goal:** As a lifter, I want to see each AI failure classified and reported in plain Russian, so that I know whether to retry, wait or give up.
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: AIE-01, AIE-02, AIE-03, AIE-04, AIE-05, AIE-06, AIE-07, AIE-08
**Success Criteria** (what must be TRUE):
  1. Every AI failure resolves to exactly one code from a closed set (quota, timeout, unavailable, invalid response, internal) with no provider text stored, and the Gemini fallback chain holds only distinct, currently supported models
  2. Starting the app or the worker while Redis is unreachable does not hang on `import ai_generator`
  3. With the queue down, generate and regenerate return a specific 503 instead of an unhandled 500, and the same request returns the same response shape whether `USE_JOB_QUEUE` is 0 or 1 (one dispatcher is the only reader of the flag)
  4. `/api/job/<id>` for a failed job returns a specific Russian message plus reason code per failure class, never a traceback, and a finished result stays fetchable for the client's full 10-minute polling window
  5. A failed workout analysis persists its reason code in a nullable column added by an additive Alembic autogenerate migration that deploys cleanly against the previous app version
**Plans**: TBD
**Planning notes**: Run `--research-phase`. Decide typed `AIError` at the SDK boundary vs out-of-band reason (recommended: typed codes introduced through a compatibility shim so return contracts and about 30 test fakes stay unchanged); check RQ `JobTimeoutException` detection and `result_ttl`. Ship the migration as its own commit first. A tail `except Exception` stays in place this phase, so behaviour is unchanged.

### Phase 3: Workout Analysis, Retry & Exception Hardening
**Goal:** As a lifter, I want to see why a workout analysis failed and retry it, so that a saved workout is never left with a silently missing analysis.
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: ANL-01, ANL-02, ANL-03, ANL-04, ANL-05, ANL-06, EXC-01, EXC-02
**Success Criteria** (what must be TRUE):
  1. On the workout history page, a workout whose analysis failed shows the specific reason in plain Russian; when AI is unavailable the user sees a clearly labelled basic analysis instead of a silent substitute
  2. The user can retry a failed analysis with one action; retry is offered only for retryable reasons, consumes AI quota, cannot double-run on a double click, and never changes the plan
  3. Editing and resaving a workout clears its previous analysis error
  4. Analysis runs through a single implementation and behaves the same with `USE_JOB_QUEUE` set to 0 and 1, and running it twice for the same workout is idempotent
  5. Broad `except Exception` handlers in `bp/plan.py`, `bp/workout.py`, `tasks.py`, `jobs.py`, `bp/ops.py` and `helpers.py` are narrowed, a workout that is already saved still records its failure state when an unexpected error is injected, and adding a new broad catch fails `ruff` (`BLE` with a shrinking per-file ignore list)
**Plans**: TBD
**UI hint**: yes
**Planning notes**: Run `--research-phase`. Highest-risk change (the workout save flow). Needs the Phase 2 dispatcher and `analysis_error` column to have been in PROD for a deploy cycle. Produce the sync-vs-async differences table (history window, commit boundaries, `previous_plan` source, second `update_prs` call) and get sign-off against `docs/plan-eval.md`. Retry uses an atomic compare-and-set `failed -> pending`. Narrow exceptions last, using `/ai_metrics` evidence of which types occur as `internal`. UI text goes through `copy-check`; the retry control uses `data-*` plus `static/ui.js`.

### Phase 4: Safety Guarantees & Defence-in-Depth
**Goal:** As a lifter, I want to trust that forbidden exercises never reach my plan and internal endpoints stay locked, so that my training and my data stay safe.
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: SAF-01, SAF-02, SAF-03, SEC-01, SEC-02, SEC-03, SEC-04, SEC-05, SPL-03
**Success Criteria** (what must be TRUE):
  1. With `EXERCISE_CATALOG_ENFORCE` off, an AI-generated plan still contains no exercise forbidden by the user's limitations, age or health conditions, and the manual constructor surfaces a forbidden exercise as prominently as the AI path does (block vs warning decided in phase planning)
  2. A new user must acknowledge the health disclaimer in onboarding before continuing
  3. `/ai_metrics` also rejects non-local callers inside the app while `/healthz` keeps working, and a weak or non-ASCII `TELEGRAM_WEBHOOK_SECRET` or header is handled safely (bytes compare; a startup warning and a disabled webhook instead of a crash)
  4. Admin access works through a `User.is_admin` column granted by CLI (with `ADMIN_EMAILS` kept as a transition), startup warns when quota storage is `memory://` with more than one worker, and rotating `SECRET_KEY` does not invalidate existing share links
  5. `helpers.py` and `validation.py` are split by concern with one-way imports and unchanged public names
**Plans**: TBD
**UI hint**: yes
**Planning notes**: Run `--research-phase`. Owner decisions needed: constructor enforcement (hard block vs warning; check first whether `bp/constructor` already filters, which decides bug fix vs new feature), disclaimer wording, and the live webhook secret length plus nginx `X-Forwarded-For` handling on PROD. Spike `SECRET_KEY_FALLBACKS` with `URLSafeTimedSerializer` for share tokens. Do SPL-03 first so later items in this phase have headroom; ship each remaining item as its own merge; `User.is_admin` migration is separate and additive.

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Safety Net & Module Structure | 0/TBD | Not started | - |
| 2. AI Error Boundary & Dispatch | 0/TBD | Not started | - |
| 3. Workout Analysis, Retry & Exception Hardening | 0/TBD | Not started | - |
| 4. Safety Guarantees & Defence-in-Depth | 0/TBD | Not started | - |
