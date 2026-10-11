---
name: new-migration
description: Создать миграцию Alembic после правки models.py (без ручных миграций). Использовать, когда менял схему БД.
disable-model-invocation: true
---
# new-migration: миграция после изменения models.py

1. Внести изменения в `models.py`.
2. Сгенерировать миграцию:
   `.venv/bin/flask --app app db migrate -m "краткое описание"`
3. Проверить созданный файл в `migrations/versions/` — только просмотр, логику вручную не писать.
4. Применить локально: `.venv/bin/flask --app app db upgrade`.
5. Прогнать тесты: `.venv/bin/python -m pytest -q`.
6. Прод-апдейт делает CI (`flask --app app db upgrade` на деплое) — вручную на прод не применять.

## Когда НЕ использовать
- `models.py` не менялся (нечего мигрировать).
- Никогда не писать/править миграцию руками — только автогенерация Alembic.
