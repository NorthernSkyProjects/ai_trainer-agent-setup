# Security Checklist — Kachlog / ai_trainer

**Created:** 2026-11-03
**Scope:** Flask app, RQ worker, Telegram bot/webhook, AI boundary, deploy pipeline, and the coding-agent layer.
**Sources:** `.planning/codebase/CONCERNS.md`, `README.md` (Раздел «Безопасность»), `.planning/REQUIREMENTS.md` (SEC-01..05), `.claude/settings.json`.
**Status legend:** `[x]` verified in the repo, `[ ]` open or planned.

## 1. Secrets and credentials

- [x] Production refuses to start without `SECRET_KEY` (`config.py`).
- [x] Dev fallback key is written to `instance/.secret_key`, and `instance/**` is denied to the agent.
- [x] `.env`, `instance/`, `settings.local.json` are gitignored; no secrets are tracked in the repo.
- [x] Agent deny rules block reading `.env`, `.env.*`, `/etc/ai_trainer.env`, `instance/**`.
- [x] `protect-files.sh` blocks edits to `*.env`, `.git/`, `instance/` before the write.
- [ ] Rotate any credential that was ever pasted into a chat, shell history, or a screenshot.
- [ ] Confirm `TELEGRAM_BOT_TOKEN`, `TELEGRAM_WEBHOOK_SECRET`, `GOOGLE_API_KEY`, `SECRET_KEY` are only in `/etc/ai_trainer.env` and `/root/ai_trainer/.env`.
- [ ] Record the rotation procedure for `SECRET_KEY` and its effect on share links (SEC-05).

## 2. Authentication, sessions, CSRF

- [x] Passwords are bcrypt-hashed (`models.py`).
- [x] Flask-Login session cookies are `HttpOnly`, `SameSite=Lax`, and `Secure` in production.
- [x] CSRF is enabled globally (`CSRFProtect`); HTML forms get flash + redirect, `/api/*` gets JSON 400.
- [x] `/login` and `/register` are rate-limited; `/api/*` has a default limit.
- [x] Password-reset tokens expire and are bound to a password/session fingerprint.
- [ ] Test the CSRF-exempt route set is exactly the Telegram webhook (FND-08).
- [ ] Confirm login/logout/session fixation behaviour after a password reset.

## 3. Internal endpoints and operations

- [x] `/healthz` and `/ai_metrics` are closed in nginx to `127.0.0.1` (`ai_trainer-internal.conf`).
- [x] `/healthz` reports DB/Redis/RQ state without exposing secrets.
- [ ] SEC-01: add an in-app localhost check to `/ai_metrics` while keeping `/healthz` working.
- [x] nginx serves a branded 50x page when the app is down.
- [ ] Verify externally that `/healthz` and `/ai_metrics` return 403, and locally 200.
- [ ] Confirm systemd units run as a non-root or least-privilege user where possible.

## 4. Telegram webhook

- [x] Webhook route returns 404 when `TELEGRAM_WEBHOOK_SECRET` is empty.
- [x] Secret comparison is constant-time (`hmac.compare_digest`) and the route is rate-limited.
- [ ] SEC-02: validate secret length at startup and compare as bytes; weak or non-ASCII values must warn and disable the webhook, not crash.
- [ ] FND-06: tests for wrong, empty and non-ASCII secret headers and non-dict JSON, asserting `handle_update` was not called.
- [ ] Confirm nginx does not forward `X-Real-IP`/`X-Forwarded-For` to the 3x-ui subscription route.

## 5. AI boundary and quota

- [x] AI calls are catalog-restricted by default (`EXERCISE_CATALOG_ENFORCE`).
- [x] Plans are normalised against age/health/limitation rules before saving (Core Value).
- [x] AI quota is enforced; Redis is the shared storage in production.
- [x] AI failures fall back between models and are logged with model/latency/fallback/cache.
- [ ] AIE-01..08: classify every AI failure into a closed reason code; never store provider text.
- [ ] ANL-03: retry only retryable reasons, consume quota, and be idempotent.
- [ ] SEC-04: warn at startup when quota storage is `memory://` and more than one worker runs.
- [ ] Confirm prompt-injection defence: user profile text never becomes a system instruction.

## 6. Data, backups, PII

- [x] SQLite runs in WAL mode with `busy_timeout=30000`.
- [x] Share links use a signed token with a max age; reports do not expose other users.
- [ ] Review whether AI prompts or logs contain email, health conditions, or other PII.
- [ ] Confirm `instance/trainer.db` backups exist and are not world-readable.
- [ ] Confirm `/share/<token>` is revocable by rotating the secret or expiring the token.

## 7. Dependencies and supply chain

- [ ] FND-03: pin dependencies in one lockfile used by CI, DEV and PROD.
- [ ] FND-01/02: run the same Python version (target 3.12) everywhere; verify PROD before bumping CI.
- [ ] Review `requests` imported by `scripts/yandex_art.py` but absent from `requirements*.txt`.
- [ ] Optional: run `pip-audit` in CI if it does not make the pipeline flaky.
- [ ] Review the GSD package legitimacy gate output before adding any new package.

## 8. Deploy and CI

- [x] `main` is gated by pytest + ruff; green CI is required before deploy.
- [x] Deploy does `git reset --hard origin/main`, `pip install`, `flask db upgrade`, restart.
- [x] Force pushes are denied to the agent; `git push` requires human confirmation.
- [ ] Keep migrations additive and nullable; never hand-write Alembic migrations.
- [ ] Confirm the CI runner cannot read `/etc/ai_trainer.env` from jobs that do not need it.

## 9. Coding-agent layer

- [x] `.claude/settings.json` has allow/ask/deny and `defaultMode: acceptEdits`.
- [x] `protect-files.sh` (PreToolUse) and `lint-python.sh` (PostToolUse) are active.
- [x] `verify-on-git.sh` runs ruff + pytest before `git commit`/`git push` and filters non-git Bash calls.
- [x] `verify-on-stop.sh` is opt-in via `.claude/.verify-on-stop`.
- [x] GSD hooks add secret-read guard, prompt/read guards, context monitor, and commit validation.
- [x] GSD local install kept the existing 13 user baseline files.
- [ ] Keep `.claude/settings.local.json` and `CLAUDE.local.md` out of git.
- [ ] Review screenshots before publishing: no tokens, emails, cookies, or `.env` contents.

## 10. Verification commands

```bash
git ls-files | grep -E "(^|/)\.env|settings\\.local|instance/" || echo "no secrets tracked"
.venv/bin/ruff check .
.venv/bin/python -m pytest -q
curl -s -o /dev/null -w "%{http_code}\\n" https://iitrainer.duckdns.org/healthz   # expect 403
curl -s -o /dev/null -w "%{http_code}\\n" http://127.0.0.1:5000/healthz           # expect 200 on PROD
node .claude/gsd-core/bin/gsd-tools.cjs progress
```

## Open items by phase

| Phase | Items |
|---|---|
| 1 | FND-01..09, SPL-01..02 (toolchain, tests, splits) |
| 2 | AIE-01..08 (error boundary and dispatcher) |
| 3 | ANL-01..06, EXC-01..02 (analysis, retry, exception narrowing) |
| 4 | SAF-01..03, SEC-01..05, SPL-03 (safety and defence-in-depth) |
