#!/usr/bin/env python3
"""Write the names Aybik's help answers use for screens and buttons, per language.

    python3 scripts/export-help-names.py          # write the file
    python3 scripts/export-help-names.py --check  # fail if it's out of date (CI)

The help facts (backend/supabase/functions/assist/help-facts.ts) name screens and
buttons in English. An answer in another language has to name them as her screen
does, so this script reads each name's translations from the app's string catalog
(ios/App/Resources/Localizable.xcstrings) and writes them to
backend/supabase/functions/assist/help-names.json, which the assist function adds
to a help request in that language. Names that read the same in a language (Retro
Cam, HD 2×) are left out of it. Run it after renaming a screen or a button, or
after changing their translations, and keep NAMES to the names the facts use
(assist's tests check that each one is in the facts).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "ios" / "App" / "Resources" / "Localizable.xcstrings"
OUT = ROOT / "backend" / "supabase" / "functions" / "assist" / "help-names.json"

# The app's languages other than English, as the assist function names them.
LANGUAGES = ["tr", "es", "pt-BR", "fr", "de", "it", "ru", "ja", "ko", "zh-Hans", "id"]

# Every screen, tab, button and setting the help facts name, as the app shows it in English.
NAMES = [
    # Tabs and tools
    "Explore", "Create", "Edit", "My Works", "Settings", "Magic Edit", "Makeup Studio", "Enhance", "Erase",
    "Adjust", "Crop", "Cut out", "Hide faces", "Text & Stickers", "Best shot", "Quick fix", "Unblur & sharpen",
    "Restore old photo", "Brighten low light", "Surprise me", "Ideas for this photo", "Save as my filter",
    "Collage", "Auto edit", "Booth", "Dreamy", "Analog", "Moody", "Golden", "Natural",
    "Doesn't look like you? Retry free", "Soft skin",
    # Settings
    "Language", "Credits", "Buy a credit pack", "Notifications", "When my free credits are back",
    "When my poll is ending", "Membership", "Restore purchases", "Manage subscription", "Account",
    "Bought Pro or credits on another device?", "Sign in", "Privacy", "Cloud AI processing", "Providers",
    "Ad privacy choices", "Delete all creations", "Delete my data & account", "Age", "Update age range",
    "About", "Show me around", "Feel good", "Find a helpline near you", "Contact support",
    "Terms, privacy & legal",
    # Credits, Pro and polls
    "Watch a short ad · +1 credit", "Try this look once · watch a short ad", "Waiting for approval",
    "Recently deleted", "Restore", "Delete now", "Which vibe?", "Ask friends", "Select", "Your polls",
    "Share again", "Delete",
]


def build() -> str:
    strings = json.loads(CATALOG.read_text(encoding="utf-8"))["strings"]
    names: dict[str, dict[str, str]] = {language: {} for language in LANGUAGES}
    problems = []
    for name in NAMES:
        localizations = strings.get(name, {}).get("localizations", {})
        for language in LANGUAGES:
            unit = localizations.get(language, {}).get("stringUnit", {})
            value = unit.get("value")
            if not value or unit.get("state") != "translated":
                problems.append(f"{name!r} has no {language} translation in Localizable.xcstrings")
            elif value != name:
                names[language][name] = value
    if problems:
        sys.exit("\n".join(problems))
    document = {
        "_comment": "Generated from ios/App/Resources/Localizable.xcstrings. Do not edit by hand: "
        "run python3 scripts/export-help-names.py.",
        "names": names,
    }
    return json.dumps(document, ensure_ascii=False, indent=2) + "\n"


def main() -> None:
    text = build()
    if "--check" in sys.argv[1:]:
        if not OUT.exists() or OUT.read_text(encoding="utf-8") != text:
            sys.exit(f"{OUT.relative_to(ROOT)} is out of date: run python3 scripts/export-help-names.py")
        return
    OUT.write_text(text, encoding="utf-8")
    print(f"Updated {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
