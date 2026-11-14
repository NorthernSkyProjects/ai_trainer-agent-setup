# Ответ на ревью Claude Code (gate 1)

**Ревью:** `docs/module3/claude-review-1.md` (NO-GO)
**Дата ответа:** 2026-11-14

| # | Блокирующее замечание | Что сделано | Где смотреть |
|---|---|---|---|
| 1 | Нет артефактов гейтов Claude Code | Ревью сохранено; добавлен `scripts/check_module3.py`, который падает без `claude-validation.md` с вердиктом GO | `docs/module3/claude-review-1.md`, `scripts/check_module3.py` |
| 2 | «Отмена» в AI pending не отменяет таймер | Таймер сохраняется; «Отмена»/Esc/backdrop вызывают `clearTimeout`, toast «Пересчёт отменён»; добавлено отдельное `ai-error` с «Повторить» | `design/screens/plan.js` |
| 3 | Тач-цели <44 px на mobile | В `@media (max-width:767px)` — `min-height:44px` для `.btn`, `.icon-btn`, `.chip`, `.day-row .icon-btn` | `design/screens/plan.css` |
| 4 | Неверные правила контраста `chart-3`/amber | `chart-3` — только графика; текст — `chart-4`/`chart-5`; amber — только иконка/короткая подпись | `DESIGN.md` §2.5 |
| 5 | Состояния протекают (cycle-card в empty/loading/error) | `body[data-state]` скрывает cycle-card, подзаголовок бренда и кнопку старта в этих состояниях | `design/screens/plan.css`, `plan.js` |

## Дополнительно исправлено из рисков и некритичных

- Убран `box-shadow` у `.card`; остался ring 1px (M6).
- Активный пункт sidebar — soft, как в продукте; добавлена primary-кнопка «Начать тренировку».
- Действия перенесены ниже уведомлений; добавлены install-баннер и amber-предупреждение.
- Loading — skeleton; добавлены partial, offline, ai-error, dark/mobile состояния.
- Видимый label у textarea; inline `onclick` убран; focus trap и возврат фокуса.
- Убрана строка «Русский UI» из матрицы (неподтверждённый факт).
- Q1/Q2 в PRD-челлендже помечены как предложение; добавлен блок «Факты».
- В UX-паттерны добавлен роут `/workout`.
- DESIGN.md: один primary на смысловой блок (≤2 на экран); preset consent уточнён;
  добавлен известный долг (белая галочка на teal, неиспользуемый синий sidebar-primary,
  inline SVG в demo, размеры референса).
- README/verification/module3 обновлены; добавлены новые скриншоты.
- `scripts/check_module3.py` — реальный гейт перед push.

## Что осталось ограничением, а не багом

- Референс `/next/plan` снят в 1280×900, demo — 1440×900; нет авторизованного доступа к живому
  экрану для попиксельного сравнения. Зафиксировано в DESIGN.md, приложение A.
- Для mobile-плана нет публичного референса; используется тот же design system и экран
  тренировки как доменный ориентир.
- Firecrawl/Stitch недоступны без ключей; брендинг снят вручную в схеме Firecrawl.

## Второй раунд (после валидации)

| Замечание валидации | Что сделано |
|---|---|
| После отмены pending sheet застревал в pending | `closeSheet()` вызывает `setSheetState("form")`; повторное открытие показывает форму, текст сохраняется |
| Error-retry оставлял `#error` на экране | `show()` сначала скрывает все состояния, затем показывает нужное |
| `ai-pending` без таймера — состояние-фантом | `?state=ai-pending` запускает реальный pending; для скриншота — `&freeze=1` |
| DESIGN.md §5.5 противоречит отмене | Зафиксирована модель «pending можно отменить; закрытие = отмена»; расхождение с продуктом отмечено как долг |
| Гейт не парсит вердикт и не ловит PDF | `check_module3.py` парсит `## Вердикт: GO|NO-GO`; `FORBIDDEN_NAMES` ловит `*.pdf` и `docs/plans/` |
| `DESIGN.md` рекомендовал `text-chart-2` | Заменено на `bg-chart-2` (заливка) / `text-chart-4` (текст) |
| Amber как подпись | Разрешена только иконка; текст — foreground |
| Preset «учесть историю» | В §6 добавлен `Technical default`: допустим, если подписан и отключается |

## Финальный раунд

| Замечание финальной валидации | Что сделано |
|---|---|
| `.memory summary` / `.check` меньше 44 px на mobile | Добавлены `min-height:44px`; хук `?check=1` расширен на `summary, a, label` |
| Подпись кнопки «Отмена» расходится с DESIGN.md | Кнопка переименована в «Отменить» |
| `check_staged` не ловит PDF в неотслеживаемой папке / кириллицу | `git status -uall` + `-c core.quotePath=false`, `re.IGNORECASE`, проверка raw-строк |
| Вердикт берётся по первому совпадению | `check_validation` читает только первую непустую строку и требует `## Вердикт: GO|NO-GO` |
