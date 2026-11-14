# Модуль 3 — чек-лист приёмки

**Дата:** 2026-11-14
**Проверяющий:** открыть репозиторий, выполнить команды ниже, сверить скриншоты.

## 1. Файлы

- [ ] `DESIGN.md` в корне, 10 разделов.
- [ ] `docs/ux/prd.md`, `docs/ux/prd-challenge.md`.
- [ ] `docs/ux/competitors.md` — ≥6 аналогов, ≥12 признаков, источники.
- [ ] `docs/ux/ux-patterns.md` — экраны, переходы, 5 состояний, AI UX.
- [ ] `docs/ux/design-loop/bar.md`, `docs/ux/design-loop.md`.
- [ ] `docs/ux/references/linear-branding.json`, `hevy-branding.json`, `fitbod-ux.md`.
- [ ] `design/screens/plan.html`, `plan.css`, `plan.js`.
- [ ] `design/fonts/*.woff2` + OFL-лицензии.
- [ ] `screenshots/module3/` — desktop/mobile, light/dark, состояния, AI.
- [ ] `.planning/phases/05-product-analytics-visual-concept/05-*.md`.
- [ ] `docs/module3.md` и этот файл.
- [ ] `docs/module3/claude-review-1.md`, `claude-validation.md`.

## 2. DESIGN.md

- [ ] 10 разделов: Atmosphere, Colors, Typography, Spacing & Grid, Components, States, AI UX,
      Motion, References, Don'ts.
- [ ] Токены совпадают с `web/src/app/globals.css` / живым CSS `/next/`.
- [ ] У каждого цвета есть роль и доля (60-30-10).
- [ ] Есть пометка, что teal `chart-2` нельзя использовать как текст на белом (<4.5:1).
- [ ] Есть shadcn-правила и чек-лист ревью.

## 3. Конкуренты и UX

- [ ] 6 аналогов: Hevy, Fitbod, Alpha Progression, RP Hypertrophy, Strong, Boostcamp.
- [ ] У каждого — источник и дата 2026.
- [ ] Есть «копируем паттерн / не копируем бренд».
- [ ] UX-паттерны ссылаются на реальные роуты и компоненты.
- [ ] Для ключевых экранов описаны empty/loading/partial/error/success.
- [ ] AI UX покрывает генерацию, пересчёт и разбор.

## 4. Demo-экран

- [ ] `plan.html?state=ready` открывается локально.
- [ ] `state=empty|loading|error|partial|ai|ai-pending|ai-error` работают; для скриншота pending — `&freeze=1`.
- [ ] `theme=dark` работает; тема переключается кнопкой; `offline=1` показывает бейдж.
- [ ] Нет внешних запросов (шрифты локальные, иконки inline).
- [ ] Desktop 1440×900 и mobile 390×844 выглядят как референс.
- [ ] CTA ≥44 px на mobile, tab bar не перекрывает контент.
- [ ] Фокус видим, `prefers-reduced-motion` учтён.

## 5. Design-loop

- [ ] В `bar.md` 8 измеримых механизмов.
- [ ] В `design-loop.md` 3 роли критика и 2 раунда.
- [ ] Найденные проблемы реальны и исправлены (ритм секций, мобильный заголовок,
      переносы load proposal, AI sheet).
- [ ] Финальный вердикт — PASS; некритичные замечания отделены.

## 6. GSD

- [ ] `05-DISCUSSION-LOG.md` — альтернативы и выбор.
- [ ] `05-CONTEXT.md` — границы, D-01…D-14, canonical refs.
- [ ] `05-01-PLAN.md` — задачи, файлы, verification, success criteria.
- [ ] `ROADMAP.md` содержит Phase 5 (product/UX track).
- [ ] `README.md` содержит раздел «Модуль 3».

## 7. Claude Code

- [ ] `claude-review-1.md` — ревью плана, verdict.
- [ ] Замечания ревью учтены или явно отклонены.
- [ ] `claude-validation.md` — валидация реализации, verdict.
- [ ] Нет открытых блокирующих замечаний.

## 8. Гейт

- [ ] `python3 scripts/check_module3.py` печатает `MODULE 3 GATE: PASS`.

## 9. Git

- [ ] `git status` чистый после коммита.
- [ ] В коммите нет `.env`, прод-env (вне репозитория), `instance/`, PDF урока, чужих ассетов.
- [ ] Коммит в `main` запушен в `NorthernSkyProjects/ai_trainer-agent-setup`.
- [ ] `git log -1` показывает осмысленное сообщение.

## Команды

```bash
cd /root/ai_trainer-agent-setup
test -f DESIGN.md && test -f docs/ux/competitors.md && test -f design/screens/plan.html && echo OK

python3 -m http.server 8767 --bind 127.0.0.1 --directory design
# открыть /screens/plan.html?state=ready и остальные состояния

git status --short
git log --oneline -1
```
