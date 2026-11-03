# Requirements: Kachlog

**Defined:** 2026-11-03
**Core Value:** A user gets a safe, personalised workout plan (AI or manual) and can reliably log and review their training; plans never include exercises forbidden by limitations, age or health conditions.

## v1 Requirements

Hardening milestone on an existing, deployed app. Each requirement maps to one roadmap phase. Every change must keep `main` green (pytest + ruff) because pushes deploy to PROD.

### Foundation & Safety Net

- [ ] **FND-01**: Developer runs CI and the dev/prod hosts on one Python version (3.12) with a lockfile, so CI resolves the same dependencies as prod
- [ ] **FND-02**: RQ is upgraded to 2.x (`>=2.12,<3`) and the `ai` queue worker still processes jobs after restart
- [ ] **FND-03**: Any test that reaches an unpatched Gemini call fails instead of calling the real API
- [ ] **FND-04**: Tests cover `/api/job/<id>` for failed, finished-with-error and unknown job states
- [ ] **FND-05**: Tests cover the enqueue-failure path for generate and regenerate
- [ ] **FND-06**: Tests assert Telegram webhook rejects wrong, empty and non-ASCII secret headers and non-dict JSON, with `handle_update` provably not called
- [ ] **FND-07**: Tests assert no forbidden exercise reaches a persisted plan with `EXERCISE_CATALOG_ENFORCE=0`, using real catalog names, including when focus areas request it
- [ ] **FND-08**: Tests cover AI quota with shared (Redis-like) storage and a test asserts the CSRF-exempt route set is exactly the Telegram webhook
- [ ] **FND-09**: A smoke test imports everything `tasks.py` lazy-imports, so a broken worker import fails CI

### Module Structure

- [ ] **SPL-01**: `bp/workout.py`, `bp/plan.py` and `bp/stats.py` each have headroom (at least 100 lines) under the 600-line ceiling via behaviour-neutral extraction of non-route code
- [ ] **SPL-02**: Endpoint names, URLs and test patch targets are unchanged after each split, and new modules are covered by the standalone-import test

### AI Error Boundary & Dispatch

- [ ] **AIE-01**: The AI boundary classifies each failure into a closed set of reason codes (quota, timeout, unavailable, invalid response, internal) without storing provider text
- [ ] **AIE-02**: The Gemini fallback chain contains only distinct, currently supported models
- [ ] **AIE-03**: Importing `ai_generator` no longer blocks on Redis connectivity (lazy init with a cooldown)
- [ ] **AIE-04**: A failed workout analysis stores a reason code (nullable column added via Alembic autogenerate, additive only)
- [ ] **AIE-05**: One dispatcher is the only reader of `USE_JOB_QUEUE` and returns the same response shape inline and queued
- [ ] **AIE-06**: When the queue is down, generate/regenerate return a specific 503 instead of an unhandled 500
- [ ] **AIE-07**: `/api/job/<id>` returns a specific Russian message and reason code per failure class and never exposes tracebacks
- [ ] **AIE-08**: Job result lifetimes cover the client's 10-minute polling window

### Workout Analysis & Retry

- [ ] **ANL-01**: Workout analysis has a single implementation shared by the inline and queued paths
- [ ] **ANL-02**: A workout whose analysis failed shows the specific reason in plain Russian
- [ ] **ANL-03**: User can retry a failed analysis with one action; retry is allowed only for retryable reasons, consumes quota, and never changes the plan
- [ ] **ANL-04**: When AI is unavailable the user sees a clearly labelled basic analysis, not a silent substitute
- [ ] **ANL-05**: Editing and resaving a workout clears the previous analysis error
- [ ] **ANL-06**: Analysis behaviour is tested for both `USE_JOB_QUEUE` values and for double execution (idempotent)

### Exception Handling

- [ ] **EXC-01**: Broad `except Exception` in `bp/plan.py`, `bp/workout.py`, `tasks.py`, `jobs.py`, `bp/ops.py` and `helpers.py` is narrowed, keeping one outermost handler that records state for already-saved workouts
- [ ] **EXC-02**: Ruff `BLE` is enabled with a shrinking per-file ignore list so new broad catches fail CI

### Safety & Defence-in-Depth

- [ ] **SAF-01**: Limitation, age and health filtering of plan exercises always applies, independent of `EXERCISE_CATALOG_ENFORCE`
- [ ] **SAF-02**: The manual constructor surfaces forbidden exercises as prominently as the AI path (behaviour hard-block vs warning decided in phase planning)
- [ ] **SAF-03**: User acknowledges a health disclaimer in onboarding (wording supplied by the owner)
- [ ] **SEC-01**: `/ai_metrics` also checks the caller in-app, without affecting `/healthz`
- [ ] **SEC-02**: A weak or non-ASCII `TELEGRAM_WEBHOOK_SECRET` or header is handled safely (bytes compare; startup warns and disables the webhook instead of crashing)
- [ ] **SEC-03**: Admin access uses a `User.is_admin` column with a CLI to grant it, keeping `ADMIN_EMAILS` as a transition
- [ ] **SEC-04**: Startup warns when quota storage is `memory://` with more than one worker
- [ ] **SEC-05**: Rotating `SECRET_KEY` does not invalidate existing share links (via `SECRET_KEY_FALLBACKS` or equivalent, subject to a spike)
- [ ] **SPL-03**: `helpers.py` and `validation.py` are split by concern with one-way imports and unchanged public names

## v2 Requirements

Deferred. Tracked, not in the current roadmap.

### Plan Safety UX

- **PSF-01**: Plan stores a restriction snapshot and shows a "plan out of date" banner when the profile changes
- **PSF-02**: User can see a safety report of what was removed and why
- **PSF-03**: User can swap a flagged exercise for a safe alternative

### Progress & Analysis

- **PRG-01**: Deterministic plateau detection and return-from-break load reduction
- **PRG-02**: User can export history as CSV
- **PRG-03**: Visible remaining AI quota
- **PRG-04**: Admin view of AI failures

### Other

- **OTH-01**: Per-exercise more/less/never feedback
- **OTH-02**: Telegram messages for AI failure recovery
- **OTH-03**: Move Redis AI cache behind a password, and PostgreSQL if write contention appears

## Out of Scope

| Feature | Reason |
|---------|--------|
| Prompt-only safety, or preferences overriding limitations | Deterministic filtering is the Core Value |
| Free-form AI chat coach, rehab/medical advice | Liability and off-product |
| Social feed, leaderboards, wearables, nutrition tracking | Not part of hardening; large scope |
| Silent auto-retry or silent fallback | Hides failures and burns quota |
| `rq.Retry` on AI tasks | Re-consumes quota; user-initiated retry instead |
| RQ 3.x, Flask-Talisman, RBAC framework, `tenacity` over the model chain | Breaking or redundant for this scope |
| Rewriting the stack, hand-written migrations, extending `scripts/legacy/` | Project rules |

## Traceability

Each v1 requirement maps to exactly one phase.

| Requirement | Phase | Status |
|-------------|-------|--------|
| FND-01 | Phase 1 | Pending |
| FND-02 | Phase 1 | Pending |
| FND-03 | Phase 1 | Pending |
| FND-04 | Phase 1 | Pending |
| FND-05 | Phase 1 | Pending |
| FND-06 | Phase 1 | Pending |
| FND-07 | Phase 1 | Pending |
| FND-08 | Phase 1 | Pending |
| FND-09 | Phase 1 | Pending |
| SPL-01 | Phase 1 | Pending |
| SPL-02 | Phase 1 | Pending |
| AIE-01 | Phase 2 | Pending |
| AIE-02 | Phase 2 | Pending |
| AIE-03 | Phase 2 | Pending |
| AIE-04 | Phase 2 | Pending |
| AIE-05 | Phase 2 | Pending |
| AIE-06 | Phase 2 | Pending |
| AIE-07 | Phase 2 | Pending |
| AIE-08 | Phase 2 | Pending |
| ANL-01 | Phase 3 | Pending |
| ANL-02 | Phase 3 | Pending |
| ANL-03 | Phase 3 | Pending |
| ANL-04 | Phase 3 | Pending |
| ANL-05 | Phase 3 | Pending |
| ANL-06 | Phase 3 | Pending |
| EXC-01 | Phase 3 | Pending |
| EXC-02 | Phase 3 | Pending |
| SAF-01 | Phase 4 | Pending |
| SAF-02 | Phase 4 | Pending |
| SAF-03 | Phase 4 | Pending |
| SEC-01 | Phase 4 | Pending |
| SEC-02 | Phase 4 | Pending |
| SEC-03 | Phase 4 | Pending |
| SEC-04 | Phase 4 | Pending |
| SEC-05 | Phase 4 | Pending |
| SPL-03 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 36 total
- Mapped to phases: 36
- Unmapped: 0 ✓

---
*Requirements defined: 2026-11-03*
*Last updated: 2026-11-03 after roadmap creation*
