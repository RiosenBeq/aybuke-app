"""Pushes docs/marketing/app-store-metadata.json to App Store Connect: name and
subtitle (app info), description, keywords and promotional text (iOS and macOS
1.0).

The Mac description is made from the iOS one by `mac_description`, the same
way every time: bullets about iPhone-only features (widgets, the Lock Screen,
the Dynamic Island, Live Activities, Control Center, the Action button) go, a
heading left without bullets gives way to the locale's `mac.section` (or goes
too), and each `mac.replace` pair must match exactly once (Retro Cam without a
flash, "iPhone, iPad and Mac", the Mac App Store's subscription path). A text
that still names an iPhone-only feature, a flash, or no Mac stops the push.

    asc_metadata.py <repo> [--dry-run]          checks, then pushes (or not)
    asc_metadata.py <repo> --check [--show=ja]  offline checks only (no API);
                                                --show prints that Mac text
    asc_metadata.py <repo> --season <id> [--dry-run]
                                                only the promotional text: each
                                                locale's `promoBySeason[<id>]`
                                                (a local season of the app, such
                                                as eidAlFitr or lunarNewYear), on
                                                iOS and macOS; `--season default`
                                                puts the usual text back after it

Promotional text can change at any time without a review, so a local season
can be announced where it's celebrated while it's on (SeasonCalendar.swift has
the dates). Locales without text for that season are left as they are.
"""
import json
import re
import sys
from pathlib import Path

LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "promotionalText": 170, "description": 4000}
APP_INFO = "8ac32843-da8f-4dc6-9e9f-f2eb04392678"
IOS = "f3e190c1-151c-4828-a349-b2c348d4ec20"
MAC = "62d912cf-8fd9-4165-a5ea-03529fd63aba"

# iPhone-only features as the 13 locales name them.
IPHONE_ONLY = re.compile(
    r"widget|Виджет|ウィジェット|위젯|小组件"
    r"|Lock Screen|Kilitli Ekran|Tela Bloqueada|Layar Terkunci|ロック画面|잠금 화면|锁定屏幕"
    r"|Dynamic Island|灵动岛|Live Activit"
    r"|Control Center|Denetim Merkezi|Centro de control|Central de Controle|centre de contrôle"
    r"|Kontrollzentrum|Centro di Controllo|Пункт управления|コントロールセンター|제어 센터|控制中心|Pusat Kontrol"
    r"|Action button|Eylem düğmesi|botón Acción|botão de Ação|bouton Action|Aktionstaste|tasto Azione"
    r"|кнопк\w* «Действие»|アクションボタン|동작 버튼|操作按钮|Tombol Tindakan",
    re.IGNORECASE,
)
# The Mac has no camera flash.
FLASH = re.compile(r"\bflash\b|flaş|Blitz|вспышк|フラッシュ|플래시|闪光灯", re.IGNORECASE)
# Every locale's iOS path goes through its "Apple Account"; the Mac's starts in the App Store.
IOS_SUBSCRIPTIONS = re.compile(r"›[^›\n]{0,15}Apple")
MAC_SUBSCRIPTIONS = re.compile(r"App Store[^›\n]{0,15}›")
BULLET = ("•", "-", "·")


def season_ids(repo):
    """The app's seasons, as `SeasonalTheme` names them."""
    source = (repo / "ios/Packages/AppCore/Sources/AppCore/TemplateCatalog.swift").read_text(encoding="utf-8")
    body = source[source.index("public enum SeasonalTheme"):]
    body = body[:body.index("public var rowTitle")]
    return set(re.findall(r"^\s*case (\w+)$", body, flags=re.M))


def check_seasons(repo, meta_all):
    """`promoBySeason`: known seasons, within the limit, never Glowlit."""
    known = season_ids(repo)
    for locale, meta in meta_all.items():
        for season, text in meta.get("promoBySeason", {}).items():
            if season not in known:
                raise SystemExit(f"{locale} promoBySeason: {season!r} isn't a season of the app ({', '.join(sorted(known))})")
            check(locale, {"promotionalText": text})
            if "Glowlit" in text:
                raise SystemExit(f"{locale} promoBySeason {season}: says Glowlit (the app is Aybuke)")


def season_argument():
    for index, arg in enumerate(sys.argv):
        if arg.startswith("--season="):
            return arg.split("=", 1)[1]
        if arg == "--season":
            if index + 1 >= len(sys.argv) or sys.argv[index + 1].startswith("--"):
                raise SystemExit("--season needs a season id (or default)")
            return sys.argv[index + 1]
    return None


def push_season(meta_all, season, dry):
    """Only the promotional text, for the locales that have one for `season`."""
    texts = {locale: meta["promotionalText"] if season == "default" else meta.get("promoBySeason", {}).get(season)
             for locale, meta in meta_all.items()}
    texts = {locale: text for locale, text in texts.items() if text}
    if not texts:
        raise SystemExit(f"no locale has promotional text for {season!r}")
    for locale, text in texts.items():
        print(f"{locale}: {text}")
    if dry:
        print("dry run ok")
        return

    import asc  # needs requests + cryptography and the API key; the check doesn't

    for locs in (localizations(asc, IOS), localizations(asc, MAC)):
        for locale, text in texts.items():
            if locale in locs:
                loc_id = locs[locale]["id"]
                asc.patch(f"/v1/appStoreVersionLocalizations/{loc_id}", {"data": {
                    "type": "appStoreVersionLocalizations", "id": loc_id, "attributes": {"promotionalText": text}}})
    print("done")


def check(locale, fields):
    for key, limit in LIMITS.items():
        if key in fields and fields[key] is not None and len(fields[key]) > limit:
            raise SystemExit(f"{locale} {key} is {len(fields[key])} characters (limit {limit})")


def mac_description(locale, meta):
    """The iOS description without iPhone-only features, in Mac words."""
    mac = meta.get("mac")
    if not mac:
        raise SystemExit(f"{locale}: no \"mac\" block in app-store-metadata.json")
    blocks, section_used = [], False
    for block in meta["description"].split("\n\n"):
        lines = block.split("\n")
        bullets = [line for line in lines if line.startswith(BULLET)]
        kept = [line for line in lines if not (line.startswith(BULLET) and IPHONE_ONLY.search(line))]
        if bullets and not any(line.startswith(BULLET) for line in kept):
            # Every bullet was iPhone-only: the heading goes too.
            if mac.get("section") and not section_used:
                blocks.append("\n".join(mac["section"]))
                section_used = True
            continue
        blocks.append("\n".join(kept))
    text = "\n\n".join(blocks)
    for old, new in mac.get("replace", []):
        count = text.count(old)
        if count != 1:
            raise SystemExit(f"{locale} mac: {old!r} appears {count} times in the description (expected once)")
        text = text.replace(old, new)

    problems = []
    if mac.get("section") and not section_used:
        problems.append("the Mac section found no iPhone-only section to replace")
    for pattern, what in ((IPHONE_ONLY, "an iPhone-only feature"), (FLASH, "a flash")):
        match = pattern.search(text)
        if match:
            problems.append(f"still names {what}: {match.group(0)!r}")
    if "Mac" not in text:
        problems.append("never says it runs on the Mac")
    if any(("iPhone" in line or "iPad" in line) and "Mac" not in line for line in text.split("\n")):
        problems.append("names iPhone or iPad without the Mac")
    # iOS: Settings › Apple Account › Subscriptions; Mac: App Store › your name › …
    if IOS_SUBSCRIPTIONS.search(text) or not MAC_SUBSCRIPTIONS.search(text):
        problems.append("doesn't give the Mac App Store's subscription path")
    if "\n\n\n" in text:
        problems.append("has an empty section")
    if problems:
        raise SystemExit(f"{locale} mac description: " + "; ".join(problems))
    return text


def pro_names(repo):
    """Names of Pro-only looks and styles, in English and each app language,
    read from AppCore's catalogs and the app's string catalog. A name a free
    item shares (the free Claymation look, the Pro Claymation style) is left out."""
    core = repo / "ios/Packages/AppCore/Sources/AppCore"
    pro, free = set(), set()
    for file, kind, key in (("TemplateCatalog.swift", "PhotoTemplate(", "title"),
                            ("StyleCatalog.swift", "ImageStyle(", "name")):
        for chunk in (core / file).read_text(encoding="utf-8").split(kind)[1:]:
            name = re.search(rf'{key}:\s*"([^"]+)"', chunk)
            if name:
                (pro if "isPro: true" in chunk else free).add(name.group(1))
    strings = json.loads((repo / "ios/App/Resources/Localizable.xcstrings").read_text(encoding="utf-8"))["strings"]
    names = {}
    for english in pro - free:
        names.setdefault("en", set()).add(english)
        for language, unit in strings.get(english, {}).get("localizations", {}).items():
            value = unit.get("stringUnit", {}).get("value")
            if value:
                names.setdefault(language, set()).add(value)
    return names


def check_pro_names(locale, description, names):
    """Guideline 2.3.2: a line that names a Pro-only look or style says Pro."""
    language = {"en-US": "en", "es-ES": "es", "es-MX": "es", "fr-FR": "fr", "de-DE": "de"}.get(locale, locale)
    for line in description.split("\n"):
        # Latin letters around a name make it another word ("Oil Paint" in "Oil Painting").
        named = sorted(n for n in names.get("en", set()) | names.get(language, set())
                       if re.search(rf"(?<![A-Za-z]){re.escape(n)}(?![A-Za-z])", line))
        if named and "Pro" not in line:
            raise SystemExit(f"{locale}: names Pro-only {', '.join(named)} without saying Pro: {line[:80]!r}")


def build(repo, meta_all):
    """Every locale's fields, checked; no network."""
    names = pro_names(repo)
    out = {}
    for locale, meta in meta_all.items():
        check_pro_names(locale, meta["description"], names)
        info = {"name": meta["name"], "subtitle": meta["subtitle"]}
        ios = {"description": meta["description"], "keywords": meta["keywords"],
               "promotionalText": meta["promotionalText"]}
        mac = dict(ios, description=mac_description(locale, meta))
        for fields in (info, ios, mac):
            check(locale, fields)
            for key, value in fields.items():
                if "Glowlit" in value:
                    raise SystemExit(f"{locale} {key}: says Glowlit (the app is Aybuke)")
        out[locale] = (info, ios, mac)
    return out


def check_listing(repo, meta_all):
    """docs/marketing/app-store-listing.md shows the en-US and Turkish text as sent."""
    listing = " ".join((repo / "docs/marketing/app-store-listing.md").read_text(encoding="utf-8").split())
    for locale in ("en-US", "tr"):
        for key in ("name", "subtitle", "promotionalText", "keywords", "description"):
            if " ".join(meta_all[locale][key].split()) not in listing:
                raise SystemExit(f"app-store-listing.md: the {locale} {key} differs from app-store-metadata.json")


def localizations(asc, version):
    items, _ = asc.get_all(f"/v1/appStoreVersions/{version}/appStoreVersionLocalizations")
    return {i["attributes"]["locale"]: i for i in items}


def main():
    repo = Path(sys.argv[1])
    dry = "--dry-run" in sys.argv
    meta_all = json.loads((repo / "docs/marketing/app-store-metadata.json").read_text(encoding="utf-8"))
    built = build(repo, meta_all)
    check_listing(repo, meta_all)
    check_seasons(repo, meta_all)
    season = season_argument()
    if season and "--check" not in sys.argv:
        if season != "default" and season not in season_ids(repo):
            raise SystemExit(f"{season!r} isn't a season of the app")
        push_season(meta_all, season, dry)
        return
    if "--check" in sys.argv:
        for locale, (_, ios, mac) in built.items():
            print(f"{locale}: description {len(ios['description'])}/{len(mac['description'])} (iOS/Mac)")
        for arg in sys.argv:
            if arg.startswith("--show="):
                print(built[arg.split("=", 1)[1]][2]["description"])
        seasons = sorted({s for meta in meta_all.values() for s in meta.get("promoBySeason", {})})
        print(f"seasonal promotional text: {', '.join(seasons) or 'none'}")
        print("check ok")
        return

    import asc  # needs requests + cryptography and the API key; the check doesn't

    info_locs, _ = asc.get_all(f"/v1/appInfos/{APP_INFO}/appInfoLocalizations")
    ios_locs, mac_locs = localizations(asc, IOS), localizations(asc, MAC)
    for item in info_locs:
        locale = item["attributes"]["locale"]
        if locale not in built:
            print("no metadata for", locale)
            continue
        info, ios_fields, mac_fields = built[locale]
        print(f"{locale}: name {info['name']!r}, description {len(ios_fields['description'])}/{len(mac_fields['description'])}")
        if dry:
            continue
        asc.patch(f"/v1/appInfoLocalizations/{item['id']}", {"data": {
            "type": "appInfoLocalizations", "id": item["id"], "attributes": info}})
        for locs, fields in ((ios_locs, ios_fields), (mac_locs, mac_fields)):
            if locale in locs:
                loc_id = locs[locale]["id"]
                asc.patch(f"/v1/appStoreVersionLocalizations/{loc_id}", {"data": {
                    "type": "appStoreVersionLocalizations", "id": loc_id, "attributes": fields}})
    print("done" if not dry else "dry run ok")


if __name__ == "__main__":
    main()
