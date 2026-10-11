---
paths:
  - "templates/**"
  - "static/**"
---
# Templates & frontend conventions (IronMind)

- Templates extend `templates/base.html` (blocks `title`, `body_class`, `body`, `scripts`).
- No inline `<style>` and no inline JS handlers (`onclick`). Use `data-*` attributes plus
  delegated listeners in `static/ui.js`.
- CSRF is global; JS must send the token via the helper in `static/ui.js`.
- Styling uses CSS variables in `static/style.css`; dark theme via `[data-theme="dark"]`,
  stored in `User.theme`. Chart.js is vendored (`static/vendor/`), no CDN.
- `templates/base.html` picks the active nav item by `request.endpoint` — update that list
  whenever an endpoint is renamed or moved.
- `/api/*` errors return JSON; HTML errors render `templates/error.html`.
