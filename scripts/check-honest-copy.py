#!/usr/bin/env python3
"""Fails when user-facing copy makes claims the code doesn't back (AGENTS.md §5).

- No promises of new content without an app update, no feed, no price
  comparison, no "higher resolution" (both tiers render at 1k).
- No "iPhone", "phone" or "iOS Settings" in app strings: the app runs on
  iPad and the Mac too ("on your device", "Settings").
- The App Store description's Pro line names no resolution in any locale.

String catalogs are skipped: they keep stale keys until the next
translation pass. Run from anywhere: python3 scripts/check-honest-copy.py
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

BANNED = re.compile(
    r"every week|added regularly|higher.resolution|half what|new look a week|tailor your feed|fresh trends",
    re.IGNORECASE,
)
BANNED_PLACES = [
    ("ios/App", "*.swift"),
    ("ios/GlowlitWidgets", "*.swift"),
    ("ios/Packages/AppCore/Sources", "*.swift"),
    ("web", "*.html"),
    ("docs/marketing", "*.md"),
    ("docs/marketing", "*.json"),
    ("legal", "*.md"),
    (".", "README.md"),
]

# A string literal mentioning a specific device, outside comments.
DEVICE = re.compile(r'"[^"\n]*(?:\biPhones?\b|\bphones?\b|iOS Settings)[^"\n]*"')
# SF Symbol names ("phone.bubble") are never shown as text.
SYMBOL = re.compile(r'(?:systemImage|systemName):\s*"[^"\n]*"')

RESOLUTION = re.compile(
    r"resolution|çözünürlük|resolución|Auflösung|résolution|risoluzione|resolução|разрешени|解像度|해상도|分辨率|resolusi",
    re.IGNORECASE,
)


def files(base, pattern):
    if base == ".":
        return [ROOT / pattern]
    return sorted((ROOT / base).rglob(pattern))


def main():
    problems = []
    for base, pattern in BANNED_PLACES:
        for file in files(base, pattern):
            for number, line in enumerate(file.read_text(encoding="utf-8").splitlines(), 1):
                if BANNED.search(line):
                    problems.append(f"{file.relative_to(ROOT)}:{number}: unsupported claim: {BANNED.search(line).group(0)!r}")

    for base in ("ios/App", "ios/GlowlitWidgets", "ios/Packages/AppCore/Sources"):
        for file in sorted((ROOT / base).rglob("*.swift")):
            for number, line in enumerate(file.read_text(encoding="utf-8").splitlines(), 1):
                # Comments, and AI prompts ("a phone" as a doll accessory), aren't UI copy.
                if line.lstrip().startswith("//") or "prompt:" in line:
                    continue
                match = DEVICE.search(SYMBOL.sub("", line))
                if match:
                    problems.append(f"{file.relative_to(ROOT)}:{number}: device-specific wording: {match.group(0)}")

    metadata = json.loads((ROOT / "docs/marketing/app-store-metadata.json").read_text(encoding="utf-8"))
    for locale, fields in metadata.items():
        for line in fields.get("description", "").splitlines():
            if "Pro" in line and RESOLUTION.search(line):
                problems.append(f"app-store-metadata.json [{locale}]: the Pro line promises a resolution")

    if problems:
        print("\n".join(problems))
        print(f"\n{len(problems)} honest-copy problem(s). See AGENTS.md §5.")
        return 1
    print("Honest-copy check passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
