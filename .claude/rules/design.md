---
paths:
  - "web/**"
  - "design/**"
  - "templates/**"
  - "static/**"
  - "docs/ux/**"
  - "DESIGN.md"
---
# Design system (Kachlog)

- Read `DESIGN.md` before changing UI. It is the source of truth for the visual language.
- Use semantic tokens, Inter + Geist Mono, 10px radius, 5 states, AI UX, motion and don'ts from DESIGN.md.
- Screen patterns, transitions and states: `docs/ux/ux-patterns.md`.
- Scope: `/next` UI (Next.js + shadcn/ui) follows DESIGN.md. Legacy Flask templates
  (`templates/`, `static/style.css`) keep the current visual language until migrated; do not mix
  the two systems.
- No new palette, fonts, gradients or emoji. One accent per context.
- Before finishing a UI task, run the `design-check` skill.
