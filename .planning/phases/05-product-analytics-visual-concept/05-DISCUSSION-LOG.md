# Phase 5: Product Analytics & Visual Concept - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md.

**Date:** 2026-11-14
**Phase:** 05-product-analytics-visual-concept
**Areas discussed:** Visual base, demo screen scope, competitor set, Claude Code gate, delivery target

---

## Visual base

**Options:**
- A new palette (graphite + signal lime) built from scratch.
- **Use the existing `/next/plan` shadcn design as the base (chosen).**

**Choice:** The current `/next/plan` implementation is the design system. DESIGN.md documents it
as-built; no new brand palette. The user explicitly said: «за основу бери этот дизайн» and
«хочу чтобы и далее дизайн был +- таким как мы брали его с ui.shadcn.com».

**Rejected:** graphite + lime, warm paper + oxblood, cold navy + cyan. They would create a second
visual language next to the working product.

## Demo screen scope

**Options:**
- Recomposition of «Мой план / Сегодня» on the same tokens (chosen).
- A new «AI plan review» screen.
- A Next.js route in the product repo.

**Choice:** A standalone, self-contained recomposition of the existing plan screen, responsive,
with 5 states and light/dark. It proves fidelity to the current design and does not change the
product code or deploy anything.

**Rejected:** new product surface (scope creep), product-repo changes (push to `main` deploys to
PROD).

## Competitor set

**Options:**
- Broad market scan.
- **Six domain-relevant apps (chosen): Hevy, Fitbod, Alpha Progression, RP Hypertrophy, Strong, Boostcamp.**

**Choice:** Six apps that cover the core loop: logging (Hevy, Strong), AI plan (Fitbod, Alpha
Progression), autoregulation (RP), programs (Boostcamp). Copy patterns, not brands.

## Claude Code collaboration

**Options:**
- Skip external review.
- **Two gates (chosen): review the plan before implementation; validate the implementation before push.**

**Choice:** Plan is sent to Claude Code on DEV (`claude -p --permission-mode plan`). Its feedback
is merged into the artifacts. After implementation, Claude Code validates DESIGN.md, UX patterns,
screen and screenshots. A red verdict blocks the GitHub push until fixed.

**Rejected:** advisory-only review (user chose a blocking gate).

## Delivery target

**Options:**
- Product GitLab repo.
- **GitHub `NorthernSkyProjects/ai_trainer-agent-setup` (chosen), like module 2.**

**Choice:** GitHub homework repo, one commit to `main` after a green Claude Code verdict.

## Deferred

- Applying tokens to the real Next.js/Flask UI.
- New product screens (AI plan review, weekly check-in).
- Visual regression e2e in CI.
- Firecrawl/Stitch automation (no API keys in this environment).
