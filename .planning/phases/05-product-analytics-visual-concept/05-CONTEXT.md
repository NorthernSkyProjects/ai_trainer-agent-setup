# Phase 5: Product Analytics & Visual Concept - Context

**Gathered:** 2026-11-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce the product analytics and visual concept package for Kachlog: competitor research, a PRD
challenge, UX patterns (screens, transitions, states, AI UX), a `DESIGN.md` with 10 sections, and a
responsive demo screen built on the same tokens with desktop/mobile screenshots. Run GSD
`discuss-phase` and `plan-phase` artifacts. No product code, migrations or deploy changes.

</domain>

<decisions>
## Implementation Decisions

### Visual base
- **D-01:** The source of truth for the visual language is the current Kachlog interface: shadcn
  `base-nova`, stone palette, Inter + Geist Mono, teal chart accent, 10px radius. Do not introduce
  a new brand palette. — **Reversibility:** reversible — docs only.
- **D-02:** `DESIGN.md` is a visual concept and design-system document with 10 sections plus
  guardrails (AI UX, motion, don'ts, shadcn rules). It must match the live tokens, not invent new ones.
- **D-03:** Teal is a progress/PR/success accent, not a general text color. On white, do not use
  `chart-2` or `chart-3` for text below 4.5:1; text accent is `chart-4`/`chart-5`.

### Demo screen
- **D-04:** Build a standalone `design/screens/plan.html` recomposition of «Мой план / Сегодня»
  on the same tokens. No product route, no product template, no deploy.
- **D-05:** Required states: ready, empty, loading, error, partial, AI form, AI pending, AI error.
  Light and dark. Desktop 1440×900 and mobile 390×844.
- **D-06:** Fonts are vendored locally (Inter + Geist Mono WOFF2, OFL); no CDN. Icons are inline
  SVG in the Lucide style.
- **D-07:** Screenshots are captured with local Chromium and stored in `screenshots/module3/`.

### Research
- **D-08:** Competitor set: Hevy, Fitbod, Alpha Progression, RP Hypertrophy, Strong, Boostcamp.
  Copy patterns, not brands. Fitbod site returns 403 → use help center/App Store/independent review.
- **D-09:** PRD challenge: 10 questions with decisions or `[нужно решение владельца]`; separate
  assumptions from facts.
- **D-10:** UX patterns must map to the real product screens and design patterns (TodayCard,
  WeekStrip, PlanAccordion, RegenerateDialog, WorkoutResult).

### Review
- **D-11:** Run a design-loop with measurable mechanisms and three critic roles (brief, system,
  craft) for two rounds. Record fixes and the final verdict in `docs/ux/design-loop.md`.

### Planner's Discretion
- Exact wording of the PRD challenge, competitor table columns, design-loop critique format,
  demo screen copy, and screenshot filenames.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Product
- `docs/ux/prd.md` — lean PRD and product context.
- `docs/ux/prd-challenge.md` — 10 questions, assumptions, decisions.
- `docs/ux/competitors.md` — competitor matrix and patterns.
- `docs/ux/ux-patterns.md` — screens, flows, transitions, states, AI UX.
- `README.md` — product overview and how to run.

### Design
- `https://iitrainer.duckdns.org/next/plan` — the live reference.
- `DESIGN.md` — the visual concept and design system produced by this phase.
- `docs/ux/design-loop/bar.md`, `docs/ux/design-loop.md` — mechanisms and verdict.
- `screenshots/module3/reference-*.png` — reference screenshots.

### Process
- `.planning/PROJECT.md`, `.planning/ROADMAP.md`, `.planning/STATE.md` — GSD state.
- Project rules and conventions.
- `docs/module3.md` — submission overview and verification.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `TodayCard` — today's workout, CTA, cycle progress, exercise list.
- `WeekStrip` — the current week at a glance, mobile scroll / desktop grid.
- `PlanAccordion` — weeks and days, statuses, weekday picker.
- `PlanNotices` — equipment/age drift, load proposal, install, recommendations.
- `RegenerateDialog` — AI quick wishes, trainer memory, pending/error.
- `WorkoutResult` — 5 analysis states (`pending/ready/stale/failed/skipped`).
- `CycleSummary` — big numbers, gains, weak spots.

### Established Patterns
- Semantic tokens only; no raw hex in components.
- `font-heading` + `font-sans` + `font-mono tabular-nums`.
- Dense desktop controls, 44px mobile targets.
- Sheet on mobile, dialog on desktop.
- Toast + persistent result, not toast alone.

### Integration Points
- The demo screen copies the tokens, not the React components; it must stay a static artifact.
- Screenshots are the proof for the module; they are stored in the repo.
- The product code is not changed.

</code_context>

<specifics>
## Specific Ideas

- The demo screen is a **recomposition**, not a redesign. If it looks like a different product,
  it is wrong.
- The design-loop should record real fixes (spacing, mobile title, load list wrapping, sheet state),
  not invented praise.

</specifics>

<deferred>
## Deferred Ideas

- Applying the tokens to the real product UI.
- New product screens (AI plan review, weekly check-in).
- Visual regression e2e in CI.
- Firecrawl/Stitch automation.
- Social feed, leaderboards, wearables.

</deferred>

---

*Phase: 05-Product Analytics & Visual Concept*
*Context gathered: 2026-11-14*
