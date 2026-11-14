# Бриф для Claude Code: ревью модуля 3

**Роль:** senior product designer + frontend reviewer.
**Режим:** read-only. Ничего не редактируй, не запускай деплой, не трогай `/root/ai_trainer`.
**Язык ответа:** русский.
**Дата:** 2026-11-14.

## Контекст

Проект — Kachlog (Flask + Next.js прототип). Модуль 3 требует:
аналоги, анализ конкурентов, полный контекст для агента, GSD `discuss`/`plan`, UX-паттерны
(экраны, переходы), цвета UI, `DESIGN.md`, экран по нему и скриншоты desktop/mobile.

Владелец продукта сказал: **за основу брать текущий дизайн `https://iitrainer.duckdns.org/next/plan`**
(shadcn/ui `base-nova`, Tailwind v4, Inter + Geist Mono, stone + teal). Новый бренд не вводим.
После реализации работа отдаётся тебе на валидацию; красный вердикт блокирует push в GitHub.

## Что прочитать

1. `DESIGN.md` — as-built дизайн-система (10 разделов).
2. `docs/ux/prd.md`, `docs/ux/prd-challenge.md` — контекст и челлендж PRD.
3. `docs/ux/competitors.md` — 6 аналогов, feature matrix, что копируем.
4. `docs/ux/ux-patterns.md` — экраны, переходы, 5 состояний, AI UX.
5. `docs/ux/design-loop/bar.md`, `docs/ux/design-loop.md` — механизмы и вердикт.
6. `design/screens/plan.html`, `plan.css`, `plan.js` — demo-экран.
7. `screenshots/module3/*` — скриншоты.
8. `.planning/phases/05-product-analytics-visual-concept/05-*.md` — GSD-фазы.
9. `docs/module3.md`, `docs/module3/verification.md` — описание и чек-лист.

Референс в коде (если доступен на этой машине): `/root/ai_trainer/web/src/app/globals.css`,
`/root/ai_trainer/web/src/design/**`. Живой CSS:
`https://iitrainer.duckdns.org/next/_next/static/css/7ff50812afa06d37.css`.

## Что проверить

### A. Верность дизайн-системе

- Токены в `DESIGN.md` и `design/screens/plan.css` совпадают с живым CSS / `globals.css`.
- Шрифты: Inter Variable + Geist Mono Variable, кириллица, локальные WOFF2.
- Радиус 10px, ring 1px, dense desktop / 44px mobile.
- Teal только прогресс/PR/успех; нет teal-текста на белом ниже 4.5:1.
- Нет градиентов, эмодзи, второго акцента, чужих шрифтов.

### B. Полнота контекста

- 6 конкурентов с источниками и датой; feature matrix ≥12 признаков.
- PRD-челлендж: 10 вопросов, допущения отделены от фактов.
- UX-паттерны: все роуты, 4 сценария, 5 состояний, AI UX, доступность.

### C. Экран

- Открывается локально без сети; `?state=ready|empty|loading|error|ai|ai-pending` работают.
- Desktop 1440×900 и mobile 390×844 выглядят как `/next/plan`, не как другой продукт.
- Один primary CTA на смысловой блок; числа mono/tabular.
- Состояния не протекают друг в друга; ошибка с retry; pending с отменой.
- Нет горизонтального скролла и обрезанного контента.

### D. GSD

- `05-DISCUSSION-LOG.md` фиксирует альтернативы и решения.
- `05-CONTEXT.md` содержит границы, D-01…, canonical refs.
- `05-01-PLAN.md` содержит задачи, файлы, verification, success criteria.
- `ROADMAP.md` и `README.md` обновлены.

### E. Процесс

- План ревью и валидация Claude Code оформлены как отдельные артефакты.
- Push блокируется красным вердиктом.
- В коммит не попадают PDF урока, секреты, чужие ассеты.

## Формат ответа

```markdown
## Вердикт
GO / NO-GO

## Блокирующие замечания (если NO-GO)
1. [файл:строка] что не так → что исправить

## 5 главных рисков
1. ...

## Пропущенные артефакты / состояния
- ...

## Расхождения с /next/plan
- ...

## Некритичные улучшения
- ...

## Что проверить перед push
- ...
```

Будь конкретным: ссылайся на файлы и строки, не давай общих советов. Если всё ок —
всё равно перечисли 5 рисков и некритичные улучшения.
