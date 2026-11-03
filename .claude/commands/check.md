---
description: Run ruff and pytest before commit or push
---
Run `ruff check .` and `pytest -q` in the project root. Report failures with file:line.
If anything is red, do not commit or push.
