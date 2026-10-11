---
name: new-route
description: >-
  Добавить новый маршрут/страницу по конвенциям IronMind (blueprint в bp/, шаблон, навигация, тест).
  Использовать при добавлении эндпоинта или страницы. НЕ использовать для правок схемы БД
  (это new-migration), текста интерфейса (copy-check) или проверки перед пушем (ship-check).
---
# new-route: добавить маршрут

1. Выбрать блюпринт в `bp/`: `auth, ops, profile, stats, onboarding, constructor, plan,
   workout, main, history`. Общий код — `helpers.py`, расширения — `extensions.py`.
   Импорт из `app` запрещён (циклические импорты).
2. Добавить view + шаблон, наследующий `base.html` (без inline-стилей/`onclick`).
3. Новый blueprint зарегистрировать в `app.py`.
4. Обновить список активного пункта навигации в `templates/base.html` (`request.endpoint`).
5. `/api/*` — только JSON-ответы. HTML-ошибки рендерит `templates/error.html`.
6. Добавить тест в `tests/` и прогнать `.venv/bin/python -m pytest -q` и `.venv/bin/ruff check .`.
