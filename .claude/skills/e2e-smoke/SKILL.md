---
name: e2e-smoke
description: Playwright (Python) smoke-прогон логина на dev-сервере. Использовать перед деплоем UI-изменений.
disable-model-invocation: true
---
# e2e-smoke: браузерный smoke через Playwright (Python)

E2E-тесты помечены `@pytest.mark.e2e` и по умолчанию исключены из прогона
(в `pytest.ini`: `addopts = -m "not e2e"`), чтобы CI-гейт не тянул браузеры.

Запуск (только на dev-стенде, где установлен chromium):
```
.venv/bin/python -m pytest -m e2e tests/e2e -q
```

Если браузер не установлен:
```
.venv/bin/python -m playwright install chromium
```

Тест сам поднимает тестовое приложение (werkzeug `make_server`) на свободном порту
с изолированной temp-БД — прод/дев данные не трогаются.

## Когда НЕ использовать
- В CI (маркер `e2e` исключён из гейта; нужен браузер).
- Как замену юнит-тестам: e2e медленный и хрупкий, держим его тонким smoke-слоем.
