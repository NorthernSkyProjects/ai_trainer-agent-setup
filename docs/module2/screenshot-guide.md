# Как снять живые скриншоты модуля 2

Готовые кадры `01`–`07` лежат в `screenshots/module2/`. Кадры `08` и `09` уже сняты в живой
сессии Claude Code (TUI): `/context` до — **112.1k / 1m (11%)**, после `/compact` —
**75k / 1m (7%)**. Ниже — инструкция для повторной съёмки `08`/`09` и для опциональных
`10`/`11`. Сохраняйте в `screenshots/module2/` с указанными именами.

Подключение:

```bash
ssh newvps
cd /root/ai_trainer-gsd
export PATH="$HOME/.local/bin:$PATH"
claude
```

> Лимит сессии Claude Code сбрасывается в 01:50 Europe/Moscow. Если сессия не стартует,
> дождитесь сброса.

## 08-context-before.png — usage до сжатия

1. В Claude Code выполните `/context`.
2. Снимите экран целиком: видно заполнение окна и разбивку по категориям.
3. Если `/context` ещё не показывает высокое заполнение, попросите агента прочитать
   `.planning/ROADMAP.md`, `.planning/PROJECT.md`, `.planning/codebase/ARCHITECTURE.md` и
   `README.md`, затем снова `/context`.

Ожидаемо: заметный процент использования (например, 40–70%) и шкала statusline.

## 09-context-after.png — usage после сжатия

1. Выполните `/compact`.
2. Дождитесь завершения и снова выполните `/context`.
3. Снимите экран.

Ожидаемо: процент заметно ниже, чем в `08`, история сжата, работа продолжается.

## 10-checkpoint.png — чек-пойнт

1. Выполните `/gsd-pause-work`.
2. Покажите вывод и созданные файлы:

```bash
ls -l .planning/HANDOFF.json .planning/continue-here.md 2>/dev/null
sed -n '1,40p' .planning/continue-here.md
```

3. Снимите экран с `HANDOFF.json` / `continue-here.md` и сообщением агента.

Ожидаемо: позиция, следующий шаг и блокеры сохранены.

## 11-memory-live.png — recall после `/clear`

1. В первой сессии примите решение, например:
   «Зафиксируй решение: Phase 1 начинается с Python 3.12 и lockfile, затем тесты, затем split.»
2. Выполните `/clear`.
3. В новой сессии спросите:
   «Что мы решили про порядок работ в Phase 1?»
4. Снимите ответ агента, где он ссылается на предыдущее решение (claude-mem + `.planning/STATE.md`).

Ожидаемо: агент воспроизводит решение без повторного объяснения.

## Дополнительно (по желанию)

- `12-resume.png` — после `/clear` выполните `/gsd-resume-work`, покажите восстановленную позицию.
- `13-discovery-live.png` — `/gsd-progress` или `/gsd-map-codebase` в TUI.

После съёмки:

```bash
cd /root/ai_trainer-agent-setup
cp /path/to/*.png screenshots/module2/
git add screenshots/module2
git commit -m "docs: add live context/memory screenshots"
```
