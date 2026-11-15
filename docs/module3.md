# Модуль 3. Продуктовая аналитика и визуальная концепция

**Проект:** Kachlog — приложение для ведения силовых тренировок и персональных планов.
**Дата:** 2026-11-14.

## Что требовалось

1. Найти аналоги продукта, разобрать фичи, UX и UI.
2. Собрать полный контекст для агента: ресерч, анализ конкурентов, PRD.
3. Пройти `gsd-discuss-phase` и `gsd-plan-phase`.
4. Подготовить UX-паттерны: экраны, переходы, состояния.
5. Подобрать цвета для UI и собрать визуальную концепцию.
6. Собрать `DESIGN.md` по каркасу из 10 разделов и экран по нему со скриншотами
   desktop/mobile.

## Что сделано

### 1. Контекст и PRD

| Артефакт | Что внутри |
|---|---|
| `docs/ux/prd.md` | сжатый PRD: пользователи, jobs-to-be-done, сценарии, scope, метрики, риски |
| `docs/ux/prd-challenge.md` | 10 вопросов к PRD, допущения, решения, следствия для дизайна |

PRD проверен по продуктовой логике и метрикам, а не пересказан из презентации.

### 2. Конкуренты

`docs/ux/competitors.md` — 6 аналогов:

- **Hevy** — быстрый лог, «в прошлый раз», PR, социальные фичи.
- **Fitbod** — AI-план, recovery-модель, mStrength.
- **Alpha Progression** — генератор плана и рекомендации на каждый подход.
- **RP Hypertrophy** — мезоциклы, авторегуляция, делоад.
- **Strong** — минималистичный логгер.
- **Boostcamp** — библиотека программ и auto progression.

Есть feature matrix (14 признаков), отдельный блок «Анти-паттерны UX», источники с датами
и правило «копируем паттерн, не бренд».

### 3. UX-паттерны

`docs/ux/ux-patterns.md`:

- карта экранов продукта;
- 4 сценария: первый пользователь, возвращающийся, ручной план, прогресс/шеринг;
- Mermaid-схема основного сценария «первый пользователь → AI-план → Сегодня»;
- переходы: sidebar/tab bar, dialog/sheet, breadcrumbs, черновик, offline;
- 5 состояний: empty / loading / partial / error / success;
- AI UX: генерация, пересчёт, разбор тренировки;
- доступность: 44 px, контраст, фокус, reduced motion.

### 4. Визуальная концепция

`DESIGN.md` — 10 разделов:

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

Плюс приложения: shadcn-правила, чек-лист ревью, источники.

Основа:
- shadcn/ui `base-nova`, Tailwind v4, Lucide;
- stone-палитра, `radius 0.625rem`;
- Inter Variable + Geist Mono Variable (кириллица);
- teal — только прогресс, PR и успех;
- dense desktop (28–40 px), mobile ≥44 px.

### 5. Demo-экран

`design/screens/plan.html` — самостоятельная адаптивная рекомпозиция экрана
«Мой план / Сегодня»:

- desktop: sidebar, breadcrumbs, TodayCard, уведомления, WeekStrip, accordion;
- mobile: topbar, контент, bottom tab bar;
- состояния: ready, empty, loading, error, partial, offline, AI form/pending/error;
- light/dark;
- локальные WOFF2, inline SVG, без CDN.

Скриншоты — `screenshots/module3/`.

### 6. GSD

`.planning/phases/05-product-analytics-visual-concept/`:

- `05-DISCUSSION-LOG.md` — альтернативы и решения;
- `05-CONTEXT.md` — границы, решения, canonical refs;
- `05-01-PLAN.md` — задачи, файлы, verification, success criteria.

## Артефакты

| Требование | Файл |
|---|---|
| PRD и челлендж PRD | `docs/ux/prd.md`, `docs/ux/prd-challenge.md` |
| Аналоги и feature matrix | `docs/ux/competitors.md` |
| UX-паттерны | `docs/ux/ux-patterns.md` |
| Визуальная концепция | `DESIGN.md` |
| Branding референсов | `docs/ux/references/*` |
| Demo-экран | `design/screens/plan.html`, `plan.css`, `plan.js` |
| Скриншоты | `screenshots/module3/*` |
| Design-loop | `docs/ux/design-loop/bar.md`, `docs/ux/design-loop.md` |
| GSD discuss/plan | `.planning/phases/05-product-analytics-visual-concept/05-*` |

## Как посмотреть

```bash
test -f DESIGN.md && test -f docs/ux/competitors.md \
  && test -f design/screens/plan.html \
  && test -f screenshots/module3/plan-desktop-light.png && echo OK

python3 -m http.server 8767 --bind 127.0.0.1 --directory design
# http://127.0.0.1:8767/screens/plan.html?state=ready
# ?state=empty | loading | error | partial | ai | ai-error, + &theme=dark
# ?state=ai-pending&freeze=1 — статичный pending для скриншота
# &offline=1 — бейдж офлайна
```

## Скриншоты

| Файл | Что показывает |
|---|---|
| `reference-plan-desktop.png` | текущий интерфейс продукта (референс) |
| `reference-workout-mobile.png` | текущая тренировка (референс) |
| `plan-desktop-light.png` | demo, desktop, light |
| `plan-mobile-light.png` | demo, mobile, light |
| `plan-desktop-dark.png` | demo, desktop, dark |
| `plan-mobile-dark.png` | demo, mobile, dark |
| `state-empty.png`, `state-loading.png`, `state-error.png` | состояния |
| `state-partial.png`, `offline-mobile.png` | partial и offline |
| `ai-desktop.png`, `ai-mobile.png`, `ai-pending-desktop.png` | AI sheet |
| `ai-error-desktop.png`, `ai-dark-desktop.png` | ошибка ИИ и тёмная тема |

## Ограничения

- Прод-код не менялся: это концепт-артефакты, а не деплой.
- Firecrawl/Stitch недоступны без ключей: брендинг снят вручную по схеме Firecrawl,
  demo собран кодом.
- Скриншоты продукта — референс для сравнения; живого доступа к авторизованной
  странице для попиксельной сверки нет.

## Чек-лист

- [ ] `DESIGN.md` содержит 10 разделов и не содержит внутренних путей к коду.
- [ ] В `competitors.md` ≥6 аналогов, feature matrix и источники с датами.
- [ ] В `ux-patterns.md` есть карта экранов, сценарии, переходы, 5 состояний и AI UX.
- [ ] Demo-экран открывается локально, состояния переключаются, внешних запросов нет.
- [ ] Скриншоты desktop/mobile, light/dark и состояний лежат в `screenshots/module3/`.
- [ ] GSD discuss/plan артефакты лежат в `.planning/phases/05-product-analytics-visual-concept/`.
- [ ] `README.md` и `docs/module3.md` ссылаются на существующие файлы.
