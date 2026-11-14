# Phase 5: Product Analytics & Visual Concept - Context

**Gathered:** 2026-11-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce the module 3 deliverables for Kachlog: competitor research, a PRD challenge, UX patterns
(screens, transitions, states, AI UX), a `DESIGN.md` that documents the existing `/next/plan`
shadcn design as-built, and a responsive demo screen built on those tokens with desktop/mobile
screenshots. Run GSD `discuss-phase` and `plan-phase` artifacts. Review the plan with Claude Code,
implement, validate with Claude Code, and only then push to GitHub. No product code, migrations or
PROD changes.

</domain>

<decisions>
## Implementation Decisions

All decisions were confirmed in the module 3 discussion.

### Visual base
- **D-01:** The source of truth is the existing `/next/plan` implementation: shadcn `base-nova`,
  stone palette, Inter + Geist Mono, teal chart accent, 10px radius. Do not introduce a new brand
  palette. — **Reversibility:** reversible — docs only.
- **D-02:** `DESIGN.md` is an as-built document plus a small set of guardrails (AI UX, motion,
  don'ts, shadcn rules). It must match the live CSS tokens, not invent new ones.
- **D-03:** Teal is a progress/PR/success accent, not a general text color. On white, do not use
  `chart-2` for text below 4.5:1.

### Demo screen
- **D-04:** Build a standalone `design/screens/plan.html` recomposition of «Мой план / Сегодня»
  on the same tokens. No Next.js route, no Flask template, no product deploy.
- **D-05:** Required states: ready, empty, loading, error, AI form, AI pending. Light and dark.
  Desktop 1440×900 and mobile 390×844.
- **D-06:** Fonts are vendored locally (Inter + Geist Mono WOFF2, OFL); no CDN. Icons are inline
  Lucide-compatible SVG.
- **D-07:** Screenshots are captured with the local Chromium and stored in `screenshots/module3/`.

### Research
- **D-08:** Competitor set: Hevy, Fitbod, Alpha Progression, RP Hypertrophy, Strong, Boostcamp.
  Copy patterns, not brands. Fitbod site returns 403 → use help center/App Store/independent review.
- **D-09:** PRD challenge: 10 questions with decisions or `[нужно решение владельца]`; separate
  assumptions from facts.
- **D-10:** UX patterns must map to real routes in `web/src/app/*` and real components in
  `web/src/design/**`.

### Claude Code gates
- **D-11:** Gate 1 (before implementation): Claude Code reviews the plan/artifacts and returns
  risks, missing states, fidelity issues and a go/no-go. Merge feedback.
- **D-12:** Gate 2 (before push): Claude Code validates the implementation against DESIGN.md,
  the live tokens, the UX checklist and the screenshots. A red verdict blocks the GitHub push.
  `scripts/check_module3.py` is the executable gate: it fails without a GO verdict.
- **D-13:** Claude Code runs on DEV via `ssh newvps` / `claude -p --permission-mode plan`; the
  homework repo is synced to DEV for the review. Do not touch `/root/ai_trainer` uncommitted work.

### Delivery
- **D-14:** Push to GitHub `NorthernSkyProjects/ai_trainer-agent-setup`, `main`, one meaningful
  commit after a green validation. No secrets, no course PDF, no competitor assets.

### Claude's Discretion
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
- `web/src/app/globals.css` — tokens (read-only reference in the product repo).
- `web/src/design/**` — components and patterns.
- `DESIGN.md` — the as-built design system produced by this phase.
- `docs/ux/design-loop/bar.md`, `docs/ux/design-loop.md` — mechanisms and verdict.

### Process
- `.planning/PROJECT.md`, `.planning/ROADMAP.md`, `.planning/STATE.md` — GSD state.
- `AGENTS.md`, `CLAUDE.md` — project rules.
- `docs/module3.md` — module description and verification.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `web/src/design/sections/plan-and-today/components/` — TodayCard, WeekStrip, PlanAccordion,
  PlanNotices, RegenerateDialog.
- `web/src/design/shell/components/` — AppShell, AppSidebar, MobileTabBar.
- `web/src/design/sections/workout-and-results/components/WorkoutResult.tsx` — 5 analysis states.
- `web/src/design/sections/plan-and-today/components/CycleSummary.tsx` — big numbers, gains.
- `web/src/components/ui/*` — shadcn primitives.

### Established Patterns
- Semantic tokens only; no raw hex in components.
- `font-heading` + `font-sans` + `font-mono tabular-nums`.
- Dense desktop controls, 44px mobile targets.
- Sheet on mobile, dialog on desktop.
- Toast + persistent result, not toast alone.

### Integration Points
- The demo screen copies the tokens, not the React components; it must stay a static artifact.
- Screenshots are the proof for the module; they are stored in the repo.
- Claude Code reads the repo on DEV; sync before review.

</code_context>

<specifics>
## Specific Ideas

- The demo screen is a **recomposition**, not a redesign. If it looks like a different product,
  it is wrong.
- The design-loop should record real fixes (spacing, mobile title, load list wrapping, sheet state),
  not invented praise.
- Claude Code reviews should be attached as markdown, with a clear verdict and blocking issues.

</specifics>

<deferred>
## Deferred Ideas

- Applying the tokens to the real Next.js/Flask UI.
- New product screens (AI plan review, weekly check-in).
- Visual regression e2e in CI.
- Firecrawl/Stitch automation (no keys in this environment).
- Social feed, leaderboards, wearables.

</deferred>

---

*Phase: 05-Product Analytics & Visual Concept*
*Context gathered: 2026-11-14*
