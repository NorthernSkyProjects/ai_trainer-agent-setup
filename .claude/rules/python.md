---
paths:
  - "**/*.py"
---
# Python conventions (IronMind)

- Python 3.10. Lint is ruff (`ruff.toml`: select `E4,E7,E9,F`, ignore `E501`, line-length 120).
  Do NOT run `ruff format` — the codebase is not formatted with it; auto-formatting creates noisy diffs.
- Tests live in `tests/`, run with pytest (`pytest.ini`: testpaths=tests). `tests/conftest.py`
  sets an isolated temp SQLite DB and env **before** importing `app` — never reorder that.
  Use the `app` fixture (drops/creates tables per test, CSRF off).
- AI calls are stubbed by patching the name in the module that uses it
  (`bp.plan.generate_full_plan`, `bp.workout.analyze_and_advise`) — not the definition site.
- On the dev stand use the venv explicitly: `.venv/bin/python -m pytest -q` and `.venv/bin/ruff check .`.
- Blueprints import from `extensions`/`models`/`forms`/`helpers`/`validation`/`ai_generator`/`report`
  — never from `app` (circular import). Task functions in `tasks.py` import `app`/`bp.plan` lazily.
- New profile options/limits: edit `validation.py` first (ranges mirror onboarding sliders).
- Migrations are Alembic only (`flask --app app db migrate`); never hand-write a migration.
