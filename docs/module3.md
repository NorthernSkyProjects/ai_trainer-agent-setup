# Модуль 3. Продуктовая аналитика и визуальная концепция

**Проект:** Kachlog (`ai_trainer`)
**Дата:** 2026-11-14
**База дизайна:** `https://iitrainer.duckdns.org/next/plan` — текущая реализация на
shadcn/ui (`base-nova`), Tailwind v4 и Lucide. Новый бренд не вводим.

## Что требовалось

1. Найти аналоги продукта, разобрать фичи, UX, UI.
2. Дать агенту полный контекст: ресерч, анализ конкурентов, PRD.
3. Пройти `gsd-discuss-phase` и `gsd-plan-phase`.
4. Подготовить UX-паттерны: экраны, переходы, состояния.
5. Подобрать цвета для UI.
6. Собрать `DESIGN.md` по каркасу из 10 разделов, экран по нему и скриншоты desktop/mobile.
7. Согласовать план с Claude Code, доработать и отдать реализацию на валидацию.

## Что сделано

### 1. Контекст и PRD

| Артефакт | Что внутри |
|---|---|
| `docs/ux/prd.md` | сжатый PRD: пользователи, JTBD, сценарии, scope, метрики, риски |
| `docs/ux/prd-challenge.md` | 10 вопросов к PRD, допущения, решения, следствия для дизайна |

PRD челленджится по реальному коду и метрикам (`product_metrics.py`, `bp/*`, `web/src/app/*`),
а не по презентации.

### 2. Конкуренты

`docs/ux/competitors.md` — 6 аналогов:

- **Hevy** — быстрый лог, «в прошлый раз», PR, соцфичи.
- **Fitbod** — AI-план, recovery-модель, mStrength.
- **Alpha Progression** — генератор плана + рекомендации на каждый подход.
- **RP Hypertrophy** — мезоциклы, авторегуляция, делоад.
- **Strong** — минималистичный логгер.
- **Boostcamp** — библиотека программ + auto progression.

Есть feature matrix (14 признаков), «копируем паттерн / не копируем бренд», источники с датами.
Fitbod отдаёт 403 — разбор по help center, Google Play и обзорам 2026.

### 3. UX-паттерны

`docs/ux/ux-patterns.md`:

- карта всех экранов по `web/src/app/*`;
- 4 сценария (первый пользователь, возвращающийся, ручной план, прогресс/шеринг);
- переходы: sidebar/tab bar, dialog/sheet, breadcrumbs, черновик, offline;
- 5 состояний: empty / loading / partial / error / success;
- AI UX: генерация, пересчёт, разбор (`pending/ready/stale/failed/skipped`);
- доступность: 44px, контраст, фокус, reduced motion.

### 4. DESIGN.md

`DESIGN.md` — 10 разделов по каркасу из презентации:

1. Atmosphere
2. Colors
3. Typography
4. Spacing & Grid
5. Components
6. States
7. AI UX
8. Motion
9. References
10. Don'ts

Плюс приложения: shadcn-правила, чек-лист ревью, источники. Токены сняты с живого CSS
`/next/_next/static/css/7ff50812afa06d37.css` и `web/src/app/globals.css`:

- stone-палитра, `--radius: 0.625rem`;
- Inter Variable + Geist Mono Variable (кириллица);
- teal (`chart-2`) только для прогресса/PR/успеха;
- dense desktop (28–40 px), mobile ≥44 px.

### 5. Demo-экран

`design/screens/plan.html` — самостоятельная рекомпозиция «Мой план / Сегодня»:

- desktop: sidebar + breadcrumbs + `max-w-5xl`, TodayCard, действия, WeekStrip, load proposal,
  accordion;
- mobile: topbar + контент + bottom tab bar;
- состояния: `ready`, `empty`, `loading`, `error`, `ai`, `ai-pending`;
- light/dark;
- локальные WOFF2, inline Lucide SVG, без CDN.

Скриншоты — `screenshots/module3/`:

| Файл | Что показывает |
|---|---|
| `reference-plan-desktop.png` | текущий `/next/plan` (референс) |
| `reference-workout-mobile.png` | текущая тренировка (референс) |
| `plan-desktop-light.png` | demo, desktop, light |
| `plan-mobile-light.png` | demo, mobile, light |
| `plan-desktop-dark.png` | demo, desktop, dark |
| `plan-mobile-dark.png` | demo, mobile, dark |
| `state-empty.png` | пустое состояние |
| `state-empty-mobile-dark.png` | пустое состояние, mobile dark |
| `state-loading.png` | загрузка, skeleton |
| `state-loading-mobile.png` | загрузка, mobile |
| `state-error.png` | ошибка + retry |
| `state-error-mobile.png` | ошибка, mobile |
| `state-partial.png` | partial: разбор задерживается |
| `offline-mobile.png` | offline-бейдж |
| `ai-desktop.png` | sheet «Пересчёт плана с ИИ» |
| `ai-mobile.png` | sheet на mobile |
| `ai-dark-desktop.png` | sheet в тёмной теме |
| `ai-pending-desktop.png` | pending ИИ |
| `ai-pending-mobile.png` | pending на mobile |
| `ai-error-desktop.png` | ошибка ИИ + «Повторить» |

### 6. Design-loop

`docs/ux/design-loop/bar.md` — 8 измеримых механизмов.
`docs/ux/design-loop.md` — 2 раунда критики (brief/system/craft), найденные и исправленные
проблемы, финальный вердикт **PASS** и некритичные замечания.

### 7. GSD-фазы

`.planning/phases/05-product-analytics-visual-concept/`:

- `05-DISCUSSION-LOG.md` — альтернативы и решения.
- `05-CONTEXT.md` — границы, D-01…D-14, canonical refs.
- `05-01-PLAN.md` — задачи, файлы, verification, success criteria.

### 8. Claude Code

Два гейта:

1. **Ревью плана** — `docs/module3/claude-review-1.md`.
2. **Валидация реализации** — `docs/module3/claude-validation.md`.

Перед push: `python3 scripts/check_module3.py`. Скрипт проверяет обязательные артефакты,
10 разделов DESIGN.md, состояния экрана, GO-вердикт и отсутствие секретов/PDF в индексе.

## Как проверить

```bash
# 1. Артефакты
test -f DESIGN.md && test -f docs/ux/competitors.md \
  && test -f docs/ux/ux-patterns.md && test -f design/screens/plan.html \
  && test -f screenshots/module3/plan-desktop-light.png \
  && test -f docs/module3/claude-validation.md && echo OK

# 2. Экран локально
python3 -m http.server 8767 --bind 127.0.0.1 --directory design
# http://127.0.0.1:8767/screens/plan.html?state=ready
# http://127.0.0.1:8767/screens/plan.html?state=empty
# http://127.0.0.1:8767/screens/plan.html?state=loading
# http://127.0.0.1:8767/screens/plan.html?state=error
# http://127.0.0.1:8767/screens/plan.html?state=ai
# http://127.0.0.1:8767/screens/plan.html?state=ai-error
# http://127.0.0.1:8767/screens/plan.html?state=partial
# http://127.0.0.1:8767/screens/plan.html?state=ai-pending&freeze=1
# http://127.0.0.1:8767/screens/plan.html?state=ready&offline=1

# 3. Скриншоты (локальный Chromium)
CHROME=$HOME/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome
$CHROME --headless --no-sandbox --hide-scrollbars \
  --window-size=1440,900 --screenshot=/tmp/plan.png \
  "http://127.0.0.1:8767/screens/plan.html?state=ready"

# 4. Никаких секретов/PDF в коммите
git diff --cached --name-only | grep -E '\.env|\.pptx|Урок_UX' && exit 1 || true
```

## Ограничения

- Firecrawl/Stitch недоступны без ключей: брендинг снят вручную в схеме Firecrawl
  (`docs/ux/references/*`), экран собран кодом.
- `/next/plan` за авторизацией: использованы живой CSS, исходники `web/` и существующие
  скриншоты.
- Продуктовый код не менялся; это концепт-артефакты, а не деплой.
- PDF урока не коммитится (входной материал).
