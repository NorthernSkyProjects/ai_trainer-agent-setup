# Feature Research

**Domain:** AI-assisted gym workout tracking and planning (strength/hypertrophy, consumer web/PWA, RU-language)
**Researched:** 2026-11-03
**Confidence:** MEDIUM (competitor feature facts come largely from vendor-authored comparisons, Jefit/SensAI/Fitbod blogs, and help-center pages; there is no independent testing or clinical evidence. The AI-failure UX findings rest on practitioner guidance, not empirical studies. Treat the "what competitors do" claims as directional, and the recommendations as judgement anchored in Kachlog's Core Value.)

**Scope note (brownfield):** Kachlog already ships auth, onboarding, AI + manual plan creation, logging, history, PRs, stats, reports/sharing, Telegram, catalog (~876 exercises), PWA, post-normalised safety filtering. This file covers only what the NEXT iteration should add or harden, in three themes: (1) AI reliability UX, (2) plan safety around health/limitations, (3) analysis and progress tracking. "Existing" items are listed only where they set a dependency or a baseline.

## Landscape Snapshot (what comparable products do)

| Product | Positioning | Relevant behaviours (source-reported) |
|---------|-------------|----------------------------------------|
| Strong | Minimal logger | No generated programs; fast logging, PRs / estimated 1RM free, plate and warm-up calculators (paid), CSV export free |
| Hevy | Social logger, cheap | Rich logging, feed/leaderboards, progressive overload via visualisation, algorithmic "Hevy Trainer" (paid), CSV export and import of Strong CSV, all-time graphs (paid) |
| JEFIT | Feature-dense | Adaptive 12-week plan (paid), progress score, movement balance, recovery chart, "override any suggestion" |
| Fitbod | Algorithmic session generator | Per-session generation from recovery and history, per-exercise recommend more / less / exclude, injury questionnaire that suggests exclusions and requires "Update Plan", auto-reduced weights after a layoff, plateau flags from 1RM trend. Help center states suggestions are not medical advice, and that Focus Exercises are NOT overridden by injury settings (a known safety gap to avoid copying) |
| Gravl / Freeletics / similar | AI-planned programs | Exclude exercises and muscle groups; Freeletics forum threads show repeated user complaints that body-area exclusions did not work reliably (reliability of the safety control is the user-visible failure) |

Key observation: none of the mainstream four use LLM coaching for core progression; they are algorithmic (progression rules over logged data). LLM generation is a feature of newer entrants and of Kachlog. That makes deterministic safety and deterministic progression rules a strength to double down on, with the LLM used for plan composition and narrative only.

## Feature Landscape

### Table Stakes (Users Expect These)

Missing these makes an AI plan product feel untrustworthy. Items marked EXISTING are baseline; the rest are the gaps this iteration should close.

#### Theme 1: AI reliability UX

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Specific, plain-language failure reason per AI failure class (quota exhausted, provider timeout/unavailable, invalid/unusable model response, validation rejected) | Practitioner guidance across sources: no jargon, say what happened, say what to do next; a generic "Не удалось выполнить задачу" is a dead end | MEDIUM | Needs a small typed failure taxonomy at the AI boundary (ties to "narrow `except Exception`"). Store reason code on `Workout.analysis_status` side (e.g. `analysis_error`) and in job result. Map code -> Russian copy in one place (copy-check skill) |
| One-tap Retry on every failed AI result (analysis, plan generation, regeneration, day edit) | Failed call with no retry action is rated high severity in UX review checklists; today the only workaround is edit + resave | MEDIUM | Retry endpoint should re-enqueue with same inputs; idempotent; respects quota; disabled with explanation when the failure is quota (show reset time instead of retry) |
| Job-status polling that returns the real reason and a terminal state | `/api/job/<id>` currently collapses all failures; users see an endless spinner or a generic error | MEDIUM | Same response shape for inline and queued mode (CONCERNS: single `run_or_enqueue`). Include `state`, `reason_code`, `retryable`, `retry_after` |
| Never lose user input on failure | Forms losing entered data on a failed submit is a classic high-severity UX defect | LOW | Workout results are saved first, analysis is a secondary async step (verify this invariant holds; analysis failure must never block or roll back saving a workout) |
| Honest degraded mode: when AI fails, show the non-AI fallback clearly labelled | Tiered fallback ladder (bigger model -> smaller model -> cache -> non-AI path -> unavailable) is the consistent practitioner pattern; the labelling is what keeps trust | LOW | Kachlog already has fallback analysis and model fallback chain. Add a visible "Базовый анализ (ИИ недоступен) [Повторить]" label instead of silently showing the fallback as if it were AI output |
| Visible quota state (calls left today, reset time) | Users hit daily caps without warning; quota failure is the only failure that is not retryable now | LOW | `ai_quota` already counts; expose remaining count in the UI where AI actions live |
| Automatic transient retry before surfacing an error (invisible recovery) | "Best error handling is invisible" (automatic retry/backoff for transient errors only), then clear options | LOW-MEDIUM | Model fallback exists; add bounded retry with backoff+jitter for transient classes only; never retry quota or validation failures; cap total latency |

#### Theme 2: Plan safety around health and limitations

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Deterministic post-filter of forbidden exercises (limitations, age, health conditions) regardless of model output | Reviews of AI fitness advice: ~90% accurate but only ~40% complete, near-identical plans for different people, and anecdotal injuries; the model cannot be the safety layer | LOW (EXISTING) | Baseline exists in `ai_safety`/`ai_normalize`. Gap: untested when `EXERCISE_CATALOG_ENFORCE=0`. Make the filter independent of that flag (always on) and test it |
| Same safety guarantee on the manual constructor path | Core Value says plans must never contain forbidden exercises, "AI or manual"; users assume the app protects them equally | MEDIUM | Verify whether `bp/constructor` enforces forbidden lists. If not: warn-on-add (soft block with override and explicit acknowledgement) rather than silent allow. Needs decision on hard vs soft block |
| Medical-advice disclaimer + health-screening acknowledgement at onboarding | Fitbod explicitly states suggestions are not medical advice; PAR-Q-style screening routes "yes" answers to "consult a physician" (vendor templates; jurisdiction-specific, needs counsel review) | LOW | Short, non-blocking-but-recorded acknowledgement stored with timestamp; if serious health conditions selected, show a "проконсультируйтесь с врачом" notice. Do not gate on it beyond acknowledgement |
| Safety re-check when profile changes | A plan generated before a user added an injury is now unsafe; Fitbod requires an explicit "Update Plan" after injury edits | MEDIUM | On profile save compare limitation/health/age-bracket set to the plan's generation snapshot; if new restrictions apply, flag the current plan as "needs review" and offer filter-in-place or regenerate. Needs a snapshot of the profile restrictions stored with `WorkoutPlan` |
| User can exclude or swap an exercise in a plan day | Every competitor (Fitbod, Gravl, Freeletics, JEFIT "override") provides exclude/swap | LOW-MEDIUM | Day edit exists; add "swap for safe alternative" backed by catalog + safety filter (alternatives must pass the same filter) |
| Safety controls must actually work, and be testable | Freeletics forum shows exclusion controls failing is a top complaint; Fitbod's Focus-Exercise-overrides-injury behaviour is a documented gap | MEDIUM | Property-style tests: for each limitation/health/age combo, no generated plan contains a forbidden exercise, including user-added favourites/focus areas (focus areas must NOT override limitations; `ensure_focus_exercises` must be checked for this exact bug) |

#### Theme 3: Workout analysis and progress tracking

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Logging: sets/reps/weight, history edit, PRs, estimated 1RM | Baseline for Strong/Hevy/JEFIT | LOW (EXISTING) | No work needed beyond verification of rest timer and plate/warm-up helpers (not confirmed in competitor sources; do not build unless missing and requested) |
| Per-exercise progression charts (est. 1RM, top set, volume over time) | Standard in every tracker; Hevy/Strong paywall some, which sets expectation of existence | LOW (EXISTING) | Verify in `bp/stats.py`; extend rather than rebuild |
| Weekly volume per muscle group | Hevy "sets per muscle", JEFIT volume/sets per muscle (free) | LOW-MEDIUM | Derivable from catalog muscle metadata + logged results; no AI needed |
| Data export (CSV) | Strong (free), JEFIT, Hevy all export; also a privacy/trust expectation since health data is stored | LOW | Single `/export.csv` from history; no new dependencies |
| AI workout analysis that is retryable and shows its basis | Existing analysis must not be a black box once failures are surfaced | MEDIUM | Depends on Theme 1 (failure/retry) and on the shared analysis helper (CONCERNS: unify sync/async paths) |
| Progression suggestion for next session (weight/reps) | Fitbod, JEFIT Progressive Overload System, Hevy Trainer | MEDIUM (partly EXISTING via `plan_insights` load adaptation) | Make suggestions deterministic (rule-based on logged RPE/reps-in-range) so they work with the AI off |

### Differentiators (Competitive Advantage)

Aligned with Core Value: safe, personalised, reliable. Do not differentiate on everything; pick safety transparency and reliability honesty, which mainstream trackers do poorly.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| "Safety report" on each generated plan: what was removed/replaced and why (e.g. "Убрали приседания со штангой: ограничение — колени") | Turns an invisible filter into visible trust; no mainstream competitor shows why. Directly supports Core Value | MEDIUM | `_normalize_plan` already filters; record removals as structured events (exercise, rule, reason) in plan metadata, render in `/my_plan`. Depends on deterministic filter being always-on |
| Plan restriction snapshot + "plan out of date" banner | Fitbod needs manual Update Plan; automatic detection is better | MEDIUM | Same as table-stakes re-check; listed here as the UX shell that makes it a feature |
| Deterministic plateau / stagnation detection with plain-language advice | Fitbod flags plateaus from 1RM/recovery trends; Hevy outsources to third parties. Works without the LLM, cheap | MEDIUM | Rule on estimated-1RM slope over N sessions per lift, plus "volume flat" check. Output feeds the weekly debrief and analysis prompt as context rather than being LLM-invented |
| Return-from-break load reduction | Fitbod auto-reduces weights after inactivity to lower injury risk | LOW-MEDIUM | Extend `plan_insights` load adaptation with days-since-last-session rule; surface with explanation |
| Explainable suggestions ("почему этот вес") | Builds trust vs opaque AI; LLM sources note plans are near-identical across users without explanation | LOW-MEDIUM | Reuse trainer memory + history context; show the rule that fired (e.g. "3 подхода по 8 с запасом 2 повтора") |
| Per-exercise feedback (more / less / never) persisted into future generations | Fitbod offers recommend more / less / exclude; improves personalisation without chat | MEDIUM | New small preference table; must pass through the safety filter (preferences never override limitations) |
| Admin AI failure view (job, reason code, model fallback count) | CONCERNS lists "no admin-facing failure view"; enables triage without SSH | MEDIUM | Reuse reason codes from Theme 1 and `ai_metrics`; gate behind a real admin role (also a listed hardening item) |
| Russian-native copy and catalog | Most competitors are English-first; RU descriptions and curated catalog already exist | LOW (EXISTING) | Keep copy-check discipline on all new failure/safety strings |
| Weekly debrief via Telegram including AI-failure recovery ("анализ не получился, повторите") | Telegram channel already exists; closes the loop when the user is away from the app | LOW-MEDIUM | Depends on reason codes; do not send alerts for transient failures that auto-recovered |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Relying on the prompt to enforce safety ("do not include X") | Cheap and feels sufficient | Model output is incomplete and non-deterministic; reviews show omission and near-identical plans; injuries are anecdotally linked to AI plans | Deterministic post-filter, always on, tested; prompt is advisory only |
| Letting Focus Areas / favourites / user preferences override limitations | "I asked for squats" | Fitbod's documented gap; undermines Core Value | Limitations always win; show a notice "исключено из-за ограничения" |
| Medical or rehabilitation advice, diagnoses, rehab programs | Users with injuries ask for it | Liability and clinical scope; no evidence base found; PAR-Q-style practice defers to a physician | Disclaimer, exclusions, "consult a doctor" notice; no condition-specific rehab |
| Silent automatic retry loops or silently swapping in a fallback plan as if AI-made | "Fewer error messages" | Hides failures, burns quota, erodes trust, and makes the quality of generated plans unknowable | Bounded transient retry, then surface a labelled degraded result with Retry |
| Exposing raw model/provider error text or stack traces | Easier debugging | Leaks internals and prompts; jargon-heavy; may include health data | Reason code to Russian message mapping; raw detail only in logs/admin view |
| Free-form AI chat coach | Looks modern; "ask the AI anything" | Unbounded safety surface, cost, no post-filter on free text; mainstream trackers do not do it | Structured, validated generation and bounded analysis outputs |
| Social feed, leaderboards, following | Hevy and JEFIT have them | Large scope, moderation and privacy load, off Core Value; share links + Telegram report already cover sharing | Keep `/share/<token>` and Telegram reports |
| Wearable and health-platform integrations (Apple Health, Health Connect, Strava) | Every competitor lists them | Native-app territory; web/PWA cannot reach them cleanly; high cost, low link to Core Value | Defer; CSV export covers data portability |
| Camera form-check / computer vision | Marketed as "AI trainer" | High cost, accuracy and liability risk, heavy infra | Exercise photos/descriptions already exist |
| Nutrition and calorie tracking | Common in "fitness" apps | Different product, regulatory and data scope | Out of scope |
| Paywall / subscription tiers | Revenue | Not in project scope; adds billing surface | None now |
| Multi-provider LLM abstraction | Resilience | Stack rewrite pressure; Gemini + model-fallback already exists | Harden failure handling and use the existing fallback chain |
| Auto-regenerating the plan on every profile edit | "Always fresh" | Burns quota, destroys user edits to the plan | Flag as "needs review" and let user choose filter-in-place or regenerate |

## Feature Dependencies

```
Failure taxonomy (typed AI errors, reason codes)
    └──requires──> Narrow `except Exception` at AI boundary
    └──enables──> Specific failure messages
                      └──enables──> Retry action (analysis, job, plan)
                      └──enables──> Honest degraded-mode label
                      └──enables──> Admin AI failure view
                      └──enables──> Telegram debrief recovery message

Single `run_or_enqueue` / shared analysis helper (sync = async)
    └──requires──> Failure taxonomy
    └──enables──> Consistent job-status contract
    └──enables──> Test coverage of job failure paths

Deterministic safety filter always on (not tied to CATALOG_ENFORCE)
    └──requires──> Tests for forbidden-exercise filtering with enforcement off
    └──enables──> Safety report (removal events)
    └──enables──> Safe exercise swap
    └──enables──> Per-exercise feedback (preferences can never override)

Plan restriction snapshot (stored at generation)
    └──requires──> Safety filter
    └──enables──> "Plan out of date" banner on profile change

Manual-constructor safety parity ──requires──> Shared forbidden-list lookup in `ai_safety`

Deterministic progression rules ──enhances──> AI analysis (as context)
Plateau detection ──requires──> est. 1RM history (existing stats)
Return-from-break rule ──enhances──> Load adaptation (`plan_insights`)
Admin AI failure view ──requires──> Admin role (hardening item)

Module splits (`helpers`, `bp/workout`, `bp/plan`, `bp/stats`) ──precede──> any of the above that touches those files (600-line ceiling)

Per-exercise feedback ──conflicts──> Focus Areas override of limitations (limitations must always win)
Auto-retry loops ──conflicts──> Quota protection (never auto-retry quota/validation failures)
```

### Dependency Notes

- **Retry requires the taxonomy:** retryability is a property of the failure class (timeout yes, quota no, validation maybe). Building retry first forces a rewrite once reasons exist.
- **Shared analysis helper before retry:** retry on two divergent code paths doubles the bug surface (CONCERNS: sync/async duplication).
- **Safety filter independence is a prerequisite for any new safety UI:** the safety report and swap features are only meaningful if the filter cannot be disabled by `EXERCISE_CATALOG_ENFORCE=0`.
- **Restriction snapshot is a schema change:** goes through Alembic autogenerate only; do it early in the safety phase because the banner, report, and tests all read it.
- **Module size:** `helpers.py` (589), `validation.py` (576), `bp/stats.py` (570), `bp/workout.py` (566), `bp/plan.py` (561) are at the 600-line ceiling; splits must precede feature work in them.

## MVP Definition

### Launch With (this iteration, v1)

Minimum set that makes Core Value credible and fixes the known silent failures.

- [ ] Typed AI failure taxonomy + reason codes at the AI boundary (narrowed exceptions) — unblocks everything in Theme 1
- [ ] Specific Russian failure messages for analysis and job status — fixes two listed Known Bugs
- [ ] Retry action for failed analysis and failed plan jobs (retryable classes only) — removes the "edit and resave" workaround
- [ ] Shared analysis helper and single run-or-enqueue path — prevents divergent fixes
- [ ] Labelled degraded fallback analysis — honesty on failure
- [ ] Always-on deterministic safety filter with tests (catalog enforcement off, focus areas, favourites) — High-priority test gaps
- [ ] Safety parity check/warning for the manual constructor — Core Value covers both paths
- [ ] Onboarding health disclaimer acknowledgement + physician notice for serious conditions — low cost, high trust (wording reviewed by the owner/counsel)
- [ ] Job-failure and Telegram-webhook negative-case tests — listed High-priority gaps (supporting, not user-facing)

### Add After Validation (v1.x)

- [ ] Plan restriction snapshot + "plan out of date" banner — trigger: first user reports a plan not matching a newly added limitation, or after v1 safety tests pass
- [ ] Safety report on plans (what was removed and why) — trigger: removal events recorded reliably
- [ ] Swap-for-safe-alternative on a plan day — trigger: users editing days after generation
- [ ] CSV export — trigger: first data-portability request; low cost, can be earlier
- [ ] Visible quota remaining in UI — trigger: users hitting daily cap
- [ ] Deterministic plateau detection + return-from-break reduction — trigger: stats and `plan_insights` stable after module splits
- [ ] Admin AI failure view with a real admin role — trigger: need to triage without SSH

### Future Consideration (v2+)

- [ ] Per-exercise more/less/never feedback persisted into generation — needs preference model and safety interplay design
- [ ] Explainable-suggestion UI ("почему этот вес") — after rule-based progression is the primary source
- [ ] Weekly muscle-group volume dashboard refinements — after catalog metadata audit
- [ ] Telegram failure-recovery messages — after reason codes proven stable

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Typed failure taxonomy + narrowed exceptions | HIGH | MEDIUM | P1 |
| Specific failure messages (analysis, job) | HIGH | MEDIUM | P1 |
| Retry for failed analysis / jobs | HIGH | MEDIUM | P1 |
| Shared analysis + run-or-enqueue helper | MEDIUM (enabler) | MEDIUM | P1 |
| Labelled degraded fallback | MEDIUM | LOW | P1 |
| Always-on safety filter + tests | HIGH | LOW-MEDIUM | P1 |
| Constructor safety parity (warn-on-add) | HIGH | MEDIUM | P1 |
| Health disclaimer acknowledgement | MEDIUM | LOW | P1 |
| Plan restriction snapshot + out-of-date banner | HIGH | MEDIUM | P2 |
| Safety report (removed + why) | HIGH | MEDIUM | P2 |
| Swap for safe alternative | MEDIUM | LOW-MEDIUM | P2 |
| Visible quota remaining | MEDIUM | LOW | P2 |
| CSV export | MEDIUM | LOW | P2 |
| Deterministic plateau detection | MEDIUM | MEDIUM | P2 |
| Return-from-break reduction | MEDIUM | LOW-MEDIUM | P2 |
| Admin AI failure view | MEDIUM | MEDIUM | P2 |
| Transient auto-retry with backoff | MEDIUM | LOW-MEDIUM | P2 |
| Per-exercise feedback | MEDIUM | MEDIUM | P3 |
| Explainable suggestions UI | MEDIUM | LOW-MEDIUM | P3 |
| Telegram failure-recovery messages | LOW | LOW-MEDIUM | P3 |

**Priority key:**
- P1: Must have this iteration (fixes known bugs or protects Core Value)
- P2: Should have, add when P1 is stable
- P3: Nice to have, future

## Competitor Feature Analysis

| Feature | Fitbod | Hevy / Strong | JEFIT | Our Approach |
|---------|--------|---------------|-------|--------------|
| AI failure handling | Not documented (algorithmic, little LLM exposure) | N/A (no generation in Strong; Hevy Trainer is algorithmic) | Not documented | Typed reasons + retry + labelled fallback; main UX differentiator because Kachlog depends on a flaky external LLM |
| Injury / limitation handling | Questionnaire suggests exclusions; user applies via "Update Plan"; Focus Exercises override injury settings; "not medical advice" | Not stated | "Override any suggestion" | Always-on deterministic filter; limitations always win; safety report; restriction snapshot and out-of-date banner |
| Exercise swap / exclude | Recommend more / less / exclude | Manual editing | Override | Swap-for-safe-alternative restricted to filter-passing catalog entries |
| Progression suggestions | Algorithmic per-session, auto-lowered after layoff | Hevy: graphs, optional Trainer (paid); Strong: none | Progressive Overload System, progress score (Elite) | Deterministic rules, work when AI is off; AI adds narrative |
| Plateau detection | Flags from 1RM/recovery trends (vendor claim) | Not in core (third-party) | Progress score | Deterministic e1RM slope rule feeding debrief and analysis prompt |
| Analytics | Recovery %, heat map, Strength Score (paid) | Charts; some paywalled | Volume, sets per muscle (free), movement balance (paid) | Free; build on existing stats; add muscle-volume view |
| Data export | Not documented | CSV (Strong free, Hevy) | CSV | CSV export, free |
| Social | Off-app only | Hevy feed/leaderboards | Opt-in feed | Skip; share links + Telegram |
| Wearables | Many | Many | Many | Skip (PWA constraint) |
| Language | English-first | English-first | English-first | Russian-native |

## Open Questions (for requirements)

- Does `bp/constructor` currently enforce or warn on forbidden exercises? Determines whether "safety parity" is a bug fix or a new feature; also decide hard block vs warn-with-acknowledge. (Not verified in this research; check code.)
- Where is the health disclaimer wording sourced and who signs it off (owner/legal)? PAR-Q-style guidance found was from vendor templates, jurisdiction-specific.
- Does a rest timer / plate calculator exist already? Competitor sources did not substantiate their importance; do not build without user demand.
- Should the restriction snapshot live on `WorkoutPlan` (new JSON column, Alembic) or be derived on read? Affects the migration.

## Sources

- Jefit-published comparison, "Fitbod vs Strong vs Jefit vs Hevy" (https://www.jefit.com/blog/fitbod-vs-strong-vs-jefit-vs-hevy), pricing, feature matrix, exercise exclusion, export. MEDIUM (vendor-authored; competitor of the apps compared)
- Other 2026 roundups surfaced by search (Boostcamp, SensAI, jeera, steelrep): feature positioning, Hevy AI routine from natural-language prompt, Fitbod no free tier. LOW-MEDIUM (affiliate/vendor blogs; exercise-library size figures conflict across sources)
- Fitbod help center via search result (help.fitbod.me): injury/limitation questionnaire, exclusions, Update Plan, Focus Exercises not overridden by limitations, "not medical advice", auto-reduced weights after inactivity. MEDIUM (first-party, accessed via search snippet; direct fetch returned 403)
- Fitbod blog on recovery/plateau flagging (fitbod.me); athletedata.health Hevy AI coach integration; Jefit Progressive Overload pages: plateau/progression claims. LOW-MEDIUM (vendor claims, no independent accuracy testing)
- Freeletics forum threads on excluding body areas/exercises and Gravl help center (exclude exercises/muscle groups): user complaints about exclusion reliability. LOW-MEDIUM (community anecdotes)
- TechRadar, rollingout, pulse.bot, fitbudd and similar on AI plan risks: injuries anecdotal; AI advice ~90% accurate/~40% complete; near-identical plans across users. LOW (anecdotal/secondary; no clinical or regulatory evidence found)
- PAR-Q template vendors (exercise.com, coachway, others): screening and "consult a physician" practice. LOW (vendor templates; wording needs counsel review)
- Practitioner guides on LLM failure UX (dev.to error-recovery patterns, maxim retries/fallbacks/circuit breakers, ux-patterns-for-developers AI error states): fallback ladder, backoff with jitter for transient errors only, plain-language messages with a next action, avoid dead-end errors, data loss. LOW-MEDIUM (practitioner advice; no empirical user-trust studies found)
- Project context: `/root/ai_trainer-gsd/.planning/PROJECT.md`, `/root/ai_trainer-gsd/.planning/codebase/CONCERNS.md` (Known Bugs, Test Coverage Gaps, Missing Critical Features). HIGH (first-party)

Confidence tiers were assigned via `classify-confidence` (web search = LOW, cross-checked = MEDIUM); the largest evidence gaps are independent evaluations of plateau detection accuracy and any clinical or regulatory guidance on contraindications.

---
*Feature research for: AI-assisted gym workout tracking (Kachlog, brownfield next iteration)*
*Researched: 2026-11-03*
