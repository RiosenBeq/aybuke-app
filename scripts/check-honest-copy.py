#!/usr/bin/env python3
"""Fails when user-facing copy makes claims the code doesn't back (AGENTS.md §5).

- No promises of new content without an app update, no feed, no price
  comparison, no "higher resolution" (both tiers render at 1k).
- No "iPhone", "phone" or "iOS Settings" in app strings: the app runs on
  iPad and the Mac too ("on your device", "Settings").
- The App Store description's Pro line names no resolution in any locale.
- While Sign in with Apple is off (`signInWithApple` in AppConfig.json), no
  App Store text, review note or website page offers it.
- No "no ads" promises: free members see ads (only Pro, under-13s and the
  Mac have none), so the old "no ads, no tracking" lines can't come back.
- The app's AI helper is "Aybik" wherever people read about it: no
  "Claude" in the app's string catalogs (current keys and every
  translation), the App Store text, the screenshot captions or the legal
  texts. No company names (Anthropic, xAI, Grok, Supabase) in the catalogs
  or the App Store text either: the app names them only in the consent
  sheet's and Settings' one small line, built from AppConfig.json, and the
  legal texts list them where the law asks.

String catalogs are skipped: they keep stale keys until the next
translation pass. Run from anywhere: python3 scripts/check-honest-copy.py
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

BANNED = re.compile(
    r"every week|added regularly|higher.resolution|half what|new look a week|tailor your feed|fresh trends"
    # Free members see ads now: "no ads" is only true of Pro, under 13 and the Mac.
    r"|no ads,? no tracking|reklam yok,? takip yok|don't show advertising|don't use advertising SDKs"
    r"|reklam göstermeyiz|reklam yazılım geliştirme kitleri \(SDK\) kullanmayız|ad-free app",
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

# "Sign in with Apple" as the App Store locales spell it.
SIGN_IN = re.compile(
    r"Sign in with Apple|Apple ile Giriş|Inicia sesión con Apple|Iniciar sessão com a Apple|Connexion avec Apple|"
    r"Mit Apple anmelden|Accedi con Apple|Вход с Apple|Appleでサインイン|Apple로 로그인|通过 Apple 登录|Masuk dengan Apple",
    re.IGNORECASE,
)


# The model's name, never shown: people meet "Aybik", the app's AI helper.
HELPER_MODEL = re.compile(r"Claude", re.IGNORECASE)
# Companies stay out of the app's copy (AIProcessor.providersLine names them).
COMPANY = re.compile(r"\bAnthropic\b|\bxAI\b|\bGrok\b|\bSupabase\b")
HELPER_CATALOGS = [
    "ios/App/Resources/Localizable.xcstrings",
    "ios/App/Resources/InfoPlist.xcstrings",
    "ios/App/Resources/AppShortcuts.xcstrings",
    "ios/GlowlitWidgets/Localizable.xcstrings",
]
HELPER_JSON = ["docs/marketing/app-store-metadata.json", "docs/marketing/screenshot-captions.json"]
HELPER_TEXTS = [("legal/en", "*.md"), ("legal/tr", "*.md"), ("ios/App/Resources/Legal", "*")]


def strings_in(value):
    """Every string in a JSON value (dictionary keys included)."""
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, item in value.items():
            yield key
            yield from strings_in(item)
    elif isinstance(value, list):
        for item in value:
            yield from strings_in(item)


def naming_problem(text):
    """Why `text` can't be shown, or None."""
    if HELPER_MODEL.search(text):
        return "says Claude: the app's AI helper is Aybik"
    company = COMPANY.search(text)
    if company:
        return f"names {company.group(0)}: say our servers, a third-party AI provider or Aybik"
    return None


def helper_name_problems():
    """'Claude' or a company where people read it. A catalog's stale keys
    aren't shown; translator comments aren't either."""
    problems = []
    for path in HELPER_CATALOGS:
        catalog = json.loads((ROOT / path).read_text(encoding="utf-8"))
        for key, entry in catalog.get("strings", {}).items():
            if entry.get("extractionState") == "stale":
                continue
            for text in [key, *strings_in(entry.get("localizations", {}))]:
                problem = naming_problem(text)
                if problem:
                    problems.append(f"{path}: {key[:60]!r} {problem}")
                    break
    for path in HELPER_JSON:
        data = json.loads((ROOT / path).read_text(encoding="utf-8"))
        for text in strings_in(data):
            problem = naming_problem(text)
            if problem:
                problems.append(f"{path}: {text[:60]!r} {problem}")
    for base, pattern in HELPER_TEXTS:
        for file in sorted((ROOT / base).rglob(pattern)):
            if not file.is_file():
                continue
            for number, line in enumerate(file.read_text(encoding="utf-8").splitlines(), 1):
                if HELPER_MODEL.search(line):
                    problems.append(f"{file.relative_to(ROOT)}:{number}: says Claude: name the company (Anthropic) or Aybik")
    return problems


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

    config = json.loads((ROOT / "ios/App/Resources/AppConfig.json").read_text(encoding="utf-8"))
    if not config.get("signInWithApple", False):
        off = "Sign in with Apple is off (signInWithApple in AppConfig.json)"
        for locale, fields in metadata.items():
            for field, value in fields.items():
                if isinstance(value, str) and SIGN_IN.search(value):
                    problems.append(f"app-store-metadata.json [{locale}] {field}: offers sign-in, but {off}")
        for file in [ROOT / "docs/marketing/app-store-listing.md", *sorted((ROOT / "web").glob("*.html"))]:
            for number, line in enumerate(file.read_text(encoding="utf-8").splitlines(), 1):
                if SIGN_IN.search(line):
                    problems.append(f"{file.relative_to(ROOT)}:{number}: offers sign-in, but {off}")

    problems += helper_name_problems()

    if problems:
        print("\n".join(problems))
        print(f"\n{len(problems)} honest-copy problem(s). See AGENTS.md §5.")
        return 1
    print("Honest-copy check passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
