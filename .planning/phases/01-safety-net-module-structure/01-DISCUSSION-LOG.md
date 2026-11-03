# Phase 1: Safety Net & Module Structure - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-11-03
**Phase:** 1-Safety Net & Module Structure
**Areas discussed:** Toolchain and lockfile, RQ 2.x upgrade, Test net, Module splits, Ordering

---

Run with `--auto`: all gray areas were selected and each question was resolved with the recommended default from `.planning/research/`. No interactive answers were given by the user.

## Toolchain and lockfile
**Options:** pip-tools/uv lockfile with existing requirements file names (chosen) vs. new lockfile with changed deploy commands.
**Choice:** keep deploy command shape; Python 3.12; verify PROD Python first.

## RQ 2.x upgrade
**Options:** `>=2.12,<3` (chosen) vs. 3.x vs. stay on 1.x.

## Test net
**Options:** pytest-socket + fakeredis (chosen) vs. only mocks.

## Module splits
**Options:** extract non-route code with re-exports (chosen) vs. new blueprints (rejected: renames endpoints).

## Claude's Discretion
Lockfile tool, file and module names, cut lines, pip-audit.

## Deferred Ideas
helpers/validation splits (Phase 4), webhook header fix (Phase 4), error boundary (Phase 2).
