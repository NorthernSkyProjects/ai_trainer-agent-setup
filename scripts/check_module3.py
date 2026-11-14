#!/usr/bin/env python3
"""Module 3 acceptance gate.

Run before committing/pushing:
    python3 scripts/check_module3.py

Checks required artifacts, DESIGN.md sections, demo states, the Claude Code
validation verdict, and that no secrets/course PDF are staged.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

REQUIRED = [
    "DESIGN.md",
    "docs/module3.md",
    "docs/module3/verification.md",
    "docs/module3/CLAUDE-BRIEF.md",
    "docs/module3/claude-review-1.md",
    "docs/module3/claude-validation.md",
    "docs/ux/prd.md",
    "docs/ux/prd-challenge.md",
    "docs/ux/competitors.md",
    "docs/ux/ux-patterns.md",
    "docs/ux/design-loop.md",
    "docs/ux/design-loop/bar.md",
    "docs/ux/references/linear-branding.json",
    "docs/ux/references/hevy-branding.json",
    "docs/ux/references/fitbod-ux.md",
    "design/screens/plan.html",
    "design/screens/plan.css",
    "design/screens/plan.js",
    ".planning/phases/05-product-analytics-visual-concept/05-DISCUSSION-LOG.md",
    ".planning/phases/05-product-analytics-visual-concept/05-CONTEXT.md",
    ".planning/phases/05-product-analytics-visual-concept/05-01-PLAN.md",
    "screenshots/module3/plan-desktop-light.png",
    "screenshots/module3/plan-mobile-light.png",
    "screenshots/module3/plan-desktop-dark.png",
    "screenshots/module3/plan-mobile-dark.png",
    "screenshots/module3/state-empty.png",
    "screenshots/module3/state-loading.png",
    "screenshots/module3/state-error.png",
    "screenshots/module3/state-partial.png",
    "screenshots/module3/ai-desktop.png",
    "screenshots/module3/ai-mobile.png",
    "screenshots/module3/ai-pending-desktop.png",
    "screenshots/module3/ai-error-desktop.png",
]

DESIGN_SECTIONS = [
    "## 1. Atmosphere",
    "## 2. Colors",
    "## 3. Typography",
    "## 4. Spacing & Grid",
    "## 5. Components",
    "## 6. States",
    "## 7. AI UX",
    "## 8. Motion",
    "## 9. References",
    "## 10. Don'ts",
]

FORBIDDEN_NAMES = re.compile(r"(\.env$|\.pptx$|\.pdf$|Урок_UX|instance/|/etc/ai_trainer\.env|/etc/app\.env|docs/plans/)", re.IGNORECASE)


def run(cmd: list[str]) -> str:
    return subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, check=False).stdout


def check_files() -> list[str]:
    return [p for p in REQUIRED if not (ROOT / p).exists()]


def check_design() -> list[str]:
    text = (ROOT / "DESIGN.md").read_text(encoding="utf-8")
    return [s for s in DESIGN_SECTIONS if s not in text]


def check_screen() -> list[str]:
    html = (ROOT / "design/screens/plan.html").read_text(encoding="utf-8")
    js = (ROOT / "design/screens/plan.js").read_text(encoding="utf-8")
    errors = []
    for state in ("empty", "loading", "error", "partial", "ai", "ai-pending", "ai-error"):
        if state not in js:
            errors.append(f"design/screens/plan.js: state `{state}` not handled")
    if "onclick=" in html:
        errors.append("design/screens/plan.html: inline onclick found")
    if "cdn." in html or "https://fonts." in html:
        errors.append("design/screens/plan.html: external CDN/font request found")
    return errors


def check_validation() -> list[str]:
    path = ROOT / "docs/module3/claude-validation.md"
    if not path.exists():
        return ["docs/module3/claude-validation.md: missing"]
    text = path.read_text(encoding="utf-8")
    lines = [line for line in text.splitlines() if line.strip()]
    first = lines[0] if lines else ""
    match = re.match(r"^##\s*Вердикт\s*:?\s*\**\s*(GO|NO-GO)\b", first, re.IGNORECASE)
    if not match:
        return ["docs/module3/claude-validation.md: first line must be `## Вердикт: GO|NO-GO`"]
    if match.group(1).upper() == "NO-GO":
        return ["docs/module3/claude-validation.md: verdict is NO-GO"]
    return []


def check_staged() -> list[str]:
    staged = run(["git", "diff", "--cached", "--name-only", "--diff-filter=ACMRT", "-z"])
    status = run(["git", "-c", "core.quotePath=false", "status", "--porcelain", "-uall"])
    names = [name for name in staged.split("\0") if name.strip()]
    names += [line[3:].strip().strip('"') for line in status.splitlines() if line.strip()]
    # Also check the raw status line, so renames/quoted Cyrillic paths are covered.
    names += [line.strip() for line in status.splitlines() if line.strip()]
    return [f"forbidden path in git: {name}" for name in names if FORBIDDEN_NAMES.search(name)]


def main() -> int:
    errors: list[str] = []
    errors += [f"missing: {p}" for p in check_files()]
    errors += [f"DESIGN.md: missing section {s}" for s in check_design()]
    errors += check_screen()
    errors += check_validation()
    errors += check_staged()

    if errors:
        print("MODULE 3 GATE: FAIL")
        for err in errors:
            print(f"  - {err}")
        return 1

    print("MODULE 3 GATE: PASS")
    print(f"  files: {len(REQUIRED)}")
    print(f"  design sections: {len(DESIGN_SECTIONS)}")
    print("  screen states: empty, loading, error, partial, ai, ai-pending, ai-error")
    print("  Claude Code validation: GO")
    return 0


if __name__ == "__main__":
    sys.exit(main())
