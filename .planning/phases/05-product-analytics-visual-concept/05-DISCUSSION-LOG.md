# Phase 5: Product Analytics & Visual Concept - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md.

**Date:** 2026-11-14
**Phase:** 05-product-analytics-visual-concept
**Areas discussed:** Visual base, demo screen scope, competitor set, design-loop, delivery format

---

## Visual base

**Options:**
- A new palette built from scratch.
- **Use the current product interface as the base (chosen).**

**Choice:** The current Kachlog interface is the design base: shadcn/ui `base-nova`, stone palette,
Inter + Geist Mono, teal for progress. DESIGN.md documents this system and the rules for new screens.
No new brand palette.

**Rejected:** graphite + lime, warm paper + oxblood, cold navy + cyan — they would create a second
visual language next to the working product.

## Demo screen scope

**Options:**
- Recomposition of «Мой план / Сегодня» on the same tokens (chosen).
- A new «AI plan review» screen.
- Changes in the product codebase.

**Choice:** A standalone, self-contained recomposition of the existing plan screen, responsive,
with 5 states and light/dark. It proves fidelity to the current design and does not change the
product code or deploy anything.

**Rejected:** new product surface (scope creep), product-repo changes.

## Competitor set

**Options:**
- Broad market scan.
- **Six domain-relevant apps (chosen): Hevy, Fitbod, Alpha Progression, RP Hypertrophy, Strong, Boostcamp.**

**Choice:** Six apps that cover the core loop: logging (Hevy, Strong), AI plan (Fitbod, Alpha
Progression), autoregulation (RP), programs (Boostcamp). Copy patterns, not brands.

## Design-loop

**Options:**
- No formal critique.
- **Two rounds with brief/system/craft critics (chosen).**

**Choice:** Define measurable mechanisms, run three critic roles for two rounds, fix the gaps and
record the verdict. The result is in `docs/ux/design-loop.md`.

## Delivery format

**Options:**
- Only DESIGN.md.
- **DESIGN.md + research + UX patterns + demo screen + screenshots + GSD artifacts (chosen).**

**Choice:** The submission includes the design concept and the evidence behind it: competitor
research, PRD challenge, UX patterns, DESIGN.md, a responsive demo, screenshots and GSD discuss/plan
artifacts.

## Deferred

- Applying tokens to the real product UI.
- New product screens (AI plan review, weekly check-in).
- Visual regression e2e in CI.
- Firecrawl/Stitch automation.
