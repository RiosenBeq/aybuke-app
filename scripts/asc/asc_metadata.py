"""Pushes docs/marketing/app-store-metadata.json to App Store Connect: name and
subtitle (app info), description, keywords and promotional text (iOS and macOS
1.0). The Mac description drops the iPhone-only bullets (widgets/Lock Screen/
Dynamic Island and Siri/Control Center/Action button), found by similarity to
the bullets the current Mac text already leaves out.

    asc_metadata.py <repo> [--dry-run]
"""
import difflib
import json
import sys
from pathlib import Path

import asc

REPO = Path(sys.argv[1])
DRY = "--dry-run" in sys.argv
META = json.loads((REPO / "docs/marketing/app-store-metadata.json").read_text(encoding="utf-8"))
APP_INFO = "8ac32843-da8f-4dc6-9e9f-f2eb04392678"
IOS = "f3e190c1-151c-4828-a349-b2c348d4ec20"
MAC = "62d912cf-8fd9-4165-a5ea-03529fd63aba"
LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "promotionalText": 170, "description": 4000}


def check(locale, fields):
    for key, limit in LIMITS.items():
        if key in fields and fields[key] is not None and len(fields[key]) > limit:
            raise SystemExit(f"{locale} {key} is {len(fields[key])} characters (limit {limit})")


def localizations(version):
    items, _ = asc.get_all(f"/v1/appStoreVersions/{version}/appStoreVersionLocalizations")
    return {i["attributes"]["locale"]: i for i in items}


def mac_description(locale, ios_text, current_ios, current_mac):
    """Drops the new text's lines that look like the bullets the current Mac text leaves out."""
    removed = [line for line in current_ios.split("\n") if line.strip() and line not in current_mac.split("\n")]
    if not removed:
        return ios_text
    kept = []
    for line in ios_text.split("\n"):
        similar = max((difflib.SequenceMatcher(None, line, r).ratio() for r in removed), default=0)
        if line.strip().startswith(("•", "-", "·")) and similar > 0.55:
            print(f"  mac {locale}: drops {line[:70]!r} ({similar:.2f})")
            continue
        kept.append(line)
    return "\n".join(kept)


def main():
    info_locs, _ = asc.get_all(f"/v1/appInfos/{APP_INFO}/appInfoLocalizations")
    ios_locs, mac_locs = localizations(IOS), localizations(MAC)
    for item in info_locs:
        locale = item["attributes"]["locale"]
        meta = META.get(locale)
        if not meta:
            print("no metadata for", locale)
            continue
        info = {"name": meta["name"], "subtitle": meta["subtitle"]}
        check(locale, info)
        ios_fields = {"description": meta["description"], "keywords": meta["keywords"],
                      "promotionalText": meta["promotionalText"]}
        check(locale, ios_fields)
        mac_fields = dict(ios_fields)
        if locale in mac_locs and locale in ios_locs:
            mac_fields["description"] = mac_description(
                locale, meta["description"],
                ios_locs[locale]["attributes"].get("description") or "",
                mac_locs[locale]["attributes"].get("description") or "")
        print(f"{locale}: name {info['name']!r}, description {len(ios_fields['description'])}/{len(mac_fields['description'])}")
        if DRY:
            continue
        asc.patch(f"/v1/appInfoLocalizations/{item['id']}", {"data": {
            "type": "appInfoLocalizations", "id": item["id"], "attributes": info}})
        for locs, fields in ((ios_locs, ios_fields), (mac_locs, mac_fields)):
            if locale in locs:
                loc_id = locs[locale]["id"]
                asc.patch(f"/v1/appStoreVersionLocalizations/{loc_id}", {"data": {
                    "type": "appStoreVersionLocalizations", "id": loc_id, "attributes": fields}})
    print("done" if not DRY else "dry run ok")


main()
