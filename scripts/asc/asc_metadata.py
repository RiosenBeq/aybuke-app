"""Pushes docs/marketing/app-store-metadata.json to App Store Connect: name and
subtitle (the editable app info), description, keywords, promotional text and
What's New (iOS and macOS), and with --review-notes the App Review notes from
app-store-listing.md.

Which version records: `--version 1.1` (the version string, on both platforms;
created when it doesn't exist yet), `--version <version id>` (that record; a
comma list for both), or by default each platform's editable version (prepare
for submission, rejected, or developer-rejected). A locale the version lacks is
added. What's New is left out where App Store Connect refuses it (an app's
first version).

The Mac description is made from the iOS one by `mac_description`, the same
way every time: bullets about iPhone-only features (widgets, the Lock Screen,
the Dynamic Island, Live Activities, Control Center, the Action button) go, a
heading left without bullets gives way to the locale's `mac.section` (or goes
too), and each `mac.replace` pair must match exactly once (Retro Cam without a
flash, "iPhone, iPad and Mac", the Mac App Store's subscription path). A text
that still names an iPhone-only feature, a flash, or no Mac stops the push.

    asc_metadata.py <repo> [--version 1.1] [--dry-run] [--review-notes]
                                                checks, then pushes (or, with
                                                --dry-run, shows the records and
                                                what would change)
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

LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "promotionalText": 170, "description": 4000,
          "whatsNew": 4000, "notes": 4000}

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

    versions = asc.resolve_versions(asc.version_spec(sys.argv), dry=dry)
    for locs in (localizations(asc, vid) for vid, _, _ in versions.values() if vid):
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
               "promotionalText": meta["promotionalText"], "whatsNew": meta["whatsNew"]}
        mac = dict(ios, description=mac_description(locale, meta),
                   promotionalText=meta["mac"].get("promotionalText", meta["promotionalText"]),
                   whatsNew=meta["mac"].get("whatsNew", meta["whatsNew"]))
        for key in ("promotionalText", "whatsNew"):
            match = IPHONE_ONLY.search(mac[key]) or FLASH.search(mac[key])
            if match:
                raise SystemExit(f"{locale} mac {key}: names {match.group(0)!r}; give the locale's mac block a {key}")
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
        for platform, text in review_notes(repo).items():
            print(f"review notes {platform}: {len(text)}/4000")
        seasons = sorted({s for meta in meta_all.values() for s in meta.get("promoBySeason", {})})
        print(f"seasonal promotional text: {', '.join(seasons) or 'none'}")
        print("check ok")
        return

    import asc  # needs requests + cryptography and the API key; the check doesn't

    versions = asc.resolve_versions(asc.version_spec(sys.argv), dry=dry)
    app_info = asc.editable_app_info()
    info_locs, _ = asc.get_all(f"/v1/appInfos/{app_info}/appInfoLocalizations")
    locs = {platform: localizations(asc, vid) if vid else {} for platform, (vid, _, _) in versions.items()}
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
        for platform, fields in (("ios", ios_fields), ("mac", mac_fields)):
            if platform in locs and locale in locs[platform]:
                patch_localization(asc, locs[platform][locale]["id"], fields)
    for platform, (vid, _, _) in versions.items():
        for locale in sorted(set(built) - set(locs[platform])):
            fields = built[locale][1 if platform == "ios" else 2]
            print(f"{platform}: {'would add' if dry or not vid else 'adding'} the {locale} localization")
            if not dry and vid:
                asc.post("/v1/appStoreVersionLocalizations", {"data": {
                    "type": "appStoreVersionLocalizations", "attributes": dict(fields, locale=locale),
                    "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    if "--review-notes" in sys.argv:
        notes = review_notes(repo)
        for platform, (vid, _, _) in versions.items():
            print(f"{platform}: review notes {len(notes[platform])}/4000")
            if not dry and vid:
                push_review_notes(asc, vid, notes[platform], versions)
    print("done" if not dry else "dry run ok")


def patch_localization(asc, loc_id, fields):
    """What's New can't be set on an app's first version: send the rest then."""
    body = lambda attrs: {"data": {"type": "appStoreVersionLocalizations", "id": loc_id, "attributes": attrs}}
    try:
        asc.patch(f"/v1/appStoreVersionLocalizations/{loc_id}", body(fields))
    except RuntimeError as error:
        if "whatsNew" not in str(error):
            raise
        asc.patch(f"/v1/appStoreVersionLocalizations/{loc_id}", body({k: v for k, v in fields.items() if k != "whatsNew"}))
        print("  (What's New not accepted for this version: left out)")


def review_notes(repo):
    """The App Review notes in app-store-listing.md: iOS, and the Mac's with its paragraph."""
    md = (repo / "docs/marketing/app-store-listing.md").read_text(encoding="utf-8")
    def block_after(marker):
        start = md.index("```text\n", md.index(marker)) + len("```text\n")
        return md[start:md.index("\n```", start)].strip()
    ios = block_after("**App Review notes**")
    mac_paragraph = block_after("For the macOS version the same text gets one more paragraph")
    body, contact = ios.rsplit("\n\nContact:", 1)
    notes = {"ios": ios, "mac": f"{body}\n\n{mac_paragraph}\n\nContact:{contact}"}
    for platform, text in notes.items():
        check(f"review notes {platform}", {"notes": text})
    return notes


def push_review_notes(asc, version_id, notes, versions):
    detail = asc.get(f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail").get("data")
    if detail:
        asc.patch(f"/v1/appStoreReviewDetails/{detail['id']}", {"data": {
            "type": "appStoreReviewDetails", "id": detail["id"], "attributes": {"notes": notes}}})
        return
    # A new record: the contact details come from another version's review detail.
    template = None
    for other, _, _ in versions.values():
        if other != version_id:
            template = asc.get(f"/v1/appStoreVersions/{other}/appStoreReviewDetail").get("data")
            if template:
                break
    if not template:
        raise SystemExit("no App Review details to copy the contact from: fill them in App Store Connect once")
    keep = ("contactFirstName", "contactLastName", "contactPhone", "contactEmail", "demoAccountRequired")
    attributes = {k: template["attributes"].get(k) for k in keep if template["attributes"].get(k) is not None}
    asc.post("/v1/appStoreReviewDetails", {"data": {
        "type": "appStoreReviewDetails", "attributes": dict(attributes, notes=notes),
        "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}})


if __name__ == "__main__":
    main()
