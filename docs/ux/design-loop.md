# design-loop: вердикт

**Референс:** `https://iitrainer.duckdns.org/next/plan` и скриншоты
`screenshots/module3/reference-plan-desktop.png`, `reference-workout-mobile.png`.
**Результат:** `design/screens/plan.html` + `screenshots/module3/plan-*.png`.
**Механизмы:** `docs/ux/design-loop/bar.md`.
**Дата:** 2026-11-14.

## Как шёл цикл

1. Снял токены и компоненты с живого `/next/plan` (CSS + `web/src/design/**`).
2. Собрал demo-экран «Мой план / Сегодня» на тех же токенах, шрифтах и паттернах.
3. Прогнал три роли критика: **brief / system / craft**.
4. Исправил найденное, снял скриншоты заново.
5. Повторил критику; вердикт — ниже.

Дополнительно экран прошёл ревью Claude Code; его блокирующие замечания вошли в раунд 1
и исправлены в раунде 2 (см. `docs/module3/claude-review-1.md`).

## Раунд 1

| Роль | Что нашла | Серьёзность |
|---|---|---|
| Brief | Все обязательные блоки есть: TodayCard, действия, WeekStrip, load proposal, accordion, AI sheet, 5 состояний | pass |
| Brief | В `empty/loading/error` в sidebar оставались данные цикла «75% / Неделя 6 из 8» — состояния протекали | **fail** |
| Brief | «Отмена» в AI pending не отменяла таймер: через 2,4 с всё равно появлялся toast «План обновлён» | **fail** |
| System | Токены, Inter/Geist Mono, радиусы и ring совпадают с `/next/plan` | pass |
| System | Карточки использовали `box-shadow`, хотя M6 требует только ring | **fail** |
| System | Активный пункт меню был залит `primary`, в продукте — soft `sidebar-accent` | **fail** |
| Craft | Блок действий стоял над TodayCard; в продукте — ниже уведомлений | **fail** |
| Craft | Не было install-баннера и amber-предупреждения — терялся важный паттерн | **fail** |
| Craft | На mobile тач-цели `.btn/.icon-btn/.chip` были 30–32 px | **fail** |
| Craft | Loading — одна строка текста, без skeleton | **fail** |
| Craft | Не было `ai-error`, partial, offline и dark/mobile вариантов состояний | **fail** |
| Craft | В demo не было видимого label у textarea и был inline `onclick` | **fail** |

## Раунд 2 — что изменил

- Добавил `body[data-state]` и скрыл cycle-card/подзаголовок бренда в `empty/loading/error`.
- AI sheet: таймер сохраняется, «Отмена»/Esc/backdrop очищают его; toast «Пересчёт отменён»,
  никакого ложного «План обновлён». Добавлено отдельное `ai-error`-состояние с «Повторить».
- Убрал `box-shadow` у `.card`; остался ring 1px.
- Активный пункт sidebar — soft `--muted`; добавлена primary-кнопка «Начать тренировку».
- Действия перенесены ниже TodayCard/уведомлений/load proposal; добавлены install-баннер и
  amber-предупреждение.
- Mobile: `.btn`, `.icon-btn`, `.chip`, `.day-row .icon-btn` — минимум 44 px.
- Loading: skeleton-карточки + текст; добавлены `partial` и `offline`.
- Добавлены видимый label у textarea, `data-retry` вместо inline `onclick`, focus trap,
  восстановление фокуса, `aria-expanded` у дней.
- Пересняты все скриншоты: desktop/mobile, light/dark, empty/loading/error/partial/offline,
  AI form/pending/error.

## Раунд 2 — вердикт

| # | Механизм | Вердикт | Доказательство |
|---|---|---|---|
| M1 | Today-карточка ≥25% первого экрана | **pass** | `plan-desktop-light.png`: ~260 px из 900 |
| M2 | Один primary на смысловой блок | **pass** | TodayCard — 1 primary; load card — 1 primary |
| M3 | Числа mono/tabular | **pass** | все веса/повторы/% — Geist Mono |
| M4 | Teal только прогресс/успех | **pass** | teal на полосе, галочках, иконке прогресса |
| M5 | Плотная навигация без шума | **pass** | 4 пункта sidebar, 5 табов mobile, soft active |
| M6 | Ring 1px + радиус 10px, без теней у карточек | **pass** | `.card` без `box-shadow` |
| M7 | Mobile: 44px + safe-area | **pass** | `min-height:44px` для кнопок/chips; CTA 48 px |
| M8 | AI-состояние с именем и выходом | **pass** | `ai-desktop.png`, `ai-pending-desktop.png`, `ai-error-desktop.png` |

**Итог: PASS.** Блокирующих расхождений с `/next/plan` нет.

## Некритичные замечания (не блокируют)

1. Empty/error-карточки стоят сверху, а не по центру свободной области. На реальном
   экране это нормально: пользователь видит контекст навигации.
2. В desktop AI sheet много воздуха в pending-состоянии. Это сознательно: состояние
   должно «дышать», а не выглядеть как ошибка.
3. Референс `/next/plan` снят в 1280×900, demo — в 1440×900. Сравнение качественное,
   не попиксельное: живого доступа к авторизованной странице нет.
4. Для mobile-плана публичного референса нет; используется тот же design system и
   экран тренировки как доменный ориентир. Это ограничение зафиксировано в DESIGN.md,
   приложение A.

## Что бы улучшил в продукте (вне модуля 3)

- Добавить в `web/src/app/globals.css` явный `--accent-progress` (teal), чтобы
  `chart-2` не использовался как «акцент» в компонентах.
- Исправить белые галочки на teal (контраст ~2.3:1) — известный долг.
- Убрать неиспользуемый синий `--sidebar-primary` из `.dark` или задокументировать его роль.
- Добавить e2e-скриншот `/plan` в CI (визуальная регрессия).

## Артефакты

- `design/screens/plan.html`, `plan.css`, `plan.js`
- `screenshots/module3/plan-desktop-light.png`, `plan-mobile-light.png`
- `screenshots/module3/plan-desktop-dark.png`, `plan-mobile-dark.png`
- `screenshots/module3/state-empty.png`, `state-empty-mobile-dark.png`
- `screenshots/module3/state-loading.png`, `state-loading-mobile.png`
- `screenshots/module3/state-error.png`, `state-error-mobile.png`
- `screenshots/module3/state-partial.png`, `offline-mobile.png`
- `screenshots/module3/ai-desktop.png`, `ai-mobile.png`, `ai-dark-desktop.png`
- `screenshots/module3/ai-pending-desktop.png`, `ai-pending-mobile.png`
- `screenshots/module3/ai-error-desktop.png`
- `screenshots/module3/reference-plan-desktop.png`, `reference-workout-mobile.png`
