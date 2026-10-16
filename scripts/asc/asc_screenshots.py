"""Replaces the App Store screenshots of every locale with docs/marketing/app-store/<lang>/
(iPhone), <lang>/ipad/ and <lang>/mac/, on the iOS and macOS versions.

    asc_screenshots.py <repo> [--version 1.1] [--dry-run] [--only=en-US,tr] [--platform=ios|mac]

--version takes a version string or a version id (see asc.resolve_versions); without
it, each platform's editable version. --dry-run shows the records and the files.
"""
import hashlib
import sys
import time
from pathlib import Path

import requests

import asc

REPO = Path(sys.argv[1])
DRY = "--dry-run" in sys.argv
ONLY = next((a.split("=", 1)[1].split(",") for a in sys.argv if a.startswith("--only=")), None)
PLATFORM = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--platform=")), None)
STORE = REPO / "docs/marketing/app-store"
FOLDER = {"en-US": "en", "tr": "tr", "es-ES": "es", "es-MX": "es", "pt-BR": "pt-BR", "fr-FR": "fr", "de-DE": "de",
          "it": "it", "ru": "ru", "ja": "ja", "ko": "ko", "zh-Hans": "zh-Hans", "id": "id"}


def sets_for(platform, folder):
    base = STORE / folder
    if platform == "ios":
        return [("APP_IPHONE_67", sorted(base.glob("[0-9][0-9]-*.jpg"))),
                ("APP_IPAD_PRO_3GEN_129", sorted((base / "ipad").glob("[0-9][0-9]-*.jpg")))]
    return [("APP_DESKTOP", sorted((base / "mac").glob("[0-9][0-9]-*.jpg")))]


def screenshot_set(localization_id, display_type):
    sets, _ = asc.get_all(f"/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets")
    for item in sets:
        if item["attributes"]["screenshotDisplayType"] == display_type:
            return item["id"]
    created = asc.post("/v1/appScreenshotSets", {"data": {
        "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display_type},
        "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": localization_id}}}}})
    return created["data"]["id"]


def upload(set_id, path):
    data = path.read_bytes()
    reserved = asc.post("/v1/appScreenshots", {"data": {
        "type": "appScreenshots", "attributes": {"fileName": path.name, "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})["data"]
    for op in reserved["attributes"]["uploadOperations"]:
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        response = requests.request(op["method"], op["url"], headers=headers, data=chunk, timeout=120)
        response.raise_for_status()
    asc.patch(f"/v1/appScreenshots/{reserved['id']}", {"data": {
        "type": "appScreenshots", "id": reserved["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    return reserved["id"]


def main():
    total = 0
    versions = asc.resolve_versions(asc.version_spec(sys.argv), platforms=(PLATFORM,) if PLATFORM else ("ios", "mac"), dry=DRY)
    for platform, (version, _, _) in versions.items():
        if version is None:  # dry run before the version exists: list the files
            for locale, folder in FOLDER.items():
                for display_type, files in sets_for(platform, folder):
                    print(f"{platform} {locale} {display_type}: {len(files)} files")
                    total += len(files)
            continue
        locs, _ = asc.get_all(f"/v1/appStoreVersions/{version}/appStoreVersionLocalizations")
        for loc in locs:
            locale = loc["attributes"]["locale"]
            if ONLY and locale not in ONLY:
                continue
            folder = FOLDER.get(locale)
            if not folder or not (STORE / folder).exists():
                print(f"skip {platform} {locale}: no folder")
                continue
            for display_type, files in sets_for(platform, folder):
                if not files:
                    print(f"skip {platform} {locale} {display_type}: no files")
                    continue
                print(f"{platform} {locale} {display_type}: {len(files)} files")
                total += len(files)
                if DRY:
                    continue
                set_id = screenshot_set(loc["id"], display_type)
                old, _ = asc.get_all(f"/v1/appScreenshotSets/{set_id}/appScreenshots")
                for shot in old:
                    asc.delete(f"/v1/appScreenshots/{shot['id']}")
                for path in files:
                    for attempt in range(3):
                        try:
                            upload(set_id, path)
                            break
                        except Exception as error:  # retry transient upload failures
                            print("  retry", path.name, str(error)[:200])
                            time.sleep(3)
    print(("would upload" if DRY else "uploaded"), total, "screenshots")


main()
