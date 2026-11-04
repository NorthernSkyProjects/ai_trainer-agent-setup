# Kachlog (ai_trainer) — AI-ориентированная среда разработки

Репозиторий-снимок окружения coding-агента для проекта **Kachlog** (ранее IronMind) —
Flask-приложения для ведения тренировок с ИИ-генерацией планов. Здесь только конфигурация
агента, артефакты планирования и доказательства работы; исходный код — в приватном
GitLab-репозитории `https://gitlab.com/ShelkunovES/ai_trainer`.

Агент: **Claude Code** на DEV-стенде + общий `AGENTS.md` (читают также OpenCode/Codex).

## Содержание

- [Модуль 2. Агентно-ориентированный пайплайн (GSD)](#модуль-2-агентно-ориентированный-пайплайн-gsd)
- [Модуль 1. Как агент работает в проекте](#модуль-1-как-агент-работает-в-проекте)
- [Как воспроизвести e2e без полного дерева](#как-воспроизвести-e2e-без-полного-дерева)
- [Структура репозитория](#структура-репозитория)

## Модуль 2. Агентно-ориентированный пайплайн (GSD)

Цель модуля — не просто «поставить агента», а собрать воспроизводимый цикл:
**Discovery → Roadmap → Plan → Progress → Memory → Context management → Verification**.
Окружение поднято на DEV-стенде под реальный проект `ai_trainer` (клон в `/root/ai_trainer-gsd`).

### Что установлено

| Компонент | Версия | Как проверено |
|---|---|---|
| Node.js | 24.22.2 | `node -v` (GSD 1.20 требует Node ≥24) |
| npm | 11.19.1 | `npm -v` |
| GSD Core | 1.20.0 | `cat .claude/gsd-core/VERSION` (после install), 76 команд в `.claude/commands/` |
| claude-mem | 15.9.0 | `npx claude-mem doctor`, worker на `127.0.0.1:37700` |
| Python (clone) | 3.12.3 + `.venv` | `ruff 0.17.3`, `pytest 9.2.0`, 645 тестов зелёные |

GSD поставлен локально (`--claude --local --relative-includes`), поэтому артефакты и команды
лежат в репозитории проекта, а не только в `~/.claude`. claude-mem поставлен с
`--provider claude`: память работает на Anthropic-плане, локальная SQLite-база, без облачной
синхронизации.

### Discovery (пройден)

Discovery выполнен на реальном коде `ai_trainer`, а не на пустом шаблоне:

1. `/gsd-map-codebase` — 7 документов в `.planning/codebase/`:
   `STACK`, `ARCHITECTURE`, `STRUCTURE`, `CONVENTIONS`, `TESTING`, `INTEGRATIONS`, `CONCERNS`.
2. `/gsd-onboard --fast --text` — `.planning/onboarding/SUMMARY.md`.
3. `/gsd-new-project --auto @README.md` — `PROJECT.md`, `REQUIREMENTS.md` (36 требований),
   `ROADMAP.md` (4 фазы), `STATE.md`, `config.json`, `research/*`.
4. `/gsd-discuss-phase 1 --auto` — `01-CONTEXT.md` и `01-DISCUSSION-LOG.md`.
5. `01-PATTERNS.md` + `01-01-PLAN.md` — паттерны и план первой фазы.

Итог Discovery — не «демо-проект», а конкретный план харденинга Kachlog: сначала safety net
(пиннинг Python 3.12, lockfile, характеризационные тесты, разгрузка модулей), затем AI error
boundary, унификация анализа тренировок и защита внутренних endpoints. Полный roadmap:
`.planning/ROADMAP.md`.

### Артефакты, которые требует модуль

| Требование | Файл |
|---|---|
| Roadmap | `.planning/ROADMAP.md` (4 фазы, 36 требований) |
| Plan | `.planning/phases/01-safety-net-module-structure/01-01-PLAN.md` |
| Progress | `.planning/STATE.md` + `.planning/reports/PROGRESS-2026-11-03.md` |
| Architecture | `.planning/codebase/ARCHITECTURE.md` |
| Security checklist | `.planning/SECURITY-CHECKLIST.md` |
| Discovery | `.planning/onboarding/SUMMARY.md`, `.planning/codebase/*`, `.planning/research/*` |

### Память агента

Два слоя:

1. **claude-mem 15.9.0** — автоматически сохраняет наблюдения/решения в
   `~/.claude-mem/claude-mem.db` и подмешивает их в следующую сессию.
   Проверка: `npx claude-mem search "Kachlog"` → 118 результатов (100 наблюдений, 18 промптов);
   `npx claude-mem doctor` → worker healthy. Скриншот: `screenshots/module2/03-memory-recall.png`.
2. **GSD native memory** — `STATE.md`, `01-CONTEXT.md`, `01-PATTERNS.md`, `HANDOFF.json`
   (после `/gsd-pause-work`) и `docs/plan.md` / `docs/memory.md` из модуля 1.

### Быстрые команды и auto hooks

- 72 команды GSD: `/gsd-new-project`, `/gsd-onboard`, `/gsd-map-codebase`, `/gsd-plan-phase`,
  `/gsd-execute-phase`, `/gsd-verify-work`, `/gsd-secure-phase`, `/gsd-progress`,
  `/gsd-pause-work`, `/gsd-resume-work`, `/gsd-quick`, `/gsd-debug`, `/gsd-ship` и др.
- 4 проектные команды: `/ctx`, `/handoff`, `/check`, `/discover` (`.claude/commands/`).
- Auto hooks (`.claude/settings.json`, 23 блока): `SessionStart`, `PreToolUse`, `PostToolUse`,
  `Stop`, `SubagentStop`, `PreCompact`, `FileChanged`.
  - модуль 1: `protect-files.sh`, `lint-python.sh`, `verify-on-git.sh`, `verify-on-stop.sh`;
  - GSD: secret-read guard, prompt/read guards, context monitor, statusline, commit validation.
- Скриншоты: `06-commands.png`, `07-hooks-statusline.png`.

### Управление контекстом

- **Statusline GSD** показывает модель, задачу, каталог и заполнение контекста
  (порог предупреждения — 35% остатка, критический — 25%).
- **Context monitor** подмешивает предупреждение агенту до автосжатия; `PreCompact` сбрасывает
  состояние, чтобы после сжатия цикл начинался заново.
- **Чек-пойнты**: `/gsd-pause-work` пишет `HANDOFF.json` + `continue-here.md`, `/gsd-resume-work`
  восстанавливает позицию после `/clear`.
- **Автосжатие**: `/compact` (или авто-компакция Claude Code) уменьшает окно; сравнение
  «до/после» снимается в живой сессии по инструкции
  `docs/module2/screenshot-guide.md`.
- GSD-конфиг: `.planning/config.json` (`hooks.context_warning_threshold` /
  `hooks.context_critical_threshold` можно переопределить).

### Безопасность

`.planning/SECURITY-CHECKLIST.md` — 10 разделов: секреты, auth/session/CSRF, внутренние
endpoints, Telegram webhook, AI boundary, PII, зависимости, deploy, agent layer. В нём
зафиксировано, что уже есть (CSRF, rate limits, nginx-localhost для `/healthz` и `/ai_metrics`,
deny `.env`/`instance/**`), и что открыто по фазам (SEC-01..05, AIE-01..08).

### Как проверить модуль 2

```bash
# 1. Артефакты GSD
test -f .planning/PROJECT.md && test -f .planning/ROADMAP.md \
  && test -f .planning/STATE.md && test -f .planning/SECURITY-CHECKLIST.md \
  && test -f .planning/phases/01-safety-net-module-structure/01-01-PLAN.md && echo OK

# 2. Прогресс/план (после scripts/install-agent-env.sh)
node .claude/gsd-core/bin/gsd-tools.cjs progress
node .claude/gsd-core/bin/gsd-tools.cjs planning inspect

# 3. Память
npx claude-mem doctor
npx claude-mem search "Kachlog" | head

# 4. Hooks и statusline
jq -r '.hooks | keys[]' .claude/settings.json
jq -r '.statusLine.type' .claude/settings.json

# 5. Тесты проекта (в клоне ai_trainer с .venv)
.venv/bin/ruff check . && .venv/bin/python -m pytest -q
```

Ожидаемо: `progress` показывает Phase 1 со статусом `Planned`, `claude-mem doctor` — все
обязательные проверки зелёные, `settings.json` содержит и GSD-hooks, и hooks модуля 1.

### Скриншоты

| Файл | Что показывает | Статус |
|---|---|---|
| `screenshots/module2/01-env-block.png` | `protect-files.sh` блокирует `.env` | готово |
| `screenshots/module2/02-posttool-lint.png` | PostToolUse `ruff check --fix` ловит `F821` | готово |
| `screenshots/module2/03-memory-recall.png` | claude-mem отдаёт 118 наблюдений по «Kachlog» | готово |
| `screenshots/module2/04-discovery.png` | `.planning/` + onboarding summary | готово |
| `screenshots/module2/05-progress.png` | `gsd-tools progress` + roadmap | готово |
| `screenshots/module2/06-commands.png` | 76 быстрых команд GSD | готово |
| `screenshots/module2/07-hooks-statusline.png` | 23 hook-блока + statusline | готово |
| `screenshots/module2/08-context-before.png` | `/context` до сжатия: **112.1k / 1m (11%)** | готово |
| `screenshots/module2/09-context-after.png` | `/context` после `/compact`: **75k / 1m (7%)** | готово |
| `screenshots/module2/10-checkpoint.png` | `/gsd-pause-work` → HANDOFF | опционально |
| `screenshots/module2/11-memory-live.png` | recall после `/clear` | опционально |

`08` и `09` — реальные TUI-скрины Claude Code: до сжатия **112.1k (11%)**, после `/compact` —
**75k (7%)**. `10` и `11` опциональны и для сдачи не требуются; инструкция —
`docs/module2/screenshot-guide.md`.

### Ограничения и честные notes

- Планировщик GSD упёрся в лимит сессии Claude Code после `01-PATTERNS.md`;
  `01-01-PLAN.md` собран из `CONTEXT`/`PATTERNS`/`ROADMAP` и помечен как план, а не как
  выполненная фаза. После сброса лимита его можно перегенерировать:
  `/gsd-plan-phase 1 --auto --skip-research`.
- `/gsd-execute-phase 1` не запускался: фаза меняет код, а для сдачи нужен инициализированный
  пайплайн. Выполнение — следующий шаг на отдельной ветке.
- `/gsd-secure-phase 1` требует выполненной фазы; `SECURITY-CHECKLIST.md` — стартовый baseline,
  а не отчёт аудита.
- Исходный код и `tests/e2e` живут в приватном GitLab; в этом репозитории их нет.

## Модуль 1. Как агент работает в проекте

**Какие инструкции агент читает**
- `AGENTS.md` — открытый стандарт (стек, команды, конвенции, правила работы), ≤200 строк.
- `CLAUDE.md` — для Claude Code; импортирует `@AGENTS.md`.
- `.claude/rules/*.md` с `paths:` — правила, которые подгружаются **лениво** только для своих
  файлов: `python.md` (для `*.py`), `templates.md` (для `templates/**`, `static/**`).
- `.claude/skills/` — переиспользуемые навыки (см. `docs/about.md`).

**Какие у него права** (`.claude/settings.json`)
- `allow`: `pytest`, `ruff`, `git status/diff/log/add/commit`, чтение и правка файлов.
- `ask` (подтверждает человек): `git push` (**push в `main` = деплой в прод**), `systemctl restart`,
  `flask db upgrade`, `pip install`.
- `deny`: чтение `.env`/прод-секретов, доступ к `instance/`, `rm -rf /*`, `git push --force`.
- Режим по умолчанию — `acceptEdits`: правки файлов идут без лишних подтверждений для скорости,
  но рискованные shell-команды и запись в защищённые пути остаются под контролем (`ask`/`deny`).
- Личные настройки — вне git (`.claude/settings.local.json`, `CLAUDE.local.md`).

**Какие проверки его страхуют** (hooks)
- `.claude/hooks/lint-python.sh` — после правки `.py` прогоняет `ruff check --fix` и возвращает
  агенту оставшиеся ошибки.
- `.claude/hooks/protect-files.sh` — блокирует правки `.env`, `.git/`, `instance/`.
- `.claude/hooks/verify-on-git.sh` — перед `git commit`/`git push` гоняет ruff + pytest; красное блокирует.
- `.claude/hooks/verify-on-stop.sh` — опциональный Stop-hook (маркер `.claude/.verify-on-stop`).

**Память между сессиями**
`docs/plan.md` (план с чекбоксами) и `docs/memory.md` (журнал: сделано / решение / дальше / ловушка).
Новая сессия продолжает с «прочитай `docs/plan.md` и `docs/memory.md`, продолжи с задачи N».

**Как запустить тесты** (в полном проекте)
```bash
pip install -r requirements-dev.txt
pytest                                 # все тесты; один — pytest tests/test_workout.py::test_name
ruff check .                           # линтер
```

## Как воспроизвести e2e без полного дерева

E2E-смоук лежит в приватном репозитории в `tests/e2e/` и не входит в этот снимок. Чтобы
повторить его на DEV-стенде:

```bash
cd /root/ai_trainer            # полный клон проекта
python -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
playwright install chromium
.venv/bin/python -m pytest -m e2e tests/e2e -q
```

Тест сам поднимает тестовое приложение, проходит регистрацию → логин, проверяет консоль и
сохраняет `screenshots/agent/e2e-smoke.png`. В CI он исключён маркером `-m "not e2e"`.

## Структура репозитория

```
AGENTS.md                  # инструкции: стек, команды, конвенции, правила работы
CLAUDE.md                  # файл для Claude Code (@AGENTS.md + разбивка)
docs/about.md              # модуль 1: paths-правило, навыки, права, hooks, скриншоты
docs/module2.md            # модуль 2: установка GSD, Discovery, память, контекст, проверка
docs/module2/              # verification.md + screenshot-guide.md
docs/plan.md, memory.md    # память между сессиями (handoff)
docs/plan-eval.md          # рубрика оценки ИИ-планов
.planning/                 # артефакты GSD: PROJECT, REQUIREMENTS, ROADMAP, STATE,
                           # codebase/*, research/*, phases/01-*, SECURITY-CHECKLIST
.claude/settings.json      # permissions + hooks + statusline
.claude/hooks/*.sh|*.js    # hooks модуля 1 и GSD
.claude/commands/*.md      # 72 команды GSD + 4 проектные
.claude/rules/*.md         # правила с paths: (python, templates)
.claude/skills/*           # навыки (SKILL.md)
scripts/install-agent-env.sh  # воспроизводимая установка Node 24 + GSD + claude-mem
screenshots/agent/*.png    # модуль 1
screenshots/module2/*.png  # модуль 2
```
