"""Renames the user-facing brand Glowlit -> Aybuke across the repo.

Keeps internal identifiers: type names (GlowlitApp, GlowlitWidgets...), the
Xcode project and scheme, bundle ids (app.glowlit.ios), the App Group and the
glowlit:// scheme. Fixes Turkish and Korean suffixes that depend on the
name ending in a vowel. Usage: rename.py <repo> [--write]
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
WRITE = "--write" in sys.argv
OLD, NEW = "Glowlit", "Aybuke"

# Turkish: Glowlit ends in a consonant, Aybuke in a front vowel.
TR_SUFFIX = {"i": "yi", "ı": "yı", "in": "nin", "ın": "nın", "e": "ye", "a": "ya", "te": "de", "ta": "da",
             "ten": "den", "tan": "dan", "le": "yle", "la": "yla", "de": "de", "den": "den", "ler": "ler"}
TR_RE = re.compile(r"\bGlowlit(['’])(in|ın|ten|tan|ler|le|la|te|ta|de|den|i|ı|e|a)\b")
# Korean particles after a vowel.
KO_SUFFIX = {"은": "는", "을": "를", "이": "가", "으로": "로", "과": "와", "의": "의", "도": "도", "에": "에", "에서": "에서"}
KO_RE = re.compile(r"Glowlit([”\"’']?)(으로|에서|은|을|이|과|의|도|에)")
PLAIN_RE = re.compile(r"(?<![\w.@/-])Glowlit(?![\w])")
# Paths and build names that must keep the old name.
KEEP_RE = re.compile(r"Glowlit(?=\.(xcodeproj|xcarchive|xcworkspace|app\b|storekit))|(?<=-scheme )Glowlit|(?<=DerivedData/)Glowlit-|"
                     r"(?<=scheme )Glowlit\b|Glowlit(?=-[*a-z]+\b)(?<!Aybuke)")


def rename_text(text: str, lang: str = "en", keep_paths: bool = False) -> str:
    if OLD not in text:
        return text
    # Turkish suffixes after an apostrophe and Korean particles never occur in
    # other languages, so they're fixed everywhere (mixed-language docs too).
    text = TR_RE.sub(lambda m: f"{NEW}{m.group(1)}{TR_SUFFIX[m.group(2)]}", text)
    text = KO_RE.sub(lambda m: f"{NEW}{m.group(1)}{KO_SUFFIX[m.group(2)]}", text)
    if keep_paths:
        protected = {}

        def protect(m):
            token = f"\u0000{len(protected)}\u0000"
            protected[token] = m.group(0)
            return token
        text = KEEP_RE.sub(protect, text)
        text = PLAIN_RE.sub(NEW, text)
        for token, value in protected.items():
            text = text.replace(token, value)
        return text
    return PLAIN_RE.sub(NEW, text)


def rename_catalog(path: Path) -> tuple[str, int]:
    data = json.loads(path.read_text(encoding="utf-8"))
    count = 0
    strings = {}
    for key, entry in data["strings"].items():
        new_key = rename_text(key)
        if new_key != key:
            count += 1
        for lang, loc in entry.get("localizations", {}).items():
            unit = loc.get("stringUnit")
            if unit and "value" in unit:
                new = rename_text(unit["value"], lang)
                count += new != unit["value"]
                unit["value"] = new
            for variation in (loc.get("variations") or {}).values():
                for case in variation.values():
                    unit = case.get("stringUnit")
                    if unit and "value" in unit:
                        new = rename_text(unit["value"], lang)
                        count += new != unit["value"]
                        unit["value"] = new
        if "comment" in entry:
            entry["comment"] = rename_text(entry["comment"])
        if new_key in strings and new_key != key:
            raise SystemExit(f"{path}: renamed key collides: {new_key!r}")
        strings[new_key] = entry
    data["strings"] = strings
    return xcode_json(data), count


def xcode_json(data) -> str:
    """Xcode's catalog format: 2-space indent, " : ", empty objects as a
    blank line, no newline at the end. Key order is kept as read."""
    out = json.dumps(data, ensure_ascii=False, indent=2, separators=(",", " : "))
    return re.sub(r'^( *)(".*" : )\{\}(,?)$', lambda m: f"{m.group(1)}{m.group(2)}{{\n\n{m.group(1)}}}{m.group(3)}", out, flags=re.M)


def metadata_json(path: Path) -> tuple[str, int]:
    data = json.loads(path.read_text(encoding="utf-8"))
    count = 0

    def walk(node, lang):
        nonlocal count
        if isinstance(node, dict):
            return {k: walk(v, k if re.fullmatch(r"[a-z]{2}(-[A-Za-z]+)?", k) else lang) for k, v in node.items()}
        if isinstance(node, list):
            return [walk(v, lang) for v in node]
        if isinstance(node, str):
            new = rename_text(node, lang)
            count += new != node
            return new
        return node
    data = walk(data, "en")
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n", count


def main():
    changes = []

    def apply(path: Path, new_text: str):
        old_text = path.read_text(encoding="utf-8")
        if new_text != old_text:
            changes.append((path, old_text.count(OLD) - new_text.count(OLD)))
            if WRITE:
                path.write_text(new_text, encoding="utf-8")

    # Swift: strings and comments; identifiers keep the old name (\b rules).
    for path in sorted((ROOT / "ios").rglob("*.swift")):
        if "/.build/" in str(path):
            continue
        text = path.read_text(encoding="utf-8")
        new = rename_text(text)
        if path.name == "TemporaryFiles.swift":
            new = new.replace('["glowlit-", "Aybuke-", "creation-"]', '["glowlit-", "Glowlit-", "aybuke-", "Aybuke-", "creation-"]')
        apply(path, new)
    # String catalogs.
    for path in [ROOT / "ios/App/Resources/Localizable.xcstrings", ROOT / "ios/App/Resources/InfoPlist.xcstrings",
                 ROOT / "ios/App/Resources/AppShortcuts.xcstrings", ROOT / "ios/GlowlitWidgets/Localizable.xcstrings"]:
        if path.exists():
            new, _ = rename_catalog(path)
            apply(path, new)
    # Display name in the project.
    pbx = ROOT / "ios/Glowlit.xcodeproj/project.pbxproj"
    apply(pbx, pbx.read_text(encoding="utf-8").replace("INFOPLIST_KEY_CFBundleDisplayName = Glowlit;",
                                                       "INFOPLIST_KEY_CFBundleDisplayName = Aybuke;"))
    # Plists and JSON resources.
    for path in list((ROOT / "ios").rglob("*.plist")) + [ROOT / "ios/App/Resources/AppConfig.json"]:
        apply(path, rename_text(path.read_text(encoding="utf-8")))
    # Legal sources (built into web/ and the app by build-legal.py).
    for path in sorted((ROOT / "legal").rglob("*")):
        if path.is_file() and path.suffix in (".md", ".json"):
            lang = "tr" if "/tr/" in str(path) else "en"
            apply(path, rename_text(path.read_text(encoding="utf-8"), lang))
    # Marketing metadata per locale.
    meta = ROOT / "docs/marketing/app-store-metadata.json"
    new, _ = metadata_json(meta)
    apply(meta, new)
    # Website, docs and scripts: prose only, paths kept.
    prose = [ROOT / "README.md", ROOT / "AGENTS.md", ROOT / "web/index.html"]
    prose += [p for p in (ROOT / "docs").rglob("*.md") if "/legal/" not in str(p)]
    prose += [p for p in (ROOT / "docs").rglob("*.json") if p.name != "app-store-metadata.json"]
    prose += [ROOT / f"scripts/{name}" for name in ("render-brand-assets.py", "marketing-images.py", "screenshot-gallery.py",
                                                     "build-legal.py", "upload-app-store.sh")]
    for path in prose:
        if not path.exists():
            continue
        lang = "tr" if path.name.endswith("-TR.md") or path.name in ("NEXT-STEPS.md", "RELEASE-CHECKLIST.md") else "en"
        apply(path, rename_text(path.read_text(encoding="utf-8"), lang, keep_paths=True))

    total = sum(n for _, n in changes)
    for path, n in changes:
        print(f"{n:4}  {path.relative_to(ROOT)}")
    print(f"{'wrote' if WRITE else 'would change'} {len(changes)} files, {total} occurrences")


main()
